import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaTypedConversationContractTests {
    private let contract = MarinaTypedConversationContract()

    @Test func typedClarificationSelectionMapsOnlyTheExecutableRequest() throws {
        let workspaceID = UUID()
        let categoryID = UUID()
        let merchantID = UUID()
        let base = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            targetName: "Grocery",
            expectedAnswerShape: .clarification
        )
        let category = choice(
            title: "Groceries",
            meaningKey: "primary|category|\(categoryID)",
            reference: MarinaResolvedEntityReference(
                entity: .category,
                id: categoryID,
                displayName: "Groceries",
                provenance: .clarificationChoice
            ),
            workspaceID: workspaceID,
            request: base
        )
        let merchant = choice(
            title: "Grocery Outlet",
            meaningKey: "primary|variableExpense|\(merchantID)",
            reference: MarinaResolvedEntityReference(
                entity: .variableExpense,
                id: merchantID,
                displayName: "Grocery Outlet",
                provenance: .clarificationChoice
            ),
            workspaceID: workspaceID,
            request: base
        )
        let choices = MarinaClarificationChoices(
            question: "Which Grocery meaning?",
            choices: [category, merchant]
        )
        let context = clarificationContext(choices: choices)
        let selected = category.executableRequest

        #expect(contract.promptTreatment(for: selected, conversationContext: context) == .contextualFollowUp)
        #expect(MarinaTypedClarificationDispatch.choiceID(selectedBy: selected, from: choices) == category.id)
        #expect(MarinaTypedClarificationDispatch.choiceID(selectedBy: merchant.executableRequest, from: choices) == merchant.id)

        let duplicate = MarinaClarificationChoices(
            question: "Which one?",
            choices: [category, category]
        )
        #expect(MarinaTypedClarificationDispatch.choiceID(selectedBy: selected, from: duplicate) == nil)
    }

    @Test func typedCorrectionReplacesPriorTargetWithoutRawPhraseRepair() {
        let prior = cardMetric(target: "Apple Card", dateRange: .currentMonth)
        var correction = cardMetric(target: "Chase Card", dateRange: .currentMonth)
        correction.dateRangeSource = .conversationContext
        let interpreted = interpreted(correction)
        let context = semanticContext(request: prior)

        let result = contract.interpretedRequest(interpreted, conversationContext: context)

        #expect(result.request == correction)
        #expect(result.request.targetName == "Chase Card")
        #expect(result.request.targetName != prior.targetName)
        #expect(contract.promptTreatment(for: result.request, conversationContext: context) == .contextualFollowUp)
    }

    @Test func typedDateRefinementAndComparisonPassThroughModelMeaning() {
        let prior = cardMetric(target: "Apple Card", dateRange: .currentMonth)
        let context = semanticContext(request: prior)

        var dateRefinement = prior
        dateRefinement.dateRangeToken = .previousMonth
        dateRefinement.dateRangeSource = .conversationContext
        #expect(contract.interpretedRequest(
            interpreted(dateRefinement),
            conversationContext: context
        ).request == dateRefinement)

        var comparison = prior
        comparison.operation = .compare
        comparison.comparisonTargetName = "Chase Card"
        comparison.expectedAnswerShape = .comparison
        comparison.dateRangeSource = .conversationContext
        #expect(contract.interpretedRequest(
            interpreted(comparison),
            conversationContext: context
        ).request == comparison)
    }

    @Test func typedShowMoreUsesPriorNextOffsetAndSamePageLimit() throws {
        var prior = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: .previousMonth,
            targetName: "Food & Drink",
            resultLimit: 5,
            resultOffset: 0,
            sort: .amountDescending,
            expenseScope: .unified,
            expectedAnswerShape: .list
        )
        prior.resolvedScope = .workspace(UUID())
        let context = semanticContext(
            request: prior,
            displayedRowCount: 5,
            totalRowCount: 12,
            hasMore: true,
            nextOffset: 5
        )
        let generated = MarinaSemanticRequest(
            entity: .category,
            operation: .list,
            measure: .categoryAvailability,
            continuationIntent: .showMore,
            resultLimit: 20,
            resultOffset: 999,
            expectedAnswerShape: .list
        )

        let continued = contract.interpretedRequest(
            interpreted(generated),
            conversationContext: context
        ).request

        #expect(continued.entity == prior.entity)
        #expect(continued.targetName == prior.targetName)
        #expect(continued.resultLimit == 5)
        #expect(continued.resultOffset == 5)
        #expect(continued.continuationIntent == .showMore)

        let semanticContext = try #require(context.lastSemanticContext)
        let showMore = try #require(
            MarinaFollowUpBuilder().followUps(for: semanticContext)
                .first { $0.reason == .showMore }
        )
        #expect(showMore.semanticRequest?.resultLimit == 5)
        #expect(showMore.semanticRequest?.resultOffset == 5)
        #expect(showMore.semanticRequest?.continuationIntent == .showMore)
    }

    @Test func freshTypedTurnDoesNotInheritStaleContext() {
        let context = semanticContext(request: cardMetric(target: "Apple Card", dateRange: .previousMonth))
        let fresh = MarinaSemanticRequest(
            entity: .category,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: .currentPeriod,
            dateRangeSource: .defaulted,
            targetName: "Hair Care",
            expectedAnswerShape: .metric
        )

        let result = contract.interpretedRequest(interpreted(fresh), conversationContext: context)

        #expect(result.request == fresh)
        #expect(result.request.targetName == "Hair Care")
        #expect(result.request.dateRangeToken == .currentPeriod)
        #expect(contract.promptTreatment(for: result.request, conversationContext: context) == .standalone)
    }

    @Test func unavailableModelOutcomeNeverFallsBackToConversationHeuristics() {
        let context = semanticContext(request: cardMetric(target: "Apple Card", dateRange: .previousMonth))
        let unavailable = MarinaInterpretedSemanticRequest(
            request: MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .unsupported,
                unsupportedReason: .unavailableModel
            ),
            confidence: .low,
            source: .unavailableFallback
        )

        let result = contract.interpretedRequest(unavailable, conversationContext: context)

        #expect(result == unavailable)
        #expect(result.source == .unavailableFallback)
        #expect(result.request.unsupportedReason == .unavailableModel)
        #expect(contract.promptTreatment(for: result.request, conversationContext: context) == .standalone)
    }

    @Test func availableNextPageIsRecommendedAheadOfRelatedBreakdown() throws {
        let context = pagedSemanticContext(offset: 0, nextOffset: 2, totalRowCount: 5)

        let followUps = MarinaFollowUpBuilder().followUps(for: context)
        let recommended = try #require(MarinaRecommendedFollowUp.suggestion(from: followUps))

        #expect(recommended.reason == .showMore)
        #expect(recommended.semanticRequest?.resultLimit == 2)
        #expect(recommended.semanticRequest?.resultOffset == 2)
        #expect(MarinaRecommendedFollowUp.confirmationQuestion(for: recommended) == "Want to see the remaining 3?")
        #expect(followUps.contains { $0.reason == .breakdown })
    }

    @Test func typedDeclineIsAcknowledgedAndRecordedInConversationMemory() throws {
        let firstContext = pagedSemanticContext(offset: 0, nextOffset: 2, totalRowCount: 5)
        let offered = try #require(
            MarinaFollowUpBuilder().followUps(for: firstContext)
                .first { $0.reason == .showMore }
        )
        let acknowledgementRequest = MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .acknowledgement
        )
        let context = MarinaConversationContext(recentTurns: [
            conversationTurn(semanticContext: firstContext, recommendedFollowUp: offered),
            conversationTurn(
                semanticContext: MarinaAnswerSemanticContext(
                    request: acknowledgementRequest,
                    dateRange: nil,
                    comparisonDateRange: nil,
                    answerKind: .message,
                    answerTitle: "",
                    answerSubtitle: nil,
                    primaryValue: nil,
                    rowReferences: []
                ),
                recommendedFollowUp: nil
            )
        ])

        #expect(contract.promptTreatment(
            for: acknowledgementRequest,
            conversationContext: context
        ) == .declinedFollowUp)
        #expect(context.followUpMemory.recentDeclines.count == 1)
        #expect(context.followUpMemory.recentDeclines.first?.reason == .showMore)
        #expect(context.followUpMemory.recentAcceptances.isEmpty)
    }

    @Test func distinctShowMoreOffsetsRemainEligibleAcrossPages() throws {
        let firstContext = pagedSemanticContext(offset: 0, nextOffset: 2, totalRowCount: 6)
        let firstShowMore = try #require(
            MarinaFollowUpBuilder().followUps(for: firstContext)
                .first { $0.reason == .showMore }
        )
        let secondContext = pagedSemanticContext(offset: 2, nextOffset: 4, totalRowCount: 6)
        let secondFollowUps = MarinaFollowUpBuilder().followUps(for: secondContext)
        let memory = MarinaConversationContext(recentTurns: [
            conversationTurn(semanticContext: firstContext, recommendedFollowUp: firstShowMore)
        ]).followUpMemory

        let filtered = MarinaRecommendedFollowUp.filteredFollowUps(
            from: secondFollowUps,
            memory: memory
        )
        let secondRecommended = try #require(MarinaRecommendedFollowUp.suggestion(from: filtered))

        #expect(firstShowMore.semanticRequest?.resultOffset == 2)
        #expect(secondRecommended.reason == .showMore)
        #expect(secondRecommended.semanticRequest?.resultOffset == 4)
    }

    @Test func validatorDoesNotRepairFormulaDateOrTargetFromRawPrompt() {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let request = MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            dateRangeToken: .currentPeriod,
            expectedAnswerShape: .list
        )
        let trace = MarinaSemanticRequestValidator().validateWithTrace(
            interpreted: interpreted(request),
            snapshot: emptySnapshot(workspace: workspace)
        )

        #expect(trace.interpreted.source == .foundationModel)
        #expect(trace.interpreted.request.entity == .workspace)
        #expect(trace.interpreted.request.operation == .list)
        #expect(trace.interpreted.request.measure == nil)
        #expect(trace.interpreted.request.dateRangeToken == .currentPeriod)
    }

    private func interpreted(_ request: MarinaSemanticRequest) -> MarinaInterpretedSemanticRequest {
        MarinaInterpretedSemanticRequest(
            request: request,
            confidence: .medium,
            source: .foundationModel
        )
    }

    private func cardMetric(
        target: String,
        dateRange: MarinaSemanticDateRangeToken
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .card,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: dateRange,
            targetName: target,
            expectedAnswerShape: .metric
        )
    }

    private func choice(
        title: String,
        meaningKey: String,
        reference: MarinaResolvedEntityReference,
        workspaceID: UUID,
        request: MarinaSemanticRequest
    ) -> MarinaClarificationChoice {
        MarinaClarificationChoice(
            meaningKey: meaningKey,
            title: title,
            aliases: [],
            targetPatch: MarinaClarificationTargetPatch(
                slot: .primary,
                reference: reference,
                scope: .workspace(workspaceID)
            ),
            request: request
        )
    }

    private func clarificationContext(
        choices: MarinaClarificationChoices
    ) -> MarinaConversationContext {
        MarinaConversationContext(recentTurns: [
            MarinaConversationTurn(
                title: "Can you clarify?",
                kind: .message,
                subtitle: choices.question,
                primaryValue: nil,
                rowTitles: [],
                semanticContext: nil,
                recommendedFollowUp: nil,
                clarificationOptions: choices.choices
            )
        ])
    }

    private func semanticContext(
        request: MarinaSemanticRequest,
        displayedRowCount: Int? = nil,
        totalRowCount: Int? = nil,
        hasMore: Bool? = nil,
        nextOffset: Int? = nil
    ) -> MarinaConversationContext {
        let semantic = MarinaAnswerSemanticContext(
            request: request,
            dateRange: nil,
            comparisonDateRange: nil,
            answerKind: request.expectedAnswerShape == .list ? .list : .metric,
            answerTitle: "Prior answer",
            answerSubtitle: nil,
            primaryValue: nil,
            rowReferences: [],
            displayedRowCount: displayedRowCount,
            totalRowCount: totalRowCount,
            hasMore: hasMore,
            nextOffset: nextOffset
        )
        return MarinaConversationContext(recentTurns: [
            MarinaConversationTurn(
                userPrompt: "Prior prompt",
                title: "Prior answer",
                kind: semantic.answerKind,
                subtitle: nil,
                primaryValue: nil,
                rowTitles: [],
                semanticContext: semantic,
                recommendedFollowUp: nil
            )
        ])
    }

    private func pagedSemanticContext(
        offset: Int,
        nextOffset: Int,
        totalRowCount: Int
    ) -> MarinaAnswerSemanticContext {
        let request = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dateRangeToken: .currentMonth,
            continuationIntent: offset == 0 ? .none : .showMore,
            resultLimit: 2,
            resultOffset: offset,
            sort: .dateAscending,
            expenseScope: .variable,
            expectedAnswerShape: .list
        )
        return MarinaAnswerSemanticContext(
            request: request,
            dateRange: nil,
            comparisonDateRange: nil,
            answerKind: .list,
            answerTitle: "Expenses",
            answerSubtitle: nil,
            primaryValue: "$100.00",
            rowReferences: [],
            displayedRowCount: 2,
            totalRowCount: totalRowCount,
            fullTotalAmount: 100,
            hasMore: true,
            nextOffset: nextOffset
        )
    }

    private func conversationTurn(
        semanticContext: MarinaAnswerSemanticContext,
        recommendedFollowUp: MarinaFollowUpSuggestion?
    ) -> MarinaConversationTurn {
        MarinaConversationTurn(
            userPrompt: "Prompt",
            title: semanticContext.answerTitle,
            kind: semanticContext.answerKind,
            subtitle: semanticContext.answerSubtitle,
            primaryValue: semanticContext.primaryValue,
            rowTitles: [],
            semanticContext: semanticContext,
            recommendedFollowUp: recommendedFollowUp
        )
    }

    private func emptySnapshot(workspace: Workspace) -> MarinaWorkspaceSnapshot {
        MarinaWorkspaceSnapshot(
            workspace: workspace,
            budgets: [],
            cards: [],
            categories: [],
            presets: [],
            plannedExpenses: [],
            variableExpenses: [],
            homePlannedExpenses: [],
            homeCalculationPlannedExpenses: [],
            homeCalculationVariableExpenses: [],
            reconciliationAccounts: [],
            expenseAllocations: [],
            allocationSettlements: [],
            savingsAccounts: [],
            savingsEntries: [],
            incomes: []
        )
    }
}
