import Foundation
import WidgetKit

nonisolated enum LockScreenWidgetWorkspace {
    static var defaults: UserDefaults? {
        UserDefaults(suiteName: IncomeWidgetSnapshotStore.appGroupID)
    }

    static var selectedID: String? {
        defaults?.string(forKey: IncomeWidgetSnapshotStore.selectedWorkspaceKey)
    }
}

nonisolated struct NextIncomeWidgetDay: Codable {
    let date: Date
    let nextIncomeDate: Date?
}

nonisolated enum NextIncomeWidgetSnapshotStore {
    static let kind = "NextIncomeWidget"

    private static func key(for workspaceID: String) -> String {
        "nextIncomeWidget.days.\(workspaceID)"
    }

    static func save(_ days: [NextIncomeWidgetDay], workspaceID: String) {
        guard let data = try? JSONEncoder().encode(days) else { return }
        LockScreenWidgetWorkspace.defaults?.set(data, forKey: key(for: workspaceID))
    }

    static func loadSelectedDays() -> [NextIncomeWidgetDay] {
        guard let workspaceID = LockScreenWidgetWorkspace.selectedID,
              let data = LockScreenWidgetWorkspace.defaults?.data(forKey: key(for: workspaceID))
        else { return [] }
        return (try? JSONDecoder().decode([NextIncomeWidgetDay].self, from: data)) ?? []
    }

    static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
