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
                emptyState(periodToken: entry.periodToken)
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

    @ViewBuilder
    private func emptyState(periodToken: String) -> some View {
        switch family {
        case .systemSmall:
            IncomeEmptyStateSmall(periodToken: periodToken)

        case .systemMedium:
            IncomeEmptyStateMedium(
                periodToken: periodToken,
                rangeText: "No range"
            )

        default:
            IncomeEmptyStateLarge(
                periodToken: periodToken,
                rangeText: "No range",
                headerStyle: .singleLine
            )
        }
    }
}

// MARK: - Small Empty State

private struct IncomeEmptyStateSmall: View {
    let periodToken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeaderView(
                title: "Income",
                periodToken: "",
                rangeText: ""
            )

            Text("No income data found.")
                .font(.headline.weight(.semibold))
                .lineLimit(2)

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - Medium Empty State

private struct IncomeEmptyStateMedium: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(
                title: "Income",
                periodToken: periodToken,
                rangeText: rangeText,
                style: .stacked
            )

            Spacer(minLength: 0)

            Text("No income data found in this range.")
                .font(.headline.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.9)

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}


// MARK: - Standard Empty State (Large, XXL)

private struct IncomeEmptyStateLarge: View {
    let periodToken: String
    let rangeText: String
    let headerStyle: WidgetHeaderView.Style

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(
                title: "Income",
                periodToken: periodToken,
                rangeText: rangeText,
                style: headerStyle
            )

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 6) {
                Text("No income data found in this range.")
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
