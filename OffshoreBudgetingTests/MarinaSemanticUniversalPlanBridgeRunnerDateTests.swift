import Foundation
import Testing
@testable import Offshore

struct MarinaSemanticUniversalPlanBridgeRunnerDateTests {
    private let bridge = MarinaSemanticUniversalPlanBridge()
    private let runner = MarinaUniversalQueryRunner()

    @Test func currentMonthMerchantSpendBridgesAndRunsThroughDateFilters() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(
            from: request(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                dateRangeToken: .currentMonth,
                textQuery: "Apple"
            ),
            planningContext: fixture.context()
        ))
        let metric = requireMetric(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(plan.search == MarinaRowSearchClause(fields: [.merchantText, .descriptionText], query: "Apple"))
        #expect(dateFilters(in: plan).count == 2)
        #expect(metric.value == .money(138))
        #expect(rowNames(metric.evidenceRows) == ["Apple Store", "Apple Market"])
    }

    @Test func previousMonthGrocerySpendBridgesAndRunsThroughDateFilters() throws {
        let fixture = makeFixture()
        let groceries = try #require(fixture.snapshot.categories.first { $0.name == "Groceries" })
        let plan = try requirePlan(bridge.makePlan(
            from: request(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                dimensions: [.category],
                dateRangeToken: .previousMonth,
                targetName: "Groceries",
                resolvedTarget: reference(.category, groceries.id, groceries.name)
            ),
            planningContext: fixture.context()
        ))
        let metric = requireMetric(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(plan.filters.contains(MarinaRowFilter(
            target: .relationship(.category),
            operation: .equals,
            value: .text(groceries.id.uuidString)
        )))
        #expect(dateFilters(in: plan).count == 2)
        #expect(metric.value == .money(116))
        #expect(rowNames(metric.evidenceRows) == ["Kroger", "Trader Joe's"])
    }

    @Test func currentPeriodIncomeBridgesAndRunsThroughDateFilters() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(
            from: request(
                entity: .income,
                operation: .sum,
                measure: .incomeAmount,
                dateRangeToken: .currentPeriod
            ),
            planningContext: fixture.context(ambientDateRange: fixture.currentPeriod)
        ))
        let metric = requireMetric(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(dateFilters(in: plan).count == 2)
        #expect(metric.value == .money(2_650))
        #expect(rowNames(metric.evidenceRows) == ["Paycheck", "Freelance"])
    }

    @Test func nextPlannedExpenseBridgesAndRunsThroughNextSevenDayFilters() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(
            from: request(
                entity: .plannedExpense,
                operation: .next,
                measure: .effectiveAmount,
                dateRangeToken: .nextSevenDays,
                shape: .list
            ),
            planningContext: fixture.context()
        ))
        let rows = requireRows(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(dateFilters(in: plan).count == 2)
        #expect(rowNames(rows) == ["Phone Bill"])
    }

    @Test func parityMerchantSpendEqualsManualSum() throws {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                search: MarinaRowSearchClause(fields: [.merchantText], query: "Apple")
            ),
            snapshot: fixture.snapshot
        ))
        let manual = fixture.variableExpenses
            .filter { $0.descriptionText.localizedCaseInsensitiveContains("Apple") }
            .reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }

        #expect(metric.value == .money(manual))
    }

    @Test func parityCategorySpendEqualsManualSum() throws {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                filters: [
                    MarinaRowFilter(target: .relationship(.category), operation: .equals, value: .text("Groceries"))
                ]
            ),
            snapshot: fixture.snapshot
        ))
        let manual = fixture.variableExpenses
            .filter { $0.category?.name == "Groceries" }
            .reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }

        #expect(metric.value == .money(manual))
    }

    @Test func parityCardSpendEqualsManualSum() throws {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                filters: [
                    MarinaRowFilter(target: .relationship(.card), operation: .equals, value: .text("Apple Card"))
                ]
            ),
            snapshot: fixture.snapshot
        ))
        let manual = fixture.variableExpenses
            .filter { $0.card?.name == "Apple Card" }
            .reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }

        #expect(metric.value == .money(manual))
    }

    @Test func parityIncomeSumEqualsManualSum() throws {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .income, operation: .sum, measure: .incomeAmount),
            snapshot: fixture.snapshot
        ))
        let manual = fixture.incomes.reduce(0) { $0 + $1.amount }

        #expect(metric.value == .money(manual))
    }

    @Test func parityPlannedExpenseSumEqualsManualSum() throws {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .plannedExpense, operation: .sum, measure: .budgetImpact),
            snapshot: fixture.snapshot
        ))
        let manual = fixture.plannedExpenses.reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }

        #expect(metric.value == .money(manual))
    }

    @Test func parityLastResultMatchesLatestVariableExpenseDate() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .variableExpense, operation: .last),
            snapshot: fixture.snapshot
        ))
        let expected = fixture.variableExpenses.max { $0.transactionDate < $1.transactionDate }?.descriptionText

        #expect(rowNames(rows) == expected.map { [$0] } ?? [])
    }

    @Test func parityNextResultMatchesEarliestFuturePlannedExpenseDate() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .plannedExpense,
                operation: .next,
                filters: [
                    MarinaRowFilter(target: .field(.expenseDate), operation: .greaterThanOrEqual, value: .date(fixture.now))
                ]
            ),
            snapshot: fixture.snapshot
        ))
        let expected = fixture.plannedExpenses
            .filter { $0.expenseDate >= fixture.now }
            .min { $0.expenseDate < $1.expenseDate }?
            .title

        #expect(rowNames(rows) == expected.map { [$0] } ?? [])
    }

    @Test func parityDateWindowFilteredSumExcludesRowsOutsideRange() throws {
        let fixture = makeFixture()
        let juneRange = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                filters: filters(field: .transactionDate, range: juneRange)
            ),
            snapshot: fixture.snapshot
        ))
        let manual = fixture.variableExpenses
            .filter { $0.transactionDate >= juneRange.startDate && $0.transactionDate <= juneRange.endDate }
            .reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }

        #expect(metric.value == .money(manual))
        #expect(rowNames(metric.evidenceRows) == ["Apple Store", "Apple Market", "Kroger"])
    }

    private func makeFixture() -> BridgeRunnerDateFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let preset = Preset(
            title: "Phone",
            plannedAmount: 80,
            workspace: workspace,
            defaultCard: appleCard,
            defaultCategory: electronics
        )

        let variableExpenses = [
            VariableExpense(
                descriptionText: "Apple Store",
                amount: 120,
                transactionDate: date(2026, 6, 5),
                workspace: workspace,
                card: appleCard,
                category: electronics
            ),
            VariableExpense(
                descriptionText: "Apple Market",
                amount: 18,
                transactionDate: date(2026, 6, 20),
                workspace: workspace,
                card: appleCard,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Apple Store",
                amount: 90,
                transactionDate: date(2026, 5, 15),
                workspace: workspace,
                card: appleCard,
                category: electronics
            ),
            VariableExpense(
                descriptionText: "Kroger",
                amount: 64,
                transactionDate: date(2026, 5, 10),
                workspace: workspace,
                card: chaseCard,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Trader Joe's",
                amount: 52,
                transactionDate: date(2026, 5, 20),
                workspace: workspace,
                card: chaseCard,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Kroger",
                amount: 30,
                transactionDate: date(2026, 6, 10),
                workspace: workspace,
                card: chaseCard,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Coffee Stand",
                amount: 9,
                transactionDate: date(2026, 7, 1),
                workspace: workspace,
                card: appleCard,
                category: nil
            )
        ]

        let plannedExpenses = [
            PlannedExpense(
                title: "Old Plan",
                plannedAmount: 45,
                expenseDate: date(2026, 5, 3),
                workspace: workspace,
                card: chaseCard,
                category: groceries,
                sourceBudgetID: budget.id
            ),
            PlannedExpense(
                title: "Phone Bill",
                plannedAmount: 80,
                expenseDate: date(2026, 6, 16),
                workspace: workspace,
                card: appleCard,
                category: electronics,
                sourcePresetID: preset.id,
                sourceBudgetID: budget.id
            ),
            PlannedExpense(
                title: "Internet Bill",
                plannedAmount: 100,
                actualAmount: 75,
                expenseDate: date(2026, 6, 18),
                workspace: workspace,
                card: appleCard,
                category: electronics,
                sourceBudgetID: budget.id
            ),
            PlannedExpense(
                title: "Rent",
                plannedAmount: 1_200,
                expenseDate: date(2026, 6, 25),
                workspace: workspace,
                card: chaseCard,
                category: nil,
                sourceBudgetID: budget.id
            )
        ]

        let incomes = [
            Income(source: "Paycheck", amount: 2_000, date: date(2026, 6, 11), isPlanned: false, workspace: workspace, card: appleCard),
            Income(source: "Freelance", amount: 650, date: date(2026, 6, 19), isPlanned: false, workspace: workspace, card: chaseCard),
            Income(source: "Paycheck", amount: 2_100, date: date(2026, 6, 25), isPlanned: true, workspace: workspace, card: appleCard),
            Income(source: "Paycheck", amount: 1_900, date: date(2026, 5, 15), isPlanned: false, workspace: workspace, card: appleCard)
        ]

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [appleCard, chaseCard],
            categories: [groceries, electronics],
            presets: [preset],
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            homePlannedExpenses: plannedExpenses,
            homeCalculationPlannedExpenses: plannedExpenses,
            homeCalculationVariableExpenses: variableExpenses,
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [],
            savingsEntries: [],
            incomes: incomes
        )

        return BridgeRunnerDateFixture(
            snapshot: snapshot,
            variableExpenses: variableExpenses,
            plannedExpenses: plannedExpenses,
            incomes: incomes,
            currentPeriod: HomeQueryDateRange(startDate: date(2026, 6, 10), endDate: date(2026, 6, 20)),
            now: date(2026, 6, 15),
            calendar: calendar
        )
    }

    private func request(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dimensions: [MarinaSemanticDimension] = [],
        dateRangeToken: MarinaSemanticDateRangeToken,
        targetName: String? = nil,
        resolvedTarget: MarinaResolvedEntityReference? = nil,
        textQuery: String? = nil,
        shape: MarinaSemanticAnswerShape = .metric
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dimensions: dimensions,
            dateRangeToken: dateRangeToken,
            targetName: targetName,
            textQuery: textQuery,
            resolvedTarget: resolvedTarget,
            expectedAnswerShape: shape
        )
    }

    private func reference(
        _ entity: MarinaSemanticEntity,
        _ id: UUID,
        _ name: String
    ) -> MarinaResolvedEntityReference {
        MarinaResolvedEntityReference(
            entity: entity,
            id: id,
            displayName: name,
            provenance: .candidateResolver
        )
    }

    private func filters(field: MarinaFieldKey, range: HomeQueryDateRange) -> [MarinaRowFilter] {
        [
            MarinaRowFilter(target: .field(field), operation: .greaterThanOrEqual, value: .date(range.startDate)),
            MarinaRowFilter(target: .field(field), operation: .lessThanOrEqual, value: .date(range.endDate))
        ]
    }

    private func dateFilters(in plan: MarinaUniversalQueryPlan) -> [MarinaRowFilter] {
        plan.filters.filter { filter in
            guard case .field = filter.target,
                  case .date = filter.value else {
                return false
            }
            return true
        }
    }

    private func requirePlan(
        _ result: MarinaSemanticUniversalPlanBridgeResult
    ) throws -> MarinaUniversalQueryPlan {
        guard case let .plan(plan) = result else {
            Issue.record("Expected plan result, got \(result).")
            throw BridgeRunnerDateTestError.expectedPlan
        }
        return plan
    }

    private func requireRows(_ result: MarinaUniversalQueryResult) -> [MarinaQueryableRow] {
        switch result {
        case let .rows(rows):
            return rows
        case let .rowsPage(page):
            return page.rows
        default:
            Issue.record("Expected row result, got \(result).")
            return []
        }
    }

    private func requireMetric(_ result: MarinaUniversalQueryResult) -> MarinaUniversalMetricResult {
        guard case let .metric(metric) = result else {
            Issue.record("Expected metric result, got \(result).")
            return MarinaUniversalMetricResult(value: .empty, evidenceRows: [])
        }
        return metric
    }

    private func rowNames(_ rows: [MarinaQueryableRow]) -> [String] {
        rows.map(\.displayName)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(secondsFromGMT: 0)

        return calendar.date(from: components) ?? .distantPast
    }
}

private struct BridgeRunnerDateFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let variableExpenses: [VariableExpense]
    let plannedExpenses: [PlannedExpense]
    let incomes: [Income]
    let currentPeriod: HomeQueryDateRange
    let now: Date
    let calendar: Calendar

    func context(ambientDateRange: HomeQueryDateRange? = nil) -> MarinaUniversalPlanningContext {
        MarinaUniversalPlanningContext(
            ambientDateRange: ambientDateRange,
            defaultBudgetingPeriod: .monthly,
            now: now,
            calendar: calendar
        )
    }
}

private enum BridgeRunnerDateTestError: Error {
    case expectedPlan
}
