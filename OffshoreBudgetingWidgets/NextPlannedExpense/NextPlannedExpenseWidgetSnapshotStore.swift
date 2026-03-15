//
//  NextPlannedExpenseWidgetSnapshotStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import Foundation
import WidgetKit

enum NextPlannedExpenseWidgetSnapshotStore {
    nonisolated static let appGroupID = "group.com.mb.offshore-budgeting"

    nonisolated private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    nonisolated static let selectedWorkspaceKey = "selectedWorkspaceID"

    nonisolated private static func snapshotKey(workspaceID: String, cardScope: String, periodToken: String) -> String {
        "nextPlannedExpenseWidget.snapshot.\(workspaceID).\(cardScope).\(periodToken)"
    }

    nonisolated private static func cardListKey(workspaceID: String) -> String {
        "nextPlannedExpenseWidget.cards.\(workspaceID)"
    }

    nonisolated static func selectedWorkspaceID() -> String? {
        defaults?.string(forKey: selectedWorkspaceKey)
    }

    nonisolated static func setSelectedWorkspaceID(_ id: String) {
        defaults?.set(id, forKey: selectedWorkspaceKey)
    }

    nonisolated static func save(snapshot: NextPlannedExpenseWidgetSnapshot, workspaceID: String, cardID: String?, periodToken: String) {
        guard let defaults else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: snapshotKey(workspaceID: workspaceID, cardScope: cardID ?? "ALL", periodToken: periodToken))
        } catch {
            // Keep silent in production.
        }
    }

    nonisolated static func load(workspaceID: String, cardID: String?, periodToken: String) -> NextPlannedExpenseWidgetSnapshot? {
        guard
            let defaults,
            let data = defaults.data(forKey: snapshotKey(workspaceID: workspaceID, cardScope: cardID ?? "ALL", periodToken: periodToken))
        else {
            return nil
        }

        return try? JSONDecoder().decode(NextPlannedExpenseWidgetSnapshot.self, from: data)
    }

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
            // Keep silent in production.
        }
    }

    nonisolated static func loadCardOptions(workspaceID: String) -> [CardOption] {
        guard
            let defaults,
            let data = defaults.data(forKey: cardListKey(workspaceID: workspaceID)),
            let decoded = try? JSONDecoder().decode([CardOption].self, from: data)
        else {
            return []
        }

        return decoded
    }

    nonisolated static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "NextPlannedExpenseWidget")
    }
}
