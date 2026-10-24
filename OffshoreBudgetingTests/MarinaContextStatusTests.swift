import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaContextStatusTests {
    @Test func measuredBoundaries() {
        #expect(MarinaContextStatus.measured(tokens: 749, capacity: 1000) == nil)
        #expect(MarinaContextStatus.measured(tokens: 750, capacity: 1000) == .approaching)
        #expect(MarinaContextStatus.measured(tokens: 999, capacity: 1000) == .approaching)
        #expect(MarinaContextStatus.measured(tokens: 1000, capacity: 1000) == .reached)
        #expect(MarinaContextStatus.measured(tokens: 1100, capacity: 1000) == .reached)
        #expect(MarinaContextStatus.measured(tokens: 0, capacity: 0) == nil)
    }

    @Test func savedNoticesDoNotLockAChatAfterSessionRenewal() throws {
        var answer = HomeAnswer(queryID: UUID(), kind: .message, title: "")
        answer.contextStatus = .approaching
        let pending = HomeAnswer(queryID: UUID(), kind: .message, title: "", responseState: .thinking)
        #expect(MarinaContextStatus.status(in: [answer, pending]) == nil)
        answer.contextStatus = .reached
        let restored = try JSONDecoder().decode(HomeAnswer.self, from: JSONEncoder().encode(answer))
        #expect(restored.contextStatus == .reached)
        #expect(MarinaContextStatus.status(in: [restored, pending]) == nil)
        #expect(MarinaContextStatus.status(in: []) == nil)
    }

    @Test func legacyHistoryAndFrameworkLimit() throws {
        let answer = HomeAnswer(queryID: UUID(), kind: .message, title: "")
        let restored = try JSONDecoder().decode(HomeAnswer.self, from: JSONEncoder().encode(answer))
        #expect(restored.contextStatus == nil)
        #expect(MarinaContextStatus.status(in: [restored]) == nil)
        let failed = HomeAnswer(queryID: UUID(), kind: .message, title: "", responseState: .contextLimit)
        #expect(MarinaContextStatus.status(in: [failed]) == nil)
        #expect(MarinaResponseState.contextLimit.canRetry)
        #expect(MarinaResponseState.recovering.isActive)
    }
}
