import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaUniversalRoutingDiagnosticsTests {
    @Test func harnessSuccessDiagnosticsIncludeScenarioAndRequestShape() throws {
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let attempt = fixture.harness().attemptUniversalResult(
            request: request,
            plan: fixture.plan(for: request),
            snapshot: fixture.snapshot,
            context: fixture.context()
        )

        guard case let .universal(_, diagnostics) = attempt else {
            Issue.record("Expected universal result, got \(attempt).")
            throw TestFailure()
        }

        #expect(diagnostics.scenario == .merchantVariableSpend)
        #expect(diagnostics.requestEntity == .variableExpense)
        #expect(diagnostics.operation == .sum)
        #expect(diagnostics.measure == .budgetImpact)
        #expect(diagnostics.usedUniversal)
        #expect(diagnostics.fallbackReason == nil)
    }

    @Test func harnessFallbackDiagnosticsIncludeReasonAndUniversalUsage() throws {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .savingsAccount,
            operation: .forecast,
            measure: .savingsTotal,
            dateRangeToken: .allTime
        )
        let attempt = fixture.harness().attemptUniversalResult(
            request: request,
            plan: fixture.plan(for: request),
            snapshot: fixture.snapshot,
            context: fixture.context()
        )

        guard case let .fallback(reason, diagnostics) = attempt else {
            Issue.record("Expected fallback result, got \(attempt).")
            throw TestFailure()
        }

        #expect(reason == .notAllowlisted)
        #expect(diagnostics.scenario == nil)
        #expect(diagnostics.requestEntity == .savingsAccount)
        #expect(diagnostics.operation == .forecast)
        #expect(diagnostics.measure == .savingsTotal)
        #expect(diagnostics.usedUniversal == false)
        #expect(diagnostics.fallbackReason == .notAllowlisted)
    }

    @Test func dualPathFallbackDiagnosticsAreNotAppendedToVisibleResultSurfaces() throws {
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let plan = fixture.plan(for: request)
        let diagnosticNote = "Diagnostics: internal routing note only."
        let diagnostics = MarinaUniversalRoutingDiagnostics(
            requestEntity: request.entity,
            operation: request.operation,
            measure: request.measure,
            scenario: .merchantVariableSpend,
            usedUniversal: false,
            fallbackReason: .unsupportedPresentation,
            notes: [diagnosticNote]
        )
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: StubUniversalHarness(
                result: .fallback(
                    reason: .unsupportedPresentation,
                    diagnostics: diagnostics
                )
            ),
            policy: .internalParityProven
        )

        let result = executor.executeResult(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        guard case let .legacy(executionResult, fallbackDiagnostics) = result else {
            Issue.record("Expected legacy fallback, got \(result).")
            throw TestFailure()
        }

        #expect(fallbackDiagnostics?.notes == [diagnosticNote])
        #expect(contains(executionResult.title, diagnosticNote) == false)
        #expect(contains(executionResult.subtitle, diagnosticNote) == false)
        #expect(contains(executionResult.primaryValue, diagnosticNote) == false)
        #expect(contains(executionResult.explanation, diagnosticNote) == false)
        #expect(executionResult.rows.allSatisfy { row in
            contains(row.title, diagnosticNote) == false
                && contains(row.value, diagnosticNote) == false
        })
    }

    @Test func nonDebugPolicyDoesNotExposeDiagnosticsThroughUserFacingResultSurfaces() throws {
        let defaults = try makeDefaults(suiteName: "MarinaUniversalRoutingDiagnosticsTests.nonDebug")
        defer { defaults.removePersistentDomain(forName: "MarinaUniversalRoutingDiagnosticsTests.nonDebug") }
        defaults.set(true, forKey: MarinaUniversalRoutingDebugFlagResolver.key)
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let plan = fixture.plan(for: request)
        let policy = MarinaUniversalRoutingDebugFlagResolver.policy(
            defaults: defaults,
            arguments: ["App", "-\(MarinaUniversalRoutingDebugFlagResolver.key)", "on"],
            environment: [MarinaUniversalRoutingDebugFlagResolver.key: "yes"],
            isDebugBuild: false
        )
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: StubUniversalHarness(result: universalResult(for: request)),
            policy: policy
        )

        let result = executor.executeResult(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        #expect(policy == .disabled)
        guard case let .legacy(executionResult, diagnostics) = result else {
            Issue.record("Expected disabled legacy result, got \(result).")
            throw TestFailure()
        }
        #expect(diagnostics == nil)
        #expect(executionResult.title != "Universal Result")
    }

    private func makeFixture() -> MarinaUniversalRoutingDiagnosticsFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let card = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let category = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)
        let budget = Budget(
            name: "June",
            startDate: date(2026, 6, 1),
            endDate: date(2026, 6, 30),
            workspace: workspace
        )
        let expense = VariableExpense(
            descriptionText: "Apple Store",
            amount: 120,
            transactionDate: date(2026, 6, 5),
            workspace: workspace,
            card: card,
            category: category
        )
        let planned = PlannedExpense(
            title: "Phone Bill",
            plannedAmount: 80,
            expenseDate: date(2026, 6, 16),
            workspace: workspace,
            card: card,
            category: category,
            sourceBudgetID: budget.id
        )
        let income = Income(
            source: "Paycheck",
            amount: 2_000,
            date: date(2026, 6, 11),
            isPlanned: false,
            workspace: workspace,
            card: card
        )
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

        return MarinaUniversalRoutingDiagnosticsFixture(
            snapshot: snapshot,
            now: date(2026, 6, 15),
            calendar: calendar
        )
    }

    private func merchantSpendRequest() -> MarinaSemanticRequest {
        semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            textQuery: "Apple",
            expenseScope: .variable
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
        resultLimit: Int? = nil,
        sort: MarinaSemanticSort? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        incomeState: MarinaSemanticIncomeState? = nil,
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
            incomeState: incomeState,
            expectedAnswerShape: shape
        )
    }

    private func universalResult(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingResult {
        .universal(
            MarinaExecutionResult(
                kind: .metric,
                title: "Universal Result",
                primaryValue: "$42.00",
                rows: [HomeAnswerRow(title: "Universal", value: "$42.00", amount: 42)]
            ),
            diagnostics: MarinaUniversalRoutingDiagnostics(
                requestEntity: request.entity,
                operation: request.operation,
                measure: request.measure,
                scenario: .merchantVariableSpend,
                usedUniversal: true,
                fallbackReason: nil,
                notes: ["Stub universal result."]
            )
        )
    }

    private func makeDefaults(suiteName: String) throws -> UserDefaults {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func contains(_ value: String?, _ needle: String) -> Bool {
        value?.contains(needle) == true
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(
            calendar: calendar,
            timeZone: TimeZone(secondsFromGMT: 0),
            year: year,
            month: month,
            day: day
        ).date!
    }
}

@MainActor
private struct MarinaUniversalRoutingDiagnosticsFixture {
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

    func harness() -> MarinaUniversalRoutingHarness {
        let formulaRegistry = MarinaFormulaRegistry(now: now, calendar: calendar)
        return MarinaUniversalRoutingHarness(
            bridge: MarinaSemanticUniversalPlanBridge(formulaRegistry: formulaRegistry),
            runner: MarinaUniversalQueryRunner(formulaRegistry: formulaRegistry),
            presenter: MarinaUniversalResultPresenter(),
            policy: .internalParityProven
        )
    }
}

@MainActor
private struct StubUniversalHarness: MarinaUniversalRoutingAttempting {
    let result: MarinaUniversalRoutingResult

    func attemptUniversalResult(
        request: MarinaSemanticRequest,
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot,
        context: MarinaUniversalPlanningContext
    ) -> MarinaUniversalRoutingResult {
        result
    }
}

private struct TestFailure: Error {}
