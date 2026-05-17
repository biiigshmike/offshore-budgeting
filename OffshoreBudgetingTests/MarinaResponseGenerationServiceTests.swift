import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaResponseGenerationServiceTests {
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
        #expect(applied.answer.title == "Your Month So Far")
        #expect(applied.answer.subtitle == generated.narrativeSubtitle)
        #expect(applied.answer.primaryValue == "$123.45")
        #expect(applied.answer.rows == raw.rows)
        #expect(applied.answer.generatedAt == raw.generatedAt)
    }

    @Test func surfaceApplicator_rewritesAndRanksOnlyDeterministicFollowUps() throws {
        let answer = HomeAnswer(queryID: UUID(), kind: .metric, title: "Spend", primaryValue: "$1")
        let first = HomeAssistantSuggestion(
            title: "Top categories this month",
            query: HomeQuery(intent: .topCategoriesThisMonth)
        )
        let second = HomeAssistantSuggestion(
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
        #expect(applied.followUpSuggestions[0].title == "Compare this with last month")
        #expect(applied.followUpSuggestions[0].query == second.query)
        #expect(applied.followUpSuggestions[1].title == "Show the top categories")
        #expect(applied.followUpSuggestions[1].query == first.query)
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
