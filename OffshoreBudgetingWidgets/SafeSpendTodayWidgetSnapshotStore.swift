import Foundation
import WidgetKit

enum SafeSpendTodayWidgetSnapshotStore {
    private static let widgetKind = "SafeSpendTodayWidget"
    nonisolated static let appGroupID = "group.com.mb.offshore-budgeting"

    nonisolated private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    nonisolated static let selectedWorkspaceKey = "selectedWorkspaceID"

    nonisolated private static func snapshotKey(workspaceID: String) -> String {
        "safeSpendTodayWidget.snapshot.\(workspaceID)"
    }

    nonisolated static func save(snapshot: SafeSpendTodayWidgetSnapshot, workspaceID: String) {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey(workspaceID: workspaceID))
    }

    nonisolated static func load(workspaceID: String) -> SafeSpendTodayWidgetSnapshot? {
        guard
            let defaults,
            let data = defaults.data(forKey: snapshotKey(workspaceID: workspaceID))
        else {
            return nil
        }

        return try? JSONDecoder().decode(SafeSpendTodayWidgetSnapshot.self, from: data)
    }

    nonisolated static func selectedWorkspaceID() -> String? {
        defaults?.string(forKey: selectedWorkspaceKey)
    }

    nonisolated static func setSelectedWorkspaceID(_ id: String) {
        defaults?.set(id, forKey: selectedWorkspaceKey)
    }

    nonisolated static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
