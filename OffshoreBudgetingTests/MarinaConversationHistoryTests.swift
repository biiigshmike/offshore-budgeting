import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaConversationHistoryTests {
    @Test func recent_keepsLatestCompleteExchangesInChronologicalOrder() {
        let answers = (0..<6).map { answer(prompt: "Question \($0)", response: "Answer \($0)") }

        let exchanges = MarinaConversationHistory.recent(answers)

        #expect(exchanges.map(\.prompt) == ["Question 2", "Question 3", "Question 4", "Question 5"])
        #expect(exchanges.map(\.response) == ["Answer 2", "Answer 3", "Answer 4", "Answer 5"])
    }

    @Test func recent_budgetExcludesWholeOlderExchangeRatherThanTruncatingIt() {
        let older = answer(prompt: "Earlier", response: "An earlier answer")
        let latest = answer(prompt: "Latest", response: "Complete reply")
        let exactBudget = "Latest".count + "Complete reply".count

        let exchanges = MarinaConversationHistory.recent([older, latest], characterBudget: exactBudget)

        #expect(exchanges.count == 1)
        #expect(exchanges.first?.prompt == "Latest")
        #expect(exchanges.first?.response == "Complete reply")
        #expect(MarinaConversationHistory.recent([latest], characterBudget: exactBudget - 1).isEmpty)
    }

    @Test func recent_doesNotSkipOversizedNewestExchangeToRestoreUnrelatedOlderContext() {
        let older = answer(prompt: "Old", response: "Reply")
        let latest = answer(prompt: "Newest", response: String(repeating: "x", count: 100))

        #expect(MarinaConversationHistory.recent([older, latest], characterBudget: 30).isEmpty)
    }

    @Test func recent_excludesButtonCreatedMessagesWithoutUserPrompt() {
        let conversation = answer(prompt: "How much?", response: "$42")
        let creationMessage = HomeAnswer(queryID: UUID(), kind: .message, title: "Income saved")

        let exchanges = MarinaConversationHistory.recent([conversation, creationMessage])

        #expect(exchanges.count == 1)
        #expect(exchanges.first?.prompt == "How much?")
        #expect(exchanges.first?.response == "$42")
    }

    @Test func legacyAnswer_decodesVisibleContentWhenObsoleteMetadataCannotDecode() throws {
        let json = """
        {
          "id": "7DC1D865-73E3-4E63-8045-D373EE629AD4",
          "queryID": "08E1C671-16AF-4C48-8A49-987687DE1174",
          "kind": "metric",
          "userPrompt": "How much did I spend?",
          "title": "Spending",
          "primaryValue": "$42.00",
          "explanation": "Your recorded spending was $42.00.",
          "semanticContext": { "obsoleteRoute": "legacy" },
          "insightBundle": { "obsoleteNarrator": true },
          "attachment": { "retiredAction": {} },
          "generatedAt": 100
        }
        """

        let decoded = try JSONDecoder().decode(HomeAnswer.self, from: Data(json.utf8))

        #expect(decoded.title == "Spending")
        #expect(decoded.primaryValue == "$42.00")
        #expect(decoded.explanation == "Your recorded spending was $42.00.")
        #expect(decoded.rows.isEmpty)
        #expect(decoded.attachment == nil)
        let restored = MarinaConversationHistory.recent([decoded])
        #expect(restored.first?.prompt == "How much did I spend?")
        #expect(restored.first?.response.contains("$42.00") == true)
        let roundTrip = try JSONDecoder().decode(HomeAnswer.self, from: JSONEncoder().encode(decoded))
        #expect(roundTrip == decoded)
    }

    private func answer(prompt: String, response: String) -> HomeAnswer {
        HomeAnswer(queryID: UUID(), kind: .message, userPrompt: prompt, title: "", explanation: response)
    }
}
