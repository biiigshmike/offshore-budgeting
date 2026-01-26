//
//  HomeSpendTrendsTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI
import Charts

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
            topN: 4
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
                        Text("No spending data in this range.")
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
        let buckets = Array(result.buckets.prefix(8))

        return Chart {
            // Invisible marks: establish x buckets + y domain for ChartProxy positioning.
            ForEach(buckets) { bucket in
                BarMark(
                    x: .value("Bucket", bucket.label),
                    y: .value("Amount", max(bucket.total, 0.000_001))
                )
                .foregroundStyle(.clear)
                .opacity(0.001)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisValueLabel().foregroundStyle(Color.secondary)
            }
        }
        .frame(height: 120)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let plotAnchor = proxy.plotFrame {
                    let plotFrame = geo[plotAnchor]

                    ZStack(alignment: .topLeading) {
                        ForEach(buckets) { bucket in
                            SpendTrendsPillBar(
                                bucket: bucket,
                                proxy: proxy,
                                plotFrame: plotFrame,
                                barWidth: min(
                                    26,
                                    plotFrame.width / CGFloat(max(4, buckets.count)) * 0.70
                                ),
                                colorForSlice: color(for:)
                            )
                        }
                    }
                    .frame(width: plotFrame.width, height: plotFrame.height)
                    .position(x: plotFrame.midX, y: plotFrame.midY)
                    .allowsHitTesting(false)
                }
            }
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

        if slice.name == "Other" {
            return .secondary
        }

        if slice.name == "Uncategorized" {
            return .secondary
        }

        return .secondary
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }
}

// MARK: - Pill Bar (feathered gradient only, no blur)

private struct SpendTrendsPillBar: View {

    let bucket: HomeSpendTrendsAggregator.Bucket
    let proxy: ChartProxy
    let plotFrame: CGRect
    let barWidth: CGFloat
    let colorForSlice: (HomeSpendTrendsAggregator.Slice) -> Color
    private let displayEpsilon: Double = 1.00

    var body: some View {
        guard bucket.total > displayEpsilon else {
            return AnyView(EmptyView())
        }

        guard let x = proxy.position(forX: bucket.label),
              let yTop = proxy.position(forY: bucket.total)
        else {
            return AnyView(EmptyView())
        }

        let xInPlot = plotFrame.minX + x
        let topInPlot = plotFrame.minY + yTop
        let barHeight = max(2, plotFrame.maxY - topInPlot)

        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        let gradient = featheredGradient(bucket: bucket)

        return AnyView(
            shape
                .fill(gradient)
                .frame(width: barWidth, height: barHeight)
                .position(x: xInPlot, y: topInPlot + (barHeight / 2))
                .overlay {
                    shape
                        .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        .frame(width: barWidth, height: barHeight)
                }
        )
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
