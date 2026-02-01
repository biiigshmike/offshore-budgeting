//
//  HomeSpendTrendsTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI

struct HomeSpendTrendsTile: View {

    let workspace: Workspace
    let cards: [Card]
    let categories: [Category]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date

    var body: some View {
        let result = HomeSpendTrendsAggregator.calculate(
            period: .period,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: startDate,
            rangeEnd: endDate,
            cardFilter: nil,
            topN: 3
        )

        NavigationLink {
            HomeSpendTrendsMetricsView(
                workspace: workspace,
                cards: cards,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                startDate: startDate,
                endDate: endDate,
                initialPeriod: .period
            )
        } label: {
            HomeTileContainer(
                title: "Spend Trends",
                subtitle: "\(formattedDate(startDate)) - \(formattedDate(endDate))",
                accent: .purple,
                showsChevron: true
            ) {
                VStack(alignment: .leading, spacing: 10) {

                    if result.buckets.allSatisfy({ $0.total <= 0 }) {
                        Text("No spending data found in this range.")
                            .foregroundStyle(.secondary)
                    } else {
                        miniChart(result: result)
                        highestSummary(result: result)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Spend Trends")
        .accessibilityHint("View spending trends for this period")
    }

    // MARK: - Mini chart (Wallet-y pill bars)

    private func miniChart(result: HomeSpendTrendsAggregator.Result) -> some View {
        // This tile is primarily a preview, but yearly ranges need all 12 months to read correctly.
        // Keeping zeros in the layout avoids bar/label drift when some buckets have no spending.
        let buckets = Array(result.buckets.prefix(12))

        return VStack(spacing: 8) {
            GeometryReader { geo in
                let maxTotal = max(1.0, buckets.map(\.total).max() ?? 1.0)
                let slotWidth = geo.size.width / CGFloat(max(1, buckets.count))
                let barWidth = min(26, slotWidth * 0.70)
                let height = geo.size.height

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(buckets) { bucket in
                        SpendTrendsScaledPillBar(
                            bucket: bucket,
                            maxTotal: maxTotal,
                            availableHeight: height,
                            barWidth: barWidth,
                            colorForSlice: color(for:)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(height: 120)

            SpendTrendsXAxisLabels(
                labels: buckets.map(\.label)
            )
            .frame(height: 18)
        }
    }

    // MARK: - Highest summary

    private func highestSummary(result: HomeSpendTrendsAggregator.Result) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let highest = result.highestBucket {
                Text("Highest: \(highest.label) • \(highest.total, format: CurrencyFormatter.currencyStyle())")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if let top = result.topCategoryInHighestBucket {
                Text("Top: \(top.name) • \(top.amount, format: CurrencyFormatter.currencyStyle())")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Color mapping (opaque, no background bleed)

    private func color(for slice: HomeSpendTrendsAggregator.Slice) -> Color {
        if let hex = slice.hexColor, let c = Color(hex: hex) {
            return c
        }

        return .secondary
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }
}

// MARK: - X Axis Labels (manual)

private struct SpendTrendsXAxisLabels: View {
    let labels: [String]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(labels.indices, id: \.self) { index in
                Text(labels[index])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}

// MARK: - Pill Bar (scaled, feathered gradient only, no blur)

private struct SpendTrendsScaledPillBar: View {

    let bucket: HomeSpendTrendsAggregator.Bucket
    let maxTotal: Double
    let availableHeight: CGFloat
    let barWidth: CGFloat
    let colorForSlice: (HomeSpendTrendsAggregator.Slice) -> Color
    private let displayEpsilon: Double = 1.00

    var body: some View {
        let fraction = min(1.0, max(0.0, bucket.total / max(0.000_1, maxTotal)))
        let barHeight = max(2, availableHeight * CGFloat(fraction))

        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let gradient = featheredGradient(bucket: bucket)

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            if bucket.total > displayEpsilon {
                ZStack(alignment: .bottom) {
                    shape
                        .fill(gradient)
                        .frame(width: barWidth, height: barHeight)

                    shape
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        .frame(width: barWidth, height: barHeight)
                }
            } else {
                // I keep a "transparent bar" here so zero buckets still reserve their slot width.
                // Without this, the HStack can compress and labels drift away from their bars.
                Color.clear
                    .frame(width: barWidth, height: 2)
            }
        }
    }

    /// Feathered gradient: blends colors at boundaries without blur, so nothing can “float”.
    private func featheredGradient(bucket: HomeSpendTrendsAggregator.Bucket) -> LinearGradient {
        let slices = bucket.slices
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }

        let total = max(bucket.total, 0.000_1)

        func clamp(_ x: Double) -> Double {
            min(1.0, max(0.0, x))
        }

        let feather: Double = 0.055

        let colors = slices.map { colorForSlice($0) }
        guard let firstColor = colors.first else {
            return LinearGradient(
                colors: [.secondary],
                startPoint: .bottom,
                endPoint: .top
            )
        }

        var rawStops: [Gradient.Stop] = []

        // Always start at 0
        rawStops.append(.init(color: firstColor, location: 0))

        var running: Double = 0

        for i in 0..<(slices.count - 1) {
            running += slices[i].amount
            let p = clamp(running / total)

            let left = clamp(p - feather)
            let right = clamp(p + feather)

            let a = colors[i]
            let b = colors[i + 1]

            // Only add if they make sense
            if left > 0 {
                rawStops.append(.init(color: a, location: left))
            }

            if right < 1 {
                rawStops.append(.init(color: b, location: right))
            }
        }

        // Always end at 1
        rawStops.append(.init(color: colors.last ?? firstColor, location: 1))

        // 🔒 FINAL SAFETY PASS
        // Sort and remove any out-of-order / duplicate locations
        let stops = rawStops
            .sorted { $0.location < $1.location }
            .reduce(into: [Gradient.Stop]()) { acc, stop in
                if let last = acc.last, abs(last.location - stop.location) < 0.0001 {
                    // Same location, replace color (later wins)
                    acc[acc.count - 1] = stop
                } else {
                    acc.append(stop)
                }
            }

        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .bottom,
            endPoint: .top
        )
    }
}
