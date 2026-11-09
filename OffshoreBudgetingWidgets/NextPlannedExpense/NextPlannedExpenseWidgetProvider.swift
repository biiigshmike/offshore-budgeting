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

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, periodToken: "1M", cardID: nil, snapshot: .placeholder)
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let now = Date()
        let source = loadSnapshots(for: configuration)
        var entry = makeEntry(for: configuration, source: source, date: now)
        if context.isPreview, entry.snapshot == nil, !entry.configurationNeedsReview {
            entry = placeholder(in: context)
        }
        return entry
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let now = Date()
        let source = loadSnapshots(for: configuration)
        let current = makeEntry(for: configuration, source: source, date: now)
        let futureDates = Set(source.series.flatMap { $0.timeline.map(\.date) })
            .filter { WidgetTimelineSchedule.isFutureEntryDate($0, after: now) }
            .sorted()
            .prefix(16)
        let entries = [current] + futureDates.map { makeEntry(for: configuration, source: source, date: $0) }
        let policy: TimelineReloadPolicy = entries.count > 1
            ? .atEnd
            : .after(WidgetTimelineSchedule.fallbackRefreshDate(afterRangeEnd: current.snapshot?.rangeEnd, now: now))
        return Timeline(entries: entries, policy: policy)
    }

    private struct SnapshotSeries {
        let current: NextPlannedExpenseWidgetSnapshot?
        let timeline: [(date: Date, snapshot: NextPlannedExpenseWidgetSnapshot)]

        func snapshot(asOf date: Date) -> NextPlannedExpenseWidgetSnapshot? {
            timeline.last { $0.date <= date }?.snapshot ?? current
        }
    }

    private struct SnapshotSource {
        var cardIDs: [String] = []
        var series: [SnapshotSeries] = []
        var configurationNeedsReview = false
    }

    private func loadSnapshots(for configuration: Intent) -> SnapshotSource {
        guard let workspaceID = NextPlannedExpenseWidgetSnapshotStore.selectedWorkspaceID(),
              !workspaceID.isEmpty else {
            return SnapshotSource(configurationNeedsReview: configuration.requestedCardIDs != nil)
        }

        if let requestedIDs = configuration.requestedCardIDs {
            let availableIDs = Set(NextPlannedExpenseWidgetSnapshotStore.loadCardOptions(workspaceID: workspaceID).map(\.id))
            guard !requestedIDs.isEmpty, requestedIDs.isSubset(of: availableIDs) else {
                return SnapshotSource(configurationNeedsReview: true)
            }

            let cardIDs = requestedIDs.sorted()
            return SnapshotSource(
                cardIDs: cardIDs,
                series: cardIDs.map {
                    loadSeries(workspaceID: workspaceID, cardID: $0, periodToken: configuration.resolvedPeriodToken)
                }
            )
        }

        return SnapshotSource(series: [
            loadSeries(workspaceID: workspaceID, cardID: nil, periodToken: configuration.resolvedPeriodToken)
        ])
    }

    private func loadSeries(workspaceID: String, cardID: String?, periodToken: String) -> SnapshotSeries {
        SnapshotSeries(
            current: NextPlannedExpenseWidgetSnapshotStore.load(
                workspaceID: workspaceID, cardID: cardID, periodToken: periodToken
            ),
            timeline: NextPlannedExpenseWidgetSnapshotStore.loadTimelineSnapshots(
                workspaceID: workspaceID, cardID: cardID, periodToken: periodToken
            )
        )
    }

    private func makeEntry(for configuration: Intent, source: SnapshotSource, date: Date) -> Entry {
        let snapshots = source.series.compactMap { $0.snapshot(asOf: date) }
        let snapshot: NextPlannedExpenseWidgetSnapshot?
        if source.cardIDs.count > 1 {
            snapshot = snapshots.count == source.cardIDs.count
                ? NextPlannedExpenseWidgetSnapshot.merging(snapshots, asOf: date)
                : nil
        } else {
            snapshot = snapshots.first
        }
        return Entry(
            date: date,
            periodToken: configuration.resolvedPeriodToken,
            cardID: source.cardIDs.count == 1 ? source.cardIDs.first : nil,
            snapshot: snapshot,
            configurationNeedsReview: source.configurationNeedsReview
        )
    }
}
