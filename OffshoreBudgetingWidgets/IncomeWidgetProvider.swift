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
        IncomeWidgetEntry(
            date: .now,
            configuration: IncomeWidgetConfigurationIntent(),
            snapshot: .placeholder
        )
    }

    func snapshot(for configuration: IncomeWidgetConfigurationIntent, in context: Context) async -> IncomeWidgetEntry {
        IncomeWidgetEntry(
            date: .now,
            configuration: configuration,
            snapshot: .placeholder
        )
    }

    func timeline(for configuration: IncomeWidgetConfigurationIntent, in context: Context) async -> Timeline<IncomeWidgetEntry> {
        // TODO: Replace with App Group snapshot loader keyed by configuration.period
        let snap: IncomeWidgetSnapshot? = .placeholder

        let entry = IncomeWidgetEntry(
            date: .now,
            configuration: configuration,
            snapshot: snap
        )

        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now) ?? .now.addingTimeInterval(1800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }
}
