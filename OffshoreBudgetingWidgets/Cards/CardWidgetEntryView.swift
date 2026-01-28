//
//  CardWidgetEntryView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import SwiftUI
import WidgetKit

struct CardWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CardWidgetEntry

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                content(for: snap)
            } else {
                emptyState(periodToken: entry.periodToken)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    @ViewBuilder
    private func content(for snap: CardWidgetSnapshot) -> some View {
        switch family {
        case .systemSmall:
            CardWidgetSmallView(snapshot: snap)
        case .systemMedium:
            CardWidgetMediumView(snapshot: snap)
        case .systemLarge:
            CardWidgetLargeView(snapshot: snap)
        case .systemExtraLarge:
            CardWidgetExtraLargeView(snapshot: snap)
        default:
            CardWidgetMediumView(snapshot: snap)
        }
    }

    @ViewBuilder
    private func emptyState(periodToken: String) -> some View {
        switch family {
        case .systemSmall:
            CardEmptyStateSmall()
        case .systemMedium:
            CardEmptyStateMedium(periodToken: periodToken, rangeText: "No range")
        default:
            CardEmptyStateLarge(periodToken: periodToken, rangeText: "No range")
        }
    }
}

// MARK: - Empty States

private struct CardEmptyStateSmall: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeaderView(title: "Card", periodToken: "", rangeText: "")
            Text("No card data found.")
                .font(.headline.weight(.semibold))
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

private struct CardEmptyStateMedium: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(title: "Card", periodToken: periodToken, rangeText: rangeText, style: .stacked)
            Spacer(minLength: 0)
            Text("No card data found in this range.")
                .font(.headline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.9)
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

private struct CardEmptyStateLarge: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(title: "Card", periodToken: periodToken, rangeText: rangeText, style: .singleLine)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 6) {
                Text("No card data found in this range.")
                    .font(.headline.weight(.semibold))
                Text("Open Offshore to generate widget data for this period.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
