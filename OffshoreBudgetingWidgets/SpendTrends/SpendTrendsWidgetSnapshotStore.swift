//
//  SpendTrendsWidgetSnapshotStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import Foundation
import WidgetKit

enum SpendTrendsWidgetSnapshotStore {
    static let appGroupID = "group.com.mb.offshore-budgeting"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static let selectedWorkspaceKey = "selectedWorkspaceID"

    private static func snapshotKey(workspaceID: String, cardScope: String, periodToken: String) -> String {
        "spendTrendsWidget.snapshot.\(workspaceID).\(cardScope).\(periodToken)"
    }

    private static func cardListKey(workspaceID: String) -> String {
        "spendTrendsWidget.cards.\(workspaceID)"
    }

    static func selectedWorkspaceID() -> String? {
        defaults?.string(forKey: selectedWorkspaceKey)
    }

    static func setSelectedWorkspaceID(_ id: String) {
        defaults?.set(id, forKey: selectedWorkspaceKey)
    }

    static func save(snapshot: SpendTrendsWidgetSnapshot, workspaceID: String, cardID: String?, periodToken: String) {
        guard let defaults else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: snapshotKey(workspaceID: workspaceID, cardScope: cardID ?? "ALL", periodToken: periodToken))
        } catch {
            // Keep silent in production.
        }
    }

    static func load(workspaceID: String, cardID: String?, periodToken: String) -> SpendTrendsWidgetSnapshot? {
        guard
            let defaults,
            let data = defaults.data(forKey: snapshotKey(workspaceID: workspaceID, cardScope: cardID ?? "ALL", periodToken: periodToken))
        else {
            return nil
        }

        return try? JSONDecoder().decode(SpendTrendsWidgetSnapshot.self, from: data)
    }

    struct CardOption: Codable, Hashable {
        let id: String
        let name: String
        let themeToken: String
        let effectToken: String
    }

    static func saveCardOptions(_ options: [CardOption], workspaceID: String) {
        guard let defaults else { return }

        do {
            let data = try JSONEncoder().encode(options)
            defaults.set(data, forKey: cardListKey(workspaceID: workspaceID))
        } catch {
            // Keep silent in production.
        }
    }

    static func loadCardOptions(workspaceID: String) -> [CardOption] {
        guard
            let defaults,
            let data = defaults.data(forKey: cardListKey(workspaceID: workspaceID)),
            let decoded = try? JSONDecoder().decode([CardOption].self, from: data)
        else {
            return []
        }

        return decoded
    }

    static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "SpendTrendsWidget")
    }
}
