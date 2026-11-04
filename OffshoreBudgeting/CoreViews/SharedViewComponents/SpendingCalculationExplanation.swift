import Foundation

/// Explains the originating Home screen's supplied calculation inputs without changing its math.
enum SpendingCalculationExplanation {
    static func spotlight(
        plannedExpenses: [PlannedExpense], variableExpenses: [VariableExpense],
        startDate: Date, endDate: Date
    ) -> [FinancialCalculationSection] {
        let planned = plannedExpenses.filter { $0.expenseDate >= startDate && $0.expenseDate <= endDate }
        let variable = variableExpenses.filter { $0.transactionDate >= startDate && $0.transactionDate <= endDate }
        var sections = spending(planned: planned, variable: variable)
        let total = planned.reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
            + variable.reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let categoryIDs = Set(planned.map { $0.category?.id }).union(variable.map { $0.category?.id })
        let categories = categoryIDs.map { id in
            let categoryPlanned = planned.filter { $0.category?.id == id }
            let categoryVariable = variable.filter { $0.category?.id == id }
            let name = categoryPlanned.first?.category?.name ?? categoryVariable.first?.category?.name
                ?? String(localized: "Uncategorized")
            let plannedImpact = categoryPlanned.reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
            let variableImpact = categoryVariable.reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
            return (id: id, name: name, planned: plannedImpact, variable: variableImpact)
        }.sorted { lhs, rhs in
            let left = lhs.planned + lhs.variable
            let right = rhs.planned + rhs.variable
            if left != right { return left > right }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
        for category in categories {
            let net = category.planned + category.variable
            let percentage = (total > 0 ? net / total : 0).formatted(.percent.precision(.fractionLength(0)))
            var notes = [String(localized: "Category share: \(percentage). Category net spending ÷ overall net spending × 100. When the overall total is zero or negative, the share is zero.")]
            notes.append(net > 0
                ? String(localized: "Only categories with positive net spending appear in the chart. Refunds in other categories can make a displayed share greater than 100%.")
                : String(localized: "This category is omitted from the chart because its net spending is zero or negative. Its signed amount still contributes to Total Spent."))
            sections.append(FinancialCalculationSection(
                id: "category-\(category.id?.uuidString ?? "uncategorized")", title: String(localized: "Category Spending"),
                explanation: String(localized: "Planned budget impact plus variable budget impact for this category."),
                rows: [
                    .init(id: "planned", title: String(localized: "Planned-expense budget impact"), amount: category.planned),
                    .init(id: "variable", title: String(localized: "Variable-expense budget impact"), amount: category.variable),
                    .init(id: "total", title: category.name, amount: net, isTotal: true, titleIsVerbatim: true)
                ], notes: notes
            ))
        }
        return sections
    }

    static func trends(
        result: HomeSpendTrendsAggregator.Result, card: Card?,
        plannedExpenses: [PlannedExpense], variableExpenses: [VariableExpense]
    ) -> [FinancialCalculationSection] {
        let planned = plannedExpenses.filter {
            $0.expenseDate >= result.resolvedStart && $0.expenseDate <= result.resolvedEnd
                && (card == nil || $0.card?.id == card?.id)
        }
        let variable = variableExpenses.filter {
            $0.transactionDate >= result.resolvedStart && $0.transactionDate <= result.resolvedEnd
                && (card == nil || $0.card?.id == card?.id)
        }
        var sections = spending(planned: planned, variable: variable)
        let cardName = card?.name ?? String(localized: "All Cards")
        sections[2].notes += [
            String(localized: "Card filter: \(cardName)."),
            String(localized: "The chart keeps positive category totals only. Other combines positive categories outside the overall top three; Uncategorized is separate."),
            String(localized: "Each period’s collapsed total matches its chart bar. Expand a period to see its categories and signed impact omitted from the chart, including refund-only categories. Net expense impacts across all periods add up to Total Spent; displayed chart totals can be higher.")
        ]
        if let highest = result.highestBucket {
            sections[2].notes.append(String(localized: "Highest: \(highest.label), \(CurrencyFormatter.string(from: highest.total)). This is the largest positive spending period in the chart; equal totals use the earliest period."))
            if let top = result.topCategoryInHighestBucket {
                sections[2].notes.append(String(localized: "Top: \(top.name), \(CurrencyFormatter.string(from: top.amount)). This is the largest displayed category in the highest spending period, which may be Other or Uncategorized."))
            }
        } else {
            sections[2].notes.append(String(localized: "There is no Highest or Top callout when no spending period has a positive chart total."))
        }
        for bucket in result.buckets {
            let net = bucket.expenseItems.reduce(0) { $0 + $1.amount }
            let dates = "\(AppDateFormat.abbreviatedDate(bucket.start)) – \(AppDateFormat.abbreviatedDate(bucket.end))"
            let sliceRows = bucket.slices.enumerated().map { index, slice in
                FinancialCalculationRow(id: "slice-\(index)", title: slice.name, amount: slice.amount, titleIsVerbatim: true)
            }
            sections.append(FinancialCalculationSection(
                id: "bucket-\(bucket.id)", title: String(localized: "Spending by Category"),
                explanation: String(localized: "\(bucket.label): \(dates). The displayed categories below add up to the chart total for this period."),
                rows: sliceRows + [
                    .init(id: "chart-total", title: String(localized: "Chart period total"), amount: bucket.total, isTotal: true)
                ]
            ))
            sections.append(FinancialCalculationSection(
                id: "bucket-net-\(bucket.id)", title: String(localized: "Period Reconciliation"),
                explanation: String(localized: "How the chart total compares with your net spending."),
                rows: [
                    .init(id: "chart", title: String(localized: "Chart period total"), amount: bucket.total),
                    .init(id: "difference", title: String(localized: "Net impact omitted from chart"), amount: net - bucket.total),
                    .init(id: "total", title: String(localized: "Net expense impact"), amount: net, isTotal: true)
                ]
            ))
        }
        return sections
    }

    static func trendPeriods(
        result: HomeSpendTrendsAggregator.Result, sections: [FinancialCalculationSection]
    ) -> [FinancialCalculationDisclosure] {
        result.buckets.map { period in
            let dates = "\(AppDateFormat.abbreviatedDate(period.start)) – \(AppDateFormat.abbreviatedDate(period.end))"
            return FinancialCalculationDisclosure(
                id: "period-\(period.id)", sectionTitle: String(localized: "Spending Periods"),
                summary: .init(id: "summary", title: dates, amount: period.total, isTotal: true, titleIsVerbatim: true),
                sections: sections.filter { $0.id == "bucket-\(period.id)" || $0.id == "bucket-net-\(period.id)" }
            )
        }
    }

    private static func spending(
        planned: [PlannedExpense], variable: [VariableExpense]
    ) -> [FinancialCalculationSection] {
        let plannedGross = planned.reduce(0) { $0 + SavingsMathService.grossEffectiveAmount(for: $1) }
        let plannedOwned = planned.reduce(0) { $0 + SavingsMathService.ownedEffectiveAmount(for: $1) }
        let plannedImpact = planned.reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
        let debits = variable.filter { $0.kind == .debit }
        let purchaseGross = debits.reduce(0) { $0 + SavingsMathService.variableGrossAmount(for: $1) }
        let purchaseOwned = debits.reduce(0) { $0 + SavingsMathService.ownedAmount(for: $1) }
        let purchaseImpact = debits.reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let refunds = variable.filter { $0.kind == .credit }.reduce(0) {
            $0 + SavingsMathService.variableBudgetImpactAmount(for: $1)
        }
        let variableImpact = purchaseImpact + refunds
        return [
            FinancialCalculationSection(
                id: "planned", title: String(localized: "Planned Expenses"),
                explanation: String(localized: "Start with each expense’s recorded actual amount when greater than zero; otherwise use its planned amount. Subtract applied shared splits, then applied Pay From Savings."),
                rows: [
                    .init(id: "gross", title: String(localized: "Effective planned amounts"), amount: plannedGross),
                    .init(id: "splits", title: String(localized: "Shared split reductions"), amount: plannedOwned - plannedGross),
                    .init(id: "savings", title: String(localized: "Pay From Savings reductions"), amount: plannedImpact - plannedOwned),
                    .init(id: "total", title: String(localized: "Planned-expense budget impact"), amount: plannedImpact, isTotal: true)
                ], notes: [String(localized: "Reductions are applied per expense and capped at its remaining amount, so purchase impact cannot fall below zero. The starting amount is the full expense before shared splits.")]
            ),
            FinancialCalculationSection(
                id: "variable", title: String(localized: "Variable Expenses"),
                explanation: String(localized: "Start with debit purchases, subtract applied shared splits and Pay From Savings, then include refunds as signed reductions."),
                rows: [
                    .init(id: "gross", title: String(localized: "Debit purchase amounts"), amount: purchaseGross),
                    .init(id: "splits", title: String(localized: "Shared split reductions"), amount: purchaseOwned - purchaseGross),
                    .init(id: "savings", title: String(localized: "Pay From Savings reductions"), amount: purchaseImpact - purchaseOwned),
                    .init(id: "refunds", title: String(localized: "Refunds"), amount: refunds),
                    .init(id: "adjustments", title: String(localized: "Adjustment budget impact"), amount: 0),
                    .init(id: "total", title: String(localized: "Variable-expense budget impact"), amount: variableImpact, isTotal: true)
                ], notes: [String(localized: "Refunds use their signed ledger amount. Adjustments remain in history and contribute zero budget impact. Purchase reductions are capped per expense.")]
            ),
            FinancialCalculationSection(
                id: "total", title: String(localized: "Total Spent"),
                explanation: String(localized: "Add planned-expense budget impact and signed variable-expense budget impact for the included dates."),
                rows: [
                    .init(id: "planned", title: String(localized: "Planned-expense budget impact"), amount: plannedImpact),
                    .init(id: "variable", title: String(localized: "Variable-expense budget impact"), amount: variableImpact),
                    .init(id: "total", title: String(localized: "Total Spent"), amount: plannedImpact + variableImpact, isTotal: true)
                ], notes: [String(localized: "These are the expenses included by Home’s calculation settings. Hiding future expenses alone does not exclude them from totals; excluding them from calculations does.")]
            )
        ]
    }
}
