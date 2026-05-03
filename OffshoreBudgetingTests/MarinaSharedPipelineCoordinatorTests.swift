import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaSharedPipelineCoordinatorTests {
    @Test func coordinator_gateOffFallsBackWithoutRunningSharedPipeline() async throws {
        let fixture = try makeFixture()
        let result = await coordinator().run(
            prompt: "What did I spend this month?",
            context: sharedContext(fixture: fixture, sharedPipelineEnabled: false)
        )

        guard case .fallbackToLegacy(let trace) = result else {
            Issue.record("Gate-off shared pipeline should fall back to legacy.")
            return
        }
        #expect(trace.fallbackReason == .gateDisabled)
        #expect(trace.selectedPath == .legacy)
        #expect(trace.candidateSummary == nil)
    }

    @Test func coordinator_gateOnAIOptOutUsesHeuristicInterpreter() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator().run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: false)
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected heuristic shared pipeline to handle card spend.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.interpreterSource == .heuristic)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
        #expect(answer.kind == .metric)
        guard case .scalar(let scalar) = aggregationResult else {
            Issue.record("Expected scalar result.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("500"))
    }

    @Test func coordinator_aiUnavailableFallsBackToHeuristic() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator(availability: SharedPipelineStubAvailability(status: .unavailable(reason: "test_unavailable"))).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("AI unavailable should still allow heuristic execution.")
            return
        }
        #expect(trace.modelAvailabilitySummary == "unavailable:test_unavailable")
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_modelServiceFailureFallsBackToHeuristicWithTrace() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator(structuredInterpreter: SharedPipelineThrowingStructuredInterpreter()).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Model service failure should not crash and should use heuristic.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.disagreementSummary == MarinaSharedPipelineFallbackReason.modelServiceFailed.rawValue)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_modelSelectedWhenOptedInAvailableAndExecutable() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "cardSpendTotal",
                    targetName: "Apple Card",
                    targetTypeRaw: "card",
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected executable model candidate to handle.")
            return
        }
        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(trace.interpreterSource == .foundationModels)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_lowConfidenceModelTriggersHeuristicFallback() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "cardSpendTotal",
                    targetName: "Apple Card",
                    targetTypeRaw: "card",
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "low",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Low-confidence model candidate should allow heuristic handling.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.disagreementSummary != nil)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_modelHeuristicDisagreementIsTracedAndNotMerged() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "spendTotal",
                    targetName: nil,
                    targetTypeRaw: nil,
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected disagreement to still produce the conservative heuristic answer.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.disagreementSummary?.contains("model[") == true)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_invalidSharedResultFallsBackToLegacyWithReason() async throws {
        let fixture = try makeFixture()
        let result = await coordinator().run(
            prompt: "total spend on my Missing Card",
            context: sharedContext(fixture: fixture)
        )

        guard case .fallbackToLegacy(let trace) = result else {
            Issue.record("Unknown target should fall back to legacy.")
            return
        }
        #expect(trace.fallbackReason == .clarificationBridgeUnavailable)
        #expect(trace.validatorOutcomeSummary?.contains("clarification") == true)
    }

    private func coordinator(
        availability: MarinaModelAvailabilityProviding = SharedPipelineStubAvailability(status: .available),
        structuredInterpreter: MarinaStructuredIntentInterpreting = SharedPipelineStubStructuredInterpreter(structuredIntent: .unresolved)
    ) -> MarinaSharedPipelineCoordinator {
        MarinaSharedPipelineCoordinator(
            availability: availability,
            structuredInterpreter: structuredInterpreter
        )
    }
}
