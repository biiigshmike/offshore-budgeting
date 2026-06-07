import Foundation
import Testing
@testable import Offshore

struct MarinaSemanticUniversalPlanBridgeRunnerTests {
    private let bridge = MarinaSemanticUniversalPlanBridge()
    private let runner = MarinaUniversalQueryRunner()

    @Test func merchantSpendBridgesAndRunsThroughUniversalRunner() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            textQuery: "Apple"
        )))
        let metric = requireMetric(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(metric.value == .money(138))
    }

    @Test func spendingByCardBridgesAndRunsThroughUniversalRunner() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            shape: .list
        )))
        let groups = requireGroups(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(groupSummaries(groups) == [
            BridgeRunnerGroupSummary(name: "Apple Card", aggregate: .money(147)),
            BridgeRunnerGroupSummary(name: "Chase Card", aggregate: .money(416))
        ])
    }

    @Test func grocerySpendBridgesAndRunsThroughUniversalRunner() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            targetName: "Groceries"
        )))
        let metric = requireMetric(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(metric.value == .money(134))
        #expect(rowNames(metric.evidenceRows) == ["Apple Market", "Kroger", "Trader Joe's"])
    }

    @Test func biggestGroceryPurchasesBridgeAndRunThroughUniversalRunner() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dimensions: [.category],
            targetName: "Groceries",
            resultLimit: 5,
            sort: .amountDescending,
            shape: .list
        )))
        let rows = requireRows(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(rowNames(rows) == ["Kroger", "Trader Joe's", "Apple Market"])
    }

    @Test func incomeBySourceBridgesAndRunsThroughUniversalRunner() throws {
        let fixture = makeFixture()
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .income,
            operation: .group,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            shape: .list
        )))
        let groups = requireGroups(runner.run(plan: plan, snapshot: fixture.snapshot))

        #expect(groupSummaries(groups) == [
            BridgeRunnerGroupSummary(name: "Freelance", aggregate: .money(650)),
            BridgeRunnerGroupSummary(name: "Paycheck", aggregate: .money(4_100))
        ])
    }

    private func makeFixture() -> BridgeRunnerFixture {
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

        return BridgeRunnerFixture(snapshot: snapshot)
    }

    private func request(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dimensions: [MarinaSemanticDimension] = [],
        targetName: String? = nil,
        textQuery: String? = nil,
        resultLimit: Int? = nil,
        sort: MarinaSemanticSort? = nil,
        shape: MarinaSemanticAnswerShape = .metric
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dimensions: dimensions,
            targetName: targetName,
            textQuery: textQuery,
            resultLimit: resultLimit,
            sort: sort,
            expectedAnswerShape: shape
        )
    }

    private func requirePlan(
        _ result: MarinaSemanticUniversalPlanBridgeResult
    ) throws -> MarinaUniversalQueryPlan {
        guard case let .plan(plan) = result else {
            Issue.record("Expected plan result, got \(result).")
            throw BridgeRunnerTestError.expectedPlan
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

    private func groupSummaries(_ groups: [MarinaUniversalGroupResult]) -> [BridgeRunnerGroupSummary] {
        groups.map { group in
            BridgeRunnerGroupSummary(name: group.group.displayName, aggregate: group.aggregate)
        }
    }
}

private struct BridgeRunnerFixture {
    let snapshot: MarinaWorkspaceSnapshot
}

private struct BridgeRunnerGroupSummary: Equatable {
    let name: String
    let aggregate: MarinaValue?
}

private enum BridgeRunnerTestError: Error {
    case expectedPlan
}
