//
//  CardWidgetSnapshotStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import Foundation
import WidgetKit

enum CardWidgetSnapshotStore {
    nonisolated static let appGroupID = "group.com.mb.offshore-budgeting"

    nonisolated private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    nonisolated static let selectedWorkspaceKey = "selectedWorkspaceID"

    nonisolated private static func snapshotKey(workspaceID: String, cardID: String, periodToken: String) -> String {
        "cardWidget.snapshot.\(workspaceID).\(cardID).\(periodToken)"
    }

    nonisolated private static func cardListKey(workspaceID: String) -> String {
        "cardWidget.cards.\(workspaceID)"
    }

    // MARK: - Workspace

    nonisolated static func selectedWorkspaceID() -> String? {
        defaults?.string(forKey: selectedWorkspaceKey)
    }

    nonisolated static func setSelectedWorkspaceID(_ id: String) {
        defaults?.set(id, forKey: selectedWorkspaceKey)
    }

    // MARK: - Snapshots

    nonisolated static func save(snapshot: CardWidgetSnapshot, workspaceID: String, cardID: String, periodToken: String) {
        guard let defaults else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: snapshotKey(workspaceID: workspaceID, cardID: cardID, periodToken: periodToken))
        } catch {
            // keep silent
        }
    }

    nonisolated static func load(workspaceID: String, cardID: String, periodToken: String) -> CardWidgetSnapshot? {
        guard
            let defaults,
            let data = defaults.data(forKey: snapshotKey(workspaceID: workspaceID, cardID: cardID, periodToken: periodToken))
        else { return nil }

        return try? JSONDecoder().decode(CardWidgetSnapshot.self, from: data)
    }

    nonisolated static func saveTimelineSnapshot(
        snapshot: CardWidgetSnapshot,
        workspaceID: String,
        cardID: String,
        periodToken: String,
        date: Date
    ) {
        WidgetTimelineSnapshotStorage.saveTimelineSnapshot(
            defaults: defaults,
            baseKey: snapshotKey(workspaceID: workspaceID, cardID: cardID, periodToken: periodToken),
            date: date,
            snapshot: snapshot
        )
    }

    nonisolated static func replaceTimelineSnapshots(
        _ snapshots: [(date: Date, snapshot: CardWidgetSnapshot)],
        workspaceID: String,
        cardID: String,
        periodToken: String
    ) {
        WidgetTimelineSnapshotStorage.replaceTimelineSnapshots(
            defaults: defaults,
            baseKey: snapshotKey(workspaceID: workspaceID, cardID: cardID, periodToken: periodToken),
            snapshots: snapshots
        )
    }

    nonisolated static func loadTimelineSnapshots(
        workspaceID: String,
        cardID: String,
        periodToken: String
    ) -> [(date: Date, snapshot: CardWidgetSnapshot)] {
        WidgetTimelineSnapshotStorage.loadTimelineSnapshots(
            defaults: defaults,
            baseKey: snapshotKey(workspaceID: workspaceID, cardID: cardID, periodToken: periodToken),
            as: CardWidgetSnapshot.self
        )
    }

    nonisolated static func loadBestSnapshot(
        workspaceID: String,
        cardID: String,
        periodToken: String,
        asOf date: Date
    ) -> CardWidgetSnapshot? {
        WidgetTimelineSnapshotStorage.loadBestTimelineSnapshot(
            defaults: defaults,
            baseKey: snapshotKey(workspaceID: workspaceID, cardID: cardID, periodToken: periodToken),
            asOf: date,
            as: CardWidgetSnapshot.self
        ) ?? load(workspaceID: workspaceID, cardID: cardID, periodToken: periodToken)
    }

    nonisolated static func pruneSnapshots(workspaceID: String, validCardIDs: Set<String>, periodTokens: [String]) {
        guard let defaults else { return }

        let prefix = "cardWidget.snapshot.\(workspaceID)."
        let periodSuffixes = periodTokens.map { ".\($0)" }

        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            let suffix = String(key.dropFirst(prefix.count))
            guard let periodSuffix = periodSuffixes.first(where: { suffix.hasSuffix($0) }) else { continue }

            let cardID = String(suffix.dropLast(periodSuffix.count))
            if !validCardIDs.contains(cardID) {
                defaults.removeObject(forKey: key)
            }
        }
    }

    // MARK: - Card Options (for AppEntity picker)

    struct CardOption: Codable, Hashable {
        let id: String
        let name: String
        let themeToken: String
        let effectToken: String
    }

    nonisolated static func saveCardOptions(_ options: [CardOption], workspaceID: String) {
        guard let defaults else { return }
        do {
            let data = try JSONEncoder().encode(options)
            defaults.set(data, forKey: cardListKey(workspaceID: workspaceID))
        } catch {
            // keep silent
        }
    }

    nonisolated static func loadCardOptions(workspaceID: String) -> [CardOption] {
        guard
            let defaults,
            let data = defaults.data(forKey: cardListKey(workspaceID: workspaceID)),
            let decoded = try? JSONDecoder().decode([CardOption].self, from: data)
        else { return [] }

        return decoded
    }

    // MARK: - Timeline reload

    nonisolated static func reloadCardWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "CardWidget")
    }
}
