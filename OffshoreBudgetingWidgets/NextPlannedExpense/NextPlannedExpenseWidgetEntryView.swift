//
//  NextPlannedExpenseWidgetEntryView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import SwiftUI
import WidgetKit

struct NextPlannedExpenseWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextPlannedExpenseWidgetEntry

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

    // MARK: - Content Switch

    @ViewBuilder
    private func content(for snapshot: NextPlannedExpenseWidgetSnapshot) -> some View {
        switch family {
        case .systemSmall:
            NextPlannedExpenseWidgetSmallView(snapshot: snapshot)
        case .systemMedium:
            NextPlannedExpenseWidgetMediumView(snapshot: snapshot)
        case .systemLarge:
            NextPlannedExpenseWidgetLargeView(snapshot: snapshot)
        case .systemExtraLarge:
            NextPlannedExpenseWidgetExtraLargeView(snapshot: snapshot)
        default:
            NextPlannedExpenseWidgetMediumView(snapshot: snapshot)
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private func emptyState(periodToken: String) -> some View {
        switch family {
        case .systemSmall:
            NextPlannedExpenseEmptyStateSmall()
        case .systemMedium:
            NextPlannedExpenseEmptyStateMedium(periodToken: periodToken, rangeText: "No range")
        case .systemExtraLarge:
            NextPlannedExpenseEmptyStateExtraLarge(periodToken: periodToken, rangeText: "No range")
        default:
            NextPlannedExpenseEmptyStateLarge(periodToken: periodToken, rangeText: "No range")
        }
    }
}

// MARK: - Empty States

private struct NextPlannedExpenseEmptyStateSmall: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeaderView(title: "Next Planned Expense", periodToken: "", rangeText: "")

            Text("No upcoming planned expenses found for this period.")
                .font(.headline.weight(.semibold))
                .lineLimit(4)

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

private struct NextPlannedExpenseEmptyStateMedium: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(
                title: "Next Planned Expense",
                periodToken: periodToken,
                rangeText: rangeText,
                style: .stacked
            )

            Spacer(minLength: 0)

            Text("No upcoming planned expenses found for this period.")
                .font(.headline.weight(.semibold))
                .lineLimit(3)
                .minimumScaleFactor(0.9)

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

private struct NextPlannedExpenseEmptyStateLarge: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(
                title: "Next Planned Expense",
                periodToken: periodToken,
                rangeText: rangeText,
                style: .singleLine
            )

            Spacer(minLength: 0)

            Text("No upcoming planned expenses found for this period.")
                .font(.headline.weight(.semibold))
                .lineLimit(3)

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

private struct NextPlannedExpenseEmptyStateExtraLarge: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeaderView(
                title: "Next Planned Expense",
                periodToken: periodToken,
                rangeText: rangeText,
                style: .singleLine
            )

            Spacer(minLength: 0)

            Text("No upcoming planned expenses found for this period.")
                .font(.headline.weight(.semibold))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
