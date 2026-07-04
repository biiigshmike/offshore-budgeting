import Foundation
import Testing
@testable import Offshore

struct MarinaUnifiedExpenseQueryRunnerTests {
    private let runner = MarinaUniversalQueryRunner()

    @Test func unifiedListReturnsVariableAndPlannedRows() {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .unifiedExpenses, operation: .list),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Apple Store", "Apple Market", "Kroger", "Coffee Stand", "Old Plan", "AppleCare Plan", "Internet Bill", "Rent"])
    }

    @Test func unifiedCountCountsVariableAndPlannedRows() {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .unifiedExpenses, operation: .count),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .integer(8))
        #expect(metric.evidenceRows.count == 8)
    }

    @Test func unifiedSearchByMerchantTextSearchesVariableDescriptionsAndPlannedTitles() {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .sum,
                measure: .budgetImpact,
                search: MarinaRowSearchClause(fields: [.merchantText], query: "Apple")
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(218))
        #expect(rowNames(metric.evidenceRows) == ["Apple Store", "Apple Market", "AppleCare Plan"])
    }

    @Test func unifiedSumBudgetImpactIncludesVariableAndPlannedRows() {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .unifiedExpenses, operation: .sum, measure: .budgetImpact),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(1_611))
    }

    @Test func unifiedAverageBudgetImpactIncludesVariableAndPlannedRows() {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .unifiedExpenses, operation: .average, measure: .budgetImpact),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(201.375))
    }

    @Test func unifiedFilterByCategoryIncludesVariableAndPlannedMatches() {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .sum,
                measure: .budgetImpact,
                filters: [
                    MarinaRowFilter(target: .relationship(.category), operation: .equals, value: .text("Electronics"))
                ]
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(275))
        #expect(rowNames(metric.evidenceRows) == ["Apple Store", "AppleCare Plan", "Internet Bill"])
    }

    @Test func unifiedFilterByCardIncludesVariableAndPlannedMatches() {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .sum,
                measure: .budgetImpact,
                filters: [
                    MarinaRowFilter(target: .relationship(.card), operation: .equals, value: .text("Apple Card"))
                ]
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(293))
        #expect(rowNames(metric.evidenceRows) == ["Apple Store", "Apple Market", "AppleCare Plan", "Internet Bill"])
    }

    @Test func unifiedSortByBudgetImpactDescendingWorksAcrossBothRowTypes() {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .list,
                sorts: [MarinaRowSort(target: .field(.budgetImpact), direction: .descending)],
                limit: 5
            ),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Rent", "Apple Store", "AppleCare Plan", "Internet Bill", "Kroger"])
    }

    @Test func unifiedSortByDateDescendingWorksAcrossBothRowTypes() {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .list,
                sorts: [MarinaRowSort(target: .field(.date), direction: .descending)],
                limit: 3
            ),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Coffee Stand", "Rent", "Apple Market"])
    }

    @Test func unifiedLastAndNextUseSharedDateField() {
        let fixture = makeFixture()
        let lastRows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .unifiedExpenses, operation: .last),
            snapshot: fixture.snapshot
        ))
        let nextRows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(surface: .unifiedExpenses, operation: .next),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(lastRows) == ["Coffee Stand"])
        #expect(rowNames(nextRows) == ["Old Plan"])
    }

    @Test func unifiedGroupByCategoryAggregatesVariableAndPlannedRows() {
        let fixture = makeFixture()
        let groups = requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .group,
                measure: .budgetImpact,
                groupBy: .relationship(.category)
            ),
            snapshot: fixture.snapshot
        ))

        #expect(groupSummaries(groups) == [
            GroupSummary(name: "Electronics", aggregate: .money(275)),
            GroupSummary(name: "Groceries", aggregate: .money(127)),
            GroupSummary(name: "Uncategorized", aggregate: .money(1_209))
        ])
    }

    @Test func unifiedGroupByCardAggregatesVariableAndPlannedRows() {
        let fixture = makeFixture()
        let groups = requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .group,
                measure: .budgetImpact,
                groupBy: .relationship(.card)
            ),
            snapshot: fixture.snapshot
        ))

        #expect(groupSummaries(groups) == [
            GroupSummary(name: "Apple Card", aggregate: .money(293)),
            GroupSummary(name: "Chase Card", aggregate: .money(1_309)),
            GroupSummary(name: "Unassigned", aggregate: .money(9))
        ])
    }

    @Test func unifiedGroupByPresetAndBudgetUseUnassignedForMissingRows() {
        let fixture = makeFixture()
        let presetGroups = requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .group,
                measure: .budgetImpact,
                groupBy: .relationship(.preset)
            ),
            snapshot: fixture.snapshot
        ))
        let budgetGroups = requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .group,
                measure: .budgetImpact,
                groupBy: .relationship(.budget)
            ),
            snapshot: fixture.snapshot
        ))

        #expect(groupSummaries(presetGroups) == [
            GroupSummary(name: "AppleCare", aggregate: .money(80)),
            GroupSummary(name: "Unassigned", aggregate: .money(1_531))
        ])
        #expect(groupSummaries(budgetGroups) == [
            GroupSummary(name: "June", aggregate: .money(1_400)),
            GroupSummary(name: "Unassigned", aggregate: .money(211))
        ])
    }

    @Test func unifiedDateWindowFiltersVariableAndPlannedRows() {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .sum,
                measure: .budgetImpact,
                filters: [
                    MarinaRowFilter(target: .field(.date), operation: .greaterThanOrEqual, value: .date(date(2026, 6, 1))),
                    MarinaRowFilter(target: .field(.date), operation: .lessThanOrEqual, value: .date(date(2026, 6, 30)))
                ]
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(1_493))
        #expect(rowNames(metric.evidenceRows) == ["Apple Store", "Apple Market", "AppleCare Plan", "Internet Bill", "Rent"])
    }

    private func makeFixture() -> UnifiedRunnerFixture {
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

        return UnifiedRunnerFixture(
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
            )
        )
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

    private func groupSummaries(_ groups: [MarinaUniversalGroupResult]) -> [GroupSummary] {
        groups.map { GroupSummary(name: $0.group.displayName, aggregate: $0.aggregate) }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(secondsFromGMT: 0)

        return calendar.date(from: components) ?? .distantPast
    }
}

private struct UnifiedRunnerFixture {
    let snapshot: MarinaWorkspaceSnapshot
}

private struct GroupSummary: Equatable {
    let name: String
    let aggregate: MarinaValue?
}
