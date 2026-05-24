import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
@Suite(.serialized)
struct MarinaTurnCoordinatorTests {
    @Test func run_whenAISettingIsOff_returnsAppleIntelligenceRequiredWithoutQuerying() async throws {
        let fixture = try makeFixture()
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let result = await coordinator.run(
            prompt: "How much did I spend on groceries?",
            context: turnContext(provider: fixture.provider, aiEnabled: false)
        )

        guard case .unavailable(let answer) = result else {
            Issue.record("Expected unavailable result when Marina AI setting is off.")
            return
        }

        #expect(answer.title == "Apple Intelligence is turned off")
        let subtitle = answer.subtitle ?? ""
        let hasDataSafetyRow = answer.rows.contains { row in
            row.title == "Data safety"
        }
        #expect(subtitle.contains("needs Apple Intelligence"))
        #expect(hasDataSafetyRow)
    }

    @Test func run_whenModelUnavailable_returnsSpecificAvailabilityCard() async throws {
        let fixture = try makeFixture()
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .unavailable(reason: .modelNotReady)),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let result = await coordinator.run(
            prompt: "How much did I spend on groceries?",
            context: turnContext(provider: fixture.provider)
        )

        guard case .unavailable(let answer) = result else {
            Issue.record("Expected unavailable result when model is not ready.")
            return
        }

        #expect(answer.title == "Apple Intelligence is still preparing")
        let hasStatusRow = answer.rows.contains { row in
            row.title == "Status" && row.value.contains("Apple Intelligence")
        }
        let leaksRawAvailability = answer.rows.contains { row in
            row.value.contains("model_not_ready")
        }
        #expect(hasStatusRow)
        #expect(leaksRawAvailability == false)
    }

    @Test func run_whenFoundationModelsTypedOutputFails_returnsDiagnosticCard() async throws {
        let fixture = try makeFixture()
        let diagnostic = MarinaFoundationModelsFailureDiagnostic(
            category: .decodingFailure,
            step: .typedEnvelope,
            debugSummary: "schema mismatch"
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: ThrowingCanonicalAIInterpreter(error: MarinaFoundationModelsServiceError.diagnosedGenerationFailure(diagnostic))
        )

        let result = await coordinator.run(
            prompt: "How much did I spend on groceries?",
            context: turnContext(provider: fixture.provider)
        )

        guard case .blocked(let answer, _) = result else {
            Issue.record("Expected blocked diagnostic result.")
            return
        }

        #expect(answer.title == "Marina could not read that request")
        let hasStatusRow = answer.rows.contains { row in
            row.title == "Status" && row.value.contains("paused")
        }
        let leaksRawDiagnostic = answer.rows.contains { row in
            row.value.contains("decodingFailure") || row.value.contains("typedEnvelope")
        }
        let hasVisibleDebugRow = answer.rows.contains { row in
            row.title == "Debug" || row.value.contains("schema mismatch")
        }
        #expect(hasStatusRow)
        #expect(leaksRawDiagnostic == false)
        #expect(hasVisibleDebugRow == false)
    }

    @Test func run_currentWorkspacePrompt_executesSelectedWorkspaceWithoutFoundationModels() async throws {
        let fixture = try makeFixture()
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .unavailable(reason: .modelNotReady)),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let result = await coordinator.run(
            prompt: "What workspace am I in?",
            context: turnContext(provider: fixture.provider, aiEnabled: false)
        )

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected current workspace to execute without Foundation Models.")
            return
        }

        #expect(answer.title == "You are in Phase 5 Workspace.")
        #expect(route?.traceName == "lookupDetail")
    }

    @Test func run_activeBudgetPrompt_executesActiveBudgetStatusWithoutFoundationModels() async throws {
        let fixture = try makeFixture()
        let budget = Budget(
            name: "May Budget",
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 31),
            workspace: fixture.workspace
        )
        let preset = Preset(
            title: "Rent",
            plannedAmount: 900,
            workspace: fixture.workspace,
            defaultCard: fixture.appleCard,
            defaultCategory: fixture.groceries
        )
        fixture.context.insert(budget)
        fixture.context.insert(preset)
        fixture.context.insert(BudgetCardLink(budget: budget, card: fixture.appleCard))
        fixture.context.insert(BudgetPresetLink(budget: budget, preset: preset))
        fixture.context.insert(BudgetCategoryLimit(maxAmount: 500, budget: budget, category: fixture.groceries))
        try fixture.context.save()

        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .unavailable(reason: .modelNotReady)),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let result = await coordinator.run(
            prompt: "What is my active budget?",
            context: turnContext(provider: fixture.provider, aiEnabled: false)
        )

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected active budget prompt to execute without Foundation Models.")
            return
        }

        #expect(answer.title == "Active Budget")
        #expect(answer.primaryValue == "May Budget")
        #expect(answer.rows.contains { $0.title == "Linked cards" && $0.value == "Apple Card" })
        #expect(answer.rows.contains { $0.title == "Linked presets" && $0.value == "Rent" })
        #expect(answer.rows.contains { $0.title == "Category limits" && $0.value == "1" })
        #expect(route?.traceName == "groupedRanked")
    }

    @Test func run_activeBudgetPrompt_reportsNoActiveBudgetWithoutFallback() async throws {
        let fixture = try makeFixture()
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let result = await coordinator.run(
            prompt: "What is my active budget?",
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected no-active-budget answer.")
            return
        }

        #expect(answer.title == "No Active Budget")
        #expect(answer.primaryValue == "None")
        #expect(answer.rows.contains { $0.title == "Status" && $0.value.contains("No active budget") })
    }

    @Test func run_activeBudgetPrompt_listsOverlappingActiveBudgetsWithoutGuessing() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(
            Budget(
                name: "May Budget",
                startDate: date(2026, 5, 1),
                endDate: date(2026, 5, 31),
                workspace: fixture.workspace
            )
        )
        fixture.context.insert(
            Budget(
                name: "Travel Budget",
                startDate: date(2026, 5, 10),
                endDate: date(2026, 5, 20),
                workspace: fixture.workspace
            )
        )
        try fixture.context.save()

        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let result = await coordinator.run(
            prompt: "What is my active budget?",
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected overlapping active budget answer.")
            return
        }

        #expect(answer.title == "Multiple Active Budgets")
        #expect(answer.primaryValue == "2")
        #expect(answer.rows.contains { $0.title == "May Budget" })
        #expect(answer.rows.contains { $0.title == "Travel Budget" })
        #expect(answer.subtitle == "Choose the budget Marina should use.")
    }

    @Test func run_activeBudgetPrompt_treatsStartAndEndDatesAsInclusive() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(
            Budget(
                name: "One Day Budget",
                startDate: date(2026, 5, 15),
                endDate: date(2026, 5, 15),
                workspace: fixture.workspace
            )
        )
        try fixture.context.save()

        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let result = await coordinator.run(
            prompt: "What is my active budget?",
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected inclusive one-day active budget answer.")
            return
        }

        #expect(answer.title == "Active Budget")
        #expect(answer.primaryValue == "One Day Budget")
    }

    @Test func run_liveNormalizerRepairsGenericIncomeTargetAcrossTypedAI() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(
            Income(
                source: "Salary",
                amount: 2_500,
                date: date(2026, 5, 5),
                isPlanned: false,
                workspace: fixture.workspace
            )
        )
        fixture.context.insert(
            Income(
                source: "Salary",
                amount: 1_000,
                date: date(2026, 5, 20),
                isPlanned: true,
                workspace: fixture.workspace
            )
        )
        try fixture.context.save()

        let prompt = "What is my actual income so far this month?"
        let scriptedIntent = MarinaAIIntent.readQuery(
            MarinaAIReadQueryIntent(
                reasoning: "Generic income target mistake.",
                subjectRaw: "income",
                operationRaw: "sum",
                measureRaw: "income",
                includeMentions: [
                    MarinaAIEntityMention(
                        roleRaw: "primaryTarget",
                        rawText: "income",
                        typeRaw: "incomeSource",
                        allowedTypeRaws: ["incomeSource"]
                    )
                ],
                excludeMentions: [],
                primaryDateRange: MarinaAIDateRange(
                    startISO8601: "2026-05-01",
                    endISO8601: "2026-05-31",
                    rawText: "this month",
                    periodUnitRaw: "month"
                ),
                comparisonDateRange: nil,
                groupingRaw: nil,
                rankingRaw: nil,
                requestedDetailRaw: nil,
                limit: nil,
                incomeStatusRaw: nil,
                insightIntentRaw: nil,
                softTimeHintRaw: nil,
                confidenceRaw: "medium"
            )
        )
        let fakeAI = MarinaFakeAIInterpreter(scriptedIntents: [prompt: scriptedIntent])
        let liveInterpreter = MarinaFoundationAIInterpreter(aiInterpreter: fakeAI)
        let repairedInterpretation = try await liveInterpreter.interpretCanonical(
            prompt: prompt,
            context: turnContext(
                provider: fixture.provider,
                incomeSourceNames: ["Salary"]
            ).routerContext
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: liveInterpreter
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(
                provider: fixture.provider,
                incomeSourceNames: ["Salary"]
            )
        )

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected repaired income prompt to execute.")
            return
        }

        let primaryDigits = answer.primaryValue?.filter { $0.isNumber } ?? ""
        #expect(primaryDigits.contains("2500"))
        #expect(repairedInterpretation.repairSummary?.contains("droppedGenericEntityTarget") == true)
    }

    @Test func run_withFakeTypedAIOutput_executesDeterministicSpendAnswerWithEvidence() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(
            VariableExpense(
                descriptionText: "Groceries",
                amount: 80,
                transactionDate: date(2026, 5, 8),
                workspace: fixture.workspace,
                card: fixture.appleCard,
                category: fixture.groceries
            )
        )
        try fixture.context.save()

        let prompt = "How much did I spend on groceries this month?"
        let mention = MarinaUnresolvedEntityMention(
            role: .primaryTarget,
            rawText: "Groceries",
            typeHint: .category,
            confidence: .high
        )
        let timeScope = MarinaUnresolvedTimeScope(
            role: .primary,
            rawText: "this month",
            resolvedRangeHint: monthRange(),
            periodUnitHint: .month
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .sum,
            measure: .spend,
            entityMentions: [mention],
            timeScopes: [timeScope],
            responseShapeHint: .scalarCurrency,
            confidence: .high
        )
        let semanticResult = MarinaSemanticQueryAdapter().interpretationResult(from: candidate)
        let interpretation = MarinaCanonicalReadInterpretation(
            result: semanticResult,
            compatibilityCandidate: candidate
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [prompt: interpretation])
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected handled Marina answer.")
            return
        }

        let primaryDigits = answer.primaryValue?.filter { $0.isNumber } ?? ""
        let amountBasisRow = answer.rows.contains { row in
            row.title == "Amount basis" && row.value == "Budget impact"
        }
        let matchedRow = answer.rows.contains { row in
            row.title == "Matched" && row.value.contains("Groceries")
        }

        #expect(primaryDigits.contains("80"))
        #expect(amountBasis == .budgetImpact)
        #expect(route?.traceName == "aggregate")
        #expect(amountBasisRow)
        #expect(matchedRow)
    }

    #if DEBUG
    @Test func run_withUIFixtureLinkedCards_executesBudgetRelationshipWithoutDateFalsePositive() async throws {
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
            availability: FakeMarinaAvailability(status: .available),
            interpreter: MarinaTypedFixtureInterpreter()
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(
                provider: fixture.provider,
                cardNames: ["Apple Card", "Backup Card"],
                budgetNames: ["May Budget"]
            )
        )

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected the UI fixture linked-card prompt to execute through Foundation.")
            return
        }

        #expect(answer.title == "Cards linked to May Budget")
        #expect(answer.rows.contains { $0.title == "Apple Card" })
        #expect(answer.rows.contains { $0.title == "Backup Card" })
        #expect(route?.traceName == "groupedRanked")
    }
    #endif

    @Test func deferredCRUDAnswer_makesRuntimeReadOnlyBoundaryVisible() {
        let answer = MarinaTurnCoordinator.deferredCRUDAnswer(prompt: "Add coffee")

        #expect(answer.title == "Marina is read-only for now")
        let hasStatusRow = answer.rows.contains { row in
            row.title == "Status" && row.value == "Saved changes are paused."
        }
        #expect(hasStatusRow)
    }

    private func turnContext(
        provider: MarinaDataProvider,
        aiEnabled: Bool = true,
        cardNames: [String] = ["Apple Card"],
        categoryNames: [String] = ["Groceries"],
        incomeSourceNames: [String] = [],
        budgetNames: [String] = []
    ) -> MarinaTurnContext {
        MarinaTurnContext(
            provider: provider,
            routerContext: MarinaInterpretationContext(
                workspaceName: "Phase 5 Workspace",
                defaultPeriodUnit: .month,
                sessionContext: MarinaSessionContext(),
                priorQueryContext: .empty,
                cardNames: cardNames,
                categoryNames: categoryNames,
                incomeSourceNames: incomeSourceNames,
                presetTitles: [],
                budgetNames: budgetNames,
                aliasSummaries: [],
                now: date(2026, 5, 15)
            ),
            defaultPeriodUnit: .month,
            aiEnabled: aiEnabled,
            now: date(2026, 5, 15)
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
}

private struct FakeMarinaAvailability: MarinaModelAvailabilityProviding {
    let status: MarinaModelAvailability.Status

    func currentStatus() -> MarinaModelAvailability.Status {
        status
    }
}

private struct ThrowingCanonicalAIInterpreter: MarinaCanonicalAIInterpreting {
    let error: Error

    func interpretCanonical(
        prompt _: String,
        context _: MarinaInterpretationContext
    ) async throws -> MarinaCanonicalReadInterpretation {
        throw error
    }
}
