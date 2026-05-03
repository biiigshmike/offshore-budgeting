import Foundation
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

    @Test func runtimeGate_typedClarificationDoesNotExecute() async throws {
        let fixture = try makeFixture()
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "What did I spend on Mystery this month?",
            context: sharedContext(fixture: fixture)
        )

        guard case .fallbackToLegacy(let trace) = result else {
            Issue.record("Unresolved target should not execute.")
            return
        }
        #expect(trace.fallbackReason == .clarificationBridgeUnavailable)
        #expect(trace.validatorOutcomeSummary?.contains("clarification") == true)
        #expect(trace.executorResultSummary == nil)
    }

    @Test func runtimeGate_typedUnsupportedDoesNotExecute() async throws {
        let fixture = try makeFixture()
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "average Groceries for the last 3 months",
            context: sharedContext(fixture: fixture)
        )

        guard case .fallbackToLegacy(let trace) = result else {
            Issue.record("Targeted average remains unsupported in shared executor.")
            return
        }
        #expect(trace.fallbackReason == .adapterUnsupported || trace.fallbackReason == .unsupportedBridgeUnavailable)
    }

    @Test func runtimeGate_simulationDoesNotExecute() async throws {
        let fixture = try makeFixture()
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "If I increase Shopping by $100, what will I have left for Transportation?",
            context: sharedContext(fixture: fixture)
        )

        guard case .fallbackToLegacy(let trace) = result else {
            Issue.record("Simulation should not execute in Phase 6.")
            return
        }
        #expect(trace.validatorOutcomeSummary?.contains("unsupported") == true || trace.fallbackReason != nil)
        #expect(trace.executorResultSummary == nil)
    }
}

