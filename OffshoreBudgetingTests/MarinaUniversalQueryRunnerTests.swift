import Foundation
import Testing
@testable import Offshore

struct MarinaUniversalQueryRunnerTests {
    private let runner = MarinaUniversalQueryRunner()

    @Test func listsVariableExpenses() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .variableExpense, operation: .list),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Apple Store", "Apple Market", "Kroger", "Trader Joe's", "Best Buy", "Coffee Stand"])
    }

    @Test func countsVariableExpenses() throws {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .variableExpense, operation: .count),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .integer(6))
        #expect(metric.evidenceRows.count == 6)
    }

    @Test func searchesMerchantTextAndSumsBudgetImpact() throws {
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

        #expect(metric.value == .money(138))
        #expect(rowNames(metric.evidenceRows) == ["Apple Store", "Apple Market"])
    }

    @Test func filtersVariableExpensesByCategoryAndSumsBudgetImpact() throws {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                filters: [
                    MarinaRowFilter(
                        target: .relationship(.category),
                        operation: .equals,
                        value: .text("Groceries")
                    )
                ]
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(134))
        #expect(rowNames(metric.evidenceRows) == ["Apple Market", "Kroger", "Trader Joe's"])
    }

    @Test func filtersVariableExpensesByCardAndSumsBudgetImpact() throws {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                filters: [
                    MarinaRowFilter(
                        target: .relationship(.card),
                        operation: .equals,
                        value: .text(fixture.appleCard.id.uuidString)
                    )
                ]
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(147))
        #expect(rowNames(metric.evidenceRows) == ["Apple Store", "Apple Market", "Coffee Stand"])
    }

    @Test func sortsVariableExpensesByBudgetImpactDescendingAndLimitsToOne() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .list,
                sorts: [
                    MarinaRowSort(target: .field(.budgetImpact), direction: .descending)
                ],
                limit: 1
            ),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Best Buy"])
    }

    @Test func sortsVariableExpensesByDateDescendingAndLimitsToOne() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .list,
                sorts: [
                    MarinaRowSort(target: .field(.transactionDate), direction: .descending)
                ],
                limit: 1
            ),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Coffee Stand"])
    }

    @Test func groupsVariableExpensesByCategoryAndAggregatesBudgetImpact() throws {
        let fixture = makeFixture()
        let groups = requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .group,
                measure: .budgetImpact,
                groupBy: .relationship(.category)
            ),
            snapshot: fixture.snapshot
        ))

        #expect(groupSummaries(groups) == [
            GroupSummary(name: "Electronics", aggregate: .money(420)),
            GroupSummary(name: "Groceries", aggregate: .money(134)),
            GroupSummary(name: "Uncategorized", aggregate: .money(9))
        ])
    }

    @Test func groupsVariableExpensesByCardAndAggregatesBudgetImpact() throws {
        let fixture = makeFixture()
        let groups = requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .group,
                measure: .budgetImpact,
                groupBy: .relationship(.card)
            ),
            snapshot: fixture.snapshot
        ))

        #expect(groupSummaries(groups) == [
            GroupSummary(name: "Apple Card", aggregate: .money(147)),
            GroupSummary(name: "Chase Card", aggregate: .money(416))
        ])
    }

    @Test func groupsUnifiedExpensesByCardAggregatesPlannedVariableAndUnassignedRows() throws {
        let firstDate = Date(timeIntervalSince1970: 1_780_300_800)
        let secondDate = Date(timeIntervalSince1970: 1_780_387_200)
        let oldDate = Date(timeIntervalSince1970: 1_777_795_200)
        let futureDate = Date(timeIntervalSince1970: 1_782_892_800)
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let budget = Budget(name: "June", startDate: firstDate, endDate: secondDate, workspace: workspace)
        let plannedExpenses = [
            PlannedExpense(title: "Phone Bill", plannedAmount: 80, expenseDate: secondDate, workspace: workspace, card: appleCard, sourceBudgetID: budget.id),
            PlannedExpense(title: "Cash Plan", plannedAmount: 100, expenseDate: secondDate, workspace: workspace, card: nil, sourceBudgetID: budget.id),
            PlannedExpense(title: "Old Cash Plan", plannedAmount: 50, expenseDate: oldDate, workspace: workspace, card: nil, sourceBudgetID: budget.id)
        ]
        let variableExpenses = [
            VariableExpense(descriptionText: "Apple Store", amount: 120, transactionDate: firstDate, workspace: workspace, card: appleCard),
            VariableExpense(descriptionText: "Kroger", amount: 30, transactionDate: secondDate, workspace: workspace, card: chaseCard),
            VariableExpense(descriptionText: "Cash Coffee", amount: 7, transactionDate: firstDate, workspace: workspace, card: nil),
            VariableExpense(descriptionText: "Future Cash", amount: 9, transactionDate: futureDate, workspace: workspace, card: nil)
        ]
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [appleCard, chaseCard],
            categories: [],
            presets: [],
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

        let groups = requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                surface: .unifiedExpenses,
                operation: .group,
                measure: .budgetImpact,
                filters: [
                    MarinaRowFilter(target: .field(.date), operation: .greaterThanOrEqual, value: .date(firstDate)),
                    MarinaRowFilter(target: .field(.date), operation: .lessThanOrEqual, value: .date(secondDate))
                ],
                groupBy: .relationship(.card)
            ),
            snapshot: snapshot
        ))

        #expect(groupSummaries(groups) == [
            GroupSummary(name: "Apple Card", aggregate: .money(200)),
            GroupSummary(name: "Chase Card", aggregate: .money(30)),
            GroupSummary(name: "Unassigned", aggregate: .money(107))
        ])
    }

    @Test func listsPlannedExpenses() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .plannedExpense, operation: .list),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Internet Bill", "Grocery Plan"])
    }

    @Test func sumsPlannedExpenseBudgetImpact() throws {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .plannedExpense,
                operation: .sum,
                measure: .budgetImpact
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(125))
    }

    @Test func listsIncomeRows() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .income, operation: .list),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Paycheck", "Freelance", "Paycheck"])
    }

    @Test func sumsIncomeAmount() throws {
        let fixture = makeFixture()
        let metric = requireMetric(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .income,
                operation: .sum,
                measure: .incomeAmount
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(4_750))
    }

    @Test func groupsIncomeBySourceAndAggregatesIncomeAmount() throws {
        let fixture = makeFixture()
        let groups = requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .income,
                operation: .group,
                measure: .incomeAmount,
                groupBy: .relationship(.incomeSource)
            ),
            snapshot: fixture.snapshot
        ))

        #expect(groupSummaries(groups) == [
            GroupSummary(name: "Freelance", aggregate: .money(650)),
            GroupSummary(name: "Paycheck", aggregate: .money(4_100))
        ])
    }

    @Test func listsCategories() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .category, operation: .list),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Groceries", "Electronics"])
    }

    @Test func listsCards() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .card, operation: .list),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Apple Card", "Chase Card"])
    }

    @Test func listsBudgets() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .budget, operation: .list),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["June"])
    }

    @Test func listsPresets() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .preset, operation: .list),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Internet"])
    }

    @Test func unsupportedOperationReturnsTypedUnsupported() throws {
        let fixture = makeFixture()
        let result = runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .income,
                operation: .share,
                measure: .incomeAmount
            ),
            snapshot: fixture.snapshot
        )

        #expect(result == .unsupported(.unsupportedCombination))
    }

    @Test func unsupportedFormulaMeasureReturnsMeasureNotAvailable() throws {
        let fixture = makeFixture()
        let result = runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .category,
                operation: .sum,
                measure: .categoryAvailability
            ),
            snapshot: fixture.snapshot
        )

        #expect(result == .unsupported(.measureNotAvailable))
    }

    @Test func missingAdapterReturnsTypedUnsupported() throws {
        let fixture = makeFixture()
        let result = runner.run(
            plan: MarinaUniversalQueryPlan(entity: .workspace, operation: .list),
            snapshot: fixture.snapshot
        )

        #expect(result == .unsupported(.unsupportedCombination))
    }

    @Test func validationFailureReturnsTypedUnsupportedAndDoesNotExecuteRows() throws {
        let fixture = makeFixture()
        let adapter = TrackingVariableExpenseAdapter()
        let runner = MarinaUniversalQueryRunner(
            adapterRegistry: MarinaEntityAdapterRegistry(adapters: [adapter])
        )
        let result = runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .list,
                search: MarinaRowSearchClause(fields: [.amount], query: "10")
            ),
            snapshot: fixture.snapshot
        )

        #expect(result == .unsupported(.fieldNotSearchable))
        #expect(adapter.loadCount == 0)
    }

    @Test func shadowMerchantSpendUsesSearchAndSum() throws {
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

        #expect(metric.value == .money(138))
    }

    @Test func shadowSpendingByCardUsesGroupAndSum() throws {
        let fixture = makeFixture()
        let groups = requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .group,
                measure: .budgetImpact,
                groupBy: .relationship(.card)
            ),
            snapshot: fixture.snapshot
        ))

        #expect(groupSummaries(groups) == [
            GroupSummary(name: "Apple Card", aggregate: .money(147)),
            GroupSummary(name: "Chase Card", aggregate: .money(416))
        ])
    }

    @Test func shadowBiggestGroceryPurchasesUsesFilterSortAndLimit() throws {
        let fixture = makeFixture()
        let rows = requireRows(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .list,
                filters: [
                    MarinaRowFilter(
                        target: .relationship(.category),
                        operation: .equals,
                        value: .text("Groceries")
                    )
                ],
                sorts: [
                    MarinaRowSort(target: .field(.budgetImpact), direction: .descending)
                ],
                limit: 5
            ),
            snapshot: fixture.snapshot
        ))

        #expect(rowNames(rows) == ["Kroger", "Trader Joe's", "Apple Market"])
    }

    @Test func shadowIncomeBySourceUsesGroupAndSum() throws {
        let fixture = makeFixture()
        let groups = requireGroups(runner.run(
            plan: MarinaUniversalQueryPlan(
                entity: .income,
                operation: .group,
                measure: .incomeAmount,
                groupBy: .relationship(.incomeSource)
            ),
            snapshot: fixture.snapshot
        ))

        #expect(groupSummaries(groups) == [
            GroupSummary(name: "Freelance", aggregate: .money(650)),
            GroupSummary(name: "Paycheck", aggregate: .money(4_100))
        ])
    }

    private func makeFixture() -> UniversalRunnerFixture {
        let firstDate = Date(timeIntervalSince1970: 1_780_300_800)
        let secondDate = Date(timeIntervalSince1970: 1_780_387_200)
        let thirdDate = Date(timeIntervalSince1970: 1_780_473_600)
        let fourthDate = Date(timeIntervalSince1970: 1_780_560_000)
        let fifthDate = Date(timeIntervalSince1970: 1_780_646_400)
        let sixthDate = Date(timeIntervalSince1970: 1_780_732_800)

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)
        let budget = Budget(name: "June", startDate: firstDate, endDate: sixthDate, workspace: workspace)
        let preset = Preset(
            title: "Internet",
            plannedAmount: 80,
            workspace: workspace,
            defaultCard: appleCard,
            defaultCategory: electronics
        )

        let plannedExpenses = [
            PlannedExpense(
                title: "Internet Bill",
                plannedAmount: 80,
                actualAmount: 75,
                expenseDate: secondDate,
                workspace: workspace,
                card: appleCard,
                category: electronics,
                sourcePresetID: preset.id,
                sourceBudgetID: budget.id
            ),
            PlannedExpense(
                title: "Grocery Plan",
                plannedAmount: 50,
                expenseDate: fourthDate,
                workspace: workspace,
                card: chaseCard,
                category: groceries,
                sourceBudgetID: budget.id
            )
        ]

        let variableExpenses = [
            VariableExpense(
                descriptionText: "Apple Store",
                amount: 120,
                transactionDate: firstDate,
                workspace: workspace,
                card: appleCard,
                category: electronics
            ),
            VariableExpense(
                descriptionText: "Apple Market",
                amount: 18,
                transactionDate: secondDate,
                workspace: workspace,
                card: appleCard,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Kroger",
                amount: 64,
                transactionDate: thirdDate,
                workspace: workspace,
                card: chaseCard,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Trader Joe's",
                amount: 52,
                transactionDate: fourthDate,
                workspace: workspace,
                card: chaseCard,
                category: groceries
            ),
            VariableExpense(
                descriptionText: "Best Buy",
                amount: 300,
                transactionDate: fifthDate,
                workspace: workspace,
                card: chaseCard,
                category: electronics
            ),
            VariableExpense(
                descriptionText: "Coffee Stand",
                amount: 9,
                transactionDate: sixthDate,
                workspace: workspace,
                card: appleCard,
                category: nil
            )
        ]

        let incomes = [
            Income(
                source: "Paycheck",
                amount: 2_000,
                date: firstDate,
                isPlanned: false,
                workspace: workspace,
                card: appleCard
            ),
            Income(
                source: "Freelance",
                amount: 650,
                date: thirdDate,
                isPlanned: false,
                workspace: workspace,
                card: chaseCard
            ),
            Income(
                source: "Paycheck",
                amount: 2_100,
                date: fifthDate,
                isPlanned: true,
                workspace: workspace,
                card: appleCard
            )
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

        return UniversalRunnerFixture(snapshot: snapshot, appleCard: appleCard)
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
        groups.map { group in
            GroupSummary(name: group.group.displayName, aggregate: group.aggregate)
        }
    }
}

private struct UniversalRunnerFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let appleCard: Card
}

private struct GroupSummary: Equatable {
    let name: String
    let aggregate: MarinaValue?
}

private final class TrackingVariableExpenseAdapter: MarinaEntityAdapter {
    let entity: MarinaSemanticEntity = .variableExpense
    var loadCount = 0

    func rows(from snapshot: MarinaWorkspaceSnapshot) -> [MarinaQueryableRow] {
        loadCount += 1
        return MarinaVariableExpenseAdapter().rows(from: snapshot)
    }
}
