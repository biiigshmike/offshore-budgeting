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
            var notes = [String(localized: "Category share: \(percentage). This category’s total divided by Total Spent gives its percentage. If Total Spent is zero or less, the share is 0%.")]
            notes.append(net > 0
                ? String(localized: "The chart shows only categories with a total above zero. Refunds in other categories can lower Total Spent and make a displayed share greater than 100%.")
                : String(localized: "This category is not shown in the chart because its total is zero or less. It still counts toward Total Spent, so refunds here can lower that total."))
            sections.append(FinancialCalculationSection(
                id: "category-\(category.id?.uuidString ?? "uncategorized")", title: String(localized: "Category Spending"),
                explanation: String(localized: "This category’s total includes Planned Expenses and Variable Expenses, minus shared expense amounts, Pay From Savings, and refunds."),
                rows: [
                    .init(id: "planned", title: String(localized: "Planned expenses counted in this total"), amount: category.planned),
                    .init(id: "variable", title: String(localized: "Variable expenses counted in this total"), amount: category.variable),
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
            String(localized: "Cards included: \(cardName)."),
            String(localized: "The chart shows only categories with a total above zero. Other groups the categories outside the top three for the full date range. Uncategorized is shown separately."),
            String(localized: "Each period below shows the same total as its chart bar. Expand it to see its categories and amounts not shown in the chart, such as categories with only refunds. These amounts still count toward Total Spent, so the chart can show a higher amount.")
        ]
        if let highest = result.highestBucket {
            sections[2].notes.append(String(localized: "Highest: \(highest.label), \(CurrencyFormatter.string(from: highest.total)). This period has the highest chart total above zero. If periods tie, the earliest one is shown."))
            if let top = result.topCategoryInHighestBucket {
                sections[2].notes.append(String(localized: "Top: \(top.name), \(CurrencyFormatter.string(from: top.amount)). This is the largest category shown in the Highest period. It can be Other or Uncategorized."))
            }
        } else {
            sections[2].notes.append(String(localized: "There is no Highest or Top label when every period’s chart total is zero."))
        }
        for bucket in result.buckets {
            let net = bucket.expenseItems.reduce(0) { $0 + $1.amount }
            let dates = "\(AppDateFormat.abbreviatedDate(bucket.start)) – \(AppDateFormat.abbreviatedDate(bucket.end))"
            let sliceRows = bucket.slices.enumerated().map { index, slice in
                FinancialCalculationRow(id: "slice-\(index)", title: slice.name, amount: slice.amount, titleIsVerbatim: true)
            }
            sections.append(FinancialCalculationSection(
                id: "bucket-\(bucket.id)", title: String(localized: "Spending by Category"),
                explanation: String(localized: "\(bucket.label): \(dates). The categories below add up to this period’s chart total."),
                rows: sliceRows + [
                    .init(id: "chart-total", title: String(localized: "Chart period total"), amount: bucket.total, isTotal: true)
                ]
            ))
            sections.append(FinancialCalculationSection(
                id: "bucket-net-\(bucket.id)", title: String(localized: "Why the chart and total can differ"),
                explanation: String(localized: "The chart leaves out categories whose totals are zero or less. Those amounts appear below to show what counts toward Total Spent."),
                rows: [
                    .init(id: "chart", title: String(localized: "Chart period total"), amount: bucket.total),
                    .init(id: "difference", title: String(localized: "Amounts not shown in the chart"), amount: net - bucket.total),
                    .init(id: "total", title: String(localized: "Amount counted toward Total Spent"), amount: net, isTotal: true)
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
                explanation: String(localized: "For each planned expense, an actual amount entered above zero takes the place of the planned amount. If it is blank or zero, the planned amount still counts. Amounts assigned to someone else and amounts covered by Pay From Savings are then taken off."),
                rows: [
                    .init(id: "gross", title: String(localized: "Planned expenses before deductions"), amount: plannedGross),
                    .init(id: "splits", title: String(localized: "Amounts assigned to someone else"), amount: plannedOwned - plannedGross),
                    .init(id: "savings", title: String(localized: "Amounts covered by Pay From Savings"), amount: plannedImpact - plannedOwned),
                    .init(id: "total", title: String(localized: "Planned expenses counted in this total"), amount: plannedImpact, isTotal: true)
                ], notes: [String(localized: "The starting amount is the full cost before shared expense amounts are taken off. Shared expenses and Pay From Savings cannot reduce an individual expense below zero.")]
            ),
            FinancialCalculationSection(
                id: "variable", title: String(localized: "Variable Expenses"),
                explanation: String(localized: "Variable Expenses include purchases you enter or import. This total includes those purchases, minus amounts assigned to someone else, amounts covered by Pay From Savings, and refunds."),
                rows: [
                    .init(id: "gross", title: String(localized: "Purchases before deductions"), amount: purchaseGross),
                    .init(id: "splits", title: String(localized: "Amounts assigned to someone else"), amount: purchaseOwned - purchaseGross),
                    .init(id: "savings", title: String(localized: "Amounts covered by Pay From Savings"), amount: purchaseImpact - purchaseOwned),
                    .init(id: "refunds", title: String(localized: "Refunds"), amount: refunds),
                    .init(id: "adjustments", title: String(localized: "Adjustments (not counted)"), amount: 0),
                    .init(id: "total", title: String(localized: "Variable expenses counted in this total"), amount: variableImpact, isTotal: true)
                ], notes: [String(localized: "Refunds lower this total. Adjustments stay in your history but do not change this total. Shared expenses and Pay From Savings cannot reduce an individual purchase below zero.")]
            ),
            FinancialCalculationSection(
                id: "total", title: String(localized: "Total Spent"),
                explanation: String(localized: "This total includes Planned Expenses and Variable Expenses for these dates, after shared expense amounts, Pay From Savings, and refunds are taken off. Planned expenses can include costs you have not recorded as paid yet."),
                rows: [
                    .init(id: "planned", title: String(localized: "Planned expenses counted in this total"), amount: plannedImpact),
                    .init(id: "variable", title: String(localized: "Variable expenses counted in this total"), amount: variableImpact),
                    .init(id: "total", title: String(localized: "Total Spent"), amount: plannedImpact + variableImpact, isTotal: true)
                ], notes: [String(localized: "Home’s calculation settings control which expenses count here. Hiding future expenses only removes them from the list. To leave them out of totals, exclude them from calculations.")]
            )
        ]
    }
}
