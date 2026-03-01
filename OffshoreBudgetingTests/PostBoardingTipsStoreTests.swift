//
//  PostBoardingTipsStoreTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 3/1/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct PostBoardingTipsStoreTests {

    // MARK: - Helpers

    private func makeDefaults() -> UserDefaults {
        let suiteName = "PostBoardingTipsStoreTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create test UserDefaults suite.")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Tests

    @Test func init_reconcilesMismatchedResetToken() {
        let defaults = makeDefaults()
        defaults.set(5, forKey: "tips_resetToken")
        defaults.set(4, forKey: "tips_seen_lastResetToken")
        defaults.set("tip.home.v1,tip.budgets.v1", forKey: "tips_seenKeys")

        let store = PostBoardingTipsStore(defaults: defaults)

        #expect(store.resetToken == 5)
        #expect(store.lastResetToken == 5)
        #expect(store.hasSeen("tip.home.v1") == false)
        #expect(defaults.integer(forKey: "tips_seen_lastResetToken") == 5)
        #expect((defaults.string(forKey: "tips_seenKeys") ?? "").isEmpty)
    }

    @Test func markSeen_isIdempotent() {
        let defaults = makeDefaults()
        let store = PostBoardingTipsStore(defaults: defaults)

        store.markSeen("tip.home.v1")
        let firstSerial = store.changeSerial
        store.markSeen("tip.home.v1")

        #expect(store.hasSeen("tip.home.v1"))
        #expect(store.changeSerial == firstSerial)
        #expect(defaults.string(forKey: "tips_seenKeys") == "tip.home.v1")
    }

    @Test func resetTips_clearsSeenAndIncrementsToken() {
        let defaults = makeDefaults()
        defaults.set(2, forKey: "tips_resetToken")
        defaults.set(2, forKey: "tips_seen_lastResetToken")
        defaults.set("tip.home.v1", forKey: "tips_seenKeys")
        let store = PostBoardingTipsStore(defaults: defaults)

        store.resetTips()

        #expect(store.resetToken == 3)
        #expect(store.lastResetToken == 3)
        #expect(store.hasSeen("tip.home.v1") == false)
        #expect(defaults.integer(forKey: "tips_resetToken") == 3)
        #expect(defaults.integer(forKey: "tips_seen_lastResetToken") == 3)
        #expect((defaults.string(forKey: "tips_seenKeys") ?? "").isEmpty)
    }

    @Test func resetToBaselineForErase_setsCleanBaseline() {
        let defaults = makeDefaults()
        defaults.set(9, forKey: "tips_resetToken")
        defaults.set(9, forKey: "tips_seen_lastResetToken")
        defaults.set("tip.home.v1,tip.budgets.v1", forKey: "tips_seenKeys")
        let store = PostBoardingTipsStore(defaults: defaults)

        store.resetToBaselineForErase()

        #expect(store.resetToken == 0)
        #expect(store.lastResetToken == 0)
        #expect(store.hasSeen("tip.home.v1") == false)
        #expect(store.hasSeen("tip.budgets.v1") == false)
        #expect(defaults.integer(forKey: "tips_resetToken") == 0)
        #expect(defaults.integer(forKey: "tips_seen_lastResetToken") == 0)
        #expect((defaults.string(forKey: "tips_seenKeys") ?? "").isEmpty)
    }

    @Test func persistsSeenKeysAcrossStoreInstances() {
        let defaults = makeDefaults()
        let store = PostBoardingTipsStore(defaults: defaults)
        store.markSeen("tip.home.v1")
        store.markSeen("tip.budgets.v1")

        let restoredStore = PostBoardingTipsStore(defaults: defaults)

        #expect(restoredStore.hasSeen("tip.home.v1"))
        #expect(restoredStore.hasSeen("tip.budgets.v1"))
    }
}
