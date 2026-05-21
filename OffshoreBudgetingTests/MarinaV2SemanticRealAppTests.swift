import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaV2SemanticRealAppTests {
    @Test func semanticRealApp_foundationTypedSpendExecutesWithEvidence() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let prompt = "How much did I spend on groceries this month?"
        let candidate = spendCandidate(
            prompt: prompt,
            mentions: [mention("Groceries", .category)],
            timeScopes: [monthScope()]
        )
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(candidate)
        ])

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected handled V2 semantic answer.")
            return
        }

        #expect(answer.kind == .metric)
        #expect(answer.rows.contains { $0.title == "Matched" && $0.value.localizedCaseInsensitiveContains("Groceries") })
        #expect(amountBasis == .budgetImpact)
        #expect(route?.traceName == "aggregate")
        assertFoundationOnly(trace)
    }

    @Test func semanticRealApp_typedRelationshipPromptUsesDeterministicExecutor() async throws {
        let fixture = try makeFixture()
        let budget = Budget(
            name: "May Budget",
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 31),
            workspace: fixture.workspace
        )
        fixture.context.insert(budget)
        fixture.context.insert(BudgetCardLink(budget: budget, card: fixture.appleCard))
        fixture.context.insert(BudgetCardLink(budget: budget, card: fixture.backupCard))
        try fixture.context.save()
        let prompt = "Which cards are linked to May Budget?"
        let coordinator = MarinaV2TurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaV2UIFixtureAIInterpreter()
        )

        let (result, trace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(
                prompt: prompt,
                context: turnContext(
                    fixture,
                    cardNames: ["Apple Card", "Backup Card"],
                    budgetNames: ["May Budget"]
                )
            )
        }

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected linked-card relationship prompt to execute through V2.")
            return
        }

        #expect(answer.rows.contains { $0.title == "Apple Card" })
        #expect(answer.rows.contains { $0.title == "Backup Card" })
        #expect(route?.traceName == "groupedRanked")
        assertFoundationOnly(trace)
    }

    @Test func semanticRealApp_clarificationResumeStaysFoundationOnly() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(
            VariableExpense(
                descriptionText: "Apple Store",
                amount: 40,
                transactionDate: date(2026, 5, 9),
                workspace: fixture.workspace,
                card: fixture.appleCard,
                category: nil
            )
        )
        try fixture.context.save()

        let prompt = "What did I spend at Apple?"
        let mentionID = UUID()
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    id: mentionID,
                    role: .filter,
                    rawText: "Apple",
                    typeHint: nil,
                    allowedTypeHints: [.card, .merchant],
                    confidence: .medium
                )
            ],
            responseShapeHint: .clarification,
            confidence: .medium
        )
        let cardChoice = MarinaClarificationChoice(
            title: "Apple Card",
            entityRole: .filter,
            entityTypeHint: .card,
            patchSlot: .target,
            rawValue: "Apple Card",
            sourceID: fixture.appleCard.id,
            mentionID: mentionID
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Apple target did you mean?",
            candidate: candidate,
            patchSlot: .target,
            choices: [
                cardChoice,
                MarinaClarificationChoice(
                    title: "Apple Store",
                    entityRole: .filter,
                    entityTypeHint: .merchant,
                    patchSlot: .target,
                    rawValue: "Apple Store",
                    mentionID: mentionID
                )
            ]
        )
        let coordinator = coordinator(for: [
            prompt: MarinaCanonicalReadInterpretation(
                result: .clarification(clarification),
                compatibilityCandidate: candidate
            )
        ])

        let (initial, initialTrace) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }
        guard case .clarification = initial else {
            Issue.record("Expected typed clarification before executing.")
            return
        }
        assertFoundationOnly(initialTrace, allowsClarificationRoute: true)

        let (resumed, resumedTrace) = await tracedTurn(prompt: "Apple Card") {
            await coordinator.resume(
                clarification: clarification,
                choice: cardChoice,
                context: turnContext(fixture, turnClassification: .clarificationAnswer)
            )
        }
        guard case .handled(let answer, _, _, _, let route) = resumed else {
            Issue.record("Expected clarified card choice to execute.")
            return
        }

        #expect(answer.kind == .metric)
        #expect(answer.rows.contains { $0.title == "Matched" && $0.value.localizedCaseInsensitiveContains("Apple Card") })
        #expect(route?.traceName == "aggregate")
        assertFoundationOnly(resumedTrace)
    }

    private func coordinator(for interpretations: [String: MarinaCanonicalReadInterpretation]) -> MarinaV2TurnCoordinator {
        MarinaV2TurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: interpretations)
        )
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
            runtimeSettingsSummary: "v2SemanticRealApp=true"
        )
        let result = await turn()
        switch result {
        case .clarification:
            MarinaTraceRecorder.shared.recordSelectedRoute(.clarification, reason: "v2_semantic_real_app")
        case .handled, .blocked, .unavailable:
            MarinaTraceRecorder.shared.recordSelectedRoute(.sharedFoundationModels, reason: "v2_semantic_real_app")
        }
        return (result, MarinaTraceRecorder.shared.finish())
    }

    private func assertFoundationOnly(
        _ trace: MarinaExecutionTrace?,
        allowsClarificationRoute: Bool = false
    ) {
        guard let trace else {
            Issue.record("Expected a Marina execution trace.")
            return
        }
        let allowedRoutes: [MarinaExecutionSelectedRoute] = allowsClarificationRoute
            ? [.sharedFoundationModels, .clarification]
            : [.sharedFoundationModels]
        #expect(allowedRoutes.contains(trace.selectedRoute))
        #expect(trace.sharedPipelinePath == .sharedFoundationModels)
        #expect(trace.sharedPipelinePath != .legacy)
        #expect(trace.sharedPipelinePath != .sharedHeuristic)
        #expect(trace.sharedPipelinePath != .sharedAttemptedThenLegacyFallback)
        #expect(trace.sharedPipelineInterpreterSource == .foundationModels)
        #expect(trace.sharedPipelineHeuristicAttempted != true)
        #expect(trace.sharedPipelineHeuristicUsedAsFallback != true)
    }

    private func canonicalInterpretation(
        _ candidate: MarinaQueryPlanCandidate
    ) -> MarinaCanonicalReadInterpretation {
        MarinaCanonicalReadInterpretation(
            result: MarinaSemanticQueryAdapter().interpretationResult(from: candidate),
            compatibilityCandidate: candidate
        )
    }

    private func spendCandidate(
        prompt: String,
        mentions: [MarinaUnresolvedEntityMention],
        timeScopes: [MarinaUnresolvedTimeScope]
    ) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .sum,
            measure: .spend,
            entityMentions: mentions,
            timeScopes: timeScopes,
            responseShapeHint: .scalarCurrency,
            confidence: .high
        )
    }

    private func mention(
        _ rawText: String,
        _ type: MarinaCandidateEntityTypeHint
    ) -> MarinaUnresolvedEntityMention {
        MarinaUnresolvedEntityMention(
            role: .primaryTarget,
            rawText: rawText,
            typeHint: type,
            allowedTypeHints: [type],
            confidence: .high
        )
    }

    private func monthScope() -> MarinaUnresolvedTimeScope {
        MarinaUnresolvedTimeScope(
            role: .primary,
            rawText: "this month",
            resolvedRangeHint: monthRange(),
            periodUnitHint: .month
        )
    }

    private func turnContext(
        _ fixture: MarinaPhase5Fixture,
        cardNames: [String] = ["Apple Card", "Backup Card"],
        categoryNames: [String] = ["Groceries", "Travel"],
        budgetNames: [String] = [],
        turnClassification: MarinaPromptTurnClassification = .freshQuestion
    ) -> MarinaV2TurnContext {
        MarinaV2TurnContext(
            provider: fixture.provider,
            routerContext: MarinaLanguageRouterContext(
                workspaceName: fixture.workspace.name,
                defaultPeriodUnit: .month,
                sessionContext: HomeAssistantSessionContext(),
                priorQueryContext: .empty,
                cardNames: cardNames,
                categoryNames: categoryNames,
                incomeSourceNames: [],
                presetTitles: [],
                budgetNames: budgetNames,
                aliasSummaries: [],
                now: date(2026, 5, 15)
            ),
            defaultPeriodUnit: .month,
            aiEnabled: true,
            now: date(2026, 5, 15),
            turnClassification: turnClassification
        )
    }

    private func monthRange() -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 31)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private struct AvailableMarinaModel: MarinaModelAvailabilityProviding {
        func currentStatus() -> MarinaModelAvailability.Status { .available }
    }
}
