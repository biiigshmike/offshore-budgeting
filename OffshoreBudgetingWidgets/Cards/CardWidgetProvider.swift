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
        let now = Date()
        let resolved = loadSnapshot(configuration: configuration, asOf: now)

        var entries = [
            CardWidgetEntry(
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
                CardWidgetEntry(
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
        configuration: CardWidgetConfigurationIntent,
        asOf date: Date? = nil
    ) -> (cardID: String?, snapshot: CardWidgetSnapshot?) {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = CardWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return (nil, nil)
        }

        let options = CardWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceID)

        // Resolve card selection:
        // 1) config card
        // 2) first cached card option in this workspace (keeps the widget usable without forcing selection)
        let cardID = configuration.resolvedCardID ?? options.first?.id
        guard let cardID, !cardID.isEmpty else {
            return (nil, nil)
        }
        if configuration.resolvedCardID != nil,
           !options.isEmpty,
           !options.contains(where: { $0.id == cardID }) {
            return (nil, nil)
        }

        let snap: CardWidgetSnapshot?
        if let date {
            snap = CardWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID,
                cardID: cardID,
                periodToken: periodToken,
                asOf: date
            )
        } else {
            snap = CardWidgetSnapshotStore.load(
                workspaceID: workspaceID,
                cardID: cardID,
                periodToken: periodToken
            )
        }

        return (cardID, snap)
    }

    private func loadFutureTimelineSnapshots(
        configuration: CardWidgetConfigurationIntent,
        cardID: String?,
        after date: Date
    ) -> [(date: Date, snapshot: CardWidgetSnapshot)] {
        let periodToken = configuration.resolvedPeriodToken

        guard
            let workspaceID = CardWidgetSnapshotStore.selectedWorkspaceID(),
            !workspaceID.isEmpty,
            let cardID,
            !cardID.isEmpty
        else {
            return []
        }

        return CardWidgetSnapshotStore.loadTimelineSnapshots(
            workspaceID: workspaceID,
            cardID: cardID,
            periodToken: periodToken
        )
        .filter { WidgetTimelineSchedule.isFutureEntryDate($0.date, after: date) }
        .prefix(16)
        .map { $0 }
    }
}
