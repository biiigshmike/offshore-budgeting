import Foundation
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaFoundationReadinessCheckTests {
    @Test func readiness_availableModelRunsTypedInterpretationAndDeterministicExecution() async throws {
        let fixture = try makeFixture()
        let prompt = MarinaFoundationReadinessCheck.diagnosticPrompt
        let check = MarinaFoundationReadinessCheck(
            availability: ReadinessAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: workspaceLookupInterpretation(prompt: prompt)
            ]),
            now: { fixedNow }
        )

        let report = await check.run(context: turnContext(provider: fixture.provider))

        #expect(report.passed)
        #expect(status(.typedInterpretation, in: report) == .passed)
        #expect(status(.deterministicExecution, in: report) == .passed)
    }

    @Test func readiness_modelNotReadySkipsTypedAndDeterministicRoundTrips() async throws {
        let fixture = try makeFixture()
        let check = MarinaFoundationReadinessCheck(
            availability: ReadinessAvailability(status: .unavailable(reason: .modelNotReady)),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:]),
            now: { fixedNow }
        )

        let report = await check.run(context: turnContext(provider: fixture.provider))

        #expect(report.passed == false)
        #expect(status(.modelReadiness, in: report) == .failed)
        #expect(status(.typedInterpretation, in: report) == .skipped)
        #expect(status(.deterministicExecution, in: report) == .skipped)
    }

    @Test func readiness_typedInterpretationFailureSkipsDeterministicExecution() async throws {
        let fixture = try makeFixture()
        let check = MarinaFoundationReadinessCheck(
            availability: ReadinessAvailability(status: .available),
            interpreter: ThrowingReadinessInterpreter(),
            now: { fixedNow }
        )

        let report = await check.run(context: turnContext(provider: fixture.provider))

        #expect(report.passed == false)
        #expect(status(.typedInterpretation, in: report) == .failed)
        #expect(status(.deterministicExecution, in: report) == .skipped)
    }

    @Test func readiness_deterministicFailureIsReportedWithoutAvailabilityFallback() async throws {
        let fixture = try makeFixture()
        let prompt = MarinaFoundationReadinessCheck.diagnosticPrompt
        let check = MarinaFoundationReadinessCheck(
            availability: ReadinessAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: unsupportedInterpretation(prompt: prompt)
            ]),
            now: { fixedNow }
        )

        let report = await check.run(context: turnContext(provider: fixture.provider))

        #expect(report.passed == false)
        #expect(status(.typedInterpretation, in: report) == .passed)
        #expect(status(.deterministicExecution, in: report) == .failed)
    }

    @Test func readiness_marinaPreferenceOffSkipsAllRuntimeChecks() async throws {
        let fixture = try makeFixture()
        let check = MarinaFoundationReadinessCheck(
            availability: ReadinessAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:]),
            now: { fixedNow }
        )

        let report = await check.run(context: turnContext(provider: fixture.provider, aiEnabled: false))

        #expect(report.passed == false)
        #expect(status(.marinaPreference, in: report) == .failed)
        #expect(status(.foundationRuntime, in: report) == .skipped)
        #expect(status(.typedInterpretation, in: report) == .skipped)
    }

    private func turnContext(
        provider: MarinaDataProvider,
        aiEnabled: Bool = true
    ) -> MarinaTurnContext {
        MarinaTurnContext(
            provider: provider,
            routerContext: MarinaInterpretationContext(
                workspaceName: "Phase 5 Workspace",
                defaultPeriodUnit: .month,
                sessionContext: MarinaSessionContext(),
                priorQueryContext: .empty,
                cardNames: [],
                categoryNames: [],
                incomeSourceNames: [],
                presetTitles: [],
                budgetNames: [],
                aliasSummaries: [],
                now: fixedNow
            ),
            defaultPeriodUnit: .month,
            aiEnabled: aiEnabled,
            now: fixedNow
        )
    }

    private func workspaceLookupInterpretation(prompt: String) -> MarinaCanonicalReadInterpretation {
        let request = MarinaDatabaseLookupRequest(
            rawPrompt: prompt,
            searchText: "",
            objectTypes: [.workspace],
            dateRange: nil,
            limit: 5,
            requestedDetail: .general
        )
        let candidate = MarinaQueryPlanCandidate(
            requestFamily: .databaseLookup,
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .lookupDetails,
            responseShapeHint: .summaryCard,
            confidence: .high,
            databaseLookupRequest: request
        )
        return MarinaCanonicalReadInterpretation(
            result: MarinaSemanticQueryAdapter().interpretationResult(from: candidate),
            compatibilityCandidate: candidate
        )
    }

    private func unsupportedInterpretation(prompt: String) -> MarinaCanonicalReadInterpretation {
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            responseShapeHint: .unsupported,
            confidence: .high,
            unsupportedHint: .unsupportedOperation
        )
        return MarinaCanonicalReadInterpretation(
            result: MarinaSemanticQueryAdapter().interpretationResult(from: candidate),
            compatibilityCandidate: candidate
        )
    }

    private func status(
        _ kind: MarinaFoundationReadinessStep.Kind,
        in report: MarinaFoundationReadinessReport
    ) -> MarinaFoundationReadinessStep.Status? {
        report.steps.first { $0.kind == kind }?.status
    }

    private var fixedNow: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 5, day: 15))!
    }
}

private struct ReadinessAvailability: MarinaModelAvailabilityProviding {
    let status: MarinaModelAvailability.Status

    func currentStatus() -> MarinaModelAvailability.Status {
        status
    }
}

private struct ThrowingReadinessInterpreter: MarinaCanonicalAIInterpreting {
    enum Failure: Error {
        case typedRoundTripFailed
    }

    func interpretCanonical(
        prompt _: String,
        context _: MarinaInterpretationContext
    ) async throws -> MarinaCanonicalReadInterpretation {
        throw Failure.typedRoundTripFailed
    }
}
