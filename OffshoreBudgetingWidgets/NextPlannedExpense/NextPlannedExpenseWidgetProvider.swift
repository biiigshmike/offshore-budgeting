//
//  NextPlannedExpenseWidgetProvider.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import WidgetKit

struct NextPlannedExpenseWidgetProvider: AppIntentTimelineProvider {
    typealias Intent = NextPlannedExpenseWidgetConfigurationIntent
    typealias Entry = NextPlannedExpenseWidgetEntry

    func placeholder(in context: Context) -> NextPlannedExpenseWidgetEntry {
        NextPlannedExpenseWidgetEntry(
            date: .now,
            periodToken: "1M",
            cardID: nil,
            snapshot: .placeholder
        )
    }

    func snapshot(for configuration: NextPlannedExpenseWidgetConfigurationIntent, in context: Context) async -> NextPlannedExpenseWidgetEntry {
        let resolved = loadSnapshot(configuration: configuration)

        return NextPlannedExpenseWidgetEntry(
            date: .now,
            periodToken: configuration.resolvedPeriodToken,
            cardID: resolved.cardID,
            snapshot: resolved.snapshot ?? .placeholder
        )
    }

    func timeline(for configuration: NextPlannedExpenseWidgetConfigurationIntent, in context: Context) async -> Timeline<NextPlannedExpenseWidgetEntry> {
        let now = Date()
        let resolved = loadSnapshot(configuration: configuration, asOf: now)

        var entries = [
            NextPlannedExpenseWidgetEntry(
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
                NextPlannedExpenseWidgetEntry(
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
        configuration: NextPlannedExpenseWidgetConfigurationIntent,
        asOf date: Date? = nil
    ) -> (cardID: String?, snapshot: NextPlannedExpenseWidgetSnapshot?) {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = NextPlannedExpenseWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return (nil, nil)
        }

        let options = NextPlannedExpenseWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceID)
        let cardID = configuration.resolvedCardID
        if configuration.card?.isAllCards == true {
            return loadAllCardsSnapshot(workspaceID: workspaceID, periodToken: periodToken, date: date)
        }

        if let cardID,
           !options.isEmpty,
           !options.contains(where: { $0.id == cardID }) {
            return (nil, nil)
        }

        let snapshot: NextPlannedExpenseWidgetSnapshot?
        if let date {
            snapshot = NextPlannedExpenseWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID,
                cardID: cardID,
                periodToken: periodToken,
                asOf: date
            )
        } else {
            snapshot = NextPlannedExpenseWidgetSnapshotStore.load(
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
    ) -> (cardID: String?, snapshot: NextPlannedExpenseWidgetSnapshot?) {
        let snapshot: NextPlannedExpenseWidgetSnapshot?
        if let date {
            snapshot = NextPlannedExpenseWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID,
                cardID: nil,
                periodToken: periodToken,
                asOf: date
            )
        } else {
            snapshot = NextPlannedExpenseWidgetSnapshotStore.load(
                workspaceID: workspaceID,
                cardID: nil,
                periodToken: periodToken
            )
        }

        return (nil, snapshot)
    }

    private func loadFutureTimelineSnapshots(
        configuration: NextPlannedExpenseWidgetConfigurationIntent,
        cardID: String?,
        after date: Date
    ) -> [(date: Date, snapshot: NextPlannedExpenseWidgetSnapshot)] {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = NextPlannedExpenseWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return []
        }

        return NextPlannedExpenseWidgetSnapshotStore.loadTimelineSnapshots(
            workspaceID: workspaceID,
            cardID: cardID,
            periodToken: periodToken
        )
        .filter { WidgetTimelineSchedule.isFutureEntryDate($0.date, after: date) }
        .prefix(16)
        .map { $0 }
    }
}
