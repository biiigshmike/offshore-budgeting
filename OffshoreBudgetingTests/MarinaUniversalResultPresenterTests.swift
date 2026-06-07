import Foundation
import Testing
@testable import Offshore

struct MarinaUniversalResultPresenterTests {
    private let presenter = MarinaUniversalResultPresenter()

    @Test func moneyMetricBecomesMetricExecutionResult() {
        let plan = MarinaUniversalQueryPlan(entity: .variableExpense, operation: .sum, measure: .budgetImpact)
        let result = presenter.presentationResult(
            for: .metric(MarinaUniversalMetricResult(value: .money(42.25), evidenceRows: [])),
            plan: plan,
            context: context()
        )

        #expect(result.kind == .metric)
        #expect(result.primaryValue == CurrencyFormatter.string(from: 42.25))
        #expect(result.rows.first?.amount == 42.25)
    }

    @Test func integerMetricBecomesMetricExecutionResult() {
        let plan = MarinaUniversalQueryPlan(entity: .card, operation: .count)
        let result = presenter.presentationResult(
            for: .metric(MarinaUniversalMetricResult(value: .integer(7), evidenceRows: [])),
            plan: plan,
            context: context()
        )

        #expect(result.kind == .metric)
        #expect(result.primaryValue == "7")
        #expect(result.rows.first?.amount == 7)
    }

    @Test func rowResultBecomesListExecutionResult() {
        let row = variableExpenseRow(displayName: "Apple Store", amount: 120, date: date(2026, 6, 5))
        let plan = MarinaUniversalQueryPlan(entity: .variableExpense, operation: .list, measure: .budgetImpact)
        let result = presenter.presentationResult(for: MarinaUniversalQueryResult.rows([row]), plan: plan, context: context())

        #expect(result.kind == .list)
        #expect(result.rows.map(\.title) == ["Apple Store"])
        #expect(result.rows.first?.sourceID == row.id)
        #expect(result.rows.first?.objectType == .variableExpense)
        #expect(result.rows.first?.amount == 120)
        #expect(result.rows.first?.date == date(2026, 6, 5))
    }

    @Test func groupResultWithMoneyAggregateBecomesListRows() {
        let rows = [
            variableExpenseRow(displayName: "Apple Store", amount: 120, date: date(2026, 6, 5)),
            variableExpenseRow(displayName: "Best Buy", amount: 300, date: date(2026, 6, 6))
        ]
        let group = MarinaUniversalGroupResult(
            group: MarinaGroupedRows(key: "Electronics", displayName: "Electronics", rows: rows),
            aggregate: .money(420)
        )
        let plan = MarinaUniversalQueryPlan(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            groupBy: .relationship(.category)
        )
        let result = presenter.presentationResult(for: MarinaUniversalQueryResult.groups([group]), plan: plan, context: context())

        #expect(result.kind == .list)
        #expect(result.rows.first?.title == "Electronics")
        #expect(result.rows.first?.value == CurrencyFormatter.string(from: 420))
        #expect(result.rows.first?.amount == 420)
    }

    @Test func groupResultWithoutAggregateUsesRowCount() {
        let rows = [
            variableExpenseRow(displayName: "Apple Store", amount: 120, date: date(2026, 6, 5)),
            variableExpenseRow(displayName: "Apple Market", amount: 18, date: date(2026, 6, 6))
        ]
        let group = MarinaUniversalGroupResult(
            group: MarinaGroupedRows(key: "Apple Card", displayName: "Apple Card", rows: rows),
            aggregate: nil
        )
        let plan = MarinaUniversalQueryPlan(entity: .variableExpense, operation: .group, groupBy: .relationship(.card))
        let result = presenter.presentationResult(for: MarinaUniversalQueryResult.groups([group]), plan: plan, context: context())

        #expect(result.kind == .list)
        #expect(result.rows.first?.title == "Apple Card")
        #expect(result.rows.first?.value == "2")
        #expect(result.rows.first?.amount == nil)
    }

    @Test func unsupportedResultBecomesMessageWithTypedReason() {
        let plan = MarinaUniversalQueryPlan(entity: .preset, operation: .sum, measure: .savingsTotal)
        let result = presenter.presentedResult(
            for: MarinaUniversalQueryResult.unsupported(.measureNotAvailable),
            plan: plan,
            context: context()
        )

        #expect(result.unsupportedReason == .measureNotAvailable)
        #expect(result.executionResult.kind == .message)
        #expect(result.executionResult.title == "I can't answer that yet")
        #expect(result.executionResult.subtitle?.contains("measureNotAvailable") == false)
    }

    @Test func expenseRowMapsDisplayNameAmountDateEntityAndSourceID() {
        let row = plannedExpenseRow(displayName: "Phone Bill", amount: 80, date: date(2026, 6, 16))
        let plan = MarinaUniversalQueryPlan(entity: .plannedExpense, operation: .next, measure: .effectiveAmount)
        let result = presenter.presentationResult(for: MarinaUniversalQueryResult.rows([row]), plan: plan, context: context())

        #expect(result.rows.first?.title == "Phone Bill")
        #expect(result.rows.first?.sourceID == row.id)
        #expect(result.rows.first?.objectType == .plannedExpense)
        #expect(result.rows.first?.amount == 80)
        #expect(result.rows.first?.date == date(2026, 6, 16))
    }

    @Test func incomeRowMapsAmountDateAndSource() {
        let row = MarinaQueryableRow(
            id: UUID(),
            entity: .income,
            displayName: "Paycheck",
            fields: [
                .id: .text(UUID().uuidString),
                .source: .text("Paycheck"),
                .incomeAmount: .money(2_000),
                .date: .date(date(2026, 6, 11))
            ],
            relationships: [:]
        )
        let plan = MarinaUniversalQueryPlan(entity: .income, operation: .list, measure: .incomeAmount)
        let result = presenter.presentationResult(for: MarinaUniversalQueryResult.rows([row]), plan: plan, context: context())

        #expect(result.rows.first?.title == "Paycheck")
        #expect(result.rows.first?.objectType == .income)
        #expect(result.rows.first?.amount == 2_000)
        #expect(result.rows.first?.date == date(2026, 6, 11))
    }

    @Test func metadataRowMapsColorWhenRequested() {
        let row = MarinaQueryableRow(
            id: UUID(),
            entity: .category,
            displayName: "Groceries",
            fields: [
                .name: .text("Groceries"),
                .color: .colorHex("#22C55E")
            ],
            relationships: [:]
        )
        let plan = MarinaUniversalQueryPlan(entity: .category, operation: .list, measure: .color)
        let result = presenter.presentationResult(for: MarinaUniversalQueryResult.rows([row]), plan: plan, context: context())

        #expect(result.rows.first?.title == "Groceries")
        #expect(result.rows.first?.value == "#22C55E")
        #expect(result.rows.first?.objectType == .category)
        #expect(result.rows.first?.amount == nil)
    }

    @Test func presentationBridgeDoesNotMutateUniversalInput() {
        let row = variableExpenseRow(displayName: "Apple Store", amount: 120, date: date(2026, 6, 5))
        let input = MarinaUniversalQueryResult.rows([row])
        let original = input
        let plan = MarinaUniversalQueryPlan(entity: .variableExpense, operation: .list, measure: .budgetImpact)

        _ = presenter.presentationResult(for: input, plan: plan, context: context())

        #expect(input == original)
    }

    @Test func formulaMetricPresentsDirectly() {
        let plan = MarinaUniversalQueryPlan(entity: .savingsAccount, operation: .sum, measure: .savingsTotal)
        let result = presenter.presentationResult(
            for: MarinaFormulaResult.metric(
                MarinaFormulaMetric(
                    value: .money(300),
                    evidenceRows: [],
                    measure: .savingsTotal,
                    source: .savingsAccountService
                )
            ),
            plan: plan,
            context: context()
        )

        #expect(result.kind == .metric)
        #expect(result.primaryValue == CurrencyFormatter.string(from: 300))
        #expect(result.rows.first?.amount == 300)
    }

    @Test func formulaUnsupportedPreservesTypedReason() {
        let plan = MarinaUniversalQueryPlan(entity: .budget, operation: .forecast, measure: .burnRate)
        let result = presenter.presentedResult(
            for: MarinaFormulaResult.unsupported(.measureNotAvailable),
            plan: plan,
            context: context()
        )

        #expect(result.unsupportedReason == .measureNotAvailable)
        #expect(result.executionResult.kind == .message)
    }

    private func variableExpenseRow(displayName: String, amount: Double, date: Date) -> MarinaQueryableRow {
        MarinaQueryableRow(
            id: UUID(),
            entity: .variableExpense,
            displayName: displayName,
            fields: [
                .descriptionText: .text(displayName),
                .budgetImpact: .money(amount),
                .amount: .money(amount),
                .date: .date(date),
                .transactionDate: .date(date)
            ],
            relationships: [:]
        )
    }

    private func plannedExpenseRow(displayName: String, amount: Double, date: Date) -> MarinaQueryableRow {
        MarinaQueryableRow(
            id: UUID(),
            entity: .plannedExpense,
            displayName: displayName,
            fields: [
                .title: .text(displayName),
                .effectiveAmount: .money(amount),
                .budgetImpact: .money(amount),
                .date: .date(date),
                .expenseDate: .date(date)
            ],
            relationships: [:]
        )
    }

    private func context() -> MarinaUniversalPresentationContext {
        MarinaUniversalPresentationContext(
            dateRange: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30)),
            now: date(2026, 6, 15),
            calendar: calendar
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }
}
