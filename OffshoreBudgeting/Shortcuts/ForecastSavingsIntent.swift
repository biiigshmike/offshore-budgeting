import AppIntents
import Foundation

// MARK: - ForecastSavingsIntent

struct ForecastSavingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Forecast Savings"
    static var description = IntentDescription("Return projected end-of-month savings and an overspend warning when applicable.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let summary = try await MainActor.run {
            try buildSummary()
        }

        return .result(
            value: summary,
            dialog: IntentDialog(stringLiteral: summary)
        )
    }

    // MARK: - Summary

    @MainActor
    private func buildSummary() throws -> String {
        let calendar = Calendar.current
        let now = Date.now
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart

        let totals = try OffshoreIntentDataStore.shared.performInSelectedWorkspace { _, workspace in
            savingsTotals(
                startDate: monthStart,
                endDate: monthEnd,
                incomes: workspace.incomes ?? [],
                plannedExpenses: workspace.plannedExpenses ?? [],
                variableExpenses: workspace.variableExpenses ?? []
            )
        }

        let projectedText = CurrencyFormatter.string(from: totals.projectedSavings)
        let actualText = CurrencyFormatter.string(from: totals.actualSavings)
        let gapText = CurrencyFormatter.string(from: totals.actualSavings - totals.projectedSavings)

        let statusLine: String
        if totals.projectedSavings < 0 {
            statusLine = "Warning: this month is forecast to overspend by \(CurrencyFormatter.string(from: abs(totals.projectedSavings)))."
        } else if totals.actualSavings < 0 {
            statusLine = "Warning: current actual savings are negative (\(actualText))."
        } else {
            statusLine = "Forecast is currently on track."
        }

        return [
            "Projected end-of-month savings: \(projectedText)",
            "Current actual savings: \(actualText)",
            "Gap vs projected: \(gapText)",
            statusLine
        ].joined(separator: "\n")
    }

    private func savingsTotals(
        startDate: Date,
        endDate: Date,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> (projectedSavings: Double, actualSavings: Double) {
        let plannedIncomeTotal = incomes
            .filter { $0.isPlanned && $0.date >= startDate && $0.date <= endDate }
            .reduce(0.0) { $0 + $1.amount }

        let actualIncomeTotal = incomes
            .filter { !$0.isPlanned && $0.date >= startDate && $0.date <= endDate }
            .reduce(0.0) { $0 + $1.amount }

        let plannedExpensesPlannedTotal = plannedExpenses
            .filter { $0.expenseDate >= startDate && $0.expenseDate <= endDate }
            .reduce(0.0) { $0 + $1.plannedAmount }

        let plannedExpensesEffectiveActualTotal = plannedExpenses
            .filter { $0.expenseDate >= startDate && $0.expenseDate <= endDate }
            .reduce(0.0) { $0 + $1.effectiveAmount() }

        let variableExpensesTotal = variableExpenses
            .filter { $0.transactionDate >= startDate && $0.transactionDate <= endDate }
            .reduce(0.0) { $0 + $1.amount }

        let projectedSavings = plannedIncomeTotal - plannedExpensesPlannedTotal
        let actualSavings = actualIncomeTotal - (plannedExpensesEffectiveActualTotal + variableExpensesTotal)
        return (projectedSavings, actualSavings)
    }
}
