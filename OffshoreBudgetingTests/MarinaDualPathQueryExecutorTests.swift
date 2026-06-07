import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaDualPathQueryExecutorTests {
    @Test func disabledPolicyUsesLegacyExecutor() throws {
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let plan = fixture.plan(for: request)
        let expected = fixture.legacyExecutor.execute(plan: plan, snapshot: fixture.snapshot)
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: StubUniversalHarness(result: universalResult(for: request)),
            policy: .disabled
        )

        let result = executor.executeResult(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        guard case let .legacy(actual, diagnostics) = result else {
            Issue.record("Expected legacy result, got \(result).")
            throw TestFailure()
        }
        expectResult(actual, matches: expected)
        #expect(diagnostics == nil)
    }

    @Test func missingHarnessUsesLegacyExecutor() throws {
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let plan = fixture.plan(for: request)
        let expected = fixture.legacyExecutor.execute(plan: plan, snapshot: fixture.snapshot)
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: nil,
            policy: .internalParityProven
        )

        let result = executor.executeResult(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        guard case let .legacy(actual, diagnostics) = result else {
            Issue.record("Expected legacy result, got \(result).")
            throw TestFailure()
        }
        expectResult(actual, matches: expected)
        #expect(diagnostics == nil)
    }

    @Test func enabledAllowlistedRequestReturnsUniversalResult() throws {
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let plan = fixture.plan(for: request)
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: fixture.harness(),
            policy: .internalParityProven
        )

        let result = executor.executeResult(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        guard case let .universal(actual, diagnostics) = result else {
            Issue.record("Expected universal result, got \(result).")
            throw TestFailure()
        }
        #expect(actual.kind == .metric)
        #expect(diagnostics.usedUniversal)
        #expect(diagnostics.fallbackReason == nil)
        #expect(diagnostics.notes.contains { $0.contains("Universal routing succeeded") })
    }

    @Test func enabledNonAllowlistedRequestFallsBackToLegacy() throws {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .burnRate
        )
        let plan = fixture.plan(for: request)
        let expected = fixture.legacyExecutor.execute(plan: plan, snapshot: fixture.snapshot)
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: fixture.harness(),
            policy: .internalParityProven
        )

        let result = executor.executeResult(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        guard case let .legacy(actual, diagnostics) = result else {
            Issue.record("Expected legacy fallback, got \(result).")
            throw TestFailure()
        }
        expectResult(actual, matches: expected)
        #expect(diagnostics?.fallbackReason == .notAllowlisted)
        #expect(diagnostics?.usedUniversal == false)
    }

    @Test func bridgeUnsupportedFallsBackToLegacy() throws {
        let fixture = makeFixture()
        let request = savingsTotalRequest(targetName: "Savings Account")
        let plan = fixture.plan(for: request)
        let expected = fixture.legacyExecutor.execute(plan: plan, snapshot: fixture.snapshot)
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: fixture.harness(bridgeUsesFormulaRegistry: false, runnerUsesFormulaRegistry: true),
            policy: .internalParityProven
        )

        let result = executor.executeResult(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        guard case let .legacy(actual, diagnostics) = result else {
            Issue.record("Expected legacy fallback, got \(result).")
            throw TestFailure()
        }
        expectResult(actual, matches: expected)
        #expect(diagnostics?.fallbackReason == .unsupportedBridge)
        #expect(diagnostics?.notes.contains { $0.contains("Bridge unsupported") } == true)
    }

    @Test func runnerUnsupportedFallsBackToLegacy() throws {
        let fixture = makeFixture()
        let request = savingsTotalRequest(targetName: "Savings Account")
        let plan = fixture.plan(for: request)
        let expected = fixture.legacyExecutor.execute(plan: plan, snapshot: fixture.snapshot)
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: fixture.harness(bridgeUsesFormulaRegistry: true, runnerUsesFormulaRegistry: false),
            policy: .internalParityProven
        )

        let result = executor.executeResult(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        guard case let .legacy(actual, diagnostics) = result else {
            Issue.record("Expected legacy fallback, got \(result).")
            throw TestFailure()
        }
        expectResult(actual, matches: expected)
        #expect(diagnostics?.fallbackReason == .unsupportedRunner)
        #expect(diagnostics?.notes.contains { $0.contains("Runner unsupported") } == true)
    }

    @Test func presentationUnsupportedFallsBackToLegacy() throws {
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let plan = fixture.plan(for: request)
        let diagnostics = fallbackDiagnostics(
            for: request,
            reason: .unsupportedPresentation,
            notes: ["Presentation unsupported=synthetic"]
        )
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: StubUniversalHarness(result: .fallback(reason: .unsupportedPresentation, diagnostics: diagnostics)),
            policy: .internalParityProven
        )

        let result = executor.executeResult(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        guard case let .legacy(_, fallbackDiagnostics) = result else {
            Issue.record("Expected legacy fallback, got \(result).")
            throw TestFailure()
        }
        #expect(fallbackDiagnostics?.fallbackReason == .unsupportedPresentation)
        #expect(fallbackDiagnostics?.notes == diagnostics.notes)
    }

    @Test func fallbackDiagnosticsPreserveFallbackReason() throws {
        let fixture = makeFixture()
        let request = semanticRequest(
            entity: .budget,
            operation: .whatIf,
            measure: .remainingRoom
        )
        let plan = fixture.plan(for: request)
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: fixture.harness(),
            policy: .internalParityProven
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

    @Test func userFacingAnswerCopyDoesNotIncludeDiagnostics() throws {
        let fixture = makeFixture()
        let request = merchantSpendRequest()
        let plan = fixture.plan(for: request)
        let diagnosticNote = "Diagnostics: do not show this to the user."
        let diagnostics = fallbackDiagnostics(
            for: request,
            reason: .unsupportedPresentation,
            notes: [diagnosticNote]
        )
        let executor = MarinaDualPathQueryExecutor(
            legacyExecutor: fixture.legacyExecutor,
            universalHarness: StubUniversalHarness(result: .fallback(reason: .unsupportedPresentation, diagnostics: diagnostics)),
            policy: .internalParityProven
        )

        let result = executor.execute(
            plan: plan,
            snapshot: fixture.snapshot,
            planningContext: fixture.context()
        )

        #expect(result.title.contains(diagnosticNote) == false)
        #expect(result.subtitle?.contains(diagnosticNote) != true)
        #expect(result.explanation?.contains(diagnosticNote) != true)
    }

    private func makeFixture() -> MarinaDualPathFixture {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let appleCard = Card(name: "Apple Card", theme: "ruby", effect: "plastic", workspace: workspace)
        let chaseCard = Card(name: "Chase Card", theme: "sky", effect: "matte", workspace: workspace)
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        let electronics = Offshore.Category(name: "Electronics", hexColor: "#0EA5E9", workspace: workspace)
        let budget = Budget(name: "June", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: workspace)

        let appleStore = VariableExpense(descriptionText: "Apple Store", amount: 120, transactionDate: date(2026, 6, 5), workspace: workspace, card: appleCard, category: electronics)
        let appleMarket = VariableExpense(descriptionText: "Apple Market", amount: 18, transactionDate: date(2026, 6, 20), workspace: workspace, card: appleCard, category: groceries)
        let kroger = VariableExpense(descriptionText: "Kroger", amount: 30, transactionDate: date(2026, 6, 10), workspace: workspace, card: chaseCard, category: groceries)

        let phoneBill = PlannedExpense(
            title: "Phone Bill",
            plannedAmount: 80,
            expenseDate: date(2026, 6, 16),
            workspace: workspace,
            card: appleCard,
            category: electronics,
            sourceBudgetID: budget.id
        )
        let rent = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: date(2026, 6, 25),
            workspace: workspace,
            card: chaseCard,
            category: nil,
            sourceBudgetID: budget.id
        )

        let actualPaycheck = Income(source: "Paycheck", amount: 2_000, date: date(2026, 6, 11), isPlanned: false, workspace: workspace, card: appleCard)
        let plannedPaycheck = Income(source: "Paycheck", amount: 2_100, date: date(2026, 6, 25), isPlanned: true, workspace: workspace, card: appleCard)

        let savings = SavingsAccount(name: "Savings Account", total: 1_000, workspace: workspace)
        let alejandro = AllocationAccount(name: "Alejandro", workspace: workspace)
        let allocation = ExpenseAllocation(
            allocatedAmount: 10,
            preservesGrossAmount: true,
            workspace: workspace,
            account: alejandro,
            expense: kroger
        )
        let settlement = AllocationSettlement(
            date: date(2026, 6, 21),
            note: "Alejandro paid back",
            amount: -4,
            workspace: workspace,
            account: alejandro
        )
        kroger.allocation = allocation
        alejandro.expenseAllocations = [allocation]
        alejandro.settlements = [settlement]

        let variableExpenses = [appleStore, appleMarket, kroger]
        let plannedExpenses = [phoneBill, rent]
        let incomes = [actualPaycheck, plannedPaycheck]
        let snapshot = MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [budget],
            cards: [appleCard, chaseCard],
            categories: [groceries, electronics],
            presets: [],
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            homePlannedExpenses: plannedExpenses,
            homeCalculationPlannedExpenses: plannedExpenses,
            homeCalculationVariableExpenses: variableExpenses,
            reconciliationAccounts: [alejandro],
            expenseAllocations: [allocation],
            allocationSettlements: [settlement],
            savingsAccounts: [savings],
            savingsEntries: [],
            incomes: incomes
        )

        return MarinaDualPathFixture(
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

    private func savingsTotalRequest(targetName: String?) -> MarinaSemanticRequest {
        semanticRequest(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            dateRangeToken: .allTime,
            targetName: targetName
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
                usedUniversal: true,
                fallbackReason: nil,
                notes: ["Stub universal result."]
            )
        )
    }

    private func fallbackDiagnostics(
        for request: MarinaSemanticRequest,
        reason: MarinaUniversalFallbackReason,
        notes: [String]
    ) -> MarinaUniversalRoutingDiagnostics {
        MarinaUniversalRoutingDiagnostics(
            requestEntity: request.entity,
            operation: request.operation,
            measure: request.measure,
            usedUniversal: false,
            fallbackReason: reason,
            notes: notes
        )
    }

    private func expectResult(
        _ actual: MarinaExecutionResult,
        matches expected: MarinaExecutionResult
    ) {
        #expect(actual.kind == expected.kind)
        #expect(actual.title == expected.title)
        #expect(actual.subtitle == expected.subtitle)
        #expect(actual.primaryValue == expected.primaryValue)
        #expect(actual.attachment == expected.attachment)
        #expect(actual.explanation == expected.explanation)
        #expect(actual.rows.count == expected.rows.count)

        for (actualRow, expectedRow) in zip(actual.rows, expected.rows) {
            #expect(actualRow.title == expectedRow.title)
            #expect(actualRow.value == expectedRow.value)
            #expect(actualRow.sourceID == expectedRow.sourceID)
            #expect(actualRow.objectType == expectedRow.objectType)
            #expect(actualRow.amount == expectedRow.amount)
            #expect(actualRow.date == expectedRow.date)
            #expect(actualRow.role == expectedRow.role)
        }
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
private struct MarinaDualPathFixture {
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

    func harness(
        bridgeUsesFormulaRegistry: Bool = true,
        runnerUsesFormulaRegistry: Bool = true
    ) -> MarinaUniversalRoutingHarness {
        let bridgeFormulaRegistry: MarinaFormulaRegistry? = bridgeUsesFormulaRegistry
            ? MarinaFormulaRegistry(now: now, calendar: calendar)
            : nil
        let runnerFormulaRegistry: MarinaFormulaRegistry? = runnerUsesFormulaRegistry
            ? MarinaFormulaRegistry(now: now, calendar: calendar)
            : nil

        return MarinaUniversalRoutingHarness(
            bridge: MarinaSemanticUniversalPlanBridge(formulaRegistry: bridgeFormulaRegistry),
            runner: MarinaUniversalQueryRunner(formulaRegistry: runnerFormulaRegistry),
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
