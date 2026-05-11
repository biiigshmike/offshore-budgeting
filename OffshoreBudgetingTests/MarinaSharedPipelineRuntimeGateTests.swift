import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaSharedPipelineRuntimeGateTests {
    @Test func runtimeGate_gateOffUsesLegacyFallbackPath() async throws {
        let fixture = try makeFixture()
        let result = await MarinaSharedPipelineCoordinator(
            availability: SharedPipelineStubAvailability(status: .available),
            structuredInterpreter: SharedPipelineStubStructuredInterpreter(structuredIntent: .unresolved)
        ).run(
            prompt: "Where is my money going?",
            context: sharedContext(fixture: fixture, sharedPipelineEnabled: false, aiOptInEnabled: true)
        )

        guard case .fallbackToLegacy(let trace) = result else {
            Issue.record("Gate-off coordinator should not handle.")
            return
        }
        #expect(trace.selectedPath == .legacy)
        #expect(trace.fallbackReason == .gateDisabled)
        #expect(trace.interpreterSource == nil)
    }

    @Test func runtimeGate_gateOnExecutableValidatedPlanRunsExecutor() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "Where is my money going?",
            context: sharedContext(fixture: fixture)
        )

        guard case .handled(let answer, let aggregationResult, _, let trace) = result else {
            Issue.record("Expected grouped ranking prompt to execute behind the gate.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(answer.kind == .list)
        guard case .rankedList(let list) = aggregationResult else {
            Issue.record("Expected ranked-list aggregation result.")
            return
        }
        #expect(list.rows.isEmpty == false)
    }

    @Test func runtimeGate_phase6DHandledShapesExecuteThroughSharedPath() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        try fixture.seedComparisonData()
        try seedMarchAprilGroceries(fixture)

        let examples: [(String, HomeQueryMetric, HomeAnswerKind, String)] = [
            ("What did I spend this month?", .spendTotal, .metric, "scalar"),
            ("What did I spend on groceries this month?", .categorySpendTotal, .metric, "scalar"),
            ("What did I spend on my Apple Card this month?", .cardSpendTotal, .metric, "scalar"),
            ("What percent of my spending was groceries this month?", .categorySpendShare, .metric, "scalar"),
            ("Break down my spending by category this month.", .topCategories, .list, "groupedBreakdown"),
            ("Compare groceries this month to last month.", .categoryMonthComparison, .comparison, "comparison"),
            ("Did groceries go up or down from March to April?", .categoryMonthComparison, .comparison, "comparison")
        ]

        for example in examples {
            let result = await MarinaSharedPipelineCoordinator().run(
                prompt: example.0,
                context: sharedContext(fixture: fixture)
            )

            guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
                Issue.record("Expected handled shared result for: \(example.0) | \(result.trace.compactSummary)")
                continue
            }
            #expect(trace.selectedPath == .sharedHeuristic)
            #expect(trace.interpreterSource == .heuristic)
            #expect(trace.validatorOutcomeSummary?.contains("executable") == true)
            #expect(trace.executorResultSummary != nil)
            #expect(trace.responseBridgeSummary?.contains("kind=\(example.2.rawValue)") == true)
            #expect(trace.fallbackReason == nil)
            #expect(homeQueryPlan?.metric == example.1)
            #expect(answer.kind == example.2)
            assertAggregationResult(aggregationResult, shape: example.3, prompt: example.0)
        }
    }

    @Test func runtimeGate_remainingBlockedShapesDoNotExecuteOrFallback() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        let prompts = [
            "Is Shopping over where it should be for this budget?",
            "If I keep spending like this, how much will I have left by the end of the period?",
            "If I add $75 to Shopping, does Transportation still have room?"
        ]

        for prompt in prompts {
            let result = await MarinaSharedPipelineCoordinator().run(
                prompt: prompt,
                context: sharedContext(fixture: fixture)
            )

            guard case .validationBlocked(let answer, let outcome, let trace) = result else {
                Issue.record("Expected validation-blocked shared result for: \(prompt) | \(result.trace.compactSummary)")
                continue
            }
            #expect(answer.kind == .message)
            switch outcome {
            case .clarification, .unsupported:
                break
            case .executable:
                Issue.record("Blocked prompt unexpectedly validated as executable: \(prompt)")
            }
            #expect(trace.selectedPath == .sharedHeuristic)
            #expect(trace.validatorOutcomeSummary?.contains("unsupported") == true || trace.validatorOutcomeSummary?.contains("clarification") == true)
            #expect(trace.executorResultSummary == nil)
            #expect(trace.responseBridgeSummary?.contains("kind=message") == true)
            #expect(trace.fallbackReason == nil)
        }
    }

    @Test func runtimeGate_typedClarificationDoesNotExecute() async throws {
        let fixture = try makeFixture()
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "What did I spend on Mystery this month?",
            context: sharedContext(fixture: fixture)
        )

        guard case .validationBlocked(let answer, let outcome, let trace) = result else {
            Issue.record("Unresolved target should not execute.")
            return
        }
        #expect(answer.kind == .message)
        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected typed clarification.")
            return
        }
        #expect(clarification.kind == .missingTarget)
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.fallbackReason == nil)
        #expect(trace.validatorOutcomeSummary?.contains("clarification") == true)
        #expect(trace.executorResultSummary == nil)
    }

    @Test func runtimeGate_typedUnsupportedDoesNotExecute() async throws {
        let fixture = try makeFixture()
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "average Groceries for the last 3 months",
            context: sharedContext(fixture: fixture)
        )

        guard case .validationBlocked(let answer, let outcome, let trace) = result else {
            Issue.record("Targeted average remains unsupported in shared executor.")
            return
        }
        #expect(answer.kind == .message)
        guard case .unsupported = outcome else {
            Issue.record("Expected typed unsupported.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.fallbackReason == nil)
        #expect(trace.executorResultSummary == nil)
    }

    @Test func runtimeGate_simulationExecutesThroughComposableWorkspaceQuery() async throws {
        let fixture = try makeFixture()
        let budget = Budget(name: "May", startDate: sharedPipelineDate(2026, 5, 1), endDate: sharedPipelineDate(2026, 5, 31), workspace: fixture.workspace)
        fixture.context.insert(budget)
        fixture.context.insert(BudgetCategoryLimit(maxAmount: 500, budget: budget, category: fixture.groceries))
        fixture.context.insert(Income(source: "Planned", amount: 1_000, date: sharedPipelineDate(2026, 5, 1), isPlanned: true, workspace: fixture.workspace))
        try fixture.context.save()

        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "If I spend $50 on Groceries, how will that affect my budget?",
            context: sharedContext(fixture: fixture)
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Simulation should execute through composable workspace query.")
            return
        }
        #expect(answer.title == "What-If Budget Impact")
        #expect(homeQueryPlan == nil)
        guard case .workspaceCard = aggregationResult else {
            Issue.record("Expected simulation workspace card.")
            return
        }
        #expect(trace.executorResultSummary?.contains("composableWorkspace=simulation") == true)
        #expect(trace.fallbackReason == nil)
    }

    private func seedMarchAprilGroceries(_ fixture: MarinaPhase5Fixture) throws {
        fixture.context.insert(PlannedExpense(title: "March Groceries", plannedAmount: 80, expenseDate: sharedPipelineDate(2026, 3, 5), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(PlannedExpense(title: "April Groceries Again", plannedAmount: 120, expenseDate: sharedPipelineDate(2026, 4, 12), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()
    }

    private func assertAggregationResult(
        _ result: MarinaAggregationResult,
        shape: String,
        prompt: String
    ) {
        switch (shape, result) {
        case ("scalar", .scalar),
             ("comparison", .comparison),
             ("rankedList", .rankedList),
             ("groupedBreakdown", .groupedBreakdown):
            break
        default:
            Issue.record("Unexpected aggregation shape for \(prompt): \(result)")
        }
    }
}
