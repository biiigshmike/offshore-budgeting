//
//  CardWidgetProvider.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import WidgetKit

struct CardWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = CardWidgetConfigurationIntent
    typealias Entry = CardWidgetEntry

    func placeholder(in context: Context) -> CardWidgetEntry {
        CardWidgetEntry(
            date: .now,
            periodToken: "1M",
            cardID: nil,
            snapshot: .placeholder
        )
    }

    func snapshot(for configuration: CardWidgetConfigurationIntent, in context: Context) async -> CardWidgetEntry {
        let resolved = loadSnapshot(configuration: configuration)

        return CardWidgetEntry(
            date: .now,
            periodToken: configuration.resolvedPeriodToken,
            cardID: resolved.cardID,
            snapshot: resolved.snapshot ?? .placeholder
        )
    }

    func timeline(for configuration: CardWidgetConfigurationIntent, in context: Context) async -> Timeline<CardWidgetEntry> {
        let resolved = loadSnapshot(configuration: configuration)

        let entry = CardWidgetEntry(
            date: .now,
            periodToken: configuration.resolvedPeriodToken,
            cardID: resolved.cardID,
            snapshot: resolved.snapshot
        )

        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 3, to: .now)
            ?? .now.addingTimeInterval(3 * 3600)

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadSnapshot(configuration: CardWidgetConfigurationIntent) -> (cardID: String?, snapshot: CardWidgetSnapshot?) {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = CardWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return (nil, nil)
        }

        // Resolve card selection:
        // 1) config card
        // 2) first cached card option in this workspace (keeps the widget usable without forcing selection)
        let cardID = configuration.resolvedCardID ?? CardWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceID).first?.id
        guard let cardID, !cardID.isEmpty else {
            return (nil, nil)
        }

        let snap = CardWidgetSnapshotStore.load(
            workspaceID: workspaceID,
            cardID: cardID,
            periodToken: periodToken
        )

        return (cardID, snap)
    }
}
