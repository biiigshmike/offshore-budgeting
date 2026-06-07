import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaUniversalQueryRunnerFormulaTests {
    @Test func rowBackedMeasuresStillWorkThroughFormulaAwareRunner() {
        let fixture = makeFixture()
        let runner = formulaRunner()

        let metric = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(150))
        #expect(metric.evidenceRows.map(\.displayName) == ["Groceries"])
    }

    @Test func formulaBackedSavingsTotalRoutesThroughRegistry() {
        let fixture = makeFixture()
        let runner = formulaRunner()

        let metric = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .savingsAccount,
                operation: .sum,
                measure: .savingsTotal,
                filters: [nameFilter("Emergency Fund")]
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(300))
        #expect(metric.evidenceRows.map(\.displayName) == ["Emergency Fund"])
    }

    @Test func formulaBackedSafeDailySpendRoutesThroughRegistry() {
        let fixture = makeFixture()
        let runner = formulaRunner()

        let metric = requireMetric(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .budget,
                operation: .forecast,
                measure: .safeDailySpend,
                dateRange: HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
            ),
            snapshot: fixture.snapshot
        ))

        #expect(metric.value == .money(65.625))
        #expect(metric.evidenceRows.map(\.displayName) == ["June"])
    }

    @Test func unsupportedFormulaMeasureReturnsTypedUnsupported() {
        let fixture = makeFixture()
        let runner = formulaRunner()

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(entity: .category, operation: .sum, measure: .categoryAvailability),
            snapshot: fixture.snapshot
        ) == .unsupported(.measureNotAvailable))

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(entity: .preset, operation: .sum, measure: .savingsTotal),
            snapshot: fixture.snapshot
        ) == .unsupported(.measureNotAvailable))
    }

    @Test func formulaBackedRequestsDoNotBypassCatalogValidation() {
        let fixture = makeFixture()
        let runner = formulaRunner()

        #expect(runner.runFormulaAware(
            plan: MarinaUniversalQueryPlan(
                entity: .savingsAccount,
                operation: .sum,
                measure: .savingsTotal,
                search: MarinaRowSearchClause(fields: [.amount], query: "300"),
                filters: [nameFilter("Emergency Fund")]
            ),
            snapshot: fixture.snapshot
        ) == .unsupported(.fieldNotSearchable))
    }

    @Test func defaultRunnerStillTreatsFormulaMeasuresAsDeferred() {
        let fixture = makeFixture()
        let runner = MarinaUniversalQueryRunner()

        #expect(runner.run(
            plan: MarinaUniversalQueryPlan(entity: .savingsAccount, operation: .list, measure: .savingsTotal),
            snapshot: fixture.snapshot
        ) == .unsupported(.measureNotAvailable))
    }

    private func formulaRunner() -> MarinaUniversalQueryRunner {
        MarinaUniversalQueryRunner(
            formulaRegistry: MarinaFormulaRegistry(now: date(2026, 6, 15), calendar: calendar)
        )
    }

    private func nameFilter(_ name: String) -> MarinaRowFilter {
        MarinaRowFilter(target: .field(.name), operation: .equals, value: .text(name))
    }

    private func requireMetric(_ result: MarinaUniversalQueryResult) -> MarinaUniversalMetricResult {
        guard case let .metric(metric) = result else {
            Issue.record("Expected universal metric, got \(result).")
            return MarinaUniversalMetricResult(value: .empty, evidenceRows: [])
        }
        return metric
    }

    private func makeFixture() -> FormulaRunnerFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let card = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let category = Offshore.Category(name: "General", hexColor: "#22C55E", workspace: workspace)
        let emergency = SavingsAccount(name: "Emergency Fund", total: 300, createdAt: date(2026, 1, 1), updatedAt: date(2026, 6, 1), workspace: workspace)
        let variableExpense = VariableExpense(descriptionText: "Groceries", amount: 150, transactionDate: date(2026, 6, 14), workspace: workspace, card: card, category: category)
        let incomeActual = Income(source: "Paycheck", amount: 1_000, date: date(2026, 6, 1), isPlanned: false, workspace: workspace)
        let incomePlanned = Income(source: "Bonus", amount: 500, date: date(2026, 6, 20), isPlanned: true, workspace: workspace)
        let consumedPlanned = PlannedExpense(title: "Rent", plannedAmount: 100, expenseDate: date(2026, 6, 10), workspace: workspace, card: card, category: category)
        let remainingPlanned = PlannedExpense(title: "Internet", plannedAmount: 200, expenseDate: date(2026, 6, 20), workspace: workspace, card: card, category: category)

        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [card],
            categories: [category],
            presets: [],
            plannedExpenses: [consumedPlanned, remainingPlanned],
            variableExpenses: [variableExpense],
            homePlannedExpenses: [consumedPlanned, remainingPlanned],
            homeCalculationPlannedExpenses: [consumedPlanned, remainingPlanned],
            homeCalculationVariableExpenses: [variableExpense],
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [emergency],
            savingsEntries: [],
            incomes: [incomeActual, incomePlanned]
        )

        return FormulaRunnerFixture(snapshot: snapshot)
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

private struct FormulaRunnerFixture {
    let snapshot: MarinaWorkspaceSnapshot
}
