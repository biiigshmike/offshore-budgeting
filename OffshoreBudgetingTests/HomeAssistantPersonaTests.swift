//
//  HomeAssistantPersonaTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeAssistantPersonaTests {

    // MARK: - Catalog

    @Test func personaCatalog_containsOnlyMarina() throws {
        let ids = HomeAssistantPersonaCatalog.allProfiles.map(\.id)

        #expect(ids == [.marina])
        #expect(HomeAssistantPersonaCatalog.defaultPersona == .marina)
    }

    @Test func personaCatalog_profileHasPreviewLines() throws {
        let profile = HomeAssistantPersonaCatalog.profile(for: .marina)

        #expect(profile.previewLines.isEmpty == false)
        #expect(profile.displayName == "Marina")
        #expect(profile.summary.isEmpty == false)
    }

    // MARK: - Formatter

    @Test func formatter_unresolvedPromptAnswer_usesMarinaCopy() throws {
        let formatter = makeFixedFormatter()
        let answer = formatter.unresolvedPromptAnswer(
            for: "can you find my leaks?",
            personaID: .marina
        )

        #expect(answer.kind == .message)
        #expect(answer.userPrompt == "can you find my leaks?")
        #expect(answer.title.contains("clearer budgeting prompt"))
        #expect(answer.rows.isEmpty)
        #expect(answer.primaryValue == nil)
    }

    @Test func formatter_styledAnswer_preservesMetricsAndRows() throws {
        let formatter = makeFixedFormatter()
        let raw = metricRawAnswer()

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "spend this month",
            personaID: .marina
        )

        #expect(styled.id == raw.id)
        #expect(styled.queryID == raw.queryID)
        #expect(styled.kind == raw.kind)
        #expect(styled.title == raw.title)
        #expect(styled.primaryValue == raw.primaryValue)
        #expect(styled.rows == raw.rows)
        #expect(styled.generatedAt == raw.generatedAt)
        #expect(styled.userPrompt == "spend this month")
        #expect(styled.subtitle?.contains("February 2026") == true)
    }

    @Test func formatter_greetingAnswer_returnsMarinaGreeting() throws {
        let formatter = makeFixedFormatter()
        let greeting = formatter.greetingAnswer(for: .marina)

        #expect(greeting.kind == .message)
        #expect(greeting.title.contains("Marina"))
        #expect(greeting.primaryValue == nil)
        #expect(greeting.rows.isEmpty)
    }

    @Test func formatter_styledAnswer_noDataMessage_usesMarinaNoDataCopy() throws {
        let formatter = makeFixedFormatter()
        let raw = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "Largest Recent Transactions",
            subtitle: "No transactions found in this range.",
            primaryValue: nil,
            rows: []
        )

        let styled = formatter.styledAnswer(from: raw, userPrompt: "largest transactions", personaID: .marina)

        #expect(styled.title == "No activity in this range yet.")
        #expect(styled.subtitle?.contains("Sources:") == true)
        #expect(styled.subtitle?.contains("Try a different date range") == true)
        #expect(styled.primaryValue == nil)
        #expect(styled.rows.isEmpty)
    }

    // MARK: - Follow-Up

    @Test func formatter_followUpSuggestions_returnDeterministicQueryIntents() throws {
        let formatter = makeFixedFormatter()

        let metricAnswer = HomeAnswer(queryID: UUID(), kind: .metric, title: "Spend", subtitle: nil, primaryValue: "$1", rows: [])
        let followUps = formatter.followUpSuggestions(after: metricAnswer, personaID: .marina)

        #expect(followUps.count == 2)
        #expect(followUps[0].query.intent == .topCategoriesThisMonth)
        #expect(followUps[1].query.intent == .compareThisMonthToPreviousMonth)
    }

    @Test func formatter_followUpSuggestions_budgetOverview_returnsNarrowingCardsFlow() throws {
        let formatter = makeFixedFormatter()
        let overview = HomeAnswer(queryID: UUID(), kind: .list, title: "Budget Overview", subtitle: nil, primaryValue: nil, rows: [])

        let followUps = formatter.followUpSuggestions(after: overview, personaID: .marina)

        #expect(followUps.count == 2)
        #expect(followUps[0].query.intent == .cardVariableSpendingHabits)
        #expect(followUps[1].query.intent == .topCategoriesThisMonth)
    }

    @Test func formatter_followUpSuggestions_v2_usesPlainActionTitles() throws {
        let formatter = HomeAssistantPersonaFormatter(
            variantIndexPicker: { _, _ in 0 },
            responseRules: .marinaV2
        )
        let metricAnswer = HomeAnswer(queryID: UUID(), kind: .metric, title: "Spend", subtitle: nil, primaryValue: "$1", rows: [])

        let followUps = formatter.followUpSuggestions(after: metricAnswer, personaID: .marina)

        #expect(followUps.count == 2)
        #expect(followUps[0].title == "Top 3 categories this month")
        #expect(followUps[1].title == "Compare with last month")
    }

    // MARK: - Variation

    @Test func formatter_styledAnswer_randomizesPersonaToneLines() throws {
        var nextIndex = 0
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { upperBound, _ in
            guard upperBound > 0 else { return 0 }
            defer { nextIndex += 1 }
            return nextIndex % upperBound
        })

        let raw = HomeAnswer(
            queryID: UUID(),
            kind: .metric,
            title: "Spend This Month",
            subtitle: "February 2026",
            primaryValue: "$1,350.00",
            rows: []
        )

        var uniqueSubtitles = Set<String>()
        for _ in 0..<5 {
            let styled = formatter.styledAnswer(from: raw, userPrompt: "spend this month", personaID: .marina)
            if let subtitle = styled.subtitle {
                uniqueSubtitles.insert(subtitle)
            }
        }

        #expect(uniqueSubtitles.count == 5)
    }

    // MARK: - Helpers

    private func makeFixedFormatter() -> HomeAssistantPersonaFormatter {
        HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
    }

    private func metricRawAnswer() -> HomeAnswer {
        HomeAnswer(
            id: UUID(uuidString: "AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB")!,
            queryID: UUID(uuidString: "CCCCCCCC-1111-2222-3333-DDDDDDDDDDDD")!,
            kind: .metric,
            title: "Spend This Month",
            subtitle: "February 2026",
            primaryValue: "$1,350.00",
            rows: [
                HomeAnswerRow(title: "Planned", value: "$1,100.00"),
                HomeAnswerRow(title: "Variable", value: "$250.00")
            ],
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }
}
