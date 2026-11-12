import Foundation

/// Uses the same scoped inputs and amount helpers as SavingsOutlookCalculator.
enum SavingsCalculationExplanation {
    static func outlook(
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        savingsEntries: [SavingsLedgerEntry],
        startDate: Date,
        endDate: Date
    ) -> [FinancialCalculationSection] {
        let income = incomes.filter { $0.date >= startDate && $0.date <= endDate }
        let planned = plannedExpenses.filter { $0.expenseDate >= startDate && $0.expenseDate <= endDate }
        let variable = variableExpenses.filter { $0.transactionDate >= startDate && $0.transactionDate <= endDate }
        let plannedIncome = income.filter(\.isPlanned).reduce(0) { $0 + $1.amount }
        let actualIncome = income.filter { !$0.isPlanned }.reduce(0) { $0 + $1.amount }
        let plannedImpact = planned.reduce(0) { $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) }
        let effectiveImpact = planned.reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
        let variableImpact = variable.reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let adjustments = SavingsMathService.actualSavingsAdjustmentTotal(
            from: savingsEntries, startDate: startDate, endDate: endDate
        )
        let totals = SavingsOutlookCalculator.totals(
            incomes: incomes, plannedExpenses: plannedExpenses, variableExpenses: variableExpenses,
            savingsEntries: savingsEntries, startDate: startDate, endDate: endDate
        )

        return [
            FinancialCalculationSection(
                id: "projected", title: "Projected Savings",
                explanation: "Start with the income you expect and subtract your share of the original planned costs.",
                rows: [
                    .init(id: "income", title: "Planned Income", amount: plannedIncome),
                    .init(id: "planned", title: "Your share of planned expenses", amount: -plannedImpact),
                    .init(id: "total", title: "Projected Savings", amount: totals.projected, isTotal: true)
                ],
                notes: ["This estimate does not include variable expenses, payments from savings, or changes you enter directly in Offshore Savings."]
            ),
            FinancialCalculationSection(
                id: "actual", title: "Actual Savings",
                explanation: "Money left from the income you’ve received, after expenses and amounts still planned for this period, plus or minus changes you enter in savings. This is separate from your Offshore Savings balance.",
                rows: [
                    .init(id: "income", title: "Actual Income", amount: actualIncome),
                    .init(id: "planned", title: "Planned expenses counted here", amount: -effectiveImpact),
                    .init(id: "variable", title: "Variable expenses counted here", amount: -variableImpact),
                    .init(id: "adjustments", title: "Changes you’ve entered", amount: adjustments),
                    .init(id: "total", title: "Actual Savings", amount: totals.actual, isTotal: true)
                ],
                notes: [
                    "For each planned expense, an actual amount entered above zero takes the place of the planned amount. Otherwise, the planned amount still counts.",
                    "Amounts assigned to someone else and amounts covered by Pay From Savings reduce the expenses counted here. Refunds reduce spending. Transactions marked Adjustment do not affect this total.",
                    "Set Aside as Savings lowers your available Offshore Savings balance. It does not change Actual Savings for this period.",
                    "Your calculation settings control which expenses count here. An expense can be hidden from the list and still count toward these totals."
                ]
            )
        ]
    }

    static func runningTotal(entries: [SavingsLedgerEntry]) -> [FinancialCalculationSection] {
        let included = entries.filter { $0.kind != .reconciliationSettlement }
        let periodCloses = included.filter { $0.kind == .periodClose }.reduce(0) { $0 + $1.amount }
        let adjustments = included.filter { $0.kind == .manualAdjustment }.reduce(0) { $0 + $1.amount }
        let expensePayments = included.filter { $0.kind == .expenseOffset }.reduce(0) { $0 + $1.amount }

        return [FinancialCalculationSection(
            id: "ledger", title: "Running Total",
            explanation: "Your available Offshore Savings balance, including all dates. This balance includes savings from completed budgeting periods and changes you’ve entered, minus amounts used through Pay From Savings or marked Set Aside as Savings.",
            rows: [
                .init(id: "closes", title: "Savings from completed periods", amount: periodCloses),
                .init(id: "adjustments", title: "Changes you’ve entered", amount: adjustments),
                .init(id: "payments", title: "Amounts used through Pay From Savings", amount: expensePayments),
                .init(id: "total", title: "Running Total", amount: included.reduce(0) { $0 + $1.amount }, isTotal: true)
            ],
            notes: [
                "Offshore calculates savings when your default budgeting period ends. Ending a custom budget does not add savings separately.",
                "Using Pay From Savings reduces your available savings. The full expense stays in your card history.",
                "Money you mark as saved elsewhere through Set Aside as Savings is taken out of this available balance. Offshore records this change; it does not transfer money between bank accounts.",
                "Running Total includes all dates, even when you’re viewing activity for a shorter period."
            ]
        )]
    }
}
