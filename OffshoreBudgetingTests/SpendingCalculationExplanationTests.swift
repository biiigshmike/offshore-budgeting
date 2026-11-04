import Foundation
import Testing
@testable import Offshore

@MainActor
struct SpendingCalculationExplanationTests {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let end = Date(timeIntervalSince1970: 2_000)

    @Test func stepsReconcileActualFallbackSplitsOffsetsRefundsAndAdjustments() throws {
        let account = AllocationAccount(name: "Shared")
        let actual = PlannedExpense(title: "Actual", plannedAmount: 150, actualAmount: 100, expenseDate: start)
        actual.allocation = ExpenseAllocation(allocatedAmount: 30, preservesGrossAmount: true, account: account, plannedExpense: actual)
        actual.savingsLedgerEntry = offset(200)
        let fallback = PlannedExpense(title: "Fallback", plannedAmount: 40, expenseDate: end)
        let purchase = VariableExpense(descriptionText: "Purchase", amount: 100, transactionDate: start)
        purchase.allocation = ExpenseAllocation(allocatedAmount: 20, preservesGrossAmount: true, account: account, expense: purchase)
        purchase.savingsLedgerEntry = offset(200)
        let refund = VariableExpense(descriptionText: "Refund", amount: 15, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: end)
        let adjustment = VariableExpense(descriptionText: "Adjustment", amount: 999, kindRaw: VariableExpenseKind.adjustment.rawValue, transactionDate: start)
        let outside = PlannedExpense(title: "Outside", plannedAmount: 999, expenseDate: end.addingTimeInterval(1))
        let outsideVariable = VariableExpense(descriptionText: "Outside", amount: 999, transactionDate: start.addingTimeInterval(-1))
        let planned = [actual, fallback, outside]
        let variable = [purchase, refund, adjustment, outsideVariable]
        let sections = SpendingCalculationExplanation.spotlight(
            plannedExpenses: planned, variableExpenses: variable, startDate: start, endDate: end
        )
        #expect(try amount(sections, "planned", "gross") == 140)
        #expect(try amount(sections, "planned", "splits") == -30)
        #expect(try amount(sections, "planned", "savings") == -70)
        #expect(try amount(sections, "variable", "gross") == 100)
        #expect(try amount(sections, "variable", "splits") == -20)
        #expect(try amount(sections, "variable", "savings") == -80)
        #expect(try amount(sections, "variable", "refunds") == -15)
        #expect(try amount(sections, "variable", "adjustments") == 0)
        let calculated = HomeCategoryMetricsCalculator.calculate(
            categories: [], plannedExpenses: planned, variableExpenses: variable, rangeStart: start, rangeEnd: end
        )
        #expect(try amount(sections, "total", "total") == calculated.totalSpent)
        #expect(calculated.totalSpent == 25)
        #expect(sections.contains { $0.id == "category-uncategorized" })
        try expectReconciled(sections)
    }

    @Test func legacyGrossRestorationAndOversizedSplitsReconcile() throws {
        let account = AllocationAccount(name: "Shared")
        let planned = PlannedExpense(title: "Legacy", plannedAmount: 100, actualAmount: 60, expenseDate: start)
        planned.allocation = ExpenseAllocation(allocatedAmount: 40, preservesGrossAmount: false, account: account, plannedExpense: planned)
        let variable = VariableExpense(descriptionText: "Legacy", amount: 60, transactionDate: start)
        variable.allocation = ExpenseAllocation(allocatedAmount: 40, preservesGrossAmount: false, account: account, expense: variable)
        let capped = VariableExpense(descriptionText: "Capped", amount: 10, transactionDate: start)
        capped.allocation = ExpenseAllocation(allocatedAmount: 20, preservesGrossAmount: true, account: account, expense: capped)
        let sections = SpendingCalculationExplanation.spotlight(
            plannedExpenses: [planned], variableExpenses: [variable, capped], startDate: start, endDate: end
        )
        #expect(try amount(sections, "planned", "gross") == 100)
        #expect(try amount(sections, "planned", "total") == 60)
        #expect(try amount(sections, "variable", "gross") == 110)
        #expect(try amount(sections, "variable", "splits") == -50)
        #expect(try amount(sections, "total", "total") == 120)
        try expectReconciled(sections)
    }

    @Test func spotlightIncludesRefundOnlyCategoriesAndExplainsPercentages() throws {
        let food = Category(name: "Food", hexColor: "#00AA00")
        let returns = Category(name: "Returns", hexColor: "#AA0000")
        let debit = VariableExpense(descriptionText: "Purchase", amount: 100, transactionDate: start, category: food)
        let refund = VariableExpense(descriptionText: "Refund", amount: 20, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: start, category: returns)
        let sections = SpendingCalculationExplanation.spotlight(
            plannedExpenses: [], variableExpenses: [debit, refund], startDate: start, endDate: end
        )
        let categories = sections.filter { $0.id.hasPrefix("category-") }
        #expect(categories.count == 2)
        #expect(categories.compactMap { $0.rows.last?.amount }.reduce(0, +) == 80)
        let negative = try #require(categories.first { $0.rows.last?.title == "Returns" })
        #expect(negative.rows.last?.amount == -20)
        #expect(negative.notes.last?.contains("omitted") == true)
        let positive = try #require(categories.first { $0.rows.last?.title == "Food" })
        #expect(positive.notes.first?.contains("125%") == true)
        let refundOnly = SpendingCalculationExplanation.spotlight(
            plannedExpenses: [], variableExpenses: [refund], startDate: start, endDate: end
        )
        #expect(refundOnly.last?.notes.first?.contains("0%") == true)
        try expectReconciled(sections)
    }

    @Test(arguments: HomeSpendTrendsAggregator.Period.allCases)
    func trendsMatchesResolvedDatesCardFilterAndBuckets(period: HomeSpendTrendsAggregator.Period) throws {
        let card = Card(name: "Selected")
        let other = Card(name: "Other card")
        let food = Category(name: "Food", hexColor: "#00AA00")
        let returns = Category(name: "Returns", hexColor: "#AA0000")
        let now = Date()
        let empty = HomeSpendTrendsAggregator.calculate(
            period: period, categories: [], plannedExpenses: [], variableExpenses: [],
            rangeStart: now, rangeEnd: now, cardFilter: card, topN: 3
        )
        let planned = [PlannedExpense(title: "Boundary", plannedAmount: 50, expenseDate: empty.resolvedEnd, card: card)]
        let variable = [
            VariableExpense(descriptionText: "Boundary", amount: 100, transactionDate: empty.resolvedStart, card: card, category: food),
            VariableExpense(descriptionText: "Refund", amount: 20, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: empty.resolvedStart, card: card, category: returns),
            VariableExpense(descriptionText: "Wrong card", amount: 999, transactionDate: empty.resolvedStart, card: other),
            VariableExpense(descriptionText: "Too early", amount: 999, transactionDate: empty.resolvedStart.addingTimeInterval(-1), card: card),
            VariableExpense(descriptionText: "Too late", amount: 999, transactionDate: empty.resolvedEnd.addingTimeInterval(1), card: card)
        ]
        for selectedCard in [card, nil] {
            let result = HomeSpendTrendsAggregator.calculate(
                period: period, categories: [food, returns], plannedExpenses: planned, variableExpenses: variable,
                rangeStart: now, rangeEnd: now, cardFilter: selectedCard, topN: 3
            )
            let sections = SpendingCalculationExplanation.trends(
                result: result, card: selectedCard, plannedExpenses: planned, variableExpenses: variable
            )
            #expect(try amount(sections, "total", "total") == result.totalSpent)
            let periods = SpendingCalculationExplanation.trendPeriods(result: result, sections: sections)
            #expect(periods.count == result.buckets.count)
            for (period, bucket) in zip(periods, result.buckets) {
                #expect(period.summary.amount == bucket.total)
                #expect(period.summary.title.contains(AppDateFormat.abbreviatedDate(bucket.start)))
                #expect(period.sections.map(\.id) == ["bucket-\(bucket.id)", "bucket-net-\(bucket.id)"])
                #expect(period.sectionTitle == "Spending Periods")
            }
            #expect(result.totalSpent == (selectedCard == nil ? 1_129 : 130))
            for bucket in result.buckets {
                #expect(try amount(sections, "bucket-\(bucket.id)", "chart-total") == bucket.total)
                #expect(try amount(sections, "bucket-net-\(bucket.id)", "total") == bucket.expenseItems.reduce(0) { $0 + $1.amount })
            }
            let bucketNet = sections.filter { $0.id.hasPrefix("bucket-net-") }.compactMap { $0.rows.last?.amount }.reduce(0, +)
            #expect(bucketNet == result.totalSpent)
            #expect(sections[2].notes.contains { $0.contains(selectedCard?.name ?? "All Cards") })
            #expect(sections[2].notes.contains { $0.contains("Highest:") })
            #expect(sections[2].notes.contains { $0.contains("Top:") })
            #expect(sections.contains { $0.rows.contains { $0.id == "difference" && $0.amount == -20 } })
            try expectReconciled(sections)
        }
    }

    @Test func emptyInputsHaveZeroTotalsAndNoCallouts() throws {
        let spotlight = SpendingCalculationExplanation.spotlight(
            plannedExpenses: [], variableExpenses: [], startDate: start, endDate: end
        )
        #expect(spotlight.count == 3)
        #expect(try amount(spotlight, "total", "total") == 0)
        let result = HomeSpendTrendsAggregator.calculate(
            period: .period, categories: [], plannedExpenses: [], variableExpenses: [],
            rangeStart: start, rangeEnd: end, cardFilter: nil, topN: 3
        )
        let trends = SpendingCalculationExplanation.trends(result: result, card: nil, plannedExpenses: [], variableExpenses: [])
        #expect(try amount(trends, "total", "total") == 0)
        #expect(trends[2].notes.contains { $0.contains("no Highest or Top") })
        try expectReconciled(spotlight + trends)
    }

    private func amount(_ sections: [FinancialCalculationSection], _ sectionID: String, _ rowID: String) throws -> Double {
        try #require(sections.first { $0.id == sectionID }?.rows.first { $0.id == rowID }?.amount)
    }

    private func expectReconciled(_ sections: [FinancialCalculationSection]) throws {
        for section in sections {
            let total = try #require(section.rows.first { $0.isTotal })
            let contributions = section.rows.filter { !$0.isTotal }.reduce(0) { $0 + $1.amount }
            #expect(abs(contributions - total.amount) < 0.000_001)
        }
    }

    private func offset(_ amount: Double) -> SavingsLedgerEntry {
        SavingsLedgerEntry(date: start, amount: -amount, note: "Covered", kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue)
    }
}
