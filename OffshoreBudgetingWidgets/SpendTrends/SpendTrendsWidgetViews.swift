//
//  SpendTrendsWidgetViews.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import SwiftUI

private extension SpendTrendsWidgetSnapshot {
    var rangeText: String {
        let start = rangeStart.formatted(.dateTime.month(.abbreviated).day())
        let end = rangeEnd.formatted(.dateTime.month(.abbreviated).day())
        return "\(start) - \(end)"
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
    let buckets: [SpendTrendsWidgetSnapshot.Bucket]
    var showsLabels: Bool
    var chartHeight: CGFloat
    var compactRangeLabels: Bool = false

    var body: some View {
        let visibleBuckets = Array(buckets.prefix(12))

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
                    ForEach(visibleBuckets) { bucket in
                        Text(normalizedLabel(bucket.label))
                            .font(.system(size: 8, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(1)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(height: 16)
            }
        }
    }

    private func normalizedLabel(_ label: String) -> String {
        guard compactRangeLabels else { return label }

        // Keep small-widget labels visually uniform (e.g. "01-04", "05-11"), even if labels use
        // non-hyphen separators or include extra text.
        let numbers = label
            .split(whereSeparator: { !$0.isNumber })
            .compactMap { Int($0) }

        guard numbers.count >= 2 else { return label }
        return String(format: "%02d-%02d", numbers[0], numbers[1])
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

            Text("\(snapshot.periodToken) • \(snapshot.rangeText)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            SpendTrendsBarChartView(
                buckets: snapshot.buckets,
                showsLabels: true,
                chartHeight: 72,
                compactRangeLabels: true
            )

            Spacer(minLength: 0)
        }
        .padding(12)
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
                style: .stacked
            )

            HStack(alignment: .top, spacing: 10) {
                SpendTrendsBarChartView(
                    buckets: snapshot.buckets,
                    showsLabels: false,
                    chartHeight: 72
                )
                .frame(width: 128)

                VStack(alignment: .leading, spacing: 3) {
                    if let highest = snapshot.highestBucket {
                        Text("Highest \(highest.label)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        Text(highest.amount, format: spendTrendsCurrencyFormatStyle())
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Text("Top \(highest.topCategoryName)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

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
                style: .singleLine
            )

            HStack {
                Spacer(minLength: 0)
                SpendTrendsBarChartView(
                    buckets: snapshot.buckets,
                    showsLabels: true,
                    chartHeight: 116
                )
                .frame(width: 265)
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
                style: .singleLine
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
