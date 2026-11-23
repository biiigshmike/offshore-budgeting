import Foundation
import SwiftData

@MainActor
enum BudgetPresetApplicationService {
    enum Result: Equatable {
        case applied
        case alreadyLinked
        case ineligible
    }

    private enum StagedApplication {
        case created(link: BudgetPresetLink, expenses: [PlannedExpense])
        case alreadyLinked
        case ineligible
    }

    static func canLink(_ preset: Preset, to budget: Budget, in workspace: Workspace) -> Bool {
        !preset.isDeleted && !budget.isDeleted
            && preset.workspace?.id == workspace.id && budget.workspace?.id == workspace.id
    }

    static func isLinked(_ preset: Preset, to budget: Budget) -> Bool {
        (budget.presetLinks ?? []).contains { !$0.isDeleted && $0.preset?.id == preset.id }
    }

    static func isEligibleForOffer(_ preset: Preset, in budget: Budget, workspace: Workspace) -> Bool {
        guard canLink(preset, to: budget, in: workspace), !preset.isArchived,
              !isLinked(preset, to: budget),
              matchingCard(for: preset, in: workspace, linkedCardIDs: linkedCardIDs(for: budget)) != nil
        else { return false }

        return !PresetScheduleEngine.occurrences(for: preset, in: budget).isEmpty
    }

    static func apply(
        _ preset: Preset,
        to budget: Budget,
        in workspace: Workspace,
        requiresMatchingCardAndDates: Bool,
        modelContext: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Result {
        try apply(preset, to: [budget], in: workspace, requiresMatchingCardAndDates: requiresMatchingCardAndDates,
                  modelContext: modelContext, save: save)
    }

    static func apply(
        _ preset: Preset,
        to budgets: [Budget],
        in workspace: Workspace,
        requiresMatchingCardAndDates: Bool,
        modelContext: ModelContext,
        save: (ModelContext) throws -> Void = { try $0.save() }
    ) throws -> Result {
        guard !budgets.isEmpty else { return .ineligible }
        var newLinks: [BudgetPresetLink] = []
        var newExpenses: [PlannedExpense] = []
        var didSave = false
        defer {
            if !didSave {
                // Discard only the rows staged by this attempt.
                newExpenses.forEach { modelContext.delete($0) }
                newLinks.forEach { modelContext.delete($0) }
            }
        }

        for budget in budgets {
            let application = try stageApplication(
                preset, to: budget, in: workspace, requiresMatchingCardAndDates: requiresMatchingCardAndDates,
                modelContext: modelContext
            )
            switch application {
            case .created(let link, let expenses):
                newLinks.append(link)
                newExpenses.append(contentsOf: expenses)
            case .alreadyLinked:
                continue
            case .ineligible:
                return .ineligible
            }
        }

        guard !newLinks.isEmpty else { return .alreadyLinked }
        try save(modelContext)
        didSave = true
        return .applied
    }

    private static func stageApplication(
        _ preset: Preset,
        to budget: Budget,
        in workspace: Workspace,
        requiresMatchingCardAndDates: Bool,
        modelContext: ModelContext
    ) throws -> StagedApplication {
        guard canLink(preset, to: budget, in: workspace) else { return .ineligible }
        guard !isLinked(preset, to: budget) else { return .alreadyLinked }
        guard !preset.isArchived else { return .ineligible }

        let cardIDs = linkedCardIDs(for: budget)
        guard !cardIDs.isEmpty else { return .ineligible }
        let dates = PresetScheduleEngine.occurrences(for: preset, in: budget)
        let card = matchingCard(for: preset, in: workspace, linkedCardIDs: cardIDs)
        if requiresMatchingCardAndDates && (card == nil || dates.isEmpty) {
            return .ineligible
        }

        let existingDates = dates.isEmpty ? [] : try existingOccurrenceDays(
            workspaceID: workspace.id, budgetID: budget.id, presetID: preset.id, modelContext: modelContext
        )
        let link = BudgetPresetLink(budget: budget, preset: preset)
        modelContext.insert(link)

        let newExpenses = dates.filter { !existingDates.contains($0) }.map { date in
            let expense = PlannedExpense(
                title: preset.title,
                plannedAmount: preset.plannedAmount,
                actualAmount: 0,
                expenseDate: date,
                workspace: workspace,
                card: card,
                category: preset.defaultCategory,
                sourcePresetID: preset.id,
                sourceBudgetID: budget.id
            )
            modelContext.insert(expense)
            return expense
        }

        return .created(link: link, expenses: newExpenses)
    }

    private static func linkedCardIDs(for budget: Budget) -> Set<UUID> {
        Set((budget.cardLinks ?? []).lazy.filter { !$0.isDeleted }.compactMap { $0.card?.id })
    }

    private static func matchingCard(for preset: Preset, in workspace: Workspace, linkedCardIDs: Set<UUID>) -> Card? {
        guard let card = preset.defaultCard, !card.isDeleted, card.workspace?.id == workspace.id,
              linkedCardIDs.contains(card.id) else { return nil }
        return card
    }

    private static func existingOccurrenceDays(
        workspaceID: UUID,
        budgetID: UUID,
        presetID: UUID,
        modelContext: ModelContext
    ) throws -> Set<Date> {
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate {
                $0.workspace?.id == workspaceID && $0.sourceBudgetID == budgetID && $0.sourcePresetID == presetID
            }
        )
        let calendar = Calendar.current
        let expenses = try modelContext.fetch(descriptor)
        return Set(expenses.lazy.filter { !$0.isDeleted }.map { calendar.startOfDay(for: $0.expenseDate) })
    }
}
