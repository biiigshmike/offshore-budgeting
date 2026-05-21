import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaFoundationSemanticRealAppTests {
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
            Issue.record("Expected handled Foundation semantic answer.")
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
        let coordinator = MarinaTurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaTypedFixtureInterpreter()
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
            Issue.record("Expected linked-card relationship prompt to execute through Foundation.")
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

    @Test func semanticRealApp_bareShowCategoryClarifiesWithRunnableChoices() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        let prompt = "Show Groceries"
        let candidate = unsupportedCandidate(prompt: prompt)
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(candidate)
        ])

        let (initial, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .clarification(_, let clarification) = initial else {
            Issue.record("Expected bare category prompt to ask a clarification.")
            return
        }

        #expect(clarification.choices.contains { $0.title == "Groceries spending" && $0.resumeIntent != nil })
        #expect(clarification.choices.contains { $0.title == "Groceries expenses" && $0.resumeIntent != nil })

        let choice = try #require(clarification.choices.first { $0.title == "Groceries spending" })
        let (resumed, _) = await tracedTurn(prompt: choice.title) {
            await coordinator.resume(
                clarification: clarification,
                choice: choice,
                context: turnContext(fixture, turnClassification: .clarificationAnswer)
            )
        }

        guard case .handled(let answer, _, _, _, _) = resumed else {
            Issue.record("Expected clarification choice to execute.")
            return
        }

        #expect(answer.rows.contains { $0.title == "Matched" && $0.value.localizedCaseInsensitiveContains("Groceries") })
    }

    @Test func semanticRealApp_upcomingBudgetsRecoverFromUnsupported() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(Budget(name: "April Budget", startDate: date(2026, 4, 1), endDate: date(2026, 4, 30), workspace: fixture.workspace))
        fixture.context.insert(Budget(name: "May Budget", startDate: date(2026, 5, 1), endDate: date(2026, 5, 31), workspace: fixture.workspace))
        fixture.context.insert(Budget(name: "June Budget", startDate: date(2026, 6, 1), endDate: date(2026, 6, 30), workspace: fixture.workspace))
        try fixture.context.save()

        let prompt = "What are my upcoming budgets?"
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
        ])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(
                prompt: prompt,
                context: turnContext(fixture, budgetNames: ["April Budget", "May Budget", "June Budget"])
            )
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected upcoming budgets to execute.")
            return
        }

        #expect(answer.title == "Upcoming Budgets")
        #expect(answer.rows.contains { $0.title == "May Budget" })
        #expect(answer.rows.contains { $0.title == "June Budget" })
        #expect(answer.rows.contains { $0.title == "April Budget" } == false)
    }

    @Test func semanticRealApp_plannedExpensesNextMonthRecoverFromUnsupported() async throws {
        let fixture = try makeFixture()
        let rent = Preset(title: "Rent", plannedAmount: 1_500, workspace: fixture.workspace, defaultCard: fixture.appleCard, defaultCategory: fixture.groceries)
        fixture.context.insert(rent)
        fixture.context.insert(PlannedExpense(title: "Rent Bill", plannedAmount: 1_500, expenseDate: date(2026, 6, 3), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries, sourcePresetID: rent.id))
        fixture.context.insert(PlannedExpense(title: "May Only", plannedAmount: 80, expenseDate: date(2026, 5, 20), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        try fixture.context.save()

        let prompt = "What are my planned expenses for next month?"
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
        ])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture, presetTitles: ["Rent"]))
        }

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected planned expenses next month to execute.")
            return
        }

        #expect(answer.title == "Planned Expenses Due")
        #expect(answer.rows.contains { $0.title == "Rent Bill" && $0.value.contains("preset Rent") })
        #expect(answer.rows.contains { $0.title == "May Only" } == false)
        #expect(route?.traceName == "aggregate")
    }

    @Test func semanticRealApp_savingsActivityUsesLedgerRows() async throws {
        let fixture = try makeFixture()
        let account = SavingsAccount(name: "True Savings", total: 0, workspace: fixture.workspace)
        fixture.context.insert(account)
        fixture.context.insert(SavingsLedgerEntry(date: date(2026, 5, 10), amount: 125, note: "Manual deposit", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: fixture.workspace, account: account))
        try fixture.context.save()

        let prompt = "Show savings activity"
        let coordinator = coordinator(for: [
            prompt: canonicalInterpretation(unsupportedCandidate(prompt: prompt))
        ])

        let (result, _) = await tracedTurn(prompt: prompt) {
            await coordinator.run(prompt: prompt, context: turnContext(fixture))
        }

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected savings activity to execute.")
            return
        }

        #expect(answer.title == "Savings Activity")
        #expect(answer.rows.contains { $0.title == "Manual deposit" })
    }

    private func coordinator(for interpretations: [String: MarinaCanonicalReadInterpretation]) -> MarinaTurnCoordinator {
        MarinaTurnCoordinator(
            availability: AvailableMarinaModel(),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: interpretations)
        )
    }

    private func tracedTurn(
        prompt: String,
        turn: () async -> MarinaTurnResult
    ) async -> (MarinaTurnResult, MarinaExecutionTrace?) {
        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(
            prompt: prompt,
            routingMode: .foundationPipeline,
            runtimeSettingsSummary: "foundationSemanticRealApp=true"
        )
        let result = await turn()
        switch result {
        case .clarification:
            MarinaTraceRecorder.shared.recordSelectedRoute(.clarification, reason: "foundation_semantic_real_app")
        case .handled, .blocked, .unavailable:
            MarinaTraceRecorder.shared.recordSelectedRoute(.foundationModels, reason: "foundation_semantic_real_app")
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
            ? [.foundationModels, .clarification]
            : [.foundationModels]
        #expect(allowedRoutes.contains(trace.selectedRoute))
        #expect(trace.foundationPipelinePath == .foundationModels)
        #expect(trace.foundationPipelineInterpreterSource == .foundationModels)
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

    private func unsupportedCandidate(prompt: String) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            responseShapeHint: .unsupported,
            confidence: .medium,
            unsupportedHint: .unsupportedOperation
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
        presetTitles: [String] = [],
        budgetNames: [String] = [],
        turnClassification: MarinaPromptTurnClassification = .freshQuestion
    ) -> MarinaTurnContext {
        MarinaTurnContext(
            provider: fixture.provider,
            routerContext: MarinaInterpretationContext(
                workspaceName: fixture.workspace.name,
                defaultPeriodUnit: .month,
                sessionContext: MarinaSessionContext(),
                priorQueryContext: .empty,
                cardNames: cardNames,
                categoryNames: categoryNames,
                incomeSourceNames: [],
                presetTitles: presetTitles,
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
