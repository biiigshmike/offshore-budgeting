//
//  DetailViewSnapshotCache.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/23/26.
//

import Foundation
import Observation

@MainActor
@Observable
final class DetailViewSnapshotCache {

    // MARK: - Storage

    private struct Entry {
        let value: Any
        let updatedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let maxEntries: Int = 120

    // MARK: - Access

    func snapshot<T>(for key: String, as type: T.Type = T.self) -> T? {
        entries[key]?.value as? T
    }

    func store<T>(_ snapshot: T, for key: String) {
        entries[key] = Entry(value: snapshot, updatedAt: Date())
        trimIfNeeded()
    }

    func remove(for key: String) {
        entries.removeValue(forKey: key)
    }

    func removeAll() {
        entries.removeAll()
    }

    // MARK: - Capacity

    private func trimIfNeeded() {
        guard entries.count > maxEntries else { return }

        let overflow = entries.count - maxEntries
        let keysToRemove = entries
            .sorted { $0.value.updatedAt < $1.value.updatedAt }
            .prefix(overflow)
            .map(\.key)

        for key in keysToRemove {
            entries.removeValue(forKey: key)
        }
    }
}
