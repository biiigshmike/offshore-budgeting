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
                if snapshot.totalSpent > 0 {
                    content(for: snapshot)
                } else {
                    emptyState(
                        periodToken: snapshot.periodToken,
                        rangeText: widgetCompactDateRangeText(start: snapshot.rangeStart, end: snapshot.rangeEnd)
                    )
                }
            } else {
                emptyState(periodToken: entry.periodToken, rangeText: widgetLocalized("No range"))
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
    private func emptyState(periodToken: String, rangeText: String) -> some View {
        switch family {
        case .systemSmall:
            SpendTrendsEmptyStateSmall(periodToken: periodToken, rangeText: rangeText)
        case .systemMedium:
            SpendTrendsEmptyStateMedium(periodToken: periodToken, rangeText: rangeText)
        default:
            SpendTrendsEmptyStateLarge(periodToken: periodToken, rangeText: rangeText)
        }
    }
}

private struct SpendTrendsEmptyStateSmall: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeaderView(title: widgetLocalized("Spend Trends"), periodToken: periodToken, rangeText: rangeText, style: .stacked)

            Text(widgetLocalized("No spending data found for this period."))
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
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .vertical) {
                WidgetHeaderView(
                    title: widgetLocalized("Spend Trends"),
                    periodToken: periodToken,
                    rangeText: rangeText,
                    style: .singleLine
                )
                WidgetHeaderView(
                    title: widgetLocalized("Spend Trends"),
                    periodToken: periodToken,
                    rangeText: rangeText,
                    style: .stacked
                )
            }

            Spacer(minLength: 0)

            Text(widgetLocalized("No spending data found for this period."))
                .font(.headline.weight(.semibold))
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

private struct SpendTrendsEmptyStateLarge: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(title: widgetLocalized("Spend Trends"), periodToken: periodToken, rangeText: rangeText, style: .singleLine)

            Spacer(minLength: 0)

            Text(widgetLocalized("No spending data found for this period."))
                .font(.headline.weight(.semibold))
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
