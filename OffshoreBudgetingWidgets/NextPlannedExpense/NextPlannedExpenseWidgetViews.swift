//
//  NextPlannedExpenseWidgetViews.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import SwiftUI

private extension NextPlannedExpenseWidgetSnapshot {
    var rangeText: String {
        let start = rangeStart.formatted(.dateTime.month(.abbreviated).day())
        let end = rangeEnd.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) - \(end)"
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
                Text("Planned: \(plannedAmount, format: nextPlannedExpenseCurrencyFormatStyle())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text("Actual: \(actualAmount, format: nextPlannedExpenseCurrencyFormatStyle())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Planned")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(plannedAmount, format: nextPlannedExpenseCurrencyFormatStyle())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    Text("Actual")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Text(actualAmount, format: nextPlannedExpenseCurrencyFormatStyle())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
            }
        }
    }
}

private struct NextPlannedExpensePrimaryRowView: View {
    let item: NextPlannedExpenseWidgetSnapshot.Item

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
            .frame(width: 132)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.expenseTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(nextPlannedExpenseDateText(item.expenseDate))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

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
        VStack(alignment: .leading, spacing: 3) {
            Text("Next Planned Expense")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .minimumScaleFactor(0.85)

            Text("\(snapshot.periodToken) • \(snapshot.rangeText)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            if let item {
                Text(item.expenseTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Planned \(item.plannedAmount, format: nextPlannedExpenseCurrencyFormatStyle())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text("Actual \(item.actualAmount, format: nextPlannedExpenseCurrencyFormatStyle())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

// MARK: - Medium

struct NextPlannedExpenseWidgetMediumView: View {
    let snapshot: NextPlannedExpenseWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WidgetHeaderView(
                title: snapshot.title,
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText,
                style: .stacked
            )

            if let item = snapshot.items.first {
                NextPlannedExpensePrimaryRowView(item: item)
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
                title: snapshot.title,
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText,
                style: .stacked
            )

            if items.count == 1, let first = items.first {
                NextPlannedExpensePrimaryRowView(item: first)
                    .frame(maxHeight: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(items, id: \.expenseID) { item in
                        NextPlannedExpensePrimaryRowView(item: item)
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
                title: snapshot.title,
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText,
                style: .singleLine
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
