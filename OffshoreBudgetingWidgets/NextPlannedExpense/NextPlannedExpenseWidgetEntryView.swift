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
            if family == .accessoryRectangular {
                NextPlannedExpenseRectangularView(entry: entry)
            } else if entry.configurationNeedsReview && family != .accessoryCircular {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Next Planned Expense")
                        .font(.caption.weight(.semibold))
                    Text("Review your widget’s card selection.")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
            } else if family == .accessoryCircular {
                NextPlannedExpenseCircularView(entry: entry)
            } else if let snapshot = entry.snapshot {
                if snapshot.items.isEmpty {
                    emptyState(
                        periodToken: snapshot.periodToken,
                        rangeText: widgetCompactDateRangeText(start: snapshot.rangeStart, end: snapshot.rangeEnd)
                    )
                } else {
                    content(for: snapshot)
                }
            } else {
                emptyState(periodToken: entry.periodToken, rangeText: widgetLocalized("No range"))
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
    private func emptyState(periodToken: String, rangeText: String) -> some View {
        switch family {
        case .systemSmall:
            NextPlannedExpenseEmptyStateSmall(periodToken: periodToken, rangeText: rangeText)
        case .systemMedium:
            NextPlannedExpenseEmptyStateMedium(periodToken: periodToken, rangeText: rangeText)
        case .systemExtraLarge:
            NextPlannedExpenseEmptyStateExtraLarge(periodToken: periodToken, rangeText: rangeText)
        default:
            NextPlannedExpenseEmptyStateLarge(periodToken: periodToken, rangeText: rangeText)
        }
    }
}

private extension NextPlannedExpenseWidgetEntry {
    var nextUpcomingExpense: (item: NextPlannedExpenseWidgetSnapshot.Item, days: Int)? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        guard let item = snapshot?.items.first(where: { $0.expenseDate >= today }),
              let days = calendar.dateComponents(
                [.day], from: today, to: calendar.startOfDay(for: item.expenseDate)
              ).day else { return nil }
        return (item, days)
    }
}

private struct NextPlannedExpenseRectangularView: View {
    let entry: NextPlannedExpenseWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Next Planned Expense")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if entry.configurationNeedsReview {
                message("Review your widget’s card selection.")
            } else if let expense = entry.nextUpcomingExpense {
                Text(expense.item.expenseTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .privacySensitive()

                HStack(spacing: 4) {
                    Text(expense.item.plannedAmount, format: nextPlannedExpenseCurrencyFormatStyle())
                        .layoutPriority(1)
                        .privacySensitive()
                    Text(verbatim: "·")
                        .accessibilityHidden(true)
                    timing(expense.days)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityElement(children: .combine)
            } else if entry.snapshot == nil {
                message("Next planned expense unavailable")
            } else {
                message("No upcoming planned expenses")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timing(_ days: Int) -> Text {
        if days == 0 { return Text("Today") }
        let duration = Duration.seconds(days * 86_400).formatted(.units(allowed: [.days], width: .wide))
        return Text("In \(duration)")
    }

    private func message(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .lineLimit(2)
    }
}

private struct NextPlannedExpenseCircularView: View {
    let entry: NextPlannedExpenseWidgetEntry

    var body: some View {
        let days = entry.nextUpcomingExpense?.days

        ZStack {
            AccessoryWidgetBackground()

            VStack(spacing: 2) {
                Image(systemName: entry.configurationNeedsReview ? "exclamationmark.circle" : "list.bullet.rectangle")
                    .font(.caption2.weight(.semibold))
                countdown(days)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .padding(.horizontal, 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(countdownLabel(days))
    }

    private func countdown(_ days: Int?) -> Text {
        if entry.configurationNeedsReview { return Text("Review") }
        guard let days else { return Text(verbatim: "—") }
        if days == 0 { return Text("Today") }
        return Text(Duration.seconds(days * 86_400).formatted(.units(allowed: [.days], width: .narrow)))
    }

    private func countdownLabel(_ days: Int?) -> Text {
        if entry.configurationNeedsReview { return Text("Review your widget’s card selection.") }
        guard let days else {
            return entry.snapshot == nil
                ? Text("Next planned expense unavailable")
                : Text("No upcoming planned expenses found for this period.")
        }
        if days == 0 { return Text("Next planned expense today") }
        let duration = Duration.seconds(days * 86_400).formatted(.units(allowed: [.days], width: .wide))
        return Text("Next planned expense in \(duration)")
    }
}

// MARK: - Empty States

private struct NextPlannedExpenseEmptyStateSmall: View {
    let periodToken: String
    let rangeText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetHeaderView(
                title: nextPlannedLocalized("Next Planned Expense"),
                periodToken: periodToken,
                rangeText: rangeText,
                style: .stacked,
                compactRangeText: rangeText,
                rangeDisplayMode: .compact
            )

            Text(widgetLocalized("No upcoming planned expenses found for this period."))
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
                title: nextPlannedLocalized("Next Planned Expense"),
                periodToken: periodToken,
                rangeText: rangeText,
                style: .stacked
            )

            Spacer(minLength: 0)

            Text(widgetLocalized("No upcoming planned expenses found for this period."))
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
                title: nextPlannedLocalized("Next Planned Expense"),
                periodToken: periodToken,
                rangeText: rangeText,
                style: .singleLine
            )

            Spacer(minLength: 0)

            Text(widgetLocalized("No upcoming planned expenses found for this period."))
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
                title: nextPlannedLocalized("Next Planned Expense"),
                periodToken: periodToken,
                rangeText: rangeText,
                style: .singleLine
            )

            Spacer(minLength: 0)

            Text(widgetLocalized("No upcoming planned expenses found for this period."))
                .font(.headline.weight(.semibold))
                .lineLimit(3)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}
