import Foundation
import WidgetKit

enum ForecastSavingsWidgetSnapshotStore {
    private static let widgetKind = "ForecastSavingsWidget"
    nonisolated static let appGroupID = "group.com.mb.offshore-budgeting"

    nonisolated private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    nonisolated static let selectedWorkspaceKey = "selectedWorkspaceID"

    nonisolated private static func snapshotKey(workspaceID: String) -> String {
        "forecastSavingsWidget.snapshot.\(workspaceID)"
    }

    nonisolated static func save(snapshot: ForecastSavingsWidgetSnapshot, workspaceID: String) {
        guard let defaults else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey(workspaceID: workspaceID))
    }

    nonisolated static func load(workspaceID: String) -> ForecastSavingsWidgetSnapshot? {
        guard
            let defaults,
            let data = defaults.data(forKey: snapshotKey(workspaceID: workspaceID))
        else {
            return nil
        }

        return try? JSONDecoder().decode(ForecastSavingsWidgetSnapshot.self, from: data)
    }

    nonisolated static func saveTimelineSnapshot(
        snapshot: ForecastSavingsWidgetSnapshot,
        workspaceID: String,
        date: Date
    ) {
        WidgetTimelineSnapshotStorage.saveTimelineSnapshot(
            defaults: defaults,
            baseKey: snapshotKey(workspaceID: workspaceID),
            date: date,
            snapshot: snapshot
        )
    }

    nonisolated static func replaceTimelineSnapshots(
        _ snapshots: [(date: Date, snapshot: ForecastSavingsWidgetSnapshot)],
        workspaceID: String
    ) {
        WidgetTimelineSnapshotStorage.replaceTimelineSnapshots(
            defaults: defaults,
            baseKey: snapshotKey(workspaceID: workspaceID),
            snapshots: snapshots
        )
    }

    nonisolated static func loadTimelineSnapshots(
        workspaceID: String
    ) -> [(date: Date, snapshot: ForecastSavingsWidgetSnapshot)] {
        WidgetTimelineSnapshotStorage.loadTimelineSnapshots(
            defaults: defaults,
            baseKey: snapshotKey(workspaceID: workspaceID),
            as: ForecastSavingsWidgetSnapshot.self
        )
    }

    nonisolated static func loadBestSnapshot(
        workspaceID: String,
        asOf date: Date
    ) -> ForecastSavingsWidgetSnapshot? {
        WidgetTimelineSnapshotStorage.loadBestTimelineSnapshot(
            defaults: defaults,
            baseKey: snapshotKey(workspaceID: workspaceID),
            asOf: date,
            as: ForecastSavingsWidgetSnapshot.self
        ) ?? load(workspaceID: workspaceID)
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
