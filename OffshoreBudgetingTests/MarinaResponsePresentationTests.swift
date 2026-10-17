import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaResponsePresentationTests {
    @Test func pendingTurnAlreadyContainsUserAndAssistantMessagesBeforeAnyModelOutput() {
        let turnID = UUID()
        let pending = HomeAnswer(
            id: turnID, queryID: turnID, kind: .message,
            userPrompt: "How much have I spent this month?", title: "",
            presentations: [], responseState: .thinking
        )

        let messages = MarinaConversationDisplayAdapter.messages(from: [pending])

        #expect(messages.count == 2)
        #expect(messages[0].role == .user)
        #expect(messages[0].prompt == pending.userPrompt)
        #expect(messages[1].role == .assistant)
        #expect(messages[1].answer?.responseState == .thinking)
        #expect(messages[1].answer?.explanation == nil)
        #expect(!MarinaPanelView.hasAssistantCardContent(pending))
    }

    @Test func streamingFailureAndRetryKeepOneUserMessageAndStableDisplayIdentity() {
        let turnID = UUID()
        var answer = HomeAnswer(
            id: turnID, queryID: turnID, kind: .message,
            userPrompt: "Show the expenses", title: "",
            presentations: [], responseState: .thinking
        )
        let initialIDs = MarinaConversationDisplayAdapter.messages(from: [answer]).map(\.id)

        for state in [MarinaResponseState.readingExpenses, .responding, .generationFailed, .thinking, .complete] {
            answer = HomeAnswer(id: turnID, queryID: turnID, kind: .message,
                userPrompt: "Show the expenses", title: "",
                explanation: state == .responding ? "Here are your expenses." : nil,
                presentations: [], responseState: state)
            let messages = MarinaConversationDisplayAdapter.messages(from: [answer])
            #expect(messages.map(\.id) == initialIDs)
            #expect(messages.filter { $0.role == .user }.count == 1)
            #expect(messages.last?.answer?.responseState == state)
        }
    }

    @Test func savedFailureRetainsScopedVisualAndRetryState() throws {
        let presentation = MarinaPresentation(
            id: "saved-result", operation: .summary, title: "Spending",
            scopeLabel: "Apple Card · October 2026",
            metrics: [.init(label: "Total", value: 3177.38)],
            card: .init(id: UUID().uuidString, name: "Apple Card", theme: "aqua", effect: "metal")
        )
        let answer = HomeAnswer(
            queryID: UUID(), kind: .message, userPrompt: "How much was on Apple Card?", title: "",
            presentations: [presentation], responseState: .generationFailed
        )

        let restored = try JSONDecoder().decode(HomeAnswer.self, from: JSONEncoder().encode(answer))

        #expect(restored.presentations == [presentation])
        #expect(restored.responseState?.canRetry == true)
        #expect(restored.userPrompt == answer.userPrompt)
        #expect(restored.id == answer.id)
        #expect(!MarinaPanelView.hasAssistantCardContent(restored))
    }
}
