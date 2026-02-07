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
        let resolved = loadSnapshot(configuration: configuration)

        let entry = NextPlannedExpenseWidgetEntry(
            date: .now,
            periodToken: configuration.resolvedPeriodToken,
            cardID: resolved.cardID,
            snapshot: resolved.snapshot
        )

        let nextRefresh = Calendar.current.date(byAdding: .hour, value: 3, to: .now)
            ?? .now.addingTimeInterval(3 * 3600)

        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    private func loadSnapshot(configuration: NextPlannedExpenseWidgetConfigurationIntent) -> (cardID: String?, snapshot: NextPlannedExpenseWidgetSnapshot?) {
        let periodToken = configuration.resolvedPeriodToken

        guard let workspaceID = NextPlannedExpenseWidgetSnapshotStore.selectedWorkspaceID(), !workspaceID.isEmpty else {
            return (nil, nil)
        }

        let cardID = configuration.resolvedCardID

        let snapshot = NextPlannedExpenseWidgetSnapshotStore.load(
            workspaceID: workspaceID,
            cardID: cardID,
            periodToken: periodToken
        )

        return (cardID, snapshot)
    }
}
