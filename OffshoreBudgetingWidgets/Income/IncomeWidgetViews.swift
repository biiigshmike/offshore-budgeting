//
//  IncomeWidgetViews.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import SwiftUI
import WidgetKit

// MARK: - Helpers

private func incomeWidgetLocalized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

private func incomeWidgetLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments)
}

private enum IncomeDeltaCopyStyle {
    case full
    case compact
    case amountOnly
}

private extension IncomeWidgetSnapshot {
    var rangeText: String {
        let start = rangeStart.formatted(.dateTime.month(.abbreviated).day())
        let end = rangeEnd.formatted(.dateTime.month(.abbreviated).day())
        return "\(start)–\(end)"
    }

    /// Extra-compact for small widgets.
    /// Examples:
    /// - "Dec 29–Jan 27"
    /// - "Dec 29–27" (same month)
    /// - avoids injecting year unless needed
    var rangeTextSmall: String {
        let cal = Calendar.current

        let startMonth = cal.component(.month, from: rangeStart)
        let endMonth = cal.component(.month, from: rangeEnd)
        let startYear = cal.component(.year, from: rangeStart)
        let endYear = cal.component(.year, from: rangeEnd)

        // Same month+year: "Dec 29–27"
        if startMonth == endMonth && startYear == endYear {
            let month = rangeStart.formatted(.dateTime.month(.abbreviated))
            let startDay = rangeStart.formatted(.dateTime.day())
            let endDay = rangeEnd.formatted(.dateTime.day())
            return "\(month) \(startDay)–\(endDay)"
        }

        // Same year but different months: "Dec 29–Jan 27"
        if startYear == endYear {
            let startText = rangeStart.formatted(.dateTime.month(.abbreviated).day())
            let endText = rangeEnd.formatted(.dateTime.month(.abbreviated).day())
            return "\(startText)–\(endText)"
        }
        
        // Different years: still keep it short, no year in small widgets
        let startText = rangeStart.formatted(.dateTime.month(.abbreviated).day())
        let endText = rangeEnd.formatted(.dateTime.month(.abbreviated).day())
        return "\(startText)–\(endText)"

    }

    var delta: Double { actualTotal - plannedTotal }
    var percent: Double? { plannedTotal > 0 ? actualTotal / plannedTotal : nil }

    var progressText: String {
        guard let pct = percent else { return incomeWidgetLocalized("Progress —") }
        let formatted = pct.formatted(.percent.precision(.fractionLength(0)))
        return incomeWidgetLocalizedFormat("Progress %@", formatted)
    }

    var deltaText: String {
        let formatted = delta.formatted(incomeWidgetCurrencyFormatStyle())
        if delta < 0 { return incomeWidgetLocalizedFormat("Remaining %@", formatted.replacingOccurrences(of: "-", with: "")) }
        if delta > 0 { return incomeWidgetLocalizedFormat("Over %@", formatted) }
        return incomeWidgetLocalized("On target")
    }

    /// Small header uses no spaces around the separator to keep it short.
    var periodAndRangeSmall: String { "\(periodToken) • \(rangeTextSmall)" }

    var compactRangeText: String {
        widgetCompactDateRangeText(start: rangeStart, end: rangeEnd)
    }

    var compactProgressText: String {
        guard let pct = percent else { return incomeWidgetLocalized("Progress —") }
        return pct.formatted(.percent.precision(.fractionLength(0)))
    }

    var gaugeFooterTextMedium: String {
        compactProgressText
    }

    func deltaText(style: IncomeDeltaCopyStyle) -> String {
        let amount = delta.formatted(incomeWidgetCurrencyFormatStyle()).replacingOccurrences(of: "-", with: "")

        switch style {
        case .full:
            if delta < 0 { return incomeWidgetLocalizedFormat("Left %@", amount) }
            if delta > 0 { return incomeWidgetLocalizedFormat("Over %@", amount) }
            return incomeWidgetLocalized("On target")

        case .compact:
            if delta < 0 { return incomeWidgetLocalizedFormat("%@ %@", incomeWidgetLocalized("Left"), amount) }
            if delta > 0 { return incomeWidgetLocalizedFormat("%@ %@", incomeWidgetLocalized("Over"), amount) }
            return incomeWidgetLocalized("On target")

        case .amountOnly:
            if delta == 0 { return incomeWidgetLocalized("On target") }
            return amount
        }
    }

}

private struct IncomeLargeFooterView: View {
    let snapshot: IncomeWidgetSnapshot

    var body: some View {
        Text(snapshot.compactProgressText)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricValueView: View {
    let title: String
    let value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(value, format: incomeWidgetCurrencyFormatStyle())
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecentIncomeCell: View {
    let item: IncomeWidgetSnapshot.IncomeWidgetRecentItem

    private var dotColor: Color {
        item.isPlanned ? .orange : .blue
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .padding(.top, 3)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.amount, format: incomeWidgetCurrencyFormatStyle())
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        }
    }
}


// MARK: - Small

struct IncomeWidgetSmallView: View {
    let snapshot: IncomeWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Trick: pass "1M·Dec 29–Jan 27" as the rangeText,
            // and keep periodToken empty so WidgetHeaderView doesn't add extra separators/spaces.
            WidgetHeaderView(
                title: snapshot.title,
                periodToken: "",
                rangeText: snapshot.periodAndRangeSmall,
                style: .stackedWrapRange
            )

            IncomeGaugeView(
                planned: snapshot.plannedTotal,
                actual: snapshot.actualTotal,
                showsPercentEnds: false,
                footer: .none
            )
            .frame(maxWidth: .infinity)
            .frame(height: 14)

            MetricValueView(title: incomeWidgetLocalized("Actual"), value: snapshot.actualTotal)

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Medium

struct IncomeWidgetMediumView: View {
    let snapshot: IncomeWidgetSnapshot

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                WidgetHeaderView(
                    title: snapshot.title,
                    periodToken: snapshot.periodToken,
                    rangeText: snapshot.rangeText,
                    style: .stacked,
                    compactRangeText: snapshot.compactRangeText,
                    rangeDisplayMode: .compact,
                    secondaryBehavior: .flexible(maxLines: 2)
                )

                IncomeGaugeView(
                    planned: snapshot.plannedTotal,
                    actual: snapshot.actualTotal,
                    showsPercentEnds: true,
                    footer: .progressOnly(snapshot.gaugeFooterTextMedium),
                    footerAlignment: .leading
                )
                .frame(height: 52)
            }

            VStack(alignment: .leading, spacing: 10) {
                MetricValueView(title: incomeWidgetLocalized("Planned"), value: snapshot.plannedTotal)
                MetricValueView(title: incomeWidgetLocalized("Actual"), value: snapshot.actualTotal)

                Spacer(minLength: 0)
            }
            .frame(width: 140, alignment: .leading)
        }
        .padding(14)
    }
}

// MARK: - Large

struct IncomeWidgetLargeView: View {
    let snapshot: IncomeWidgetSnapshot

    private let columns: [GridItem] = [
        GridItem(.flexible(minimum: 0), spacing: 12),
        GridItem(.flexible(minimum: 0), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetHeaderView(
                title: snapshot.title,
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText,
                style: .singleLine,
                compactRangeText: snapshot.compactRangeText,
                rangeDisplayMode: .compact,
                secondaryBehavior: .flexible(maxLines: 2)
            )

            IncomeGaugeView(
                planned: snapshot.plannedTotal,
                actual: snapshot.actualTotal,
                showsPercentEnds: false,
                footer: .none
            )
            .frame(maxWidth: .infinity)
            .frame(height: 22)

            IncomeLargeFooterView(snapshot: snapshot)

            HStack(spacing: 12) {
                MetricValueView(title: incomeWidgetLocalized("Planned"), value: snapshot.plannedTotal)
                MetricValueView(title: incomeWidgetLocalized("Actual"), value: snapshot.actualTotal)

                Spacer(minLength: 0)
            }

            if let items = snapshot.recentItems, !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(incomeWidgetLocalized("Recent Income"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(Array(items.prefix(4).enumerated()), id: \.offset) { _, item in
                            RecentIncomeCell(item: item)
                        }
                    }
                }
            } else {
                Text(incomeWidgetLocalized("No recent entries."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Extra Large (XXL)

struct IncomeWidgetExtraLargeView: View {
    let snapshot: IncomeWidgetSnapshot

    private let columns: [GridItem] = [
        GridItem(.flexible(minimum: 0), spacing: 14),
        GridItem(.flexible(minimum: 0), spacing: 14)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            WidgetHeaderView(
                title: snapshot.title,
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText,
                style: .singleLine,
                compactRangeText: snapshot.compactRangeText,
                rangeDisplayMode: .compact,
                secondaryBehavior: .flexible(maxLines: 2)
            )

            IncomeGaugeView(
                planned: snapshot.plannedTotal,
                actual: snapshot.actualTotal,
                showsPercentEnds: false,
                footer: .progressOnly("\(snapshot.compactProgressText) • \(snapshot.deltaText(style: .full))"),
                footerAlignment: .centered,
                footerLineLimit: 1
            )
            .frame(maxWidth: .infinity)
            .frame(height: 52)

            // Planned leading, Actual trailing
            HStack(alignment: .top) {
                MetricValueView(title: incomeWidgetLocalized("Planned"), value: snapshot.plannedTotal)

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(incomeWidgetLocalized("Actual"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text(snapshot.actualTotal, format: incomeWidgetCurrencyFormatStyle())
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .accessibilityElement(children: .combine)
            }

            if let items = snapshot.recentItems, !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(incomeWidgetLocalized("Recent Income"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                        ForEach(Array(items.prefix(8).enumerated()), id: \.offset) { _, item in
                            RecentIncomeCell(item: item)
                        }
                    }
                }
            } else {
                Text(incomeWidgetLocalized("No recent income entries."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Widget formatting helpers

private func incomeWidgetCurrencyFormatStyle() -> FloatingPointFormatStyle<Double>.Currency {
    let code = Locale.current.currency?.identifier ?? "USD"
    return .currency(code: code)
}

#Preview("Income Small Long Content") {
    IncomeWidgetSmallView(snapshot: .truncationPreview)
        .containerBackground(.background, for: .widget)
}

#Preview("Income Medium Long Content") {
    IncomeWidgetMediumView(snapshot: .truncationPreview)
        .containerBackground(.background, for: .widget)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Income Large Long Content") {
    IncomeWidgetLargeView(snapshot: .truncationPreview)
        .containerBackground(.background, for: .widget)
}
