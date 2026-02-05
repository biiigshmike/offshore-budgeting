//
//  IncomeWidgetProvider.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import WidgetKit

struct IncomeWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = IncomeWidgetConfigurationIntent
    typealias Entry = IncomeWidgetEntry

    func placeholder(in context: Context) -> IncomeWidgetEntry {
        // Placeholder should always render even if the app group has no data yet.
        IncomeWidgetEntry(
            date: .now,
            periodToken: "1M",
            snapshot: .placeholder
        )
    }

    func snapshot(for configuration: IncomeWidgetConfigurationIntent, in context: Context) async -> IncomeWidgetEntry {
        let snap = loadSnapshot(configuration: configuration)

        return IncomeWidgetEntry(
            date: .now,
            periodToken: configuration.resolvedPeriodToken,
            snapshot: snap ?? .placeholder
        )
    }

    func timeline(for configuration: IncomeWidgetConfigurationIntent, in context: Context) async -> Timeline<IncomeWidgetEntry> {
        let snap = loadSnapshot(configuration: configuration)

        let entry = IncomeWidgetEntry(
            date: .now,
            periodToken: configuration.resolvedPeriodToken,
            snapshot: snap
        )

        // Refresh a few times a day
        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 3, to: .now)
            ?? .now.addingTimeInterval(3 * 3600)

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadSnapshot(configuration: IncomeWidgetConfigurationIntent) -> IncomeWidgetSnapshot? {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = IncomeWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return nil
        }

        return IncomeWidgetSnapshotStore.load(
            workspaceID: workspaceID,
            periodToken: periodToken
        )
    }
}
