//
//  WidgetTimelineSnapshotStorage.swift
//  OffshoreBudgeting
//
//  Created by Codex on 6/2/26.
//

import Foundation

nonisolated struct WidgetTimelineSnapshotRecord<Snapshot: Codable>: Codable {
    let date: Date
    let snapshot: Snapshot
}

nonisolated enum WidgetTimelineSchedule {
    static let minimumEntrySpacing: TimeInterval = 5 * 60
    private static let defaultFallbackInterval: TimeInterval = 3 * 60 * 60

    static func nextEntryDate(
        afterRangeEnd rangeEnd: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        let nextInstant = calendar.date(byAdding: .second, value: 1, to: rangeEnd)
            ?? rangeEnd.addingTimeInterval(1)
        let nextRangeStart = calendar.startOfDay(for: nextInstant)
        let minimumDate = now.addingTimeInterval(minimumEntrySpacing)
        return nextRangeStart < minimumDate ? minimumDate : nextRangeStart
    }

    static func dailyEntryDates(
        after now: Date,
        count: Int,
        calendar: Calendar = .current
    ) -> [Date] {
        guard count > 0 else { return [] }

        let todayStart = calendar.startOfDay(for: now)
        let minimumDate = now.addingTimeInterval(minimumEntrySpacing)

        return (1...count).compactMap { offset in
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: todayStart) else {
                return nil
            }
            return dayStart < minimumDate ? minimumDate : dayStart
        }
    }

    static func fallbackRefreshDate(
        afterRangeEnd rangeEnd: Date?,
        now: Date,
        calendar: Calendar = .current
    ) -> Date {
        guard let rangeEnd else {
            return now.addingTimeInterval(defaultFallbackInterval)
        }

        return nextEntryDate(afterRangeEnd: rangeEnd, now: now, calendar: calendar)
    }

    static func isFutureEntryDate(_ date: Date, after now: Date) -> Bool {
        date.timeIntervalSince(now) >= minimumEntrySpacing
    }
}

nonisolated enum WidgetTimelineSnapshotStorage {
    private static func manifestKey(baseKey: String) -> String {
        "\(baseKey).timeline.manifest"
    }

    private static func timelineKey(baseKey: String, dateToken: String) -> String {
        "\(baseKey).timeline.\(dateToken)"
    }

    private static func dateToken(for date: Date) -> String {
        String(Int64(date.timeIntervalSinceReferenceDate.rounded(.down)))
    }

    static func saveTimelineSnapshot<Snapshot: Codable>(
        defaults: UserDefaults?,
        baseKey: String,
        date: Date,
        snapshot: Snapshot
    ) {
        guard let defaults else { return }

        let token = dateToken(for: date)
        var tokens = defaults.stringArray(forKey: manifestKey(baseKey: baseKey)) ?? []
        if !tokens.contains(token) {
            tokens.append(token)
            tokens.sort()
            defaults.set(tokens, forKey: manifestKey(baseKey: baseKey))
        }

        let record = WidgetTimelineSnapshotRecord(date: date, snapshot: snapshot)
        guard let data = try? JSONEncoder().encode(record) else { return }
        defaults.set(data, forKey: timelineKey(baseKey: baseKey, dateToken: token))
    }

    static func replaceTimelineSnapshots<Snapshot: Codable>(
        defaults: UserDefaults?,
        baseKey: String,
        snapshots: [(date: Date, snapshot: Snapshot)]
    ) {
        guard let defaults else { return }

        let oldTokens = defaults.stringArray(forKey: manifestKey(baseKey: baseKey)) ?? []
        for token in oldTokens {
            defaults.removeObject(forKey: timelineKey(baseKey: baseKey, dateToken: token))
        }

        defaults.removeObject(forKey: manifestKey(baseKey: baseKey))

        for item in snapshots {
            saveTimelineSnapshot(
                defaults: defaults,
                baseKey: baseKey,
                date: item.date,
                snapshot: item.snapshot
            )
        }
    }

    static func loadTimelineSnapshots<Snapshot: Codable>(
        defaults: UserDefaults?,
        baseKey: String,
        as type: Snapshot.Type = Snapshot.self
    ) -> [(date: Date, snapshot: Snapshot)] {
        guard let defaults else { return [] }

        let tokens = defaults.stringArray(forKey: manifestKey(baseKey: baseKey)) ?? []
        return tokens.compactMap { token in
            guard
                let data = defaults.data(forKey: timelineKey(baseKey: baseKey, dateToken: token)),
                let record = try? JSONDecoder().decode(WidgetTimelineSnapshotRecord<Snapshot>.self, from: data)
            else {
                return nil
            }

            return (record.date, record.snapshot)
        }
        .sorted { $0.date < $1.date }
    }

    static func loadBestTimelineSnapshot<Snapshot: Codable>(
        defaults: UserDefaults?,
        baseKey: String,
        asOf date: Date,
        as type: Snapshot.Type = Snapshot.self
    ) -> Snapshot? {
        loadTimelineSnapshots(defaults: defaults, baseKey: baseKey, as: type)
            .filter { $0.date <= date }
            .last?
            .snapshot
    }
}
