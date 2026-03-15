//
//  NextPlannedExpenseWidgetViews.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import SwiftUI
import WidgetKit

func nextPlannedLocalized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

func nextPlannedLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments)
}

private extension NextPlannedExpenseWidgetSnapshot {
    var rangeText: String {
        let start = rangeStart.formatted(.dateTime.month(.abbreviated).day())
        let end = rangeEnd.formatted(.dateTime.month(.abbreviated).day())
        return nextPlannedLocalizedFormat("%@ - %@", start, end)
    }

    var compactRangeText: String {
        widgetCompactDateRangeText(start: rangeStart, end: rangeEnd)
    }

    var displayRangeText: String {
        let start = rangeStart.formatted(.dateTime.month(.abbreviated).day())
        let end = rangeEnd.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) - \(end)"
    }

    var smallTitle: String {
        nextPlannedLocalized("Next Expense")
    }

    var compactPeriodRangeText: String {
        widgetJoinedPeriodRangeText(periodToken: periodToken, rangeText: compactRangeText)
    }
}

private func nextPlannedExpenseCurrencyFormatStyle() -> FloatingPointFormatStyle<Double>.Currency {
    let code = Locale.current.currency?.identifier ?? "USD"
    return .currency(code: code)
}

private func nextPlannedExpenseDateText(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
}

private struct NextPlannedExpenseAmountsView: View {
    let plannedAmount: Double
    let actualAmount: Double
    var compact: Bool = false

    var body: some View {
        if compact {
            VStack(alignment: .leading, spacing: 3) {
                Text(nextPlannedLocalizedFormat("Planned: %@", plannedAmount.formatted(nextPlannedExpenseCurrencyFormatStyle())))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(nextPlannedLocalizedFormat("Actual: %@", actualAmount.formatted(nextPlannedExpenseCurrencyFormatStyle())))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(nextPlannedLocalized("Planned"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    Text(plannedAmount, format: nextPlannedExpenseCurrencyFormatStyle())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                HStack(spacing: 8) {
                    Text(nextPlannedLocalized("Actual"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    Text(actualAmount, format: nextPlannedExpenseCurrencyFormatStyle())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
        }
    }
}

private struct NextPlannedExpensePrimaryRowView: View {
    let item: NextPlannedExpenseWidgetSnapshot.Item
    var cardWidth: CGFloat = 132
    var titleLineLimit: Int = 1

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            WidgetCardVisualView(
                title: item.cardName,
                themeToken: item.cardThemeToken,
                effectToken: item.cardEffectToken,
                showsTitle: true,
                titleFont: .caption.weight(.semibold),
                titlePadding: 12,
                titleOpacity: 0.86,
                titleLineLimit: 2
            )
            .frame(width: cardWidth)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.expenseTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(titleLineLimit)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                Text(nextPlannedExpenseDateText(item.expenseDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                NextPlannedExpenseAmountsView(
                    plannedAmount: item.plannedAmount,
                    actualAmount: item.actualAmount
                )
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct NextPlannedExpenseCompactItemView: View {
    let item: NextPlannedExpenseWidgetSnapshot.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WidgetCardVisualView(
                title: item.cardName,
                themeToken: item.cardThemeToken,
                effectToken: item.cardEffectToken,
                showsTitle: true,
                titleFont: .caption.weight(.semibold),
                titlePadding: 10,
                titleOpacity: 0.86,
                titleLineLimit: 2
            )
            .frame(height: 92)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityHidden(true)

            Text(item.expenseTitle)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(nextPlannedExpenseDateText(item.expenseDate))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            NextPlannedExpenseAmountsView(
                plannedAmount: item.plannedAmount,
                actualAmount: item.actualAmount,
                compact: true
            )
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Small

struct NextPlannedExpenseWidgetSmallView: View {
    let snapshot: NextPlannedExpenseWidgetSnapshot

    private var item: NextPlannedExpenseWidgetSnapshot.Item? {
        snapshot.items.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(snapshot.smallTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Text(snapshot.compactPeriodRangeText)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.76)
                .allowsTightening(true)

            if let item {
                Text(item.expenseTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.74)

                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 4) {
                        amountRow(title: nextPlannedLocalized("Planned"), amount: item.plannedAmount)
                        amountRow(title: nextPlannedLocalized("Actual"), amount: item.actualAmount)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        compactAmountRow(title: nextPlannedLocalized("Planned"), amount: item.plannedAmount)
                        compactAmountRow(title: nextPlannedLocalized("Actual"), amount: item.actualAmount)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func amountRow(title: String, amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(amount, format: nextPlannedExpenseCurrencyFormatStyle())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.66)
        }
    }

    private func compactAmountRow(title: String, amount: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)

            Text(amount, format: nextPlannedExpenseCurrencyFormatStyle())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Medium

struct NextPlannedExpenseWidgetMediumView: View {
    let snapshot: NextPlannedExpenseWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(
                title: nextPlannedLocalized("Next Planned Expense"),
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText,
                style: .stacked,
                compactRangeText: snapshot.compactRangeText,
                rangeDisplayMode: .compact,
                secondaryBehavior: .flexible(maxLines: 2)
            )

            if let item = snapshot.items.first {
                NextPlannedExpensePrimaryRowView(item: item, cardWidth: 118)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Large

struct NextPlannedExpenseWidgetLargeView: View {
    let snapshot: NextPlannedExpenseWidgetSnapshot

    private var items: [NextPlannedExpenseWidgetSnapshot.Item] {
        Array(snapshot.items.prefix(2))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(
                title: nextPlannedLocalized("Next Planned Expense"),
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText,
                style: .stacked,
                compactRangeText: snapshot.compactRangeText,
                rangeDisplayMode: .compact,
                secondaryBehavior: .flexible(maxLines: 2)
            )

            if items.count == 1, let first = items.first {
                NextPlannedExpensePrimaryRowView(item: first, cardWidth: 124, titleLineLimit: 2)
                    .frame(maxHeight: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items, id: \.expenseID) { item in
                        NextPlannedExpensePrimaryRowView(item: item, cardWidth: 120, titleLineLimit: 2)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .padding(14)
    }
}

// MARK: - Extra Large

struct NextPlannedExpenseWidgetExtraLargeView: View {
    let snapshot: NextPlannedExpenseWidgetSnapshot

    private var items: [NextPlannedExpenseWidgetSnapshot.Item] {
        Array(snapshot.items.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeaderView(
                title: nextPlannedLocalized("Next Planned Expense"),
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText,
                style: .singleLine,
                compactRangeText: snapshot.compactRangeText,
                rangeDisplayMode: .compact,
                secondaryBehavior: .flexible(maxLines: 2)
            )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if items.count == 1, let first = items.first {
            HStack {
                Spacer(minLength: 0)
                NextPlannedExpenseCompactItemView(item: first)
                    .frame(maxWidth: 220, alignment: .topLeading)
                Spacer(minLength: 0)
            }
        } else if items.count == 2 {
            HStack(alignment: .top, spacing: 12) {
                ForEach(items, id: \.expenseID) { item in
                    NextPlannedExpenseCompactItemView(item: item)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(items, id: \.expenseID) { item in
                    NextPlannedExpenseCompactItemView(item: item)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
    }
}

#Preview("Next Planned Expense Small Long Content") {
    NextPlannedExpenseWidgetSmallView(snapshot: .truncationPreview)
        .containerBackground(.background, for: .widget)
}

#Preview("Next Planned Expense Medium Long Content") {
    NextPlannedExpenseWidgetMediumView(snapshot: .truncationPreview)
        .containerBackground(.background, for: .widget)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Next Planned Expense Large Long Content") {
    NextPlannedExpenseWidgetLargeView(snapshot: .truncationPreview)
        .containerBackground(.background, for: .widget)
}
