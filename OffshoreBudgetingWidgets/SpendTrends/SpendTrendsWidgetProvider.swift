//
//  SpendTrendsWidgetProvider.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import WidgetKit

struct SpendTrendsWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = SpendTrendsWidgetConfigurationIntent
    typealias Entry = SpendTrendsWidgetEntry

    func placeholder(in context: Context) -> SpendTrendsWidgetEntry {
        SpendTrendsWidgetEntry(
            date: .now,
            periodToken: "1M",
            cardID: nil,
            snapshot: .placeholder
        )
    }

    func snapshot(for configuration: SpendTrendsWidgetConfigurationIntent, in context: Context) async -> SpendTrendsWidgetEntry {
        let resolved = loadSnapshot(configuration: configuration)

        return SpendTrendsWidgetEntry(
            date: .now,
            periodToken: configuration.resolvedPeriodToken,
            cardID: resolved.cardID,
            snapshot: resolved.snapshot ?? .placeholder
        )
    }

    func timeline(for configuration: SpendTrendsWidgetConfigurationIntent, in context: Context) async -> Timeline<SpendTrendsWidgetEntry> {
        let resolved = loadSnapshot(configuration: configuration)

        let entry = SpendTrendsWidgetEntry(
            date: .now,
            periodToken: configuration.resolvedPeriodToken,
            cardID: resolved.cardID,
            snapshot: resolved.snapshot
        )

        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 3, to: .now)
            ?? .now.addingTimeInterval(3 * 3600)

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadSnapshot(configuration: SpendTrendsWidgetConfigurationIntent) -> (cardID: String?, snapshot: SpendTrendsWidgetSnapshot?) {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = SpendTrendsWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return (nil, nil)
        }

        let cardID = configuration.resolvedCardID
        let snapshot = SpendTrendsWidgetSnapshotStore.load(
            workspaceID: workspaceID,
            cardID: cardID,
            periodToken: periodToken
        )

        return (cardID, snapshot)
    }
}
