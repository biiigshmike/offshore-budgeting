//
//  IncomeWidgetEntryView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import SwiftUI
import WidgetKit

struct IncomeWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: IncomeWidgetEntry

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                content(for: snap)
            } else {
                emptyState(periodToken: entry.configuration.resolvedPeriod.rawValue)
            }
        }
        .containerBackground(.background, for: .widget)
    }

    // MARK: - Content Switch

    @ViewBuilder
    private func content(for snap: IncomeWidgetSnapshot) -> some View {
        switch family {
        case .systemSmall:
            IncomeWidgetSmallView(snapshot: snap)

        case .systemMedium:
            IncomeWidgetMediumView(snapshot: snap)

        case .systemLarge:
            IncomeWidgetLargeView(snapshot: snap)

        case .systemExtraLarge:
            IncomeWidgetExtraLargeView(snapshot: snap)

        default:
            IncomeWidgetMediumView(snapshot: snap)
        }
    }

    // MARK: - Empty State

    private func emptyState(periodToken: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(
                title: "Income",
                periodToken: periodToken,
                rangeText: "No range"
            )

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("No income data.")
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
