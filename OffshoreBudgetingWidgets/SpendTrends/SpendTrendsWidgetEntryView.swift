//
//  SpendTrendsWidgetEntryView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import SwiftUI
import WidgetKit

struct SpendTrendsWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: SpendTrendsWidgetEntry

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                content(for: snapshot)
            } else {
                emptyState(periodToken: entry.periodToken)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private func content(for snapshot: SpendTrendsWidgetSnapshot) -> some View {
        switch family {
        case .systemSmall:
            SpendTrendsWidgetSmallView(snapshot: snapshot)
        case .systemMedium:
            SpendTrendsWidgetMediumView(snapshot: snapshot)
        case .systemLarge:
            SpendTrendsWidgetLargeView(snapshot: snapshot)
        case .systemExtraLarge:
            SpendTrendsWidgetExtraLargeView(snapshot: snapshot)
        default:
            SpendTrendsWidgetMediumView(snapshot: snapshot)
        }
    }

    @ViewBuilder
    private func emptyState(periodToken: String) -> some View {
        switch family {
        case .systemSmall:
            SpendTrendsEmptyStateSmall(periodToken: periodToken)
        case .systemMedium:
            SpendTrendsEmptyStateMedium(periodToken: periodToken, rangeText: "No range")
        default:
            SpendTrendsEmptyStateLarge(periodToken: periodToken, rangeText: "No range")
        }
    }
}

private struct SpendTrendsEmptyStateSmall: View {
    let periodToken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeaderView(title: "Spend Trends", periodToken: periodToken, rangeText: "No range", style: .stacked)

            Text("No spending data found for this period.")
                .font(.headline.weight(.semibold))
                .lineLimit(4)

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

private struct SpendTrendsEmptyStateMedium: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(title: "Spend Trends", periodToken: periodToken, rangeText: rangeText, style: .stacked)

            Spacer(minLength: 0)

            Text("No spending data found for this period.")
                .font(.headline.weight(.semibold))
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

private struct SpendTrendsEmptyStateLarge: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(title: "Spend Trends", periodToken: periodToken, rangeText: rangeText, style: .singleLine)

            Spacer(minLength: 0)

            Text("No spending data found for this period.")
                .font(.headline.weight(.semibold))
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
