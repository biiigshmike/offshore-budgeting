import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaUniversalRoutingDebugFlagTests {
    @Test func defaultFlagResolvesDisabled() throws {
        let defaults = try makeDefaults(suiteName: "MarinaUniversalRoutingDebugFlagTests.default")
        defer { defaults.removePersistentDomain(forName: "MarinaUniversalRoutingDebugFlagTests.default") }

        let policy = MarinaUniversalRoutingDebugFlagResolver.policy(
            defaults: defaults,
            arguments: [],
            environment: [:],
            isDebugBuild: true
        )

        #expect(policy == .disabled)
    }

    @Test func debugEnabledFlagResolvesInternalParityPolicy() throws {
        let defaults = try makeDefaults(suiteName: "MarinaUniversalRoutingDebugFlagTests.enabled")
        defer { defaults.removePersistentDomain(forName: "MarinaUniversalRoutingDebugFlagTests.enabled") }
        defaults.set(true, forKey: MarinaUniversalRoutingDebugFlagResolver.key)

        let policy = MarinaUniversalRoutingDebugFlagResolver.policy(
            defaults: defaults,
            arguments: [],
            environment: [:],
            isDebugBuild: true
        )

        #expect(policy == .internalParityProven)
    }

    @Test func nonDebugBuildAlwaysResolvesDisabledEvenWhenFlagIsOn() throws {
        let defaults = try makeDefaults(suiteName: "MarinaUniversalRoutingDebugFlagTests.release")
        defer { defaults.removePersistentDomain(forName: "MarinaUniversalRoutingDebugFlagTests.release") }
        defaults.set(true, forKey: MarinaUniversalRoutingDebugFlagResolver.key)

        let policy = MarinaUniversalRoutingDebugFlagResolver.policy(
            defaults: defaults,
            arguments: ["App", "-\(MarinaUniversalRoutingDebugFlagResolver.key)", "on"],
            environment: [MarinaUniversalRoutingDebugFlagResolver.key: "yes"],
            isDebugBuild: false
        )

        #expect(policy == .disabled)
    }

    @Test func enabledPolicyStillRejectsNonAllowlistedScenarios() throws {
        let defaults = try makeDefaults(suiteName: "MarinaUniversalRoutingDebugFlagTests.rejectsUnsupported")
        defer { defaults.removePersistentDomain(forName: "MarinaUniversalRoutingDebugFlagTests.rejectsUnsupported") }
        defaults.set(true, forKey: MarinaUniversalRoutingDebugFlagResolver.key)
        let policy = MarinaUniversalRoutingDebugFlagResolver.policy(
            defaults: defaults,
            arguments: [],
            environment: [:],
            isDebugBuild: true
        )
        let request = semanticRequest(
            entity: .category,
            operation: .forecast,
            measure: .categoryAvailability
        )

        #expect(policy == .internalParityProven)
        #expect(policy.allows(request) == false)
        #expect(policy.scenario(for: request) == nil)
    }

    @Test func enabledFlagDoesNotBypassLegacyFallback() throws {
        let defaults = try makeDefaults(suiteName: "MarinaUniversalRoutingDebugFlagTests.fallback")
        defer { defaults.removePersistentDomain(forName: "MarinaUniversalRoutingDebugFlagTests.fallback") }
        defaults.set(true, forKey: MarinaUniversalRoutingDebugFlagResolver.key)
        let policy = MarinaUniversalRoutingDebugFlagResolver.policy(
            defaults: defaults,
            arguments: [],
            environment: [:],
            isDebugBuild: true
        )
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .category,
            operation: .forecast,
            measure: .categoryAvailability
        )
        let plan = fixture.plan(for: request)
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: fixture.harness(policy: policy),
            policy: policy
        )

        let result = executor.executeResult(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        guard case let .legacy(_, diagnostics) = result else {
            Issue.record("Expected legacy fallback, got \(result).")
            throw TestFailure()
        }
        #expect(diagnostics?.fallbackReason == .notAllowlisted)
        #expect(diagnostics?.usedUniversal == false)
    }

    private func makeFixture() -> MarinaDebugFlagFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Apple Card", workspace: workspace)
        let category = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)
        let expense = VariableExpense(
            descriptionText: "Apple Store",
            amount: 120,
            transactionDate: date(2026, 6, 5),
            workspace: workspace,
            card: card,
            category: category
        )
        let planned = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: date(2026, 6, 25),
            workspace: workspace,
            card: card,
            category: category,
            sourceBudgetID: budget.id
        )
        let income = Income(source: "Paycheck", amount: 2_000, date: date(2026, 6, 11), isPlanned: false, workspace: workspace)
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [card],
            categories: [category],
            presets: [],
            plannedExpenses: [planned],
            variableExpenses: [expense],
            homePlannedExpenses: [planned],
            homeCalculationPlannedExpenses: [planned],
            homeCalculationVariableExpenses: [expense],
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [],
            savingsEntries: [],
            incomes: [income]
        )

        return MarinaDebugFlagFixture(
            snapshot: snapshot,
            now: date(2026, 6, 15),
            calendar: calendar
        )
    }

    private func semanticRequest(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dimensions: [MarinaSemanticDimension] = [],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentMonth,
        targetName: String? = nil,
        textQuery: String? = nil,
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
            expenseScope: expenseScope,
            expectedAnswerShape: shape
        )
    }

    private func makeDefaults(suiteName: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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

@MainActor
private struct MarinaDebugFlagFixture {
    let snapshot: MarinaWorkspaceSnapshot
    let now: Date
    let calendar: Calendar

    var legacyExecutor: MarinaQueryExecutor {
        MarinaQueryExecutor(calendar: calendar)
    }

    func context() -> MarinaUniversalPlanningContext {
        MarinaUniversalPlanningContext(
            defaultBudgetingPeriod: .monthly,
            now: now,
            calendar: calendar
        )
    }

    func plan(for request: MarinaSemanticRequest) -> MarinaQueryPlan {
        MarinaQueryPlanner(calendar: calendar).plan(
            request: request,
            ambientDateRange: context().ambientDateRange,
            defaultBudgetingPeriod: context().defaultBudgetingPeriod,
            now: context().now
        )
    }

    func harness(policy: MarinaUniversalRoutingPolicy) -> MarinaUniversalRoutingHarness {
        let formulaRegistry = MarinaFormulaRegistry(now: now, calendar: calendar)
        return MarinaUniversalRoutingHarness(
            bridge: MarinaSemanticUniversalPlanBridge(formulaRegistry: formulaRegistry),
            runner: MarinaUniversalQueryRunner(formulaRegistry: formulaRegistry),
            presenter: MarinaUniversalResultPresenter(),
            policy: policy
        )
    }
}

private struct TestFailure: Error {}
