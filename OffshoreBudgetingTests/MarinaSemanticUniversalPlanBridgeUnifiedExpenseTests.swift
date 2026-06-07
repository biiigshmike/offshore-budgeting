import Foundation
import Testing
@testable import Offshore

struct MarinaSemanticUniversalPlanBridgeUnifiedExpenseTests {
    private let bridge = MarinaSemanticUniversalPlanBridge()
    private let runner = MarinaUniversalQueryRunner()

    @Test func unifiedExpenseScopeBridgesToUnifiedExpenseSurface() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            expenseScope: .unified
        )))

        #expect(plan.surface == .unifiedExpenses)
    }

    @Test func variableExpenseScopeRemainsVariableOnly() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .plannedExpense,
            operation: .sum,
            measure: .budgetImpact,
            expenseScope: .variable
        )))

        #expect(plan.surface == .semantic(.variableExpense))
    }

    @Test func plannedExpenseScopeRemainsPlannedOnly() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            expenseScope: .planned
        )))

        #expect(plan.surface == .semantic(.plannedExpense))
    }

    @Test func genericUnifiedSpendWithTextQueryBridgesToUnifiedSearch() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            textQuery: " Apple ",
            expenseScope: .unified
        )))

        #expect(plan.surface == .unifiedExpenses)
        #expect(plan.search == MarinaRowSearchClause(fields: [.merchantText], query: "Apple"))
    }

    @Test func unifiedGroupByCategoryBridgesToUnifiedGroup() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.category],
            expenseScope: .unified,
            shape: .list
        )))

        #expect(plan.surface == .unifiedExpenses)
        #expect(plan.groupBy == .relationship(.category))
    }

    @Test func unifiedGroupByCardBridgesToUnifiedGroup() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .plannedExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            expenseScope: .unified,
            shape: .list
        )))

        #expect(plan.surface == .unifiedExpenses)
        #expect(plan.groupBy == .relationship(.card))
    }

    @Test func unifiedCurrentMonthSpendBridgesToUnifiedDateFilteredPlan() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(
            from: request(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                dateRangeToken: .currentMonth,
                expenseScope: .unified
            ),
            planningContext: fixture.context()
        ))

        #expect(plan.surface == .unifiedExpenses)
        #expect(dateFilters(in: plan) == [
            MarinaRowFilter(target: .field(.date), operation: .greaterThanOrEqual, value: .date(date(2026, 6, 1))),
            MarinaRowFilter(target: .field(.date), operation: .lessThanOrEqual, value: .date(date(2026, 6, 30)))
        ])
        #expect(plan.requiresDateField)
    }

    @Test func unsupportedUnifiedDimensionsReturnTypedUnsupported() {
        let result = bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.savingsAccount],
            expenseScope: .unified,
            shape: .list
        ))

        #expect(result == .unsupported(.unsupportedCombination))
    }

    @Test func totalSpendingThisMonthShadowRequestRunsUnifiedCurrentMonthTotal() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(
            from: request(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                dateRangeToken: .currentMonth,
                expenseScope: .unified
            ),
            planningContext: fixture.context()
        ))
        let metric = requireMetric(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(metric.value == .money(1_493))
        #expect(rowNames(metric.evidenceRows) == ["Apple Store", "Apple Market", "AppleCare Plan", "Internet Bill", "Rent"])
    }

    @Test func spendingByCategoryShadowRequestRunsUnifiedGroup() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(
            from: request(
                entity: .variableExpense,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category],
                dateRangeToken: .currentPeriod,
                expenseScope: .unified,
                shape: .list
            ),
            planningContext: fixture.context(ambientDateRange: fixture.currentPeriod)
        ))
        let groups = requireGroups(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(groupSummaries(groups) == [
            UnifiedBridgeGroupSummary(name: "Electronics", aggregate: .money(275)),
            UnifiedBridgeGroupSummary(name: "Groceries", aggregate: .money(18)),
            UnifiedBridgeGroupSummary(name: "Uncategorized", aggregate: .money(1_200))
        ])
    }

    @Test func biggestSpendingRowsShadowRequestRunsUnifiedSortAndLimit() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            resultLimit: 5,
            sort: .amountDescending,
            expenseScope: .unified,
            shape: .list
        )))
        let rows = requireRows(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(rowNames(rows) == ["Rent", "Apple Store", "AppleCare Plan", "Internet Bill", "Kroger"])
    }

    @Test func searchAppleAcrossAllExpensesShadowRequestRunsUnifiedSearch() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dateRangeToken: .allTime,
            textQuery: "Apple",
            expenseScope: .unified
        )))
        let metric = requireMetric(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(metric.value == .money(218))
        #expect(rowNames(metric.evidenceRows) == ["Apple Store", "Apple Market", "AppleCare Plan"])
    }

    private func request(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dimensions: [MarinaSemanticDimension] = [],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod,
        targetName: String? = nil,
        textQuery: String? = nil,
        resultLimit: Int? = nil,
        sort: MarinaSemanticSort? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
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
            resultLimit: resultLimit,
            sort: sort,
            expenseScope: expenseScope,
            expectedAnswerShape: shape
        )
    }

    private func makeFixture() -> UnifiedBridgeFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let preset = Preset(title: "AppleCare", plannedAmount: 80, workspace: workspace, defaultCard: appleCard, defaultCategory: electronics)

        let variableExpenses = [
            VariableExpense(descriptionText: "Apple Store", amount: 120, transactionDate: date(2026, 6, 5), workspace: workspace, card: appleCard, category: electronics),
            VariableExpense(descriptionText: "Apple Market", amount: 18, transactionDate: date(2026, 6, 20), workspace: workspace, card: appleCard, category: groceries),
            VariableExpense(descriptionText: "Kroger", amount: 64, transactionDate: date(2026, 5, 10), workspace: workspace, card: chaseCard, category: groceries),
            VariableExpense(descriptionText: "Coffee Stand", amount: 9, transactionDate: date(2026, 7, 1), workspace: workspace, card: nil, category: nil)
        ]
        let plannedExpenses = [
            PlannedExpense(title: "Old Plan", plannedAmount: 45, expenseDate: date(2026, 5, 3), workspace: workspace, card: chaseCard, category: groceries, sourceBudgetID: budget.id),
            PlannedExpense(title: "AppleCare Plan", plannedAmount: 80, expenseDate: date(2026, 6, 16), workspace: workspace, card: appleCard, category: electronics, sourcePresetID: preset.id, sourceBudgetID: budget.id),
            PlannedExpense(title: "Internet Bill", plannedAmount: 100, actualAmount: 75, expenseDate: date(2026, 6, 18), workspace: workspace, card: appleCard, category: electronics, sourceBudgetID: budget.id),
            PlannedExpense(title: "Rent", plannedAmount: 1_200, expenseDate: date(2026, 6, 25), workspace: workspace, card: chaseCard, category: nil, sourceBudgetID: budget.id)
        ]

        return UnifiedBridgeFixture(
            snapshot: MarinaWorkspaceSnapshot(
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
                incomes: []
            ),
            currentPeriod: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30)),
            now: date(2026, 6, 15),
            calendar: calendar
        )
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

    private func requirePlan(_ result: MarinaSemanticUniversalPlanBridgeResult) throws -> MarinaUniversalQueryPlan {
        guard case let .plan(plan) = result else {
            Issue.record("Expected plan result, got \(result).")
            throw UnifiedBridgeTestError.expectedPlan
        }
        return plan
    }

    private func requireRows(_ result: MarinaUniversalQueryResult) -> [MarinaQueryableRow] {
        guard case let .rows(rows) = result else {
            Issue.record("Expected row result, got \(result).")
            return []
        }
        return rows
    }

    private func requireMetric(_ result: MarinaUniversalQueryResult) -> MarinaUniversalMetricResult {
        guard case let .metric(metric) = result else {
            Issue.record("Expected metric result, got \(result).")
            return MarinaUniversalMetricResult(value: .empty, evidenceRows: [])
        }
        return metric
    }

    private func requireGroups(_ result: MarinaUniversalQueryResult) -> [MarinaUniversalGroupResult] {
        guard case let .groups(groups) = result else {
            Issue.record("Expected grouped result, got \(result).")
            return []
        }
        return groups
    }

    private func rowNames(_ rows: [MarinaQueryableRow]) -> [String] {
        rows.map(\.displayName)
    }

    private func groupSummaries(_ groups: [MarinaUniversalGroupResult]) -> [UnifiedBridgeGroupSummary] {
        groups.map { UnifiedBridgeGroupSummary(name: $0.group.displayName, aggregate: $0.aggregate) }
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
        components.timeZone = TimeZone(secondsFromGMT: 0)

        return calendar.date(from: components) ?? .distantPast
    }
}

private struct UnifiedBridgeFixture {
    let snapshot: MarinaWorkspaceSnapshot
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

private struct UnifiedBridgeGroupSummary: Equatable {
    let name: String
    let aggregate: MarinaValue?
}

private enum UnifiedBridgeTestError: Error {
    case expectedPlan
}
