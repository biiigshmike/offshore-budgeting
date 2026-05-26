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

    @Test func run_whenFoundationModelsFailsForBroadCanonicalRead_usesDeterministicFallback() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let diagnostic = MarinaFoundationModelsFailureDiagnostic(
            category: .malformedResponse,
            step: .typedEnvelope,
            debugSummary: "model unavailable during typed output"
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: ThrowingCanonicalAIInterpreter(error: MarinaFoundationModelsServiceError.diagnosedGenerationFailure(diagnostic))
        )

        let result = await coordinator.run(
            prompt: "Actual income",
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected deterministic canonical fallback for broad actual income.")
            return
        }

        #expect(answerText(answer).contains("3,100"))
        #expect(amountBasis == .actualIncome)
        #expect(route?.traceName == "aggregate")
    }

    @Test func run_whenFoundationModelsFailsForCardBalance_usesDeterministicTargetedBalance() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(
            descriptionText: "May coffee",
            amount: 42,
            transactionDate: date(2026, 5, 5),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        fixture.context.insert(PlannedExpense(
            title: "May planned",
            plannedAmount: 100,
            expenseDate: date(2026, 5, 10),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        try fixture.context.save()
        let diagnostic = MarinaFoundationModelsFailureDiagnostic(
            category: .malformedResponse,
            step: .typedEnvelope,
            debugSummary: "model unavailable during typed output"
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: ThrowingCanonicalAIInterpreter(error: MarinaFoundationModelsServiceError.diagnosedGenerationFailure(diagnostic))
        )

        let result = await coordinator.run(
            prompt: "What is my Apple Card balance",
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected deterministic targeted balance fallback for Apple Card balance.")
            return
        }

        #expect(answer.title == "Apple Card Balance")
        #expect(answerText(answer).contains("142"))
        #expect(answerText(answer).contains("Recent") == false)
        #expect(route?.traceName == "aggregate")
    }

    @Test func run_whenFoundationModelsFailsForDetailWord_usesDeterministicTargetedDetail() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let diagnostic = MarinaFoundationModelsFailureDiagnostic(
            category: .malformedResponse,
            step: .typedEnvelope,
            debugSummary: "model unavailable during typed output"
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: ThrowingCanonicalAIInterpreter(error: MarinaFoundationModelsServiceError.diagnosedGenerationFailure(diagnostic))
        )

        let result = await coordinator.run(
            prompt: "Apple Card activity",
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected deterministic targeted detail fallback for card activity.")
            return
        }

        #expect(answer.title == "Recent Purchases")
        #expect(answerText(answer).contains("Whole Foods") || answerText(answer).contains("Cafe"))
        #expect(route?.traceName == "groupedRanked")
    }

    @Test func run_targetedReconciliationActivityIncludesAllocationsAndSettlements() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let diagnostic = MarinaFoundationModelsFailureDiagnostic(
            category: .malformedResponse,
            step: .typedEnvelope,
            debugSummary: "model unavailable during typed output"
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: ThrowingCanonicalAIInterpreter(error: MarinaFoundationModelsServiceError.diagnosedGenerationFailure(diagnostic))
        )

        let result = await coordinator.run(
            prompt: "Roommate activity",
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected deterministic reconciliation activity execution.")
            return
        }

        let text = answerText(answer)
        #expect(answer.title == "Roommate Activity")
        #expect(text.contains("Cafe"))
        #expect(text.contains("Roommate paid back"))
        #expect(amountBasis == .reconciliationBalance)
        #expect(route?.traceName == "groupedRanked")
    }

    @Test func run_currentWorkspacePrompt_requiresFoundationModelsWhenChatAIUnavailable() async throws {
        let fixture = try makeFixture()
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .unavailable(reason: .modelNotReady)),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [:])
        )

        let result = await coordinator.run(
            prompt: "What workspace am I in?",
            context: turnContext(provider: fixture.provider, aiEnabled: false)
        )

        guard case .unavailable(let answer) = result else {
            Issue.record("Expected current workspace prompt to respect the one Foundation Models pipeline.")
            return
        }

        #expect(answer.title == "Apple Intelligence is turned off")
    }

    @Test func run_activeBudgetPrompt_executesActiveBudgetStatusFromTurnIntent() async throws {
        let fixture = try makeFixture()
        let prompt = "What is my active budget?"
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
            availability: FakeMarinaAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: activeBudgetInterpretation(prompt: prompt)
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, _, let route) = result else {
            Issue.record("Expected active budget prompt to execute from typed TurnIntent query.")
            return
        }

        #expect(answer.title == "Active Budget")
        #expect(answer.primaryValue == "May Budget")
        #expect(answer.rows.contains { $0.title == "Linked cards" && $0.value == "Apple Card" })
        #expect(answer.rows.contains { $0.title == "Linked presets" && $0.value == "Rent" })
        #expect(answer.rows.contains { $0.title == "Category limits" && $0.value == "1" })
        #expect(route?.traceName == "groupedRanked")
    }

    @Test func run_activeBudgetPrompt_reportsNoActiveBudgetFromTurnIntent() async throws {
        let fixture = try makeFixture()
        let prompt = "What is my active budget?"
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: activeBudgetInterpretation(prompt: prompt)
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
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
        let prompt = "What is my active budget?"
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
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: activeBudgetInterpretation(prompt: prompt)
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
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
        let prompt = "What is my active budget?"
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
            interpreter: MarinaFakeCanonicalAIInterpreter(interpretationsByPrompt: [
                prompt: activeBudgetInterpretation(prompt: prompt)
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected inclusive one-day active budget answer.")
            return
        }

        #expect(answer.title == "Active Budget")
        #expect(answer.primaryValue == "One Day Budget")
    }

    @Test func run_liveUnsupportedForSafeCatalogQuestions_adjudicatesThroughUniversalCatalog() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let promptsAndExpectedText = [
            ("What workspace am I in?", "Personal"),
            ("What is the name of this current workspace?", "Personal"),
            ("What is my income this month?", "3,100"),
            ("What is my savings this month?", "250"),
            ("Show savings activity this month", "250"),
            ("How many cards do I have?", "5")
        ]
        let prompts = promptsAndExpectedText.map(\.0)
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: ScriptedTurnIntentInterpreter(
                interpretationsByPrompt: Dictionary(uniqueKeysWithValues: prompts.map {
                    ($0, unsupportedTurnInterpretation(message: "I need a narrower query."))
                })
            )
        )

        for (prompt, expectedText) in promptsAndExpectedText {
            let result = await coordinator.run(
                prompt: prompt,
                context: turnContext(provider: fixture.provider)
            )
            guard case .handled(let answer, _, _, _, let route) = result else {
                Issue.record("Expected universal adjudication to answer \(prompt).")
                continue
            }
            #expect(route != nil)
            #expect(answerText(answer).contains(expectedText))
        }
    }

    @Test func run_malformedTokenizedReadRequest_recoversUsualReadQuestions() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
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
            Budget(
                name: "May Budget",
                startDate: date(2026, 5, 1),
                endDate: date(2026, 5, 31),
                workspace: fixture.workspace
            )
        )
        try fixture.context.save()

        let promptsAndExpectedText: [(String, String?)] = [
            ("What workspace am I in?", "Phase 5 Workspace"),
            ("What is my top category this month?", nil),
            ("How many cards do I have?", "2"),
            ("What is my Apple Card spend this month?", nil),
            ("What is my actual income for this month?", "2,500"),
            ("How is my budget for this period?", "May Budget")
        ]
        let prompts = promptsAndExpectedText.map(\.0)
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: ScriptedTurnIntentInterpreter(
                interpretationsByPrompt: Dictionary(uniqueKeysWithValues: prompts.map {
                    ($0, malformedTokenizedTurnInterpretation())
                })
            )
        )

        for (prompt, expectedText) in promptsAndExpectedText {
            let result = await coordinator.run(
                prompt: prompt,
                context: turnContext(provider: fixture.provider)
            )
            guard case .handled(let answer, _, _, _, let route) = result else {
                Issue.record("Expected malformed tokenized recovery to answer \(prompt).")
                continue
            }
            let text = answerText(answer)
            #expect(route != nil)
            #expect(text.localizedCaseInsensitiveContains("narrower") == false)
            #expect(text.localizedCaseInsensitiveContains("couldn't safely resolve") == false)
            if let expectedText {
                #expect(text.contains(expectedText))
            }
            #expect(answer.rows.contains { $0.title == "Why this answer?" } == false)
        }
    }

    @Test func run_malformedTokenizedReadRequest_traceMarksFoundationFailureRecovery() async throws {
        let fixture = try makeFixture()
        let prompt = "What workspace am I in?"
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: ScriptedTurnIntentInterpreter(interpretationsByPrompt: [
                prompt: malformedTokenizedTurnInterpretation()
            ])
        )

        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(prompt: prompt, routingMode: .foundationPipeline)
        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )
        let trace = MarinaTraceRecorder.shared.finish()

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected malformed tokenized current-workspace prompt to recover.")
            return
        }

        #expect(answerText(answer).contains("Phase 5 Workspace"))
        #expect(answer.rows.contains { $0.title == "Why this answer?" } == false)
        #expect(trace?.foundationPipelineInterpreterSource == .foundationModels)
        #expect(trace?.foundationRepairSummary?.contains("tokenizedReadRequest:malformed") == true)
        #expect(trace?.foundationRepairSummary?.contains("foundationFailure=malformedResponse") == true)
        #expect(trace?.foundationRepairSummary?.contains("tokenizedReadRequest:universal") != true)
    }

    @Test func run_liveUnsupportedForReconciliationBalance_executesDeterministicTargetedBalance() async throws {
        let fixture = try makeFixture()
        let prompt = "What is Alejandro's balance?"
        let account = AllocationAccount(name: "Alejandro", workspace: fixture.workspace)
        let dinner = VariableExpense(
            descriptionText: "Dinner",
            amount: 120,
            transactionDate: date(2026, 5, 5),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        )
        fixture.context.insert(account)
        fixture.context.insert(dinner)
        fixture.context.insert(ExpenseAllocation(
            allocatedAmount: 60,
            preservesGrossAmount: true,
            workspace: fixture.workspace,
            account: account,
            expense: dinner
        ))
        fixture.context.insert(AllocationSettlement(
            date: date(2026, 5, 20),
            note: "Alejandro paid back",
            amount: -20,
            workspace: fixture.workspace,
            account: account,
            expense: dinner
        ))
        try fixture.context.save()
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: ScriptedTurnIntentInterpreter(
                interpretationsByPrompt: [
                    prompt: unsupportedTurnInterpretation(message: "I need a narrower query.")
                ]
            )
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected deterministic targeted balance to replace vague unsupported response.")
            return
        }

        #expect(answer.title == "Alejandro Balance")
        #expect(answerText(answer).contains("40"))
        #expect(amountBasis == .reconciliationBalance)
        #expect(route?.traceName == "aggregate")
    }

    @Test func run_liveVagueClarificationForSafeCatalogQuestion_adjudicatesWithoutSecondModelCall() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompt = "What is my income this month?"
        let interpreter = ScriptedTurnIntentInterpreter(interpretationsByPrompt: [
            prompt: MarinaTurnInterpretation(
                result: .clarification(
                    MarinaTypedClarification(
                        kind: .missingTarget,
                        message: "I need a clearer target."
                    )
                )
            )
        ])
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: interpreter
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected vague clarification to be adjudicated into an income query.")
            return
        }

        #expect(answerText(answer).contains("3,100"))
        #expect(amountBasis == .actualIncome)
        #expect(route?.traceName == "aggregate")
    }

    @Test func run_liveMissingTargetClarificationForActualIncome_adjudicatesThroughCatalog() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompt = "What is my actual income this month?"
        let clarification = MarinaTypedClarification(
            kind: .missingTarget,
            message: "I need a clearer target.",
            choices: [
                MarinaClarificationChoice(title: "Salary", entityTypeHint: .incomeSource, patchSlot: .target, rawValue: "Salary"),
                MarinaClarificationChoice(title: "Freelance", entityTypeHint: .incomeSource, patchSlot: .target, rawValue: "Freelance")
            ]
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: ScriptedTurnIntentInterpreter(interpretationsByPrompt: [
                prompt: MarinaTurnInterpretation(result: .clarification(clarification))
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected broad actual income missing-target clarification to compile and answer.")
            return
        }

        #expect(answerText(answer).contains("3,100"))
        #expect(amountBasis == .actualIncome)
        #expect(route?.traceName == "aggregate")
    }

    @Test func run_liveExecutableBroadActualIncome_usesAnswerFirstPlan() async throws {
        let fixture = try MarinaRealisticWorkspaceFixture.make()
        let prompt = "Actual income"
        let query = MarinaSemanticQuery(
            subject: .income,
            operation: .sum,
            incomeStatusScope: .actual,
            responseShape: .summaryCard
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: ScriptedTurnIntentInterpreter(interpretationsByPrompt: [
                prompt: MarinaTurnInterpretation(result: .query(query))
            ])
        )

        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected broad actual income to answer through the answer-first plan.")
            return
        }

        #expect(answer.title.contains("Income"))
        #expect(answerText(answer).contains("3,100"))
        #expect(amountBasis == .actualIncome)
        #expect(route?.traceName == "aggregate")
    }

    @available(iOS 26.0, macOS 26.0, *)
    @Test func run_tokenizedSimpleListExecutesUniversalWithoutCanonicalRescue() async throws {
        let fixture = try makeFixture()
        let prompt = "Show all cards"
        let tokenized = MarinaTokenizedReadRequest(
            kindRaw: "query",
            modelNameRaw: "Card",
            operationRaw: "list",
            amountFieldRaw: nil,
            amountBasisRaw: nil,
            targetTokens: [],
            dateTokens: [],
            groupingRaw: nil,
            rankingRaw: nil,
            limit: nil,
            responseShapeRaw: "relationshipList",
            requestedDetailRaw: nil,
            metricContractRaw: nil,
            incomeStatusRaw: nil,
            confidenceRaw: "high",
            clarificationKindRaw: nil,
            clarificationMessage: nil,
            clarificationPatchSlotRaw: nil,
            unsupportedReasonRaw: nil,
            unsupportedMessage: nil,
            unsupportedSafeAlternative: nil
        )
        let interpretation = tokenized.interpretation(prompt: prompt, context: turnContext(provider: fixture.provider).routerContext)
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: ScriptedTurnIntentInterpreter(interpretationsByPrompt: [
                prompt: interpretation
            ])
        )

        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(prompt: prompt, routingMode: .foundationPipeline)
        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )
        let trace = MarinaTraceRecorder.shared.finish()

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected tokenized card list to execute universally.")
            return
        }

        #expect(answer.rows.contains { $0.title == "Apple Card" })
        #expect(answer.rows.contains { $0.title == "Backup Card" })
        #expect(answer.rows.contains { $0.title == "Why this answer?" && $0.value.contains("model=Card") })
        #expect(amountBasis == .count)
        #expect(route?.traceName == "list")
        #expect(trace?.foundationRepairSummary?.contains("tokenizedReadRequest") == true)
        #expect(trace?.foundationRepairSummary?.contains("canonicalQuery") != true)
        #expect(trace?.foundationPipelineExecutorSummary?.contains("universalQuery=model:Card") == true)
    }

    @Test func run_tokenizedUniversalCandidateExecutesWithoutCanonicalRescue() async throws {
        let fixture = try makeFixture()
        let prompt = "Show all cards"
        let universalQuery = MarinaUniversalQueryIR(
            operation: .list,
            modelName: "Card",
            workspaceScopePolicy: .selectedWorkspace,
            presentationShape: .relationshipList,
            evidenceRowType: "Card"
        )
        let candidate = MarinaQueryPlanCandidate(
            requestFamily: .databaseLookup,
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .listRows,
            measure: .transactionAmount,
            responseShapeHint: .relationshipList,
            confidence: .high,
            universalQuery: universalQuery
        )
        let interpretation = MarinaTurnInterpretation(
            result: .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: "Tokenized catalog read.",
                    candidate: candidate
                )
            ),
            compatibilityCandidate: candidate,
            repairSummary: "tokenizedReadRequest:model=Card:operation=list",
            generatedSchemaName: MarinaFoundationLiveContractRegistry.liveGeneratedSchemaName
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: ScriptedTurnIntentInterpreter(interpretationsByPrompt: [
                prompt: interpretation
            ])
        )

        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(prompt: prompt, routingMode: .foundationPipeline)
        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )
        let trace = MarinaTraceRecorder.shared.finish()

        guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
            Issue.record("Expected tokenized universal card list to execute directly.")
            return
        }

        #expect(answer.rows.contains { $0.title == "Apple Card" })
        #expect(answer.rows.contains { $0.title == "Backup Card" })
        #expect(answer.rows.contains { $0.title == "Why this answer?" && $0.value.contains("model=Card") })
        #expect(amountBasis == .count)
        #expect(route?.traceName == "list")
        #expect(trace?.foundationRepairSummary?.contains("tokenizedReadRequest") == true)
        #expect(trace?.foundationRepairSummary?.contains("canonicalQuery") != true)
        #expect(trace?.foundationPipelineExecutorSummary?.contains("universalQuery=model:Card") == true)
    }

    @Test func run_liveUniversalCandidateWithoutTokenizedMarkerDoesNotUseTokenizedEvidence() async throws {
        let fixture = try makeFixture()
        let prompt = "Show all cards"
        let universalQuery = MarinaUniversalQueryIR(
            operation: .list,
            modelName: "Card",
            workspaceScopePolicy: .selectedWorkspace,
            presentationShape: .relationshipList,
            evidenceRowType: "Card"
        )
        let candidate = MarinaQueryPlanCandidate(
            requestFamily: .databaseLookup,
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .listRows,
            measure: .transactionAmount,
            responseShapeHint: .relationshipList,
            confidence: .high,
            universalQuery: universalQuery
        )
        let interpretation = MarinaTurnInterpretation(
            result: .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: "Catalog candidate without tokenized provenance.",
                    candidate: candidate
                )
            ),
            compatibilityCandidate: candidate,
            generatedSchemaName: MarinaFoundationLiveContractRegistry.liveGeneratedSchemaName
        )
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: ScriptedTurnIntentInterpreter(interpretationsByPrompt: [
                prompt: interpretation
            ])
        )

        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(prompt: prompt, routingMode: .foundationPipeline)
        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )
        let trace = MarinaTraceRecorder.shared.finish()

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected the non-tokenized catalog candidate to be handled by the existing pipeline.")
            return
        }

        #expect(answer.rows.contains { $0.title == "Why this answer?" } == false)
        #expect(trace?.foundationRepairSummary?.contains("tokenizedReadRequest") != true)
    }

    @Test func run_liveFormulaPromptExecutesCompositeBeforeUniversalPlanner() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let prompt = "Sum Groceries spend this month."
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            turnInterpreter: ScriptedTurnIntentInterpreter(interpretationsByPrompt: [
                prompt: unsupportedTurnInterpretation(message: "I need a narrower query.")
            ])
        )

        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(prompt: prompt, routingMode: .foundationPipeline)
        let result = await coordinator.run(
            prompt: prompt,
            context: turnContext(provider: fixture.provider)
        )
        let trace = MarinaTraceRecorder.shared.finish()

        guard case .handled(let answer, _, _, _, _) = result else {
            Issue.record("Expected formula prompt to execute through the formula executor.")
            return
        }

        #expect(answer.title == "Groceries Total Spending")
        #expect(answer.primaryValue?.contains("50") == true)
        #expect(answer.rows.contains { $0.title == "Formula family" && $0.value == MarinaFormulaFamily.sum.rawValue })
        #expect(answer.rows.contains { $0.title == "Measure" && $0.value == MarinaFormulaMeasure.variableBudgetImpact.rawValue })
        #expect(trace?.foundationPipelineInterpreterSource == .foundationModels)
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

    @Test func run_phraseEquivalentCardSpendPromptsPreserveRouteAmountBasisAndValue() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(
            VariableExpense(
                descriptionText: "Apple Store",
                amount: 42,
                transactionDate: date(2026, 5, 9),
                workspace: fixture.workspace,
                card: fixture.appleCard,
                category: fixture.groceries
            )
        )
        try fixture.context.save()

        let prompts = [
            "How much did I spend on Apple Card this month?",
            "Apple Card spending this month"
        ]
        let scriptedIntents = Dictionary(uniqueKeysWithValues: prompts.map { prompt in
            (
                prompt,
                MarinaAIIntent.readQuery(
                    MarinaAIReadQueryIntent(
                        reasoning: "Card spend total.",
                        subjectRaw: "variableExpenses",
                        operationRaw: "sum",
                        measureRaw: "spend",
                        includeMentions: [
                            MarinaAIEntityMention(
                                roleRaw: "primaryTarget",
                                rawText: "Apple Card",
                                typeRaw: "card",
                                allowedTypeRaws: ["card"]
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
                        confidenceRaw: "high"
                    )
                )
            )
        })
        let coordinator = MarinaTurnCoordinator(
            availability: FakeMarinaAvailability(status: .available),
            interpreter: MarinaFoundationAIInterpreter(
                aiInterpreter: MarinaFakeAIInterpreter(scriptedIntents: scriptedIntents)
            )
        )

        var signatures: [String] = []
        for prompt in prompts {
            let result = await coordinator.run(
                prompt: prompt,
                context: turnContext(provider: fixture.provider)
            )
            guard case .handled(let answer, _, _, let amountBasis, let route) = result else {
                Issue.record("Expected handled result for \(prompt).")
                continue
            }
            signatures.append([
                answer.primaryValue ?? "nil",
                amountBasis?.rawValue ?? "nil",
                route?.traceName ?? "nil"
            ].joined(separator: "|"))
        }

        #expect(signatures.count == prompts.count)
        #expect(Set(signatures).count == 1)
        #expect(signatures.first?.contains("budgetImpact") == true)
        #expect(signatures.first?.contains("aggregate") == true)
    }

    @Test func semanticWorkspaceCompatibilityBridge_doesNotRecognizeCrossWorkspaceComparisonPrompt() throws {
        let fixture = try makeFixture()

        #expect(MarinaSemanticWorkspaceQueryExecutor.recognizes(prompt: "workspace personal versus business") == false)
        if let card = MarinaSemanticWorkspaceQueryExecutor().execute(
            prompt: "workspace personal versus business",
            provider: fixture.provider,
            now: date(2026, 5, 15)
        ) {
            Issue.record("Expected cross-workspace prompt to stay outside compatibility bridge, got \(card.title).")
        }
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

    private func activeBudgetInterpretation(prompt: String) -> MarinaCanonicalReadInterpretation {
        let routeIntent = MarinaRouteIntent(
            kind: .activeBudget,
            subject: .budgets,
            operation: .lookupDetails,
            measure: .remainingBudget,
            grouping: nil,
            targetTypes: [.budget],
            requestedDetail: .status,
            responseShape: .summaryCard,
            preferredExecutorRoute: .composableWorkspace
        )
        let query = MarinaSemanticQuery(
            subject: .budgets,
            operation: .lookupDetails,
            amountField: nil,
            responseShape: .summaryCard,
            requestedDetail: .status,
            routeIntent: routeIntent
        )
        return MarinaCanonicalReadInterpretation(
            result: .query(query),
            compatibilityCandidate: MarinaSemanticQueryAdapter().compatibilityCandidate(
                from: query,
                prompt: prompt
            )
        )
    }

    private func unsupportedTurnInterpretation(message: String) -> MarinaTurnInterpretation {
        MarinaTurnInterpretation(
            result: .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: message
                )
            )
        )
    }

    private func malformedTokenizedTurnInterpretation() -> MarinaTurnInterpretation {
        MarinaTurnInterpretation(
            result: .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: "Apple Intelligence returned model tokens Marina could not safely validate."
                )
            ),
            repairSummary: "tokenizedReadRequest:malformed",
            generatedSchemaName: MarinaFoundationLiveContractRegistry.liveGeneratedSchemaName
        )
    }

    private func answerText(_ answer: HomeAnswer) -> String {
        ([answer.title, answer.subtitle, answer.primaryValue].compactMap { $0 } + answer.rows.flatMap { [$0.title, $0.value] })
            .joined(separator: " ")
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

private struct ScriptedTurnIntentInterpreter: MarinaTurnIntentInterpreting {
    enum Failure: Error {
        case missingPrompt(String)
    }

    let interpretationsByPrompt: [String: MarinaTurnInterpretation]

    func interpretTurnIntent(
        prompt: String,
        context _: MarinaInterpretationContext
    ) async throws -> MarinaTurnInterpretation {
        guard let interpretation = interpretationsByPrompt[prompt] else {
            throw Failure.missingPrompt(prompt)
        }
        return interpretation
    }
}
