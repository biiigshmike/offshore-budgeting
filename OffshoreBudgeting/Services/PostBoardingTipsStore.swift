//
//  PostBoardingTipsStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 3/1/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class PostBoardingTipsStore {

    // MARK: - Keys

    private enum Keys {
        static let resetToken = "tips_resetToken"
        static let seenKeys = "tips_seenKeys"
        static let lastResetToken = "tips_seen_lastResetToken"
    }

    // MARK: - State

    private let defaults: UserDefaults
    private(set) var resetToken: Int
    private(set) var seenKeys: Set<String>
    private(set) var lastResetToken: Int
    private(set) var changeSerial: Int = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.resetToken = defaults.integer(forKey: Keys.resetToken)
        self.lastResetToken = defaults.integer(forKey: Keys.lastResetToken)
        self.seenKeys = Self.parseSeenKeys(defaults.string(forKey: Keys.seenKeys) ?? "")
        reconcileResetStateIfNeeded()
    }

    // MARK: - Access

    func hasSeen(_ key: String) -> Bool {
        seenKeys.contains(key)
    }

    func markSeen(_ key: String) {
        guard !key.isEmpty else { return }
        let inserted = seenKeys.insert(key).inserted
        guard inserted else { return }
        persistSeenKeys()
        bumpChangeSerial()
    }

    // MARK: - Mutations

    func resetTips() {
        resetToken += 1
        seenKeys = []
        lastResetToken = resetToken
        persistAll()
        bumpChangeSerial()
    }

    func resetToBaselineForErase() {
        resetToken = 0
        seenKeys = []
        lastResetToken = 0
        persistAll()
        bumpChangeSerial()
    }

    // MARK: - Persistence

    private func reconcileResetStateIfNeeded() {
        guard lastResetToken != resetToken else { return }
        seenKeys = []
        lastResetToken = resetToken
        persistAll()
    }

    private func persistAll() {
        defaults.set(resetToken, forKey: Keys.resetToken)
        defaults.set(lastResetToken, forKey: Keys.lastResetToken)
        persistSeenKeys()
    }

    private func persistSeenKeys() {
        let csv = seenKeys.sorted().joined(separator: ",")
        defaults.set(csv, forKey: Keys.seenKeys)
    }

    private func bumpChangeSerial() {
        changeSerial += 1
    }

    private static func parseSeenKeys(_ csv: String) -> Set<String> {
        Set(
            csv
                .split(separator: ",")
                .map { String($0) }
                .filter { !$0.isEmpty }
        )
    }
}
