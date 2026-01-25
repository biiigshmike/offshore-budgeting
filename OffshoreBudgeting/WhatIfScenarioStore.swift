//
//  WhatIfScenarioStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import Foundation

struct WhatIfScenarioStore {

    // MARK: - Config

    private let workspaceID: UUID
    private let calendar: Calendar
    private let maxSavedRanges: Int

    init(workspaceID: UUID, calendar: Calendar = .current, maxSavedRanges: Int = 24) {
        self.workspaceID = workspaceID
        self.calendar = calendar
        self.maxSavedRanges = max(1, maxSavedRanges)
    }

    // MARK: - Keys

    private var indexKey: String {
        "home_whatIfScenarioIndex_\(workspaceID.uuidString)"
    }

    private func payloadKey(rangeKey: String) -> String {
        "home_whatIfScenario_\(workspaceID.uuidString)_\(rangeKey)"
    }

    // MARK: - Public API

    func load(startDate: Date, endDate: Date) -> [UUID: Double]? {
        let rk = rangeKey(startDate: startDate, endDate: endDate)
        bumpLastAccessed(for: rk)

        guard let data = UserDefaults.standard.data(forKey: payloadKey(rangeKey: rk)) else { return nil }
        let decoded = try? JSONDecoder().decode(ScenarioPayload.self, from: data)
        return decoded?.scenarioByCategoryID
    }

    func save(_ scenarioByCategoryID: [UUID: Double], startDate: Date, endDate: Date) {
        let rk = rangeKey(startDate: startDate, endDate: endDate)

        let payload = ScenarioPayload(
            rangeKey: rk,
            scenarioByCategoryID: scenarioByCategoryID
        )

        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        UserDefaults.standard.set(data, forKey: payloadKey(rangeKey: rk))

        upsertIndexEntry(for: rk)
        pruneIfNeeded()
    }

    func clear(startDate: Date, endDate: Date) {
        let rk = rangeKey(startDate: startDate, endDate: endDate)
        UserDefaults.standard.removeObject(forKey: payloadKey(rangeKey: rk))
        removeIndexEntry(for: rk)
    }

    // MARK: - Range Key (day-only)

    func rangeKey(startDate: Date, endDate: Date) -> String {
        let s = calendar.startOfDay(for: startDate)
        let e = calendar.startOfDay(for: endDate)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyyMMdd"

        return "\(formatter.string(from: s))_\(formatter.string(from: e))"
    }

    // MARK: - Index Management

    private func loadIndex() -> [ScenarioIndexEntry] {
        guard let data = UserDefaults.standard.data(forKey: indexKey) else { return [] }
        return (try? JSONDecoder().decode([ScenarioIndexEntry].self, from: data)) ?? []
    }

    private func saveIndex(_ entries: [ScenarioIndexEntry]) {
        let data = (try? JSONEncoder().encode(entries)) ?? Data()
        UserDefaults.standard.set(data, forKey: indexKey)
    }

    private func upsertIndexEntry(for rangeKey: String) {
        var entries = loadIndex()
        let now = Date().timeIntervalSince1970

        if let idx = entries.firstIndex(where: { $0.rangeKey == rangeKey }) {
            entries[idx].lastAccessed = now
        } else {
            entries.append(ScenarioIndexEntry(rangeKey: rangeKey, lastAccessed: now))
        }

        saveIndex(entries)
    }

    private func bumpLastAccessed(for rangeKey: String) {
        var entries = loadIndex()
        guard let idx = entries.firstIndex(where: { $0.rangeKey == rangeKey }) else { return }
        entries[idx].lastAccessed = Date().timeIntervalSince1970
        saveIndex(entries)
    }

    private func removeIndexEntry(for rangeKey: String) {
        var entries = loadIndex()
        entries.removeAll { $0.rangeKey == rangeKey }
        saveIndex(entries)
    }

    private func pruneIfNeeded() {
        var entries = loadIndex()
        guard entries.count > maxSavedRanges else { return }

        entries.sort { $0.lastAccessed > $1.lastAccessed } // newest first
        let keep = Array(entries.prefix(maxSavedRanges))
        let drop = Array(entries.dropFirst(maxSavedRanges))

        // Delete payloads for dropped ranges
        for entry in drop {
            UserDefaults.standard.removeObject(forKey: payloadKey(rangeKey: entry.rangeKey))
        }

        saveIndex(keep)
    }
}

// MARK: - Codable Models

private struct ScenarioPayload: Codable {
    let rangeKey: String
    let scenarioByCategoryID: [UUID: Double]
}

private struct ScenarioIndexEntry: Codable, Equatable {
    let rangeKey: String
    var lastAccessed: Double
}
