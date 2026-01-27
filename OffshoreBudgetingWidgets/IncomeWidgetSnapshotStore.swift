//
//  IncomeWidgetSnapshotStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import Foundation
import WidgetKit

enum IncomeWidgetSnapshotStore {
    // IMPORTANT:
    // 1) Add App Group capability to BOTH targets.
    // 2) Replace this with your real group identifier.
    static let appGroupID = "group.com.michaelbrown.offshorebudgeting"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // Keep the selected workspace ID in the same suite so the widget knows what to read.
    static let selectedWorkspaceKey = "selectedWorkspaceID"

    private static func key(workspaceID: String, periodToken: String) -> String {
        "incomeWidget.snapshot.\(workspaceID).\(periodToken)"
    }

    static func save(snapshot: IncomeWidgetSnapshot, workspaceID: String, periodToken: String) {
        guard let defaults else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: key(workspaceID: workspaceID, periodToken: periodToken))
        } catch {
            // Keep silent in production. If you want, you can add an os_log here.
        }
    }

    static func load(workspaceID: String, periodToken: String) -> IncomeWidgetSnapshot? {
        guard
            let defaults,
            let data = defaults.data(forKey: key(workspaceID: workspaceID, periodToken: periodToken))
        else { return nil }

        return try? JSONDecoder().decode(IncomeWidgetSnapshot.self, from: data)
    }

    static func selectedWorkspaceID() -> String? {
        defaults?.string(forKey: selectedWorkspaceKey)
    }

    static func setSelectedWorkspaceID(_ id: String) {
        defaults?.set(id, forKey: selectedWorkspaceKey)
    }

    static func reloadIncomeWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "IncomeWidget")
    }
}
