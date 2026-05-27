import Foundation
import SwiftData

struct MarinaWorkspaceSnapshot {
    let workspace: Workspace
    let budgets: [Budget]
    let cards: [Card]
    let categories: [Category]
    let presets: [Preset]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let homePlannedExpenses: [PlannedExpense]
    let homeCalculationPlannedExpenses: [PlannedExpense]
    let homeCalculationVariableExpenses: [VariableExpense]
    let reconciliationAccounts: [AllocationAccount]
    let expenseAllocations: [ExpenseAllocation]
    let allocationSettlements: [AllocationSettlement]
    let savingsAccounts: [SavingsAccount]
    let savingsEntries: [SavingsLedgerEntry]
    let incomes: [Income]
}

@MainActor
struct MarinaWorkspaceSnapshotProvider {
    func snapshot(
        for workspace: Workspace,
        modelContext: ModelContext,
        homeContext: MarinaPanelHomeContext? = nil,
        now: Date = Date()
    ) throws -> MarinaWorkspaceSnapshot {
        let workspaceID = workspace.id

        let budgets = try modelContext.fetch(
            FetchDescriptor<Budget>(
                predicate: #Predicate<Budget> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Budget.startDate, order: .reverse)]
            )
        )
        let cards = try modelContext.fetch(
            FetchDescriptor<Card>(
                predicate: #Predicate<Card> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Card.name, order: .forward)]
            )
        )
        let categories = try modelContext.fetch(
            FetchDescriptor<Category>(
                predicate: #Predicate<Category> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Category.name, order: .forward)]
            )
        )
        let presets = try modelContext.fetch(
            FetchDescriptor<Preset>(
                predicate: #Predicate<Preset> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Preset.title, order: .forward)]
            )
        )
        let plannedExpenses = try modelContext.fetch(
            FetchDescriptor<PlannedExpense>(
                predicate: #Predicate<PlannedExpense> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\PlannedExpense.expenseDate, order: .forward)]
            )
        )
        let variableExpenses = try modelContext.fetch(
            FetchDescriptor<VariableExpense>(
                predicate: #Predicate<VariableExpense> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\VariableExpense.transactionDate, order: .forward)]
            )
        )
        let reconciliationAccounts = try modelContext.fetch(
            FetchDescriptor<AllocationAccount>(
                predicate: #Predicate<AllocationAccount> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\AllocationAccount.name, order: .forward)]
            )
        )
        let expenseAllocations = try modelContext.fetch(
            FetchDescriptor<ExpenseAllocation>(
                predicate: #Predicate<ExpenseAllocation> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\ExpenseAllocation.createdAt, order: .forward)]
            )
        )
        let allocationSettlements = try modelContext.fetch(
            FetchDescriptor<AllocationSettlement>(
                predicate: #Predicate<AllocationSettlement> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\AllocationSettlement.date, order: .forward)]
            )
        )
        let savingsAccounts = try modelContext.fetch(
            FetchDescriptor<SavingsAccount>(
                predicate: #Predicate<SavingsAccount> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\SavingsAccount.name, order: .forward)]
            )
        )
        let savingsEntries = try modelContext.fetch(
            FetchDescriptor<SavingsLedgerEntry>(
                predicate: #Predicate<SavingsLedgerEntry> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .forward)]
            )
        )
        let incomes = try modelContext.fetch(
            FetchDescriptor<Income>(
                predicate: #Predicate<Income> { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Income.date, order: .forward)]
            )
        )
        let existingBudgetIDs = Set(budgets.map(\.id))
        let homePlannedExpenses = plannedExpenses.filter { expense in
            guard let sourceBudgetID = expense.sourceBudgetID else {
                return true
            }
            return existingBudgetIDs.contains(sourceBudgetID)
        }
        let homeCalculationPlannedExpenses = PlannedExpenseFuturePolicy.filteredForCalculations(
            homePlannedExpenses,
            excludeFuture: homeContext?.excludeFuturePlannedExpensesFromCalculations ?? false,
            now: now
        )
        let homeCalculationVariableExpenses = VariableExpenseFuturePolicy.filteredForCalculations(
            variableExpenses,
            excludeFuture: homeContext?.excludeFutureVariableExpensesFromCalculations ?? false,
            now: now
        )

        return MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: budgets,
            cards: cards,
            categories: categories,
            presets: presets,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            homePlannedExpenses: homePlannedExpenses,
            homeCalculationPlannedExpenses: homeCalculationPlannedExpenses,
            homeCalculationVariableExpenses: homeCalculationVariableExpenses,
            reconciliationAccounts: reconciliationAccounts,
            expenseAllocations: expenseAllocations,
            allocationSettlements: allocationSettlements,
            savingsAccounts: savingsAccounts,
            savingsEntries: savingsEntries,
            incomes: incomes
        )
    }
}
