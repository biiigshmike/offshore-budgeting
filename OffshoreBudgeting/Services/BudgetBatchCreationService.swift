import Foundation
import SwiftData

@MainActor
enum BudgetBatchCreationService {
    enum CreationError: LocalizedError {
        case invalidInput, wrongWorkspace, duplicateDates, overlapConfirmationRequired, previewChanged, tooManyExpenses

        var errorDescription: String? {
            switch self {
            case .invalidInput: String(localized: "Check the budget names, dates, and category goals before creating budgets.")
            case .wrongWorkspace: String(localized: "The selected items must belong to this workspace.")
            case .duplicateDates: String(localized: "A budget already has these exact dates. Change the starting date or number of budgets.")
            case .overlapConfirmationRequired: String(localized: "Review and confirm overlapping budgets before continuing.")
            case .previewChanged: String(localized: "Budget information changed. Close this preview and review it again before creating budgets.")
            case .tooManyExpenses: String(localized: "This would create more than 10,000 planned expenses. Reduce the number of budgets or the cycle interval.")
            }
        }
    }

    static func preview(
        workspace: Workspace,
        ranges: [BudgetCycleRange],
        templateName: String,
        customName: Bool,
        preserveFirstName: Bool,
        presets: [Preset],
        modelContext: ModelContext
    ) throws -> BudgetBatchPreview {
        let name = templateName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, (1...52).contains(ranges.count),
              ranges.allSatisfy({ $0.startDate.timeIntervalSinceReferenceDate.isFinite
                  && $0.endDate.timeIntervalSinceReferenceDate.isFinite && $0.startDate <= $0.endDate }) else {
            throw CreationError.invalidInput
        }
        guard presets.allSatisfy({ $0.workspace?.id == workspace.id }) else { throw CreationError.wrongWorkspace }
        let existing = try budgets(in: workspace, modelContext: modelContext)
        var usedNames = Set(existing.map { normalizedName($0.name) })
        let drafts = ranges.enumerated().map { index, range in
            let dateName = BudgetNameSuggestion.suggestedName(start: range.startDate, end: range.endDate, calendar: .current)
            let base = preserveFirstName && index == 0 ? name : (customName ? "\(name) — \(dateName)" : dateName)
            var unique = base
            var suffix = 2
            while usedNames.contains(normalizedName(unique)) {
                unique = "\(base) (\(suffix))"
                suffix += 1
            }
            usedNames.insert(normalizedName(unique))
            return BudgetBatchDraft(name: unique, startDate: range.startDate, endDate: range.endDate)
        }
        try validateDrafts(drafts)
        let overlaps = try overlappingNames(drafts: drafts, existing: existing)
        return BudgetBatchPreview(
            drafts: drafts,
            plannedExpenseCount: try plannedCount(drafts: drafts, presets: presets),
            overlappingBudgetNames: overlaps
        )
    }

    /// All validation precedes insertion. A failed save discards only this batch's new graph.
    @discardableResult
    static func create(
        workspace: Workspace,
        preview: BudgetBatchPreview,
        cards: [Card],
        presets: [Preset],
        categories: [Category],
        categoryGoalDrafts: [UUID: CategoryGoalDraft],
        allowOverlaps: Bool,
        modelContext: ModelContext,
        save: (() throws -> Void)? = nil
    ) throws -> [Budget] {
        try validateDrafts(preview.drafts)
        guard cards.allSatisfy({ $0.workspace?.id == workspace.id }),
              presets.allSatisfy({ $0.workspace?.id == workspace.id }),
              categories.allSatisfy({ $0.workspace?.id == workspace.id }) else { throw CreationError.wrongWorkspace }
        let categoryIDs = Set(categories.map(\.id))
        guard categoryGoalDrafts.values.allSatisfy(\.isValid),
              Set(categoryGoalDrafts.filter { $0.value.hasValues }.keys).isSubset(of: categoryIDs),
              Set(cards.map(\.id)).count == cards.count,
              Set(presets.map(\.id)).count == presets.count else { throw CreationError.invalidInput }
        let activePresets = presets.filter { !$0.isArchived }
        guard activePresets.allSatisfy({ preset in
            preset.plannedAmount.isFinite && preset.plannedAmount > 0
                && (preset.defaultCard == nil || preset.defaultCard?.workspace?.id == workspace.id)
                && (preset.defaultCategory == nil || preset.defaultCategory?.workspace?.id == workspace.id)
        }) else { throw CreationError.invalidInput }

        let existing = try budgets(in: workspace, modelContext: modelContext)
        let overlaps = try overlappingNames(drafts: preview.drafts, existing: existing)
        let existingNames = Set(existing.map { normalizedName($0.name) })
        let currentPlannedCount = try plannedCount(drafts: preview.drafts, presets: activePresets)
        guard preview.drafts.allSatisfy({ !existingNames.contains(normalizedName($0.name)) }),
              overlaps == preview.overlappingBudgetNames,
              currentPlannedCount == preview.plannedExpenseCount else {
            throw CreationError.previewChanged
        }
        guard overlaps.isEmpty || allowOverlaps else { throw CreationError.overlapConfirmationRequired }

        let cardIDs = Set(cards.map(\.id))
        var created: [(budget: Budget, expenses: [PlannedExpense])] = []
        for draft in preview.drafts {
            let budget = Budget(name: draft.name, startDate: draft.startDate, endDate: draft.endDate, workspace: workspace)
            modelContext.insert(budget)
            BudgetCategoryGoalStore.apply(categoryGoalDrafts, categories: categories, budget: budget, workspaceID: workspace.id, modelContext: modelContext)
            for card in cards { modelContext.insert(BudgetCardLink(budget: budget, card: card)) }
            var expenses: [PlannedExpense] = []
            for preset in activePresets {
                modelContext.insert(BudgetPresetLink(budget: budget, preset: preset))
                let card = preset.defaultCard.flatMap { cardIDs.contains($0.id) ? $0 : nil }
                for date in PresetScheduleEngine.occurrences(for: preset, in: budget) {
                    let expense = PlannedExpense(
                        title: preset.title, plannedAmount: preset.plannedAmount, actualAmount: 0,
                        expenseDate: date, workspace: workspace, card: card, category: preset.defaultCategory,
                        sourcePresetID: preset.id, sourceBudgetID: budget.id
                    )
                    modelContext.insert(expense)
                    expenses.append(expense)
                }
            }
            created.append((budget, expenses))
        }
        do {
            try WorkspaceProgressService.saveCompleting([.budget], in: workspace) {
                if let save { try save() } else { try modelContext.save() }
            }
        } catch {
            for attempt in created {
                BudgetCreationAttemptCleanup.discard(budget: attempt.budget, createdPlannedExpenses: attempt.expenses, modelContext: modelContext)
            }
            throw error
        }
        return created.map(\.budget)
    }

    private static func budgets(in workspace: Workspace, modelContext: ModelContext) throws -> [Budget] {
        let workspaceID = workspace.id
        return try modelContext.fetch(FetchDescriptor<Budget>(predicate: #Predicate { $0.workspace?.id == workspaceID }))
    }

    private static func validateDrafts(_ drafts: [BudgetBatchDraft]) throws {
        guard (1...52).contains(drafts.count),
              drafts.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && $0.startDate.timeIntervalSinceReferenceDate.isFinite
                  && $0.endDate.timeIntervalSinceReferenceDate.isFinite
                  && $0.startDate <= $0.endDate }),
              Set(drafts.map { normalizedName($0.name) }).count == drafts.count else { throw CreationError.invalidInput }
        for pair in zip(drafts, drafts.dropFirst()) {
            guard Calendar.current.startOfDay(for: pair.0.endDate) < Calendar.current.startOfDay(for: pair.1.startDate) else {
                throw CreationError.invalidInput
            }
        }
    }

    private static func overlappingNames(drafts: [BudgetBatchDraft], existing: [Budget]) throws -> [String] {
        let calendar = Calendar.current
        var names = Set<String>()
        for draft in drafts {
            let start = calendar.startOfDay(for: draft.startDate)
            let end = calendar.startOfDay(for: draft.endDate)
            for budget in existing {
                let existingStart = calendar.startOfDay(for: budget.startDate)
                let existingEnd = calendar.startOfDay(for: budget.endDate)
                if start == existingStart && end == existingEnd { throw CreationError.duplicateDates }
                if start <= existingEnd && end >= existingStart { names.insert(budget.name) }
            }
        }
        return names.sorted()
    }

    private static func plannedCount(drafts: [BudgetBatchDraft], presets: [Preset]) throws -> Int {
        var count = 0
        for draft in drafts {
            for preset in presets where !preset.isArchived {
                count += PresetScheduleEngine.occurrences(for: preset, startDate: draft.startDate, endDate: draft.endDate).count
                guard count <= 10_000 else { throw CreationError.tooManyExpenses }
            }
        }
        return count
    }

    private static func normalizedName(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ").folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
