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
        let now = Date()
        let resolved = loadSnapshot(configuration: configuration, asOf: now)

        var entries = [
            SpendTrendsWidgetEntry(
                date: now,
                periodToken: configuration.resolvedPeriodToken,
                cardID: resolved.cardID,
                snapshot: resolved.snapshot
            )
        ]
        entries.append(
            contentsOf: loadFutureTimelineSnapshots(
                configuration: configuration,
                cardID: resolved.cardID,
                after: now
            ).map {
                SpendTrendsWidgetEntry(
                    date: $0.date,
                    periodToken: configuration.resolvedPeriodToken,
                    cardID: resolved.cardID,
                    snapshot: $0.snapshot
                )
            }
        )

        let policy: TimelineReloadPolicy = entries.count > 1
            ? .atEnd
            : .after(WidgetTimelineSchedule.fallbackRefreshDate(afterRangeEnd: resolved.snapshot?.rangeEnd, now: now))

        return Timeline(entries: entries, policy: policy)
    }

    private func loadSnapshot(
        configuration: SpendTrendsWidgetConfigurationIntent,
        asOf date: Date? = nil
    ) -> (cardID: String?, snapshot: SpendTrendsWidgetSnapshot?) {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = SpendTrendsWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return (nil, nil)
        }

        let options = SpendTrendsWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceID)
        let cardID = configuration.resolvedCardID
        if configuration.card?.isAllCards == true {
            return loadAllCardsSnapshot(workspaceID: workspaceID, periodToken: periodToken, date: date)
        }

        if let cardID,
           !options.isEmpty,
           !options.contains(where: { $0.id == cardID }) {
            return (nil, nil)
        }

        let snapshot: SpendTrendsWidgetSnapshot?
        if let date {
            snapshot = SpendTrendsWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID,
                cardID: cardID,
                periodToken: periodToken,
                asOf: date
            )
        } else {
            snapshot = SpendTrendsWidgetSnapshotStore.load(
                workspaceID: workspaceID,
                cardID: cardID,
                periodToken: periodToken
            )
        }

        return (cardID, snapshot)
    }

    private func loadAllCardsSnapshot(
        workspaceID: String,
        periodToken: String,
        date: Date?
    ) -> (cardID: String?, snapshot: SpendTrendsWidgetSnapshot?) {
        let snapshot: SpendTrendsWidgetSnapshot?
        if let date {
            snapshot = SpendTrendsWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID,
                cardID: nil,
                periodToken: periodToken,
                asOf: date
            )
        } else {
            snapshot = SpendTrendsWidgetSnapshotStore.load(
                workspaceID: workspaceID,
                cardID: nil,
                periodToken: periodToken
            )
        }

        return (nil, snapshot)
    }

    private func loadFutureTimelineSnapshots(
        configuration: SpendTrendsWidgetConfigurationIntent,
        cardID: String?,
        after date: Date
    ) -> [(date: Date, snapshot: SpendTrendsWidgetSnapshot)] {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = SpendTrendsWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return []
        }

        return SpendTrendsWidgetSnapshotStore.loadTimelineSnapshots(
            workspaceID: workspaceID,
            cardID: cardID,
            periodToken: periodToken
        )
        .filter { WidgetTimelineSchedule.isFutureEntryDate($0.date, after: date) }
        .prefix(16)
        .map { $0 }
    }
}
