import Foundation
import SwiftData

@MainActor
enum BudgetCategoryGoalStore {
    /// Shared on-demand history lookup for creation and existing-budget editors.
    static func maximumSuggestions(
        workspace: Workspace, categories: [Category], startDate: Date, endDate: Date,
        excludingBudgetID: UUID? = nil, modelContext: ModelContext
    ) throws -> [UUID: CategoryGoalSuggestion] {
        let workspaceID = workspace.id
        let cutoff = min(Calendar.current.startOfDay(for: startDate), Calendar.current.startOfDay(for: .now))
        let budgets = try modelContext.fetch(FetchDescriptor<Budget>(predicate: #Predicate {
            $0.workspace?.id == workspaceID && $0.startDate < cutoff
        }))
        let planned = try modelContext.fetch(FetchDescriptor<PlannedExpense>(predicate: #Predicate {
            $0.workspace?.id == workspaceID && $0.expenseDate < cutoff
        }))
        let variable = try modelContext.fetch(FetchDescriptor<VariableExpense>(predicate: #Predicate {
            $0.workspace?.id == workspaceID && $0.transactionDate < cutoff
        }))
        let settings = workspace.categoryGoalAutoConfiguration
        return CategoryGoalSuggestionCalculator.calculate(
            workspaceID: workspaceID,
            budgets: budgets.filter { $0.id != excludingBudgetID },
            categories: categories,
            plannedExpenses: planned,
            variableExpenses: variable,
            startDate: startDate,
            endDate: endDate,
            historyCount: settings.historyCount,
            cushionPercent: settings.cushionPercent
        )
    }

    /// Previews only spending that will participate in the new budget's category totals.
    static func plannedContributions(
        presets: [Preset],
        selectedPresetIDs: Set<UUID>,
        selectedCardIDs: Set<UUID>,
        workspaceID: UUID,
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) -> [UUID: Double] {
        var totals: [UUID: Double] = [:]
        for preset in presets {
            guard selectedPresetIDs.contains(preset.id), !preset.isArchived,
                  preset.workspace?.id == workspaceID,
                  let card = preset.defaultCard, card.workspace?.id == workspaceID,
                  selectedCardIDs.contains(card.id),
                  let category = preset.defaultCategory, category.workspace?.id == workspaceID else { continue }
            let count = PresetScheduleEngine.occurrences(
                for: preset, startDate: startDate, endDate: endDate, calendar: calendar
            ).count
            guard count > 0 else { continue }
            totals[category.id, default: 0] += preset.plannedAmount * Double(count)
        }
        return totals
    }

    static func drafts(for budget: Budget) -> [UUID: CategoryGoalDraft] {
        var result: [UUID: CategoryGoalDraft] = [:]
        for goal in budget.categoryLimits ?? [] {
            guard let category = goal.category,
                  category.workspace?.id == budget.workspace?.id,
                  result[category.id] == nil else { continue }
            result[category.id] = CategoryGoalDraft(minimum: goal.minAmount, maximum: goal.maxAmount)
        }
        return result
    }

    /// Applies only explicitly supplied categories in this budget's workspace.
    /// Other budgets, hidden categories, and historical expenses are untouched.
    @discardableResult
    static func apply(
        _ drafts: [UUID: CategoryGoalDraft],
        categories: [Category],
        budget: Budget,
        workspaceID: UUID,
        modelContext: ModelContext
    ) -> Bool {
        guard budget.workspace?.id == workspaceID, drafts.values.allSatisfy(\.isValid) else { return false }

        for category in categories where category.workspace?.id == workspaceID {
            guard let draft = drafts[category.id] else { continue }
            let existing = (budget.categoryLimits ?? []).first { $0.category?.id == category.id }

            if let existing {
                if !draft.hasValues {
                    modelContext.delete(existing)
                } else {
                    existing.minAmount = draft.minimum
                    existing.maxAmount = draft.maximum
                }
            } else if draft.hasValues {
                modelContext.insert(BudgetCategoryLimit(
                    minAmount: draft.minimum,
                    maxAmount: draft.maximum,
                    budget: budget,
                    category: category
                ))
            }
        }
        return true
    }
}
