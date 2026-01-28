//
//  CardWidgetSnapshotStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import Foundation
import WidgetKit

enum CardWidgetSnapshotStore {
    static let appGroupID = "group.com.mb.offshore-budgeting"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static let selectedWorkspaceKey = "selectedWorkspaceID"

    private static func snapshotKey(workspaceID: String, cardID: String, periodToken: String) -> String {
        "cardWidget.snapshot.\(workspaceID).\(cardID).\(periodToken)"
    }

    private static func cardListKey(workspaceID: String) -> String {
        "cardWidget.cards.\(workspaceID)"
    }

    // MARK: - Workspace

    static func selectedWorkspaceID() -> String? {
        defaults?.string(forKey: selectedWorkspaceKey)
    }

    static func setSelectedWorkspaceID(_ id: String) {
        defaults?.set(id, forKey: selectedWorkspaceKey)
    }

    // MARK: - Snapshots

    static func save(snapshot: CardWidgetSnapshot, workspaceID: String, cardID: String, periodToken: String) {
        guard let defaults else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: snapshotKey(workspaceID: workspaceID, cardID: cardID, periodToken: periodToken))
        } catch {
            // keep silent
        }
    }

    static func load(workspaceID: String, cardID: String, periodToken: String) -> CardWidgetSnapshot? {
        guard
            let defaults,
            let data = defaults.data(forKey: snapshotKey(workspaceID: workspaceID, cardID: cardID, periodToken: periodToken))
        else { return nil }

        return try? JSONDecoder().decode(CardWidgetSnapshot.self, from: data)
    }

    // MARK: - Card Options (for AppEntity picker)

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
            // keep silent
        }
    }

    static func loadCardOptions(workspaceID: String) -> [CardOption] {
        guard
            let defaults,
            let data = defaults.data(forKey: cardListKey(workspaceID: workspaceID)),
            let decoded = try? JSONDecoder().decode([CardOption].self, from: data)
        else { return [] }

        return decoded
    }

    // MARK: - Timeline reload

    static func reloadCardWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "CardWidget")
    }
}
