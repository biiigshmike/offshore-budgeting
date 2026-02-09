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

    @Test func personaCatalog_containsAllExpectedPersonas() throws {
        let ids = Set(HomeAssistantPersonaCatalog.allProfiles.map(\.id))
        let expected = Set(HomeAssistantPersonaID.allCases)

        #expect(ids == expected)
        #expect(HomeAssistantPersonaCatalog.defaultPersona == .marina)
    }

    @Test func personaCatalog_profilesHavePreviewLines() throws {
        for profile in HomeAssistantPersonaCatalog.allProfiles {
            #expect(profile.previewLines.isEmpty == false)
            #expect(profile.displayName.isEmpty == false)
            #expect(profile.summary.isEmpty == false)
        }
    }

    // MARK: - Store

    @Test func personaStore_defaultsToCatalogDefaultWhenUnset() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        let selected = setup.store.loadSelectedPersona()

        #expect(selected == HomeAssistantPersonaCatalog.defaultPersona)
    }

    @Test func personaStore_roundTripPersistsSelectedPersona() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        setup.store.saveSelectedPersona(.harper)
        let selected = setup.store.loadSelectedPersona()

        #expect(selected == .harper)
    }

    @Test func personaStore_invalidStoredValueFallsBackToDefault() throws {
        let setup = makeStore()
        defer { clearDefaults(setup.suiteName) }

        setup.defaults.set("invalid_persona", forKey: setup.key)

        let selected = setup.store.loadSelectedPersona()

        #expect(selected == HomeAssistantPersonaCatalog.defaultPersona)
    }

    // MARK: - Formatter

    @Test func formatter_unresolvedPromptAnswer_usesPersonaSpecificCopy() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let answer = formatter.unresolvedPromptAnswer(
            for: "can you find my leaks?",
            personaID: .captainCash
        )

        #expect(answer.kind == .message)
        #expect(answer.userPrompt == "can you find my leaks?")
        #expect(answer.title.contains("Command not recognized"))
        #expect(answer.rows.isEmpty)
        #expect(answer.primaryValue == nil)
    }

    @Test func formatter_styledAnswer_preservesMetricsAndRows() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let raw = HomeAnswer(
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

        let styled = formatter.styledAnswer(
            from: raw,
            userPrompt: "spend this month",
            personaID: .harper
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

    @Test func formatter_styledAnswer_changesPersonaCopyOnly() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let raw = HomeAnswer(
            queryID: UUID(),
            kind: .comparison,
            title: "This Month vs Last Month",
            subtitle: "Up $150.00",
            primaryValue: "$400.00",
            rows: [
                HomeAnswerRow(title: "February 2026", value: "$400.00"),
                HomeAnswerRow(title: "January 2026", value: "$250.00")
            ]
        )

        let marina = formatter.styledAnswer(from: raw, userPrompt: nil, personaID: .marina)
        let captain = formatter.styledAnswer(from: raw, userPrompt: nil, personaID: .captainCash)

        #expect(marina.primaryValue == raw.primaryValue)
        #expect(captain.primaryValue == raw.primaryValue)
        #expect(marina.rows == raw.rows)
        #expect(captain.rows == raw.rows)
        #expect(marina.subtitle != captain.subtitle)
    }

    @Test func formatter_greetingAnswer_returnsPersonaGreeting() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let greeting = formatter.greetingAnswer(for: .marina)

        #expect(greeting.kind == .message)
        #expect(greeting.title.contains("Marina"))
        #expect(greeting.primaryValue == nil)
        #expect(greeting.rows.isEmpty)
    }

    @Test func formatter_styledAnswer_noDataMessage_usesPersonaNoDataCopy() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let raw = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            title: "Largest Recent Transactions",
            subtitle: "No transactions found in this range.",
            primaryValue: nil,
            rows: []
        )

        let styled = formatter.styledAnswer(from: raw, userPrompt: "largest transactions", personaID: .harper)

        #expect(styled.title == "The selected range has no matching records.")
        #expect(styled.subtitle?.contains("Sources:") == true)
        #expect(styled.subtitle?.contains("Expand or shift the date range") == true)
        #expect(styled.primaryValue == nil)
        #expect(styled.rows.isEmpty)
    }

    @Test func formatter_followUpSuggestions_returnDeterministicQueryIntents() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })

        let metricAnswer = HomeAnswer(queryID: UUID(), kind: .metric, title: "Spend", subtitle: nil, primaryValue: "$1", rows: [])
        let followUps = formatter.followUpSuggestions(after: metricAnswer, personaID: .marina)

        #expect(followUps.count == 2)
        #expect(followUps[0].query.intent == .topCategoriesThisMonth)
        #expect(followUps[1].query.intent == .compareThisMonthToPreviousMonth)
    }

    @Test func formatter_followUpSuggestions_personaPrefixChangesCopyNotIntent() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let listAnswer = HomeAnswer(queryID: UUID(), kind: .list, title: "Top Categories", subtitle: nil, primaryValue: nil, rows: [])

        let marina = formatter.followUpSuggestions(after: listAnswer, personaID: .marina)
        let captain = formatter.followUpSuggestions(after: listAnswer, personaID: .captainCash)

        #expect(marina.count == captain.count)
        #expect(marina[0].query.intent == captain[0].query.intent)
        #expect(marina[1].query.intent == captain[1].query.intent)
        #expect(marina[0].title != captain[0].title)
    }

    @Test func formatter_followUpSuggestions_budgetOverview_returnsNarrowingCardsFlow() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let overview = HomeAnswer(queryID: UUID(), kind: .list, title: "Budget Overview", subtitle: nil, primaryValue: nil, rows: [])

        let followUps = formatter.followUpSuggestions(after: overview, personaID: .marina)

        #expect(followUps.count == 2)
        #expect(followUps[0].query.intent == .cardVariableSpendingHabits)
        #expect(followUps[1].query.intent == .topCategoriesThisMonth)
    }

    @Test func formatter_followUpSuggestions_lowConfidence_returnsClarifyingChips() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let lowConfidenceAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Budget Check-In",
            subtitle: "Best-effort summary. Use follow-up chips to narrow this.",
            primaryValue: "$1,234",
            rows: []
        )

        let followUps = formatter.followUpSuggestions(after: lowConfidenceAnswer, personaID: .captainCash)

        #expect(followUps.count == 2)
        #expect(followUps[0].query.intent == .spendThisMonth)
        #expect(followUps[1].query.intent == .topCategoriesThisMonth)
    }

    @Test func formatter_followUpSuggestions_mediumConfidence_returnsNarrowingChips() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let mediumConfidenceAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .list,
            title: "Budget Check-In",
            subtitle: "Likely match for your request.",
            primaryValue: "$1,234",
            rows: []
        )

        let followUps = formatter.followUpSuggestions(after: mediumConfidenceAnswer, personaID: .marina)

        #expect(followUps.count == 2)
        #expect(followUps[0].query.intent == .topCategoriesThisMonth)
        #expect(followUps[1].query.intent == .compareThisMonthToPreviousMonth)
    }

    @Test func formatter_personaDidChangeAnswer_containsOldAndNewPersona() throws {
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { _, _ in 0 })
        let answer = formatter.personaDidChangeAnswer(from: .finn, to: .harper)

        #expect(answer.kind == .message)
        #expect(answer.title.contains("Harper"))
        #expect(answer.subtitle?.contains("Finn") == true)
        #expect(answer.primaryValue == nil)
        #expect(answer.rows.isEmpty)
    }

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

    @Test func formatter_followUpSuggestions_randomizesTitleLeadButKeepsIntent() throws {
        var nextIndex = 0
        let formatter = HomeAssistantPersonaFormatter(variantIndexPicker: { upperBound, _ in
            guard upperBound > 0 else { return 0 }
            defer { nextIndex += 1 }
            return nextIndex % upperBound
        })

        let metricAnswer = HomeAnswer(queryID: UUID(), kind: .metric, title: "Spend", subtitle: nil, primaryValue: "$1", rows: [])

        let first = formatter.followUpSuggestions(after: metricAnswer, personaID: .captainCash)
        let second = formatter.followUpSuggestions(after: metricAnswer, personaID: .captainCash)

        #expect(first[0].query.intent == second[0].query.intent)
        #expect(first[1].query.intent == second[1].query.intent)
        #expect(first[0].title != second[0].title)
    }

    @Test func formatter_followUpSuggestions_sessionSeedKeepsTitlesStableForSameAnswer() throws {
        let formatter = HomeAssistantPersonaFormatter(sessionSeed: 42)
        let metricAnswer = HomeAnswer(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            queryID: UUID(),
            kind: .metric,
            title: "Spend",
            subtitle: nil,
            primaryValue: "$1",
            rows: []
        )

        let first = formatter.followUpSuggestions(after: metricAnswer, personaID: .captainCash)
        let second = formatter.followUpSuggestions(after: metricAnswer, personaID: .captainCash)

        #expect(first.count == second.count)
        #expect(first[0].query.intent == second[0].query.intent)
        #expect(first[1].query.intent == second[1].query.intent)
        #expect(first[0].title == second[0].title)
        #expect(first[1].title == second[1].title)
    }

    // MARK: - Helpers

    private func makeStore() -> (
        store: HomeAssistantPersonaStore,
        defaults: UserDefaults,
        suiteName: String,
        key: String
    ) {
        let suiteName = "HomeAssistantPersonaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        let key = "test.assistant.persona.id"

        return (
            store: HomeAssistantPersonaStore(userDefaults: defaults, storageKey: key),
            defaults: defaults,
            suiteName: suiteName,
            key: key
        )
    }

    private func clearDefaults(_ suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }
}
