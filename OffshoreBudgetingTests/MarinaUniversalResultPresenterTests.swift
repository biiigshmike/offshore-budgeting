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

    @Test func emptyCategoryListUsesHelpfulMessage() {
        let request = expenseListRequest(target: "Hair Care", dimensions: [.category])
        let plan = MarinaUniversalQueryPlan(entity: .variableExpense, operation: .list, measure: .budgetImpact)
        let result = presenter.presentationResult(
            for: .rowsPage(MarinaUniversalRowsPage(rows: [], totalRowCount: 0, displayLimit: 8)),
            plan: plan,
            context: context(request: request)
        )

        #expect(result.kind == .message)
        #expect(result.title == "Hair Care Expenses")
        #expect(result.subtitle == "This budgeting period")
        #expect(result.primaryValue == "No expenses found")
        #expect(result.explanation == "I didn't find any Hair Care expenses in this budgeting period.")
        #expect(result.rows.isEmpty)
    }

    @Test func emptyMerchantListUsesHelpfulMessage() {
        let request = expenseListRequest(
            target: "Uber",
            dimensions: [.merchantText],
            dateRangeToken: .previousMonth,
            textQuery: "Uber"
        )
        let plan = MarinaUniversalQueryPlan(entity: .variableExpense, operation: .list, measure: .budgetImpact)
        let result = presenter.presentationResult(
            for: .rowsPage(MarinaUniversalRowsPage(rows: [], totalRowCount: 0, displayLimit: 8)),
            plan: plan,
            context: context(request: request)
        )

        #expect(result.kind == .message)
        #expect(result.title == "Uber Expenses")
        #expect(result.subtitle == "Last month")
        #expect(result.primaryValue == "No expenses found")
        #expect(result.explanation == "I didn't find any Uber expenses last month.")
        #expect(result.rows.isEmpty)
    }

    @Test func targetListTitlesAreSpecific() {
        let row = variableExpenseRow(displayName: "Cafe", amount: 12, date: date(2026, 6, 5))
        let plan = MarinaUniversalQueryPlan(entity: .variableExpense, operation: .list, measure: .budgetImpact)

        let category = presenter.presentationResult(
            for: .rowsPage(MarinaUniversalRowsPage(rows: [row], totalRowCount: 1, fullTotalAmount: 12, displayLimit: 8)),
            plan: plan,
            context: context(request: expenseListRequest(target: "Food & Drink", dimensions: [.category]))
        )
        let merchant = presenter.presentationResult(
            for: .rowsPage(MarinaUniversalRowsPage(rows: [row], totalRowCount: 1, fullTotalAmount: 12, displayLimit: 8)),
            plan: plan,
            context: context(request: expenseListRequest(target: "Uber", dimensions: [.merchantText], textQuery: "Uber"))
        )
        let card = presenter.presentationResult(
            for: .rowsPage(MarinaUniversalRowsPage(rows: [row], totalRowCount: 1, fullTotalAmount: 12, displayLimit: 8)),
            plan: plan,
            context: context(request: expenseListRequest(target: "Apple Card", dimensions: [.card]))
        )

        #expect(category.title == "Food & Drink Expenses")
        #expect(merchant.title == "Uber Expenses")
        #expect(card.title == "Apple Card Expenses")
    }

    @Test func limitedListExplainsShownAndTotalCounts() {
        let rows = (1...8).map { index in
            variableExpenseRow(displayName: "Cafe \(index)", amount: Double(index), date: date(2026, 6, index))
        }
        let plan = MarinaUniversalQueryPlan(entity: .variableExpense, operation: .list, measure: .budgetImpact)
        let result = presenter.presentationResult(
            for: .rowsPage(
                MarinaUniversalRowsPage(
                    rows: rows,
                    totalRowCount: 11,
                    fullTotalAmount: 66,
                    displayLimit: 8
                )
            ),
            plan: plan,
            context: context(request: expenseListRequest(target: "Food & Drink", dimensions: [.category], dateRangeToken: .previousMonth))
        )

        #expect(result.title == "Food & Drink Expenses")
        #expect(result.subtitle == "Showing 8 of 11 Food & Drink expenses from last month.")
        #expect(result.primaryValue == CurrencyFormatter.string(from: 66))
        #expect(result.displayedRowCount == 8)
        #expect(result.totalRowCount == 11)
    }

    @Test func formulaTitlesAreSpecific() {
        let safeDailySpend = presenter.presentationResult(
            for: .metric(MarinaUniversalMetricResult(value: .money(42), evidenceRows: [])),
            plan: MarinaUniversalQueryPlan(entity: .budget, operation: .forecast, measure: .safeDailySpend),
            context: context()
        )
        let projectedSpend = presenter.presentationResult(
            for: .metric(MarinaUniversalMetricResult(value: .money(420), evidenceRows: [])),
            plan: MarinaUniversalQueryPlan(entity: .budget, operation: .forecast, measure: .projectedSpend),
            context: context()
        )
        let budgetPace = presenter.presentationResult(
            for: .metric(MarinaUniversalMetricResult(value: .money(14), evidenceRows: [])),
            plan: MarinaUniversalQueryPlan(entity: .budget, operation: .average, measure: .burnRate),
            context: context()
        )
        let categoryShare = presenter.presentationResult(
            for: .metric(MarinaUniversalMetricResult(value: .number(0.9), evidenceRows: [])),
            plan: MarinaUniversalQueryPlan(entity: .category, operation: .share, measure: .concentration),
            context: context()
        )
        let remainingRoom = presenter.presentationResult(
            for: .metric(MarinaUniversalMetricResult(value: .money(100), evidenceRows: [])),
            plan: MarinaUniversalQueryPlan(entity: .budget, operation: .forecast, measure: .remainingRoom),
            context: context()
        )

        #expect(safeDailySpend.title == "Safe Daily Spend")
        #expect(projectedSpend.title == "Projected Spend")
        #expect(budgetPace.title == "Budget Pace")
        #expect(categoryShare.title == "Category Spend Share")
        #expect(remainingRoom.title == "Remaining Room")
    }

    @Test func safeDailySpendFormulaCardUsesCuratedRowsAndPlainClampCopy() {
        let result = presenter.presentationResult(
            for: .metric(
                MarinaUniversalMetricResult(
                    value: .money(0),
                    evidenceRows: [budgetEvidenceRow(displayName: "May 2026")],
                    details: [
                        .init(.period, value: .text("Jun 1, 2026 - Jun 30, 2026")),
                        .init(.remainingDays, value: .integer(12), style: .integer),
                        .init(.plannedSpending, value: .money(1_500), style: .money),
                        .init(.plannedSpendingRemaining, value: .money(900), style: .money),
                        .init(.actualSpendSoFar, value: .money(1_200), style: .money),
                        .init(.periodRemainingRoom, value: .money(0), style: .money),
                        .init(.safePerDay, value: .money(0), style: .money),
                        .init(.clampedToZero, value: .boolean(true))
                    ],
                    presentationRows: [
                        MarinaFormulaPresentationRow(
                            title: "Safe per day",
                            primaryValue: .money(0),
                            primaryStyle: .money,
                            amount: 0
                        )
                    ]
                )
            ),
            plan: MarinaUniversalQueryPlan(entity: .budget, operation: .forecast, measure: .safeDailySpend),
            context: context()
        )

        #expect(result.rows.map(\.title) == [
            "Period",
            "Remaining days",
            "Planned spending remaining",
            "Actual spend so far",
            "Remaining room",
            "Safe per day"
        ])
        #expect(result.rows.contains { $0.title == "Clamped to zero" } == false)
        #expect(result.rows.contains { $0.title == "May 2026" } == false)
        #expect(result.rows.filter { $0.title == "Safe per day" }.count == 1)
        #expect(result.explanation == "Your safe daily spend is $0.00 because there is no remaining room left in this budgeting period.")
    }

    @Test func remainingRoomFormulaCardUsesCuratedRowsOnly() {
        let result = presenter.presentationResult(
            for: .metric(
                MarinaUniversalMetricResult(
                    value: .money(450),
                    evidenceRows: [budgetEvidenceRow(displayName: "April 2026")],
                    details: [
                        .init(.period, value: .text("Jun 1, 2026 - Jun 30, 2026")),
                        .init(.remainingDays, value: .integer(12), style: .integer),
                        .init(.plannedSpending, value: .money(1_500), style: .money),
                        .init(.plannedSpendingRemaining, value: .money(900), style: .money),
                        .init(.actualSpendSoFar, value: .money(1_200), style: .money),
                        .init(.periodRemainingRoom, value: .money(450), style: .money),
                        .init(.safePerDay, value: .money(37.50), style: .money),
                        .init(.clampedToZero, value: .boolean(false))
                    ],
                    presentationRows: [
                        MarinaFormulaPresentationRow(
                            title: "Remaining room",
                            primaryValue: .money(450),
                            primaryStyle: .money,
                            amount: 450
                        )
                    ]
                )
            ),
            plan: MarinaUniversalQueryPlan(entity: .budget, operation: .forecast, measure: .remainingRoom),
            context: context()
        )

        #expect(result.rows.map(\.title) == [
            "Period",
            "Planned spending",
            "Planned spending remaining",
            "Actual spend so far",
            "Remaining room"
        ])
        #expect(result.rows.contains { $0.title == "Clamped to zero" } == false)
        #expect(result.rows.contains { $0.title == "Safe per day" } == false)
        #expect(result.rows.contains { $0.title == "April 2026" } == false)
    }

    @Test func projectedSpendFormulaCardShowsBudgetAwareRowsOnly() {
        let result = presenter.presentationResult(
            for: .metric(
                MarinaUniversalMetricResult(
                    value: .money(1_611.07),
                    evidenceRows: [budgetEvidenceRow(displayName: "March 2026")],
                    details: [
                        .init(.actualSpendSoFar, value: .money(1_521.07), style: .money),
                        .init(.plannedSpendingRemaining, value: .money(90), style: .money),
                        .init(.projectedSpend, value: .money(1_611.07), style: .money)
                    ]
                )
            ),
            plan: MarinaUniversalQueryPlan(entity: .budget, operation: .forecast, measure: .projectedSpend),
            context: context()
        )

        #expect(result.rows.map(\.title) == ["Actual spend so far", "Planned spending remaining", "Projected spend"])
        #expect(result.rows.contains { $0.title == "March 2026" } == false)
        #expect(result.rows.contains { $0.title == "Average per day" } == false)
        #expect(result.rows.contains { $0.title == "Projected total" } == false)
    }

    @Test func categorySpendShareIncludesRankedAmountAndPercentRows() {
        let plan = MarinaUniversalQueryPlan(entity: .category, operation: .share, measure: .concentration)
        let result = presenter.presentationResult(
            for: .metric(
                MarinaUniversalMetricResult(
                    value: .number(0.907),
                    evidenceRows: [],
                    presentationRows: [
                        MarinaFormulaPresentationRow(
                            title: "Bills & Utilities",
                            primaryValue: .money(2_410.94),
                            primaryStyle: .money,
                            secondaryValue: .number(0.907),
                            secondaryStyle: .percent,
                            amount: 2_410.94
                        ),
                        MarinaFormulaPresentationRow(
                            title: "Shopping",
                            primaryValue: .money(140.13),
                            primaryStyle: .money,
                            secondaryValue: .number(0.053),
                            secondaryStyle: .percent,
                            amount: 140.13
                        )
                    ]
                )
            ),
            plan: plan,
            context: context()
        )

        #expect(result.title == "Category Spend Share")
        #expect(Array(result.rows.map(\.title).prefix(2)) == ["Bills & Utilities", "Shopping"])
        #expect(result.rows.first?.value == "\(CurrencyFormatter.string(from: 2_410.94)) - \(0.907.formatted(.percent.precision(.fractionLength(1))))")
        #expect(result.rows.dropFirst().first?.value == "\(CurrencyFormatter.string(from: 140.13)) - \(0.053.formatted(.percent.precision(.fractionLength(1))))")
    }

    private func budgetEvidenceRow(displayName: String) -> MarinaQueryableRow {
        MarinaQueryableRow(
            id: UUID(),
            entity: .budget,
            displayName: displayName,
            fields: [
                .name: .text(displayName),
                .startDate: .date(date(2026, 6, 1))
            ],
            relationships: [:]
        )
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

    private func context(request: MarinaSemanticRequest) -> MarinaUniversalPresentationContext {
        MarinaUniversalPresentationContext(
            dateRange: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30)),
            semanticRequest: request,
            now: date(2026, 6, 15),
            calendar: calendar
        )
    }

    private func expenseListRequest(
        target: String,
        dimensions: [MarinaSemanticDimension],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod,
        textQuery: String? = nil
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dimensions: dimensions,
            dateRangeToken: dateRangeToken,
            targetName: textQuery == nil ? target : nil,
            textQuery: textQuery,
            targetDisplayName: target,
            resultLimit: 8,
            expenseScope: .unified,
            expectedAnswerShape: .list
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
