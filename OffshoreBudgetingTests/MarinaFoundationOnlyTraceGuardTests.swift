import Foundation
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaFoundationOnlyTraceGuardTests {
    @Test func normalReadTrace_staysFoundationOnly() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let prompt = "How much did I spend on Groceries this month?"
        let interpretation = canonicalInterpretation(
            candidate: spendCandidate(
                prompt: prompt,
                mentions: [mention("Groceries", .category)],
                timeScopes: [timeScope("this month", monthRange(2026, 5), .month)]
            )
        )
        let coordinator = MarinaV2TurnCoordinator(
            availability: FoundationOnlyAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [prompt: interpretation])
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(provider: fixture.provider))
        }

        guard case .handled = result else {
            Issue.record("Expected handled Foundation-only read.")
            return
        }
        assertFoundationOnly(trace)
    }

    @Test func typedClarificationTrace_staysFoundationOnly() async throws {
        let fixture = try makeFixture()
        let prompt = "What did I spend at Apple?"
        let candidate = spendCandidate(
            prompt: prompt,
            mentions: [mention("Apple", .merchant)]
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Apple did you mean?",
            candidate: candidate,
            patchSlot: .target,
            choices: [
                choice("Apple", .merchant),
                choice("Apple Card", .card)
            ]
        )
        let interpretation = MarinaCanonicalReadInterpretation(
            result: .clarification(clarification),
            compatibilityCandidate: candidate
        )
        let coordinator = MarinaV2TurnCoordinator(
            availability: FoundationOnlyAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [prompt: interpretation])
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(provider: fixture.provider))
        }

        guard case .clarification = result else {
            Issue.record("Expected typed clarification.")
            return
        }
        assertFoundationOnly(trace, allowsClarificationRoute: true)
    }

    @Test func clarificationResumeTrace_staysFoundationOnly() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let prompt = "What did I spend at Apple?"
        let mentionID = UUID()
        let candidate = spendCandidate(
            prompt: prompt,
            mentions: [mention("Apple", .merchant, id: mentionID)],
            timeScopes: [timeScope("this month", monthRange(2026, 5), .month)]
        )
        let selectedChoice = choice("Groceries", .category, mentionID: mentionID)
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Apple did you mean?",
            candidate: candidate,
            patchSlot: .target,
            choices: [selectedChoice]
        )
        let coordinator = MarinaV2TurnCoordinator(
            availability: FoundationOnlyAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.resume(
                clarification: clarification,
                choice: selectedChoice,
                context: turnContext(provider: fixture.provider, turnClassification: .clarificationAnswer)
            )
        }

        guard case .handled = result else {
            Issue.record("Expected clarification resume to execute through V2.")
            return
        }
        assertFoundationOnly(trace)
        #expect(trace?.sharedPipelineTurnClassification == .clarificationAnswer)
    }

    @Test func followUpTrace_staysFoundationOnlyAndIncludesPriorContext() async throws {
        let fixture = try makeFixture()
        try fixture.seedComparisonData()
        let prompt = "Compare to last month"
        let interpretation = canonicalInterpretation(
            candidate: spendCandidate(
                prompt: prompt,
                operation: .compare,
                mentions: [mention("Groceries", .category)],
                timeScopes: [
                    timeScope("this month", monthRange(2026, 5), .month),
                    timeScope("last month", monthRange(2026, 4), .month, role: .comparison)
                ],
                responseShape: .comparison
            )
        )
        let coordinator = MarinaV2TurnCoordinator(
            availability: FoundationOnlyAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [prompt: interpretation])
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(
                prompt: prompt,
                context: turnContext(
                    provider: fixture.provider,
                    turnClassification: .followUp,
                    priorQueryContext: MarinaPriorQueryContext(
                        lastQueryPlan: nil,
                        lastMetric: .topCategories,
                        lastTargetName: "Groceries",
                        lastTargetType: .category,
                        lastDateRange: monthRange(2026, 5),
                        lastResultLimit: nil,
                        lastPeriodUnit: .month
                    )
                )
            )
        }

        guard case .handled = result else {
            Issue.record("Expected handled Foundation-only follow-up.")
            return
        }
        assertFoundationOnly(trace)
        #expect(trace?.sharedPipelineTurnClassification == .followUp)
        #expect(trace?.sharedPipelinePriorContextIncluded == true)
    }

    @Test func presetChipTrace_staysFoundationOnly() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let prompt = "What did I spend this month?"
        let coordinator = MarinaV2TurnCoordinator(
            availability: FoundationOnlyAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(
                query: HomeQuery(
                    intent: .spendThisMonth,
                    dateRange: monthRange(2026, 5),
                    periodUnit: .month
                ),
                sourceTitle: prompt,
                context: turnContext(provider: fixture.provider)
            )
        }

        guard case .handled = result else {
            Issue.record("Expected preset chip to execute through V2.")
            return
        }
        assertFoundationOnly(trace)
        #expect(trace?.sharedPipelineInterpreterSource == .foundationModels)
    }

    @Test func typedUnsupportedTrace_staysFoundationOnly() async throws {
        let fixture = try makeFixture()
        let prompt = "Can you delete my grocery category?"
        let candidate = spendCandidate(prompt: prompt)
        let interpretation = MarinaCanonicalReadInterpretation(
            result: .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedOperation,
                    message: "CRUD is deferred.",
                    candidate: candidate
                )
            ),
            compatibilityCandidate: candidate
        )
        let coordinator = MarinaV2TurnCoordinator(
            availability: FoundationOnlyAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [prompt: interpretation])
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(provider: fixture.provider))
        }

        guard case .blocked = result else {
            Issue.record("Expected typed unsupported response.")
            return
        }
        assertFoundationOnly(trace)
    }

    @Test func aiDisabledTrace_staysFoundationOnlyWithoutHeuristicAnswer() async throws {
        let fixture = try makeFixture()
        let prompt = "How much did I spend on Groceries this month?"
        let coordinator = MarinaV2TurnCoordinator(
            availability: FoundationOnlyAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(
                prompt: prompt,
                context: turnContext(provider: fixture.provider, aiEnabled: false)
            )
        }

        guard case .unavailable(let answer) = result else {
            Issue.record("Expected Apple Intelligence required response.")
            return
        }
        #expect(answer.title == "Apple Intelligence is turned off")
        assertFoundationOnly(trace)
    }

    @Test func foundationUnavailableTrace_staysFoundationOnlyWithoutHeuristicAnswer() async throws {
        let fixture = try makeFixture()
        let prompt = "How much did I spend on Groceries this month?"
        let coordinator = MarinaV2TurnCoordinator(
            availability: FoundationOnlyAvailability(status: .unavailable(reason: "model_not_ready")),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(provider: fixture.provider))
        }

        guard case .unavailable(let answer) = result else {
            Issue.record("Expected Apple Intelligence unavailable response.")
            return
        }
        #expect(answer.title == "Apple Intelligence is still preparing")
        assertFoundationOnly(trace)
    }

    @Test func typedGenerationFailureTrace_staysFoundationOnlyWithoutHeuristicAnswer() async throws {
        let fixture = try makeFixture()
        let prompt = "How much did I spend on Groceries this month?"
        let diagnostic = MarinaFoundationModelsFailureDiagnostic(
            category: .decodingFailure,
            step: .typedEnvelope,
            debugSummary: "schema mismatch"
        )
        let coordinator = MarinaV2TurnCoordinator(
            availability: FoundationOnlyAvailability(status: .available),
            interpreter: ThrowingFoundationOnlyInterpreter(
                error: MarinaFoundationModelsServiceError.diagnosedGenerationFailure(diagnostic)
            )
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(provider: fixture.provider))
        }

        guard case .blocked(let answer, _) = result else {
            Issue.record("Expected typed generation failure response.")
            return
        }
        #expect(answer.title == "Marina could not read the typed response")
        assertFoundationOnly(trace)
    }

    @Test func legacyRuntimeFlagsDoNotSelectModelRouterOrNLQ() throws {
        let defaults = try #require(UserDefaults(suiteName: "MarinaFoundationOnlyTraceGuardTests.flags"))
        defer { defaults.removePersistentDomain(forName: "MarinaFoundationOnlyTraceGuardTests.flags") }
        defaults.set(false, forKey: MarinaRuntimeSettings.sharedPipelineKey)
        defaults.set(true, forKey: MarinaRuntimeSettings.nlqV1Key)

        let settings = MarinaRuntimeSettings.resolve(defaults: defaults, arguments: [], environment: [:])

        #expect(settings.routingMode == .sharedPipeline)
        #expect(settings.routingMode != .modelRouter)
        #expect(settings.routingMode != .nlqAuthoritative)
    }

    private func tracedTurn(
        prompt: String,
        turn: () async -> MarinaV2TurnResult
    ) async -> (MarinaV2TurnResult, MarinaExecutionTrace?) {
        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(
            prompt: prompt,
            routingMode: .sharedPipeline,
            marinaNLQv1Enabled: false,
            runtimeSettingsSummary: "foundationOnlyTest=true"
        )
        let result = await turn()
        recordSelectedRoute(for: result)
        return (result, MarinaTraceRecorder.shared.finish())
    }

    private func recordSelectedRoute(for result: MarinaV2TurnResult) {
        switch result {
        case .clarification:
            MarinaTraceRecorder.shared.recordSelectedRoute(.clarification, reason: "foundation_only_test")
        case .handled, .blocked, .unavailable:
            MarinaTraceRecorder.shared.recordSelectedRoute(.sharedFoundationModels, reason: "foundation_only_test")
        }
    }

    private func assertFoundationOnly(
        _ trace: MarinaExecutionTrace?,
        allowsClarificationRoute: Bool = false
    ) {
        guard let trace else {
            Issue.record("Expected a Marina execution trace.")
            return
        }

        let allowedSelectedRoutes: [MarinaExecutionSelectedRoute] = allowsClarificationRoute
            ? [.sharedFoundationModels, .clarification]
            : [.sharedFoundationModels]
        #expect(allowedSelectedRoutes.contains(trace.selectedRoute))
        #expect(trace.selectedRoute != .fallback)
        #expect(trace.selectedRoute != .nlq)
        #expect(trace.selectedRoute != .sharedHeuristic)
        #expect(trace.selectedRoute != .sharedFallback)
        #expect(trace.routingMode == .sharedPipeline)
        #expect(trace.routingMode != .modelRouter)
        #expect(trace.routingMode != .nlqAuthoritative)
        #expect(trace.sharedPipelinePath == .sharedFoundationModels)
        #expect(trace.sharedPipelinePath != .legacy)
        #expect(trace.sharedPipelinePath != .sharedHeuristic)
        #expect(trace.sharedPipelinePath != .sharedAttemptedThenLegacyFallback)
        #expect(trace.sharedPipelineInterpreterSource != .heuristic)
        #expect(trace.sharedPipelineHeuristicAttempted != true)
        #expect(trace.sharedPipelineHeuristicUsedAsFallback != true)
    }

    private func canonicalInterpretation(
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaCanonicalReadInterpretation {
        MarinaCanonicalReadInterpretation(
            result: MarinaSemanticQueryAdapter().interpretationResult(from: candidate),
            compatibilityCandidate: candidate
        )
    }

    private func spendCandidate(
        prompt: String,
        operation: MarinaCandidateOperation = .sum,
        mentions: [MarinaUnresolvedEntityMention] = [],
        timeScopes: [MarinaUnresolvedTimeScope] = [],
        responseShape: MarinaResponseShapeHint = .scalarCurrency
    ) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: operation,
            measure: .spend,
            entityMentions: mentions,
            timeScopes: timeScopes,
            responseShapeHint: responseShape,
            confidence: .high
        )
    }

    private func mention(
        _ rawText: String,
        _ type: MarinaCandidateEntityTypeHint?,
        id: UUID = UUID(),
        role: MarinaEntityMentionRole = .primaryTarget
    ) -> MarinaUnresolvedEntityMention {
        MarinaUnresolvedEntityMention(
            id: id,
            role: role,
            rawText: rawText,
            typeHint: type,
            allowedTypeHints: type.map { [$0] },
            confidence: .high
        )
    }

    private func choice(
        _ title: String,
        _ type: MarinaCandidateEntityTypeHint,
        mentionID: UUID? = nil
    ) -> MarinaClarificationChoice {
        MarinaClarificationChoice(
            title: title,
            entityRole: .primaryTarget,
            entityTypeHint: type,
            patchSlot: .target,
            rawValue: title,
            mentionID: mentionID
        )
    }

    private func timeScope(
        _ rawText: String,
        _ range: HomeQueryDateRange,
        _ periodUnit: HomeQueryPeriodUnit,
        role: MarinaTimeScopeRole = .primary
    ) -> MarinaUnresolvedTimeScope {
        MarinaUnresolvedTimeScope(
            role: role,
            rawText: rawText,
            resolvedRangeHint: range,
            periodUnitHint: periodUnit
        )
    }

    private func turnContext(
        provider: MarinaDataProvider,
        aiEnabled: Bool = true,
        turnClassification: MarinaPromptTurnClassification = .freshQuestion,
        priorQueryContext: MarinaPriorQueryContext = .empty
    ) -> MarinaV2TurnContext {
        MarinaV2TurnContext(
            provider: provider,
            routerContext: MarinaLanguageRouterContext(
                workspaceName: "Foundation Only Workspace",
                defaultPeriodUnit: .month,
                sessionContext: HomeAssistantSessionContext(),
                priorQueryContext: priorQueryContext,
                cardNames: ["Apple Card", "Backup Card"],
                categoryNames: ["Groceries", "Travel"],
                incomeSourceNames: [],
                presetTitles: [],
                budgetNames: [],
                aliasSummaries: [],
                now: date(2026, 5, 15)
            ),
            defaultPeriodUnit: .month,
            aiEnabled: aiEnabled,
            now: date(2026, 5, 15),
            turnClassification: turnClassification
        )
    }

    private func monthRange(_ year: Int, _ month: Int) -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(year, month, 1),
            endDate: date(year, month, Calendar(identifier: .gregorian).range(of: .day, in: .month, for: date(year, month, 1))!.count)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private struct FoundationOnlyAvailability: MarinaModelAvailabilityProviding {
    let status: MarinaModelAvailability.Status

    func currentStatus() -> MarinaModelAvailability.Status {
        status
    }
}

private struct ThrowingFoundationOnlyInterpreter: MarinaCanonicalAIInterpreting {
    let error: Error

    func interpretCanonicalV2(
        prompt _: String,
        context _: MarinaLanguageRouterContext
    ) async throws -> MarinaCanonicalReadInterpretation {
        throw error
    }
}
