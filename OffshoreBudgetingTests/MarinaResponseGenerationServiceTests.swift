import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaResponseGenerationServiceTests {
    @Test func surfaceRequest_usesRawAnswerForFoundationModelsAndStyledAnswerForFallback() throws {
        let raw = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            userPrompt: "am I spending weirdly on food lately?",
            title: "Food & Drink",
            subtitle: "May 1 - May 31",
            primaryValue: "$123.45",
            rows: [
                HomeAnswerRow(title: "Status", value: "Watch: spending is above the comparison period")
            ]
        )
        let styled = HomeAnswer(
            id: raw.id,
            queryID: raw.queryID,
            kind: raw.kind,
            userPrompt: raw.userPrompt,
            title: raw.title,
            subtitle: "Quick read: this is where your month stands right now.",
            primaryValue: raw.primaryValue,
            rows: raw.rows,
            generatedAt: raw.generatedAt
        )
        let fallback = MarinaResponseSurfaceApplication(
            answer: styled,
            followUpSuggestions: [
                MarinaSuggestion(title: "Compare with last month", query: HomeQuery(intent: .compareThisMonthToPreviousMonth))
            ]
        )

        let request = MarinaResponseSurfaceRequestFactory.make(
            userPrompt: raw.userPrompt ?? "",
            workspaceName: "Personal",
            routeSourceRaw: MarinaAnswerProvenance.foundationModels.rawValue,
            generationBaseAnswer: raw,
            deterministicApplication: fallback,
            followUpCandidates: [
                MarinaResponseSuggestionCandidate(index: 0, title: "Compare with last month", querySummary: "intent=compareThisMonthToPreviousMonth")
            ]
        )

        #expect(request.context.deterministicAnswer == raw)
        #expect(request.context.deterministicAnswer.subtitle == "May 1 - May 31")
        #expect(request.context.presentationMode == .foundationModelsStreaming)
        #expect(request.context.surfaceKind == .answer)
        #expect(request.context.voiceProfile == .marina)
        #expect(request.deterministicApplication.answer == styled)
        #expect(request.deterministicApplication.answer.subtitle?.contains("MarinaResponseRules") == false)
    }

    @Test func surfacePrompt_includesAIVoiceContextWithoutJSONSamples() throws {
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            title: "Dining",
            subtitle: "May 1 - May 31",
            primaryValue: "$68.00",
            rows: [
                HomeAnswerRow(title: "Status", value: "Watch: spending is above the comparison period"),
                HomeAnswerRow(title: "Main Driver", value: "Cafe ($60.00)")
            ]
        )
        let context = MarinaResponseGenerationContext(
            userPrompt: "why is dining higher?",
            workspaceName: "Personal",
            routeSourceRaw: MarinaAnswerProvenance.foundationModels.rawValue,
            deterministicAnswer: answer,
            presentationGrounding: MarinaPresentationGroundingBuilder().build(
                userPrompt: "why is dining higher?",
                answer: answer,
                surfaceKind: .answer,
                dateWindow: "2026-05-01...2026-05-31",
                provenance: "Budget data",
                validationOutcomeSummary: nil,
                sourceSummary: "deterministic read answer",
                clarificationChoices: []
            ),
            dateWindow: "2026-05-01...2026-05-31",
            provenance: "Budget data",
            followUpCandidates: [
                MarinaResponseSuggestionCandidate(index: 0, title: "Biggest offenders", querySummary: "intent=largestRecentTransactions")
            ],
            recentResponses: [
                MarinaRecentResponseSummary(title: "Groceries", kindRaw: "metric", primaryValue: "$50.00")
            ]
        )

        let prompt = MarinaFoundationSurfacePromptBuilder.prompt(context: context)

        #expect(prompt.contains("Presentation mode: foundationModelsStreaming"))
        #expect(prompt.contains("Surface kind: answer"))
        #expect(prompt.contains("Voice: Marina"))
        #expect(prompt.contains("Allowed tone: warm, observant, practical, lightly witty, grounded"))
        #expect(prompt.contains("User ask summary: why is dining higher?"))
        #expect(prompt.contains("Answer highlights:"))
        #expect(prompt.contains("Primary value: $68.00"))
        #expect(prompt.contains("User prompt: why is dining higher?"))
        #expect(prompt.contains("Status: Watch: spending is above the comparison period"))
        #expect(prompt.contains("Main Driver: Cafe ($60.00)"))
        #expect(prompt.contains("Follow-up candidates:") == false)
        #expect(prompt.contains("Quick read:") == false)
        #expect(prompt.contains("MarinaResponseRules") == false)
    }

    @Test func surfaceInstructions_shapeFoundationModelsWithoutJSONCopy() throws {
        let instructions = MarinaFoundationSurfacePromptBuilder.instructions()

        #expect(instructions.contains("warm, observant, practical"))
        #expect(instructions.contains("more alive than Basic Marina"))
        #expect(instructions.contains("Do not compute, change, or invent totals"))
        #expect(instructions.contains("Status, Compared With, Main Driver, Pattern, or Watch"))
        #expect(instructions.contains("Do not rewrite follow-up suggestions"))
        #expect(instructions.contains("MarinaResponses") == false)
        #expect(instructions.contains("Quick read:") == false)
        #expect(instructions.contains("Bestie, this number") == false)
    }

    @Test func surfaceApplicator_preservesDeterministicFinancialPayload() throws {
        let answerID = UUID()
        let queryID = UUID()
        let raw = HomeAnswer(
            id: answerID,
            queryID: queryID,
            kind: .metric,
            userPrompt: "What did I spend this month?",
            title: "Spend This Month",
            subtitle: "Deterministic fallback text.",
            primaryValue: "$123.45",
            rows: [
                HomeAnswerRow(title: "Food", value: "$50.00")
            ],
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let generated = MarinaGeneratedSurfaceResponse(
            titleOverride: "Your Month So Far",
            narrativeSubtitle: "You are at $123.45 so far, with Food showing up as the visible row."
        )

        let applied = try MarinaResponseSurfaceApplicator().apply(
            generated: generated,
            to: raw,
            deterministicFollowUps: []
        )

        #expect(applied.answer.id == answerID)
        #expect(applied.answer.queryID == queryID)
        #expect(applied.answer.kind == .metric)
        #expect(applied.answer.title == raw.title)
        #expect(applied.answer.subtitle == generated.narrativeSubtitle)
        #expect(applied.answer.primaryValue == "$123.45")
        #expect(applied.answer.rows == raw.rows)
        #expect(applied.answer.generatedAt == raw.generatedAt)
    }

    @Test func surfaceApplicator_preservesDeterministicInsightRows() throws {
        let raw = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            title: "Dining",
            primaryValue: "$68.00",
            rows: [
                HomeAnswerRow(title: "Status", value: "Watch: spending is above the comparison period"),
                HomeAnswerRow(title: "Main Driver", value: "Cafe ($60.00)")
            ]
        )
        let generated = MarinaGeneratedSurfaceResponse(
            titleOverride: "Dining Check",
            narrativeSubtitle: "Dining is worth watching, mainly because Cafe is the visible driver."
        )
        let followUpQuery = HomeQuery(intent: .compareThisMonthToPreviousMonth)

        let applied = try MarinaResponseSurfaceApplicator().apply(
            generated: generated,
            to: raw,
            deterministicFollowUps: [
                MarinaSuggestion(title: "Compare with last month", query: followUpQuery)
            ]
        )

        #expect(applied.answer.title == raw.title)
        #expect(applied.answer.primaryValue == "$68.00")
        #expect(applied.answer.rows == raw.rows)
        #expect(applied.followUpSuggestions.map(\.query) == [followUpQuery])
    }

    @Test func surfaceApplicator_preservesCardSummaryAttachment() throws {
        let summary = CardSummaryPresentationModel(
            cardID: UUID(),
            title: "Apple Card",
            themeRaw: CardThemeOption.ruby.rawValue,
            effectRaw: CardEffectOption.plastic.rawValue,
            startDate: Date(timeIntervalSince1970: 1_776_729_600),
            endDate: Date(timeIntervalSince1970: 1_779_321_599),
            plannedTotal: 579.45,
            variableTotal: 909.06,
            total: 1_488.51
        )
        let raw = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "I found Apple Card.",
            subtitle: "Here's your Apple Card.",
            rows: [
                HomeAnswerRow(title: "Total", value: "$1,488.51"),
                HomeAnswerRow(title: "Planned", value: "$579.45"),
                HomeAnswerRow(title: "Variable", value: "$909.06")
            ],
            attachment: .cardSummary(summary)
        )
        let generated = MarinaGeneratedSurfaceResponse(
            titleOverride: "Different Title",
            narrativeSubtitle: "Here's your Apple Card. Total spending is currently $1,488.51."
        )

        let applied = try MarinaResponseSurfaceApplicator().apply(
            generated: generated,
            to: raw,
            deterministicFollowUps: []
        )

        #expect(applied.answer.title == raw.title)
        #expect(applied.answer.rows == raw.rows)
        #expect(applied.answer.attachment == raw.attachment)
        #expect(applied.answer.subtitle == generated.narrativeSubtitle)
    }

    @Test func surfaceApplicator_rewritesAndRanksOnlyDeterministicFollowUps() throws {
        let answer = HomeAnswer(queryID: UUID(), kind: .metric, title: "Spend", primaryValue: "$1")
        let first = MarinaSuggestion(
            title: "Top categories this month",
            query: HomeQuery(intent: .topCategoriesThisMonth)
        )
        let second = MarinaSuggestion(
            title: "Compare with last month",
            query: HomeQuery(intent: .compareThisMonthToPreviousMonth)
        )
        let generated = MarinaGeneratedSurfaceResponse(
            narrativeSubtitle: "Here is the read.",
            suggestionRewrites: [
                MarinaGeneratedSuggestionRewrite(candidateIndex: 1, title: "Compare this with last month"),
                MarinaGeneratedSuggestionRewrite(candidateIndex: 99, title: "Invented chip"),
                MarinaGeneratedSuggestionRewrite(candidateIndex: 0, title: "Show the top categories")
            ]
        )

        let applied = try MarinaResponseSurfaceApplicator().apply(
            generated: generated,
            to: answer,
            deterministicFollowUps: [first, second]
        )

        #expect(applied.followUpSuggestions.count == 2)
        #expect(applied.followUpSuggestions[0].title == "Top categories this month")
        #expect(applied.followUpSuggestions[0].query == first.query)
        #expect(applied.followUpSuggestions[1].title == "Compare with last month")
        #expect(applied.followUpSuggestions[1].query == second.query)
    }

    @Test func surfaceApplicator_rejectsInternalQuerySummarySuggestionTitles() throws {
        let answer = HomeAnswer(queryID: UUID(), kind: .message, title: "Fallback")
        let suggestion = MarinaSuggestion(
            title: "Spend this month",
            query: HomeQuery(intent: .spendThisMonth)
        )
        let generated = MarinaGeneratedSurfaceResponse(
            narrativeSubtitle: "Here is the read.",
            suggestionRewrites: [
                MarinaGeneratedSuggestionRewrite(candidateIndex: 0, title: "Spend this month -> intent=spendThisMonth")
            ]
        )

        let applied = try MarinaResponseSurfaceApplicator().apply(
            generated: generated,
            to: answer,
            deterministicFollowUps: [suggestion]
        )

        #expect(applied.followUpSuggestions.map(\.title) == ["Spend this month"])
    }

    @Test func surfaceApplicator_rejectsTitleOnlyOrDebugGeneratedSurface() throws {
        let answer = HomeAnswer(queryID: UUID(), kind: .message, title: "Fallback", subtitle: "Use me.")

        #expect(throws: MarinaResponseGenerationError.invariantViolation) {
            _ = try MarinaResponseSurfaceApplicator().apply(
                generated: MarinaGeneratedSurfaceResponse(titleOverride: "Do not use this"),
                to: answer,
                deterministicFollowUps: []
            )
        }

        #expect(throws: MarinaResponseGenerationError.invariantViolation) {
            _ = try MarinaResponseSurfaceApplicator().apply(
                generated: MarinaGeneratedSurfaceResponse(narrativeSubtitle: "{\"narrativeSubtitle\":\"Nope\"}"),
                to: answer,
                deterministicFollowUps: []
            )
        }
    }

    @Test func groundingBuilder_extractsCompactDeterministicFacts() throws {
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            title: "Dining",
            subtitle: "May 1 - May 31",
            primaryValue: "$68.00",
            rows: [
                HomeAnswerRow(title: "Status", value: "Watch: spending is above the comparison period"),
                HomeAnswerRow(title: "Main Driver", value: "Cafe ($60.00)"),
                HomeAnswerRow(title: "Other", value: "Visible but not an insight row")
            ]
        )

        let grounding = MarinaPresentationGroundingBuilder().build(
            userPrompt: "why is dining higher?",
            answer: answer,
            surfaceKind: .answer,
            dateWindow: "2026-05-01..2026-05-31",
            provenance: "Budget data",
            validationOutcomeSummary: "accepted",
            sourceSummary: "Foundation Models",
            clarificationChoices: []
        )

        #expect(grounding.userAskSummary == "why is dining higher?")
        #expect(grounding.answerHighlights.contains("Primary value: $68.00"))
        #expect(grounding.insightRows.contains("Status: Watch: spending is above the comparison period"))
        #expect(grounding.insightRows.contains("Main Driver: Cafe ($60.00)"))
        #expect(grounding.promptText.contains("Date/provenance: date=2026-05-01..2026-05-31; provenance=Budget data"))
    }

    @Test func surfaceApplicator_rejectsEmptyGeneratedSurface() throws {
        let answer = HomeAnswer(queryID: UUID(), kind: .message, title: "Fallback", subtitle: "Use me.")

        #expect(throws: MarinaResponseGenerationError.invariantViolation) {
            _ = try MarinaResponseSurfaceApplicator().apply(
                generated: MarinaGeneratedSurfaceResponse(),
                to: answer,
                deterministicFollowUps: []
            )
        }
    }

    @Test func surfaceApplicator_clarificationRewritePreservesChoices() throws {
        let answer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "I need one choice first",
            subtitle: "Which target did you mean?",
            rows: [
                HomeAnswerRow(title: "Groceries (category)", value: "Groceries"),
                HomeAnswerRow(title: "Groceries (merchant)", value: "Groceries")
            ]
        )
        let generated = MarinaGeneratedSurfaceResponse(
            clarificationMessage: "I found two Groceries matches. Which one should I use?"
        )

        let applied = try MarinaResponseSurfaceApplicator().apply(
            generated: generated,
            to: answer,
            deterministicFollowUps: []
        )

        #expect(applied.answer.subtitle == "I found two Groceries matches. Which one should I use?")
        #expect(applied.answer.rows == answer.rows)
    }
}
