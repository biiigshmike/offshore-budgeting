//
//  CardWidgetViews.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import SwiftUI
import WidgetKit

// MARK: - Small

struct CardWidgetSmallView: View {
    let snapshot: CardWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.title)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .minimumScaleFactor(0.78)
                .allowsTightening(true)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 4) {
                Text("Expenses")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(snapshot.unifiedExpensesTotal, format: widgetCurrencyFormatStyle())
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
        }
        .padding(12)
    }
}

// MARK: - Medium (card tile visible)

struct CardWidgetMediumView: View {
    let snapshot: CardWidgetSnapshot

    private let cardWidth: CGFloat = 130
    private let cardHeight: CGFloat = 110

    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            // Leading content
            VStack(alignment: .leading, spacing: 8) {

                Text(snapshot.title)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.82)
                    .allowsTightening(true)

                Text("\(snapshot.periodToken) • \(formattedRange(snapshot.rangeStart, snapshot.rangeEnd))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                // group the metric so it reads as a unit
                VStack(alignment: .leading, spacing: 4) {
                    Text("Expenses")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(snapshot.unifiedExpensesTotal, format: widgetCurrencyFormatStyle())
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)
            }

            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .padding(.trailing, cardWidth + 14)

            WidgetCardVisualView(
                title: snapshot.title,
                themeToken: snapshot.themeToken,
                effectToken: snapshot.effectToken,
                showsTitle: false
            )
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.trailing, 14)
            .padding(.bottom, 14)
            .accessibilityHidden(true)
        }
    }
}



//
//// MARK: - Medium (no card preview)
//
//struct CardWidgetMediumView: View {
//    let snapshot: CardWidgetSnapshot
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 10) {
//            Text(snapshot.title)
//                .font(.headline.weight(.semibold))
//                .foregroundStyle(.primary)
//                .lineLimit(1)
//                .minimumScaleFactor(0.82)
//
//            Text("\(snapshot.periodToken) • \(formattedRange(snapshot.rangeStart, snapshot.rangeEnd))")
//                .font(.footnote)
//                .foregroundStyle(.secondary)
//                .lineLimit(1)
//
//            Text("Expenses")
//                .font(.caption.weight(.semibold))
//                .foregroundStyle(.secondary)
//
//            Text(snapshot.unifiedExpensesTotal, format: widgetCurrencyFormatStyle())
//                .font(.title2.weight(.semibold))
//                .foregroundStyle(.primary)
//
//            Spacer(minLength: 0)
//        }
//        .frame(maxWidth: .infinity, alignment: .leading)
//        .padding(14)
//
//    }
//}

// MARK: - Large

struct CardWidgetLargeView: View {
    let snapshot: CardWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            WidgetHeaderView(
                title: snapshot.title,
                periodToken: snapshot.periodToken,
                rangeText: formattedRange(snapshot.rangeStart, snapshot.rangeEnd),
                style: .singleLine
            )

            HStack {
                Spacer(minLength: 0)

                WidgetCardVisualView(
                    title: snapshot.title,
                    themeToken: snapshot.themeToken,
                    effectToken: snapshot.effectToken,
                    titleFont: .title3.weight(.semibold),
                    titlePadding: 14,
                    titleOpacity: 0.86
                )
                .frame(width: 260)

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Expenses")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(snapshot.unifiedExpensesTotal, format: widgetCurrencyFormatStyle())
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }

            Spacer(minLength: 4)
        }
        .padding(14)
    }
}

// MARK: - Extra Large (XXL)

struct CardWidgetExtraLargeView: View {
    let snapshot: CardWidgetSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 16) {

            VStack(alignment: .leading, spacing: 12) {
                WidgetHeaderView(
                    title: snapshot.title,
                    periodToken: snapshot.periodToken,
                    rangeText: formattedRange(snapshot.rangeStart, snapshot.rangeEnd),
                    style: .singleLine
                )

                WidgetCardVisualView(
                    title: snapshot.title,
                    themeToken: snapshot.themeToken,
                    effectToken: snapshot.effectToken,
                    titleFont: .title3.weight(.semibold),
                    titlePadding: 14,
                    titleOpacity: 0.86
                )
                .frame(width: 292)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Expenses")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(snapshot.unifiedExpensesTotal, format: widgetCurrencyFormatStyle())
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }

                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Recent")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                if let items = snapshot.recentItems, !items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(items.prefix(3), id: \.self) { item in
                            CardWidgetRecentExpenseRow(item: item)
                        }
                    }
                } else {
                    Text("No recent expenses.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }
}

// MARK: - Recent Expense Row

private struct CardWidgetRecentExpenseRow: View {
    let item: CardWidgetSnapshot.CardWidgetRecentItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(widgetColor(fromHex: item.categoryHex) ?? Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(item.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Text(item.amount, format: widgetCurrencyFormatStyle())
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
    }
}

// MARK: - Helpers

private func formattedRange(_ start: Date, _ end: Date) -> String {
    // Short dates, no year: "Jan 1 - Jan 31"
    let s = start.formatted(.dateTime.month(.abbreviated).day())
    let e = end.formatted(.dateTime.month(.abbreviated).day())
    return "\(s) - \(e)"
}

private func widgetCurrencyFormatStyle() -> FloatingPointFormatStyle<Double>.Currency {
    let code = Locale.current.currency?.identifier ?? "USD"
    return .currency(code: code)
}

private func widgetColor(fromHex hex: String?) -> Color? {
    guard var hex else { return nil }

    hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") { hex.removeFirst() }

    guard hex.count == 6 || hex.count == 8 else { return nil }

    var int: UInt64 = 0
    guard Scanner(string: hex).scanHexInt64(&int) else { return nil }

    let r, g, b: Double

    if hex.count == 6 {
        r = Double((int >> 16) & 0xFF) / 255.0
        g = Double((int >> 8) & 0xFF) / 255.0
        b = Double(int & 0xFF) / 255.0
    } else {
        r = Double((int >> 16) & 0xFF) / 255.0
        g = Double((int >> 8) & 0xFF) / 255.0
        b = Double(int & 0xFF) / 255.0
    }

    return Color(red: r, green: g, blue: b)
}
