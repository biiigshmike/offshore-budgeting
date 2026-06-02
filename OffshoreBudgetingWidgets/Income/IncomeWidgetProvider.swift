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
        let now = Date()
        let snap = loadSnapshot(configuration: configuration, asOf: now)

        var entries = [
            IncomeWidgetEntry(
                date: now,
                periodToken: configuration.resolvedPeriodToken,
                snapshot: snap
            )
        ]
        entries.append(
            contentsOf: loadFutureTimelineSnapshots(configuration: configuration, after: now)
                .map {
                    IncomeWidgetEntry(
                        date: $0.date,
                        periodToken: configuration.resolvedPeriodToken,
                        snapshot: $0.snapshot
                    )
                }
        )

        let policy: TimelineReloadPolicy = entries.count > 1
            ? .atEnd
            : .after(WidgetTimelineSchedule.fallbackRefreshDate(afterRangeEnd: snap?.rangeEnd, now: now))

        return Timeline(entries: entries, policy: policy)
    }

    private func loadSnapshot(
        configuration: IncomeWidgetConfigurationIntent,
        asOf date: Date? = nil
    ) -> IncomeWidgetSnapshot? {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = IncomeWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return nil
        }

        if let date {
            return IncomeWidgetSnapshotStore.loadBestSnapshot(
                workspaceID: workspaceID,
                periodToken: periodToken,
                asOf: date
            )
        }

        return IncomeWidgetSnapshotStore.load(
            workspaceID: workspaceID,
            periodToken: periodToken
        )
    }

    private func loadFutureTimelineSnapshots(
        configuration: IncomeWidgetConfigurationIntent,
        after date: Date
    ) -> [(date: Date, snapshot: IncomeWidgetSnapshot)] {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = IncomeWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return []
        }

        return IncomeWidgetSnapshotStore.loadTimelineSnapshots(
            workspaceID: workspaceID,
            periodToken: periodToken
        )
        .filter { WidgetTimelineSchedule.isFutureEntryDate($0.date, after: date) }
        .prefix(16)
        .map { $0 }
    }
}
