//
//  SpendTrendsWidgetViews.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import SwiftUI
import WidgetKit

private func spendTrendsLocalizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: Locale.current, arguments)
}

private extension SpendTrendsWidgetSnapshot {
    var rangeText: String {
        let start = rangeStart.formatted(.dateTime.month(.abbreviated).day())
        let end = rangeEnd.formatted(.dateTime.month(.abbreviated).day())
        return spendTrendsLocalizedFormat("%@ - %@", start, end)
    }

    var compactRangeText: String {
        widgetCompactDateRangeText(start: rangeStart, end: rangeEnd)
    }

    var displayRangeText: String {
        let start = rangeStart.formatted(.dateTime.month(.abbreviated).day())
        let end = rangeEnd.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) - \(end)"
    }

    var compactPeriodRangeText: String {
        widgetJoinedPeriodRangeText(periodToken: periodToken, rangeText: compactRangeText)
    }

    var compactPeriodRangeTextWithEnDash: String {
        let start = rangeStart.formatted(.dateTime.month(.abbreviated).day())
        let endDay = rangeEnd.formatted(.dateTime.day())
        return widgetJoinedPeriodRangeText(periodToken: periodToken, rangeText: "\(start)-\(endDay)")
    }

    var slashPeriodRangeText: String {
        let start = rangeStart.formatted(.dateTime.month(.defaultDigits).day())
        let end = rangeEnd.formatted(.dateTime.month(.defaultDigits).day())
        return widgetJoinedPeriodRangeText(periodToken: periodToken, rangeText: "\(start)-\(end)")
    }
}

private func spendTrendsCurrencyFormatStyle() -> FloatingPointFormatStyle<Double>.Currency {
    let code = Locale.current.currency?.identifier ?? "USD"
    return .currency(code: code)
}

private func spendTrendsColor(fromHex hex: String?) -> Color {
    guard var hex else { return .secondary.opacity(0.6) }

    hex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if hex.hasPrefix("#") { hex.removeFirst() }
    guard hex.count == 6 || hex.count == 8 else { return .secondary.opacity(0.6) }

    var int: UInt64 = 0
    guard Scanner(string: hex).scanHexInt64(&int) else { return .secondary.opacity(0.6) }

    let r = Double((int >> 16) & 0xFF) / 255.0
    let g = Double((int >> 8) & 0xFF) / 255.0
    let b = Double(int & 0xFF) / 255.0

    return Color(red: r, green: g, blue: b)
}

private struct SpendTrendsBarChartView: View {
    enum LabelCadence {
        case all
        case everyOther
        case adaptive
    }

    let buckets: [SpendTrendsWidgetSnapshot.Bucket]
    var showsLabels: Bool
    var chartHeight: CGFloat
    var compactRangeLabels: Bool = false
    var labelMinimumScaleFactor: CGFloat = 0.72
    var labelFontSize: CGFloat = 8
    var labelCadence: LabelCadence = .all
    var minimumLabelSlotWidth: CGFloat = 28
    var maxVisibleBucketCount: Int? = nil

    var body: some View {
        GeometryReader { outerGeo in
            let visibleBuckets = displayBuckets(forWidth: outerGeo.size.width)
            let resolvedCadence = resolvedLabelCadence(forWidth: outerGeo.size.width, bucketCount: visibleBuckets.count)

            VStack(spacing: 6) {
                GeometryReader { geo in
                    let maxTotal = max(1.0, visibleBuckets.map(\.total).max() ?? 1.0)
                    let slotWidth = geo.size.width / CGFloat(max(1, visibleBuckets.count))
                    let barWidth = min(24, slotWidth * 0.66)

                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(visibleBuckets) { bucket in
                            SpendTrendsBarView(
                                bucket: bucket,
                                maxTotal: maxTotal,
                                barWidth: barWidth,
                                availableHeight: geo.size.height
                            )
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }
                .frame(height: chartHeight)

                if showsLabels {
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        ForEach(Array(visibleBuckets.enumerated()), id: \.element.id) { index, bucket in
                            Text(displayLabel(for: bucket.label, index: index, cadence: resolvedCadence))
                                .font(.system(size: labelFontSize, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(labelMinimumScaleFactor)
                                .allowsTightening(true)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 16)
                }
            }
        }
        .frame(height: chartHeight + (showsLabels ? 22 : 0))
    }

    private func normalizedLabel(_ label: String) -> String {
        guard compactRangeLabels else { return label }

        // Keep small-widget labels visually uniform (e.g. "1-4", "5-11"), even if labels use
        // non-hyphen separators or include extra text.
        let numbers = label
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }

        guard numbers.count >= 2 else { return label }
        return "\(numbers[0])-\(numbers[1])"
    }

    private func displayBuckets(forWidth width: CGFloat?) -> [SpendTrendsWidgetSnapshot.Bucket] {
        let limitedBuckets = Array(buckets.prefix(maxVisibleBucketCount ?? 12))
        _ = width
        return limitedBuckets
    }

    private func resolvedLabelCadence(forWidth width: CGFloat, bucketCount: Int) -> LabelCadence {
        guard bucketCount > 0 else { return .all }

        switch labelCadence {
        case .all:
            return .all
        case .everyOther:
            return .everyOther
        case .adaptive:
            let slotWidth = width / CGFloat(bucketCount)
            return slotWidth >= minimumLabelSlotWidth ? .all : .everyOther
        }
    }

    private func displayLabel(for label: String, index: Int, cadence: LabelCadence) -> String {
        switch cadence {
        case .all:
            return normalizedLabel(label)
        case .everyOther:
            return index.isMultiple(of: 2) ? normalizedLabel(label) : ""
        case .adaptive:
            return normalizedLabel(label)
        }
    }

}

private struct SpendTrendsBarView: View {
    let bucket: SpendTrendsWidgetSnapshot.Bucket
    let maxTotal: Double
    let barWidth: CGFloat
    let availableHeight: CGFloat

    var body: some View {
        let ratio = min(1.0, max(0.0, bucket.total / max(0.000_1, maxTotal)))
        let barHeight = max(2, availableHeight * CGFloat(ratio))

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if bucket.total > 0 {
                VStack(spacing: 0) {
                    ForEach(bucket.slices) { slice in
                        let segment = max(1, barHeight * CGFloat(slice.amount / max(0.000_1, bucket.total)))
                        Rectangle()
                            .fill(spendTrendsColor(fromHex: slice.hexColor))
                            .frame(width: barWidth, height: segment)
                    }
                }
                .frame(width: barWidth, height: barHeight, alignment: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
            } else {
                Color.clear
                    .frame(width: barWidth, height: 2)
            }
        }
    }
}

private struct SpendTrendsCategoryRowView: View {
    let item: SpendTrendsWidgetSnapshot.TopCategory

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(spendTrendsColor(fromHex: item.hexColor))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            Text(item.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 0)

            Text(item.amount, format: spendTrendsCurrencyFormatStyle())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(item.percentOfTotal, format: .percent.precision(.fractionLength(0)))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 36, alignment: .trailing)
        }
    }
}

// MARK: - Small

struct SpendTrendsWidgetSmallView: View {
    let snapshot: SpendTrendsWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(snapshot.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.78)

            ViewThatFits(in: .horizontal) {
                smallHeaderCandidate(snapshot.compactPeriodRangeText)
                smallHeaderCandidate(snapshot.compactPeriodRangeTextWithEnDash)
                smallHeaderCandidate(snapshot.slashPeriodRangeText)
                smallHeaderCandidate(snapshot.periodToken)
            }

            SpendTrendsBarChartView(
                buckets: snapshot.buckets,
                showsLabels: true,
                chartHeight: 72,
                compactRangeLabels: true,
                labelMinimumScaleFactor: 0.72,
                labelFontSize: 8,
                labelCadence: .adaptive,
                minimumLabelSlotWidth: 24
            )

            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private func smallHeaderCandidate(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - Medium

struct SpendTrendsWidgetMediumView: View {
    let snapshot: SpendTrendsWidgetSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WidgetHeaderView(
                title: snapshot.title,
                periodToken: snapshot.periodToken,
                rangeText: snapshot.rangeText,
                style: .stacked,
                compactRangeText: snapshot.compactRangeText,
                rangeDisplayMode: .compact,
                secondaryBehavior: .flexible(maxLines: 2)
            )

            GeometryReader { geo in
                let chartWidth = max(112, min(140, geo.size.width * 0.44))

                HStack(alignment: .top, spacing: 10) {
                    SpendTrendsBarChartView(
                        buckets: snapshot.buckets,
                        showsLabels: true,
                        chartHeight: 72,
                        compactRangeLabels: true,
                        labelMinimumScaleFactor: 0.72,
                        labelFontSize: 8,
                        labelCadence: .adaptive,
                        minimumLabelSlotWidth: 28
                    )
                    .frame(width: chartWidth)

                    VStack(alignment: .leading, spacing: 4) {
                        if let highest = snapshot.highestBucket {
                            HStack(spacing: 8) {
                                Text("High")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Text(highest.label)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.9)
                            }

                            Text(highest.amount, format: spendTrendsCurrencyFormatStyle())
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)

                            HStack(spacing: 8) {
                                Text("Top")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)

                                Spacer(minLength: 0)

                                Text(highest.topCategoryName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }

                            HStack(spacing: 6) {
                                Text(highest.topCategoryAmount, format: spendTrendsCurrencyFormatStyle())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(highest.topCategoryPercentOfBucket, format: .percent.precision(.fractionLength(0)))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
    }
}

// MARK: - Large

struct SpendTrendsWidgetLargeView: View {
    let snapshot: SpendTrendsWidgetSnapshot

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

            HStack {
                Spacer(minLength: 0)
                SpendTrendsBarChartView(
                    buckets: snapshot.buckets,
                    showsLabels: true,
                    chartHeight: 116
                )
                .frame(width: 252)
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(snapshot.topCategories.prefix(6)) { item in
                    SpendTrendsCategoryRowView(item: item)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

// MARK: - Extra Large

struct SpendTrendsWidgetExtraLargeView: View {
    let snapshot: SpendTrendsWidgetSnapshot

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

            HStack(alignment: .top, spacing: 16) {
                SpendTrendsBarChartView(
                    buckets: snapshot.buckets,
                    showsLabels: true,
                    chartHeight: 148
                )
                .frame(width: 310)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(snapshot.topCategories.prefix(12)) { item in
                        SpendTrendsCategoryRowView(item: item)
                    }

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
    }
}

#Preview("Spend Trends Small Long Content") {
    SpendTrendsWidgetSmallView(snapshot: .truncationPreview)
        .containerBackground(.background, for: .widget)
}

#Preview("Spend Trends Medium Long Content") {
    SpendTrendsWidgetMediumView(snapshot: .truncationPreview)
        .containerBackground(.background, for: .widget)
        .environment(\.locale, Locale(identifier: "de"))
}

#Preview("Spend Trends Large Long Content") {
    SpendTrendsWidgetLargeView(snapshot: .truncationPreview)
        .containerBackground(.background, for: .widget)
}
