import Foundation

/// The savings outlook is a flow for the selected dates, not a savings-account balance.
/// Callers provide workspace-scoped expenses after applying their future-expense policy.
enum SavingsOutlookCalculator {
    struct Summary: Equatable, Sendable {
        let actual: Double
        let projected: Double
        var gap: Double { actual - projected }
    }

    struct Progress: Equatable, Sendable {
        enum Mode: String, Codable, Sendable { case projection, breakEven, unavailable }
        let mode: Mode
        /// Keep the real ratio, including negative values and values above one.
        let ratio: Double?
        var gaugeValue: Double { min(max(ratio ?? 0, 0), 1) }
        var formatted: String { ratio?.formatted(.percent.precision(.fractionLength(0))) ?? "—" }
    }

    struct Point: Equatable, Sendable {
        let startDate: Date
        let endDate: Date
        let actual: Double
        let projected: Double
    }

    static func totals(incomes: [Income], plannedExpenses: [PlannedExpense],
                       variableExpenses: [VariableExpense], savingsEntries: [SavingsLedgerEntry],
                       startDate: Date, endDate: Date) -> Summary {
        let income = incomes.filter { $0.date >= startDate && $0.date <= endDate }
        let planned = plannedExpenses.filter { $0.expenseDate >= startDate && $0.expenseDate <= endDate }
        let variable = variableExpenses.filter { $0.transactionDate >= startDate && $0.transactionDate <= endDate }
        let expectedIncome = income.filter(\.isPlanned).reduce(0) { $0 + $1.amount }
        let receivedIncome = income.filter { !$0.isPlanned }.reduce(0) { $0 + $1.amount }
        let expectedExpenses = planned.reduce(0) { $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) }
        let effectiveExpenses = planned.reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
        let variableImpact = variable.reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let adjustments = SavingsMathService.actualSavingsAdjustmentTotal(
            from: savingsEntries, startDate: startDate, endDate: endDate)
        return Summary(actual: receivedIncome - effectiveExpenses - variableImpact + adjustments,
                       projected: expectedIncome - expectedExpenses)
    }

    static func progress(projected: Double, actual: Double) -> Progress {
        guard projected != 0 else { return .init(mode: .unavailable, ratio: nil) }
        if projected > 0 { return .init(mode: .projection, ratio: actual / projected) }
        return .init(mode: .breakEven, ratio: (actual - projected) / abs(projected))
    }

    /// Ranges are inclusive, ordered, disjoint buckets within the selected period.
    /// Each running value uses the same calculation as the headline, including manual adjustments.
    static func cumulativePoints(ranges: [HomeQueryDateRange], incomes: [Income],
                                 plannedExpenses: [PlannedExpense], variableExpenses: [VariableExpense],
                                 savingsEntries: [SavingsLedgerEntry]) -> [Point] {
        var actual = 0.0
        var projected = 0.0
        return ranges.map { range in
            let total = totals(incomes: incomes, plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses, savingsEntries: savingsEntries,
                startDate: range.startDate, endDate: range.endDate)
            actual += total.actual
            projected += total.projected
            return Point(startDate: range.startDate, endDate: range.endDate, actual: actual, projected: projected)
        }
    }
}
