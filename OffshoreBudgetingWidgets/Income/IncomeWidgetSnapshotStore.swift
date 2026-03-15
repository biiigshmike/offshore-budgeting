//
//  IncomeWidgetSnapshotStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import Foundation
import WidgetKit

enum IncomeWidgetSnapshotStore {
    
    nonisolated static let appGroupID = "group.com.mb.offshore-budgeting"

    nonisolated private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    // Keep the selected workspace ID in the same suite so the widget knows what to read.
    nonisolated static let selectedWorkspaceKey = "selectedWorkspaceID"

    nonisolated private static func key(workspaceID: String, periodToken: String) -> String {
        "incomeWidget.snapshot.\(workspaceID).\(periodToken)"
    }

    nonisolated static func save(snapshot: IncomeWidgetSnapshot, workspaceID: String, periodToken: String) {
        guard let defaults else { return }
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: key(workspaceID: workspaceID, periodToken: periodToken))
        } catch {
            // Keep silent in production
        }
    }

    nonisolated static func load(workspaceID: String, periodToken: String) -> IncomeWidgetSnapshot? {
        guard
            let defaults,
            let data = defaults.data(forKey: key(workspaceID: workspaceID, periodToken: periodToken))
        else { return nil }

        return try? JSONDecoder().decode(IncomeWidgetSnapshot.self, from: data)
    }

    nonisolated static func selectedWorkspaceID() -> String? {
        defaults?.string(forKey: selectedWorkspaceKey)
    }

    nonisolated static func setSelectedWorkspaceID(_ id: String) {
        defaults?.set(id, forKey: selectedWorkspaceKey)
    }

    nonisolated static func reloadIncomeWidgetTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: "IncomeWidget")
    }
}
