import Foundation

struct HomeDashboardSnapshot {
    let plannedExpensesForHome: [PlannedExpense]
    let calculationPlannedExpensesForHome: [PlannedExpense]
    let calculationVariableExpensesForHome: [VariableExpense]
    let nextPlannedExpense: PlannedExpense?

    static let empty = HomeDashboardSnapshot(
        plannedExpensesForHome: [], calculationPlannedExpensesForHome: [],
        calculationVariableExpensesForHome: [], nextPlannedExpense: nil
    )

    static func prepare(from data: HomeDashboardData, now: Date, calendar: Calendar) -> Self {
        let budgetIDs = Set(data.budgets.filter { $0.workspace?.id == data.workspaceID }.map(\.id))
        let planned = data.plannedExpenses.filter {
            guard $0.workspace?.id == data.workspaceID else { return false }
            guard let sourceBudgetID = $0.sourceBudgetID else { return true }
            return budgetIDs.contains(sourceBudgetID)
        }
        let variable = data.variableExpenses.filter { $0.workspace?.id == data.workspaceID }
        return Self(
            plannedExpensesForHome: planned,
            calculationPlannedExpensesForHome: PlannedExpenseFuturePolicy.filteredForCalculations(
                planned, excludeFuture: data.excludeFuturePlannedExpenses, now: now, calendar: calendar
            ),
            calculationVariableExpensesForHome: VariableExpenseFuturePolicy.filteredForCalculations(
                variable, excludeFuture: data.excludeFutureVariableExpenses, now: now, calendar: calendar
            ),
            nextPlannedExpense: HomeNextPlannedExpenseFinder.nextExpense(
                from: planned, in: data.startDate, to: data.endDate, now: now, calendar: calendar
            )
        )
    }
}
