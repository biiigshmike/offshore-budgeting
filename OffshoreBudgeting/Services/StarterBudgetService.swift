import Foundation
import SwiftData

enum StarterBudgetService {
    @discardableResult
    static func createIfNeeded(
        in workspace: Workspace,
        defaultBudgetingPeriodRaw: String,
        modelContext: ModelContext,
        calendar: Calendar = .current,
        now: Date = .now
    ) throws -> Budget? {
        guard try hasNoBudgets(in: workspace, modelContext: modelContext) else {
            return nil
        }

        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let range = period.defaultRange(containing: now, calendar: calendar)
        let budget = Budget(
            name: BudgetNameSuggestion.suggestedName(
                start: range.start,
                end: range.end,
                calendar: calendar
            ),
            startDate: range.start,
            endDate: range.end,
            workspace: workspace
        )
        modelContext.insert(budget)

        let workspaceID = workspace.id
        let cardsDescriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sortBy: [SortDescriptor(\Card.name, order: .forward)]
        )
        let presetsDescriptor = FetchDescriptor<Preset>(
            predicate: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sortBy: [SortDescriptor(\Preset.title, order: .forward)]
        )

        let cards = try modelContext.fetch(cardsDescriptor)
        let presets = try modelContext.fetch(presetsDescriptor).filter { !$0.isArchived }

        for card in cards {
            modelContext.insert(BudgetCardLink(budget: budget, card: card))
        }

        for preset in presets {
            modelContext.insert(BudgetPresetLink(budget: budget, preset: preset))
            let dates = PresetScheduleEngine.occurrences(for: preset, in: budget, calendar: calendar)

            for date in dates {
                let plannedExpense = PlannedExpense(
                    title: preset.title,
                    plannedAmount: preset.plannedAmount,
                    actualAmount: 0,
                    expenseDate: date,
                    workspace: workspace,
                    card: preset.defaultCard,
                    category: preset.defaultCategory,
                    sourcePresetID: preset.id,
                    sourceBudgetID: budget.id
                )
                modelContext.insert(plannedExpense)
            }
        }

        try modelContext.save()
        return budget
    }

    private static func hasNoBudgets(in workspace: Workspace, modelContext: ModelContext) throws -> Bool {
        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate<Budget> { $0.workspace?.id == workspaceID }
        )
        return try modelContext.fetchCount(descriptor) == 0
    }
}

@MainActor
enum BudgetDeletionService {
    static func deleteBudgetOnly(_ budget: Budget, modelContext: ModelContext) throws {
        modelContext.delete(budget)
        try modelContext.save()
    }

    static func deleteBudgetAndGeneratedPlannedExpenses(_ budget: Budget, modelContext: ModelContext) throws {
        let budgetID: UUID? = budget.id
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID
            }
        )

        let expenses = try modelContext.fetch(descriptor)
        for expense in expenses {
            PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        }

        modelContext.delete(budget)
        try modelContext.save()
    }
}
