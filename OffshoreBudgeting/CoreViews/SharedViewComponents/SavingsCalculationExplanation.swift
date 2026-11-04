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
                explanation: "Expected income minus planned expenses at their planned amounts, after shared splits.",
                rows: [
                    .init(id: "income", title: "Planned Income", amount: plannedIncome),
                    .init(id: "planned", title: "Planned-expense allowance", amount: -plannedImpact),
                    .init(id: "total", title: "Projected Savings", amount: totals.projected, isTotal: true)
                ],
                notes: ["Variable expenses, Pay From Savings, and manual savings adjustments do not change this projection."]
            ),
            FinancialCalculationSection(
                id: "actual", title: "Actual Savings",
                explanation: "Received income minus the budget impact of planned and variable expenses, plus manual savings adjustments.",
                rows: [
                    .init(id: "income", title: "Actual Income", amount: actualIncome),
                    .init(id: "planned", title: "Planned-expense budget impact", amount: -effectiveImpact),
                    .init(id: "variable", title: "Variable-expense budget impact", amount: -variableImpact),
                    .init(id: "adjustments", title: "Manual savings adjustments", amount: adjustments),
                    .init(id: "total", title: "Actual Savings", amount: totals.actual, isTotal: true)
                ],
                notes: [
                    "A planned expense uses its actual amount when recorded; otherwise, its planned amount is still allowed for.",
                    "Shared splits and Pay From Savings reduce expense budget impact. Refunds reduce variable-expense impact; adjustments have no budget impact.",
                    "Set Aside as Savings reduces the Offshore Savings running balance and leaves Actual Savings unchanged.",
                    "These totals use the expenses included by this screen’s calculation settings. Hiding an expense does not by itself exclude it from totals."
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
            explanation: "The sum of this account’s savings ledger entries across all dates.",
            rows: [
                .init(id: "closes", title: "Completed-period savings", amount: periodCloses),
                .init(id: "adjustments", title: "Manual savings adjustments", amount: adjustments),
                .init(id: "payments", title: "Payments from savings", amount: expensePayments),
                .init(id: "total", title: "Running Total", amount: included.reduce(0) { $0 + $1.amount }, isTotal: true)
            ],
            notes: [
                "Automatic period closes follow your default budgeting period and its calendar dates. Individual custom budgets do not create separate deposits when they end.",
                "Pay From Savings reduces this available balance. The full purchase remains in your card history.",
                "Set Aside as Savings removes money you have reserved elsewhere from this available balance. Offshore records the change; it does not move money between bank accounts.",
                "In Current Period, the date filter limits ledger entries and the chart. Running Total always includes all dates."
            ]
        )]
    }
}
