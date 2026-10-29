import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaFrameRetrievalTests {
    @Test func initialTopicCanBeRetrievedAfterTwentyOtherTurnsAndRestoration() throws {
        var fixture = Fixture()
        let first = try fixture.append(prompt: "Show my June Apple Card expenses", scope: "Apple Card · June 2026")
        for index in 1...20 {
            _ = try fixture.append(prompt: "October category report \(index)", scope: "Personal · October 2026")
        }
        fixture.history = try JSONDecoder().decode([HomeAnswer].self, from: JSONEncoder().encode(fixture.history))
        fixture.memory = try JSONDecoder().decode(MarinaConversationMemory.self, from: JSONEncoder().encode(fixture.memory))
        #expect(fixture.memory.completedFrame(reference: first.reference) == nil)
        let chosen = MarinaFrameRetrieval.frames(for: "Return to the June card report", memory: fixture.memory,
                                                 history: fixture.history)
        #expect(chosen.first?.reference == fixture.memory.latestCompletedFrame?.reference)
        #expect(chosen.dropFirst().first?.reference == first.reference)
        #expect(chosen.count <= MarinaFrameRetrieval.maxEarlierFrames + 1)
    }

    @Test func equallyMatchingRepeatedQuestionsKeepTheOldestCandidateAvailable() throws {
        var fixture = Fixture()
        let first = try fixture.append(prompt: "June expenses", scope: "Personal June")
        for _ in 0..<20 { _ = try fixture.append(prompt: "June expenses", scope: "Personal June") }
        let chosen = MarinaFrameRetrieval.frames(for: "June expenses", memory: fixture.memory,
                                                 history: fixture.history, limit: 1)
        #expect(chosen.map(\.reference) == ["t21", first.reference])
        #expect(chosen == MarinaFrameRetrieval.frames(for: "June expenses", memory: fixture.memory,
                                                     history: fixture.history, limit: 1))
    }

    @Test func rankingUsesGenericTextRatherThanFinancialOperations() throws {
        var fixture = Fixture()
        let first = try fixture.append(prompt: "Same question", scope: "Same scope", tool: .income)
        let second = try fixture.append(prompt: "Same question", scope: "Same scope", tool: .expenses)
        _ = try fixture.append(prompt: "Current topic", scope: "Current scope", tool: .budgetSummary)
        let chosen = MarinaFrameRetrieval.frames(for: "Same question", memory: fixture.memory, history: fixture.history)
        #expect(chosen.dropFirst().map(\.reference) == [first.reference, second.reference])
    }

    @Test func punctuationCaseAndDiacriticsUseTheSameGenericTerms() throws {
        var fixture = Fixture()
        let match = try fixture.append(prompt: "CAFÉ—DOS, Inc.!", scope: "Personal")
        _ = try fixture.append(prompt: "Cafe", scope: "Personal")
        _ = try fixture.append(prompt: "Latest topic", scope: "Personal")
        let chosen = MarinaFrameRetrieval.frames(for: "cafe dos inc", memory: fixture.memory,
                                                 history: fixture.history, limit: 1)
        #expect(chosen.dropFirst().first?.reference == match.reference)
    }

    @Test func rareTermsOutrankCommonConversationalTerms() throws {
        var fixture = Fixture()
        let match = try fixture.append(prompt: "Lunar purchases", scope: "Personal")
        for _ in 0..<18 { _ = try fixture.append(prompt: "My spending", scope: "Personal") }
        _ = try fixture.append(prompt: "Active topic", scope: "Personal")
        let chosen = MarinaFrameRetrieval.frames(for: "my spending Lunar", memory: fixture.memory,
                                                 history: fixture.history, limit: 1)
        #expect(chosen.dropFirst().first?.reference == match.reference)
    }

    @Test func boundsAndEmptyQueriesAlwaysRetainOnlyRelevantMetadataPlusActive() throws {
        var fixture = Fixture()
        for index in 0..<15 { _ = try fixture.append(prompt: "Common topic \(index)", scope: "Personal") }
        let active = try #require(fixture.memory.latestCompletedFrame)
        for limit in [0, -1] {
            #expect(MarinaFrameRetrieval.frames(for: "Common", memory: fixture.memory,
                                               history: fixture.history, limit: limit) == [active])
        }
        let bounded = MarinaFrameRetrieval.frames(for: "Common", memory: fixture.memory,
                                                  history: fixture.history, limit: Int.max)
        #expect(bounded.count == MarinaFrameRetrieval.maxEarlierFrames + 1)
        #expect(Set(bounded.map(\.reference)).count == bounded.count)
        for prompt in ["", " ! ", "unrelated"] {
            #expect(MarinaFrameRetrieval.frames(for: prompt, memory: fixture.memory,
                                               history: fixture.history) == [active])
        }
    }

    @Test func foreignMetadataAndAnswerFinancialPayloadsNeverSupplyCandidates() throws {
        var fixture = Fixture()
        _ = try fixture.append(prompt: "Previous question", scope: "Personal", explanation: "Canary 987654.32")
        _ = try fixture.append(prompt: "Current question", scope: "Personal")
        var foreign = Fixture()
        _ = try foreign.append(prompt: "Canary", scope: "Foreign")
        fixture.history.append(contentsOf: foreign.history)
        let chosen = MarinaFrameRetrieval.frames(for: "Canary", memory: fixture.memory, history: fixture.history)
        let active = try #require(fixture.memory.latestCompletedFrame)
        #expect(chosen == [active])
    }

    @MainActor private struct Fixture {
        var memory = MarinaConversationMemory(workspaceID: UUID(), chatID: UUID())
        var history: [HomeAnswer] = []

        mutating func append(prompt: String, scope: String, tool: MarinaDataRequest.Tool = .expenses,
                             explanation: String? = nil) throws -> MarinaConversationMemory.CompletedFrame {
            let answerID = UUID()
            let request = MarinaDataRequest(tool: tool, startDate: "2026-06-01", endDate: "2026-06-30")
            let committed = memory.commitCompletedFrame(request: request,
                result: .init(scope: scope, resolvedRequest: request), answerID: answerID, prompt: prompt)
            let frame = try #require(committed)
            var answer = HomeAnswer(id: answerID, queryID: UUID(), kind: .message,
                                    userPrompt: prompt, title: "", explanation: explanation)
            answer.completedFrame = frame
            history.append(answer)
            return frame
        }
    }
}
