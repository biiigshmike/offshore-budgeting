import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaSharedPipelineTraceTests {
    @Test func sharedTrace_recordsHandledPathDetails() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture)
        )

        guard case .handled(_, _, _, let trace) = result else {
            Issue.record("Expected handled trace.")
            return
        }
        #expect(trace.sharedPipelineEnabled)
        #expect(trace.aiOptInEnabled == false)
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.interpreterSource == .heuristic)
        #expect(trace.candidateSummary?.contains("source=heuristic") == true)
        #expect(trace.resolverSummary?.contains("resolved=1") == true)
        #expect(trace.validatorOutcomeSummary?.contains("executable") == true)
        #expect(trace.executorResultSummary?.contains("scalar") == true)
        #expect(trace.responseBridgeSummary?.contains("kind=metric") == true)
        #expect(trace.fallbackReason == nil)
    }

    @Test func sharedTrace_recordsFallbackReason() async throws {
        let fixture = try makeFixture()
        let result = await MarinaSharedPipelineCoordinator().run(
            prompt: "What did I spend on Unknown this month?",
            context: sharedContext(fixture: fixture)
        )

        guard case .fallbackToLegacy(let trace) = result else {
            Issue.record("Expected fallback trace.")
            return
        }
        #expect(trace.selectedPath == .sharedAttemptedThenLegacyFallback)
        #expect(trace.fallbackReason == .clarificationBridgeUnavailable)
        #expect(trace.compactSummary.contains("fallback=clarificationBridgeUnavailable"))
    }

    @Test func executionTraceRecorderStoresSharedPipelineFields() {
        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(
            prompt: "What did I spend this month?",
            routingMode: .sharedPipeline,
            marinaNLQv1Enabled: false
        )
        MarinaTraceRecorder.shared.recordSharedPipelineTrace(
            MarinaSharedPipelineTrace(
                sharedPipelineEnabled: true,
                aiOptInEnabled: false,
                selectedPath: .sharedHeuristic,
                interpreterSource: .heuristic,
                candidateSummary: "candidate",
                resolverSummary: "resolver",
                validatorOutcomeSummary: "validator",
                executorResultSummary: "executor",
                responseBridgeSummary: "bridge",
                fallbackReason: nil,
                disagreementSummary: nil
            )
        )
        MarinaTraceRecorder.shared.recordSelectedRoute(.sharedHeuristic, reason: "test")
        let trace = MarinaTraceRecorder.shared.finish()

        #expect(trace?.routingMode == .sharedPipeline)
        #expect(trace?.selectedRoute == .sharedHeuristic)
        #expect(trace?.sharedPipelineEnabled == true)
        #expect(trace?.sharedPipelinePath == .sharedHeuristic)
        #expect(trace?.sharedPipelineCandidateSummary == "candidate")
        #expect(trace?.sharedPipelineResolverSummary == "resolver")
        #expect(trace?.sharedPipelineValidatorSummary == "validator")
        #expect(trace?.sharedPipelineExecutorSummary == "executor")
        #expect(trace?.sharedPipelineResponseBridgeSummary == "bridge")
    }
}

