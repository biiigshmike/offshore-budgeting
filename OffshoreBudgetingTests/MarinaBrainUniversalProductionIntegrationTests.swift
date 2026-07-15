import Foundation
import SwiftData
import Testing
@testable import Offshore

#if canImport(FoundationModels)
import FoundationModels
#endif

@Suite(.serialized)
@MainActor
struct MarinaBrainUniversalProductionIntegrationTests {
    @Test func injectedTypedInterpreterExecutesDirectlyThroughUniversalProductionPath() async throws {
        let fixture = try makeFixture()
        let prompt = "How much did I spend this month?"
        let brain = MarinaBrain(
            interpreter: TypedInterpreter([
                prompt: interpreted(variableExpenseSumRequest())
            ])
        )

        let seed = await answerSeed(
            prompt: prompt,
            brain: brain,
            fixture: fixture
        )
        let trace = try #require(seed.debugTrace)

        #expect(seed.answer.kind == .metric)
        #expect(seed.answer.title == "Spending")
        #expect(seed.answer.rows.first?.title == "Value")
        #expect(seed.answer.rows.first?.amount == 150)
        #expect(trace.interpretedSource == .foundationModel)
        #expect(trace.executionRoute == .universal)
        #expect(trace.validatorAccepted)
        #expect(trace.promptTreatment == .standalone)
        #expect(trace.debugDescription.contains("executionRoute=universal"))
    }

    @Test func universalProductionQueryRemainsInsideActiveWorkspace() async throws {
        let fixture = try makeFixture()
        let prompt = "List every expense this month"
        let request = variableExpenseListRequest(limit: 20)
        let brain = MarinaBrain(
            interpreter: TypedInterpreter([prompt: interpreted(request)])
        )

        let seed = await answerSeed(
            prompt: prompt,
            brain: brain,
            fixture: fixture
        )
        let rowIDs = Set(seed.answer.rows.compactMap(\.sourceID))

        #expect(seed.answer.kind == .list)
        #expect(rowIDs == Set(fixture.personalExpenseIDs))
        #expect(rowIDs.contains(fixture.otherWorkspaceExpenseID) == false)
        #expect(seed.answer.semanticContext?.totalRowCount == fixture.personalExpenseIDs.count)
        #expect(seed.answer.semanticContext?.fullTotalAmount == 150)
        #expect(seed.debugTrace?.executionRoute == .universal)
    }

    @Test func unavailableFoundationModelReturnsExplicitMessageWithoutFallback() async throws {
        let fixture = try makeFixture()
        let brain = MarinaBrain(interpreter: MarinaUnavailableModelInterpreter())

        let seed = await answerSeed(
            prompt: "What did I spend?",
            brain: brain,
            fixture: fixture
        )
        let trace = try #require(seed.debugTrace)

        #expect(seed.answer.kind == .message)
        #expect(seed.answer.title == "I can't answer that yet")
        #expect(seed.answer.subtitle?.contains("Apple Intelligence is not available or ready") == true)
        #expect(seed.answer.rows.isEmpty)
        #expect(trace.interpretedSource == .unavailableFallback)
        #expect(trace.validatorOutput.unsupportedReason == .unavailableModel)
        #expect(trace.validatorAccepted == false)
        #expect(trace.executionRoute == .universal)
    }

    @Test func terminalCompilerAttemptStopsBeforeResolutionValidationPlanningAndExecution() async throws {
        let fixture = try makeFixture()
        let prompt = "Show category availability."
        let terminalRequest = MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: .modelGenerationFailed
        )
        let diagnostic = MarinaFoundationModelAttemptDiagnostic(
            attempt: 2,
            compilerVersion: "marina.semantic-compiler.v3",
            stage: .alignment,
            status: .terminal,
            rejection: .alignment(.entityMismatch),
            alignmentVerdict: .rejected,
            generatedIntent: MarinaFoundationModelGeneratedIntentDigest(
                intent: .query,
                entity: .workspace,
                projection: .records,
                operation: .list
            ),
            compiledRequest: MarinaFoundationModelCompiledRequestDigest(request: terminalRequest),
            alignment: MarinaFoundationModelAlignmentDigest(
                expected: MarinaFoundationModelCompiledRequestDigest(
                    request: MarinaSemanticRequest(
                        entity: .category,
                        operation: .forecast,
                        measure: .categoryAvailability,
                        expectedAnswerShape: .metric
                    )
                ),
                actual: MarinaFoundationModelCompiledRequestDigest(request: terminalRequest)
            )
        )
        let brain = MarinaBrain(interpreter: TypedInterpreter([
            prompt: MarinaInterpretedSemanticRequest(
                request: terminalRequest,
                confidence: .low,
                source: .unavailableFallback,
                diagnosticNotes: [diagnostic.diagnosticNote],
                attemptDiagnostics: [diagnostic]
            )
        ]))

        let seed = await answerSeed(prompt: prompt, brain: brain, fixture: fixture)
        let trace = try #require(seed.debugTrace)

        #expect(seed.answer.kind == .message)
        #expect(seed.answer.title == "I can't answer that yet")
        #expect(trace.candidateSearches.isEmpty)
        #expect(trace.resolverOutput == terminalRequest)
        #expect(trace.validatorOutput == terminalRequest)
        #expect(trace.validatorAccepted == false)
        #expect(trace.validatorNotes == [
            "Skipped candidate resolution, validation, planning, and execution after a terminal semantic compiler attempt."
        ])
        #expect(trace.executionRoute == .notExecuted)
        #expect(trace.executionSucceeded == false)
        #expect(trace.rowCount == 0)
        #expect(trace.compilerAttempts == [diagnostic])
    }

    #if canImport(FoundationModels)
    @Test func twoRejectedModelCandidatesNeverReachResolverPlannerOrExecutor() async throws {
        let fixture = try makeFixture()
        let prompt = "Show category availability."
        let runtime = AlwaysUnrelatedV3Runtime()
        let brain = MarinaBrain(interpreter: MarinaFoundationModelsInterpreter(
            runtime: runtime,
            localeConfiguration: MarinaFoundationModelLocaleConfiguration(
                locale: Locale(identifier: "en_US")
            )
        ))

        let seed = await answerSeed(prompt: prompt, brain: brain, fixture: fixture)
        let trace = try #require(seed.debugTrace)

        #expect(trace.compilerAttempts.map(\.status) == [.rejected, .terminal])
        #expect(trace.compilerAttempts.map(\.rejectionCode) == [
            "alignment.entityMismatch",
            "alignment.entityMismatch"
        ])
        #expect(trace.interpretedRequest.unsupportedReason == .modelGenerationFailed)
        #expect(trace.candidateSearches.isEmpty)
        #expect(trace.resolverOutput == trace.interpretedRequest)
        #expect(trace.validatorOutput == trace.interpretedRequest)
        #expect(trace.validatorAccepted == false)
        #expect(trace.executionRoute == .notExecuted)
        #expect(trace.executionSucceeded == false)
        #expect(trace.rowCount == 0)
    }
    #endif

    @Test func typedClarificationStopsAtSemanticBoundaryWithChoices() async throws {
        let fixture = try makeFixture()
        let prompt = "How much did I spend at Grocery?"
        let clarification = clarificationOutcome(prompt: prompt, workspaceID: fixture.workspace.id)
        let brain = MarinaBrain(
            interpreter: TypedInterpreter([prompt: clarification])
        )

        let seed = await answerSeed(
            prompt: prompt,
            brain: brain,
            fixture: fixture
        )
        let trace = try #require(seed.debugTrace)
        let choices = try #require(clarification.clarificationChoices)
        let attachment = try #require(seed.answer.attachment)

        #expect(seed.answer.kind == .message)
        #expect(seed.answer.title == "Can you clarify?")
        #expect(seed.answer.subtitle == choices.question)
        #expect(attachment == .clarificationChoices(choices))
        #expect(seed.answer.rows.isEmpty)
        #expect(trace.validatorAccepted == false)
        #expect(trace.executionRoute == .universal)
        #expect(trace.rowCount == 0)
    }

    @Test func typedShowMoreTraversesThreeUniversalPagesWithStableTotals() async throws {
        let fixture = try makeFixture()
        let firstPrompt = "List my expenses"
        let morePrompt = "Show more"
        let lastPrompt = "Show the last page"
        let initialRequest = variableExpenseListRequest(limit: 2)
        let generatedContinuation = MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            continuationIntent: .showMore,
            resultLimit: 20,
            resultOffset: 999,
            expectedAnswerShape: .list
        )
        let brain = MarinaBrain(
            interpreter: TypedInterpreter([
                firstPrompt: interpreted(initialRequest),
                morePrompt: interpreted(generatedContinuation),
                lastPrompt: interpreted(generatedContinuation)
            ])
        )

        let first = await answerSeed(
            prompt: firstPrompt,
            brain: brain,
            fixture: fixture
        )
        let firstContext = try #require(first.answer.semanticContext)
        #expect(first.answer.rows.compactMap(\.sourceID) == Array(fixture.personalExpenseIDs.prefix(2)))
        #expect(firstContext.displayedRowCount == 2)
        #expect(firstContext.totalRowCount == 5)
        #expect(firstContext.fullTotalAmount == 150)
        #expect(firstContext.hasMore == true)
        #expect(firstContext.nextOffset == 2)
        #expect(MarinaRecommendedFollowUp.suggestion(
            from: first.answer.insightBundle?.followUps ?? []
        )?.reason == .showMore)

        let second = await answerSeed(
            prompt: morePrompt,
            brain: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [first.answer])
        )
        let secondTrace = try #require(second.debugTrace)
        let secondContext = try #require(second.answer.semanticContext)

        #expect(second.answer.rows.compactMap(\.sourceID) == Array(fixture.personalExpenseIDs[2..<4]))
        #expect(secondContext.request.entity == initialRequest.entity)
        #expect(secondContext.request.resultLimit == 2)
        #expect(secondContext.request.resultOffset == 2)
        #expect(secondContext.request.continuationIntent == .showMore)
        #expect(secondContext.displayedRowCount == 2)
        #expect(secondContext.totalRowCount == 5)
        #expect(secondContext.fullTotalAmount == firstContext.fullTotalAmount)
        #expect(secondContext.hasMore == true)
        #expect(secondContext.nextOffset == 4)
        #expect(secondTrace.interpretedRequest == secondContext.request)
        #expect(secondTrace.promptTreatment == .recommendedFollowUpConfirmation)
        #expect(secondTrace.priorContextChangedRequest)
        #expect(secondTrace.executionRoute == .universal)
        #expect(MarinaRecommendedFollowUp.suggestion(
            from: second.answer.insightBundle?.followUps ?? []
        )?.semanticRequest?.resultOffset == 4)

        let third = await answerSeed(
            prompt: lastPrompt,
            brain: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [first.answer, second.answer])
        )
        let thirdTrace = try #require(third.debugTrace)
        let thirdContext = try #require(third.answer.semanticContext)

        #expect(third.answer.rows.compactMap(\.sourceID) == Array(fixture.personalExpenseIDs.suffix(1)))
        #expect(thirdContext.request.resultLimit == 2)
        #expect(thirdContext.request.resultOffset == 4)
        #expect(thirdContext.displayedRowCount == 1)
        #expect(thirdContext.totalRowCount == 5)
        #expect(thirdContext.fullTotalAmount == firstContext.fullTotalAmount)
        #expect(thirdContext.hasMore == false)
        #expect(thirdContext.nextOffset == nil)
        #expect(thirdTrace.promptTreatment == .recommendedFollowUpConfirmation)
        #expect(thirdTrace.executionRoute == .universal)
    }

    @Test func typedDeclineReturnsAcknowledgementAndRecordsDeclineMemory() async throws {
        let fixture = try makeFixture()
        let firstPrompt = "List my expenses"
        let declinePrompt = "No thanks"
        let brain = MarinaBrain(
            interpreter: TypedInterpreter([
                firstPrompt: interpreted(variableExpenseListRequest(limit: 2)),
                declinePrompt: interpreted(MarinaSemanticRequest(
                    entity: .workspace,
                    operation: .list,
                    expectedAnswerShape: .acknowledgement
                ))
            ])
        )
        let first = await answerSeed(
            prompt: firstPrompt,
            brain: brain,
            fixture: fixture
        )
        let offered = try #require(
            MarinaRecommendedFollowUp.suggestion(from: first.answer.insightBundle?.followUps ?? [])
        )
        #expect(offered.reason == .showMore)

        let declined = await answerSeed(
            prompt: declinePrompt,
            brain: brain,
            fixture: fixture,
            conversationContext: MarinaConversationContext(recentAnswers: [first.answer])
        )
        let trace = try #require(declined.debugTrace)

        #expect(declined.answer.kind == .message)
        #expect(declined.answer.title.isEmpty)
        #expect(declined.answer.explanation == "No problem. I’m here whenever you want to dig into something else.")
        #expect(declined.answer.semanticContext?.request.expectedAnswerShape == .acknowledgement)
        #expect(trace.promptTreatment == .declinedFollowUp)
        #expect(trace.executionSucceeded)
        #expect(trace.executionRoute == .universal)

        let memory = MarinaConversationContext(
            recentAnswers: [first.answer, declined.answer]
        ).followUpMemory
        #expect(memory.recentDeclines.count == 1)
        #expect(memory.recentDeclines.first?.reason == .showMore)
    }

    private func answerSeed(
        prompt: String,
        brain: MarinaBrain,
        fixture: Fixture,
        conversationContext: MarinaConversationContext = .empty
    ) async -> MarinaAnswerSeed {
        await brain.answerSeed(
            prompt: prompt,
            workspace: fixture.workspace,
            modelContext: fixture.context,
            ambientDateRange: fixture.currentRange,
            homeContext: MarinaPanelHomeContext(dateRange: fixture.currentRange),
            defaultBudgetingPeriod: .monthly,
            conversationContext: conversationContext,
            now: fixture.now
        )
    }

    private func variableExpenseSumRequest() -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dateRangeToken: .currentMonth,
            dateRangeSource: .explicit,
            expenseScope: .variable,
            expectedAnswerShape: .metric
        )
    }

    private func variableExpenseListRequest(limit: Int) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dateRangeToken: .currentMonth,
            dateRangeSource: .explicit,
            resultLimit: limit,
            resultOffset: 0,
            sort: .dateAscending,
            expenseScope: .variable,
            expectedAnswerShape: .list
        )
    }

    private func clarificationOutcome(
        prompt: String,
        workspaceID: UUID
    ) -> MarinaInterpretedSemanticRequest {
        let categoryRequest = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            targetName: "Groceries",
            expenseScope: .variable,
            expectedAnswerShape: .metric
        )
        let merchantRequest = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            textQuery: "Grocery",
            expenseScope: .variable,
            expectedAnswerShape: .metric
        )
        let choices = MarinaClarificationChoices(
            originalPrompt: prompt,
            question: "Did you mean the Groceries category or a merchant containing Grocery?",
            choices: [
                MarinaClarificationChoice(
                    meaningKey: "category-groceries",
                    title: "Groceries category",
                    aliases: ["category"],
                    request: categoryRequest
                ),
                MarinaClarificationChoice(
                    meaningKey: "merchant-grocery",
                    title: "Grocery merchant",
                    aliases: ["merchant"],
                    request: merchantRequest
                )
            ]
        )
        return MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                resolvedScope: .workspace(workspaceID),
                expenseScope: .variable,
                expectedAnswerShape: .clarification,
                clarificationQuestion: choices.question,
                unsupportedReason: .ambiguousEntity
            ),
            confidence: .medium,
            source: .foundationModel,
            diagnosticNotes: ["The typed model outcome requires a user choice."],
            clarificationChoices: choices
        )
    }

    private func interpreted(_ request: MarinaSemanticRequest) -> MarinaInterpretedSemanticRequest {
        MarinaInterpretedSemanticRequest(
            request: request,
            confidence: .high,
            source: .foundationModel,
            diagnosticNotes: ["Injected typed production request."]
        )
    }

    private func makeFixture() throws -> Fixture {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let personalCard = Card(
            name: "Everyday Card",
            theme: "ruby",
            effect: "plastic",
            workspace: workspace
        )
        let otherWorkspace = Workspace(name: "Work", hexColor: "#F97316")
        let workCard = Card(
            name: "Work Card",
            theme: "sky",
            effect: "matte",
            workspace: otherWorkspace
        )
        let expenseDates = try (1...5).map { day in
            try date(2026, 4, day)
        }
        let personalExpenses = zip(expenseDates, [10.0, 20.0, 30.0, 40.0, 50.0]).enumerated().map {
            index, values in
            VariableExpense(
                descriptionText: "Personal Expense \(index + 1)",
                amount: values.1,
                transactionDate: values.0,
                workspace: workspace,
                card: personalCard
            )
        }
        let workExpense = VariableExpense(
            descriptionText: "Workspace Leak Sentinel",
            amount: 999,
            transactionDate: try date(2026, 4, 3),
            workspace: otherWorkspace,
            card: workCard
        )

        context.insert(workspace)
        context.insert(personalCard)
        personalExpenses.forEach(context.insert)
        context.insert(otherWorkspace)
        context.insert(workCard)
        context.insert(workExpense)
        try context.save()

        return Fixture(
            context: context,
            workspace: workspace,
            personalExpenseIDs: personalExpenses.map(\.id),
            otherWorkspaceExpenseID: workExpense.id,
            currentRange: HomeQueryDateRange(
                startDate: try date(2026, 4, 1),
                endDate: try date(2026, 4, 30)
            ),
            now: try date(2026, 4, 20)
        )
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self,
            Budget.self,
            BudgetCategoryLimit.self,
            Card.self,
            BudgetCardLink.self,
            BudgetPresetLink.self,
            Category.self,
            Preset.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            MarinaChatSession.self,
            IncomeSeries.self,
            Income.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(
            Calendar(identifier: .gregorian).date(
                from: DateComponents(year: year, month: month, day: day)
            )
        )
    }
}

private final class TypedInterpreter: MarinaModelInterpreting {
    private let outcomes: [String: MarinaInterpretedSemanticRequest]

    init(_ outcomes: [String: MarinaInterpretedSemanticRequest]) {
        self.outcomes = outcomes
    }

    func interpretedSemanticRequest(
        for prompt: String,
        context: MarinaBrainContext
    ) async throws -> MarinaInterpretedSemanticRequest {
        guard let outcome = outcomes[prompt] else {
            return MarinaInterpretedSemanticRequest(
                request: MarinaSemanticRequest(
                    entity: .workspace,
                    operation: .list,
                    expectedAnswerShape: .unsupported,
                    unsupportedReason: .unsupportedCombination
                ),
                confidence: .low,
                source: .foundationModel,
                diagnosticNotes: ["No typed test outcome was registered for this prompt."]
            )
        }
        return outcome
    }
}

#if canImport(FoundationModels)
@available(iOS 26.0, macCatalyst 26.0, *)
private actor AlwaysUnrelatedV3Runtime: MarinaFoundationModelGenerating {
    func generateOutcome(
        for prompt: String,
        localeConfiguration: MarinaFoundationModelLocaleConfiguration
    ) async -> MarinaFoundationModelRuntimeResult {
        .generated(
            .query(.workspaceMetadata(.init(action: .name(.init())))),
            diagnosticNotes: ["fixture.unrelatedWorkspaceMetadata"]
        )
    }
}
#endif

private struct Fixture {
    let context: ModelContext
    let workspace: Workspace
    let personalExpenseIDs: [UUID]
    let otherWorkspaceExpenseID: UUID
    let currentRange: HomeQueryDateRange
    let now: Date
}
