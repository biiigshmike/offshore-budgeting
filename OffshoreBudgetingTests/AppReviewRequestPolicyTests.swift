import Foundation
import Testing
@testable import Offshore

@MainActor
struct AppReviewRequestPolicyTests {
    @Test func newUsersAndRapidEntryDoNotTriggerReviewRequests() throws {
        let suite = "AppReviewRequestPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        for _ in 0..<20 {
            #expect(!AppReviewRequestPolicy.recordExpenseAdded(defaults: defaults, now: start))
        }
        #expect(AppReviewRequestPolicy.recordExpenseAdded(defaults: defaults, now: start.addingTimeInterval(8 * 86_400)))
    }

    @Test func requestsRequireTenEntriesAndRespectTheCooldown() throws {
        let suite = "AppReviewRequestPolicyTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(!AppReviewRequestPolicy.recordExpenseAdded(defaults: defaults, now: start))
        let later = start.addingTimeInterval(8 * 86_400)
        for _ in 0..<8 {
            #expect(!AppReviewRequestPolicy.recordExpenseAdded(defaults: defaults, now: later))
        }
        #expect(AppReviewRequestPolicy.recordExpenseAdded(defaults: defaults, now: later))
        #expect(!AppReviewRequestPolicy.recordExpenseAdded(defaults: defaults, now: later))
        #expect(!AppReviewRequestPolicy.recordExpenseAdded(defaults: defaults, now: later.addingTimeInterval(179 * 86_400)))
        #expect(AppReviewRequestPolicy.recordExpenseAdded(defaults: defaults, now: later.addingTimeInterval(180 * 86_400)))
    }
}
