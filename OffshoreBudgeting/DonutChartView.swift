//
//  DonutChartView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI
import Charts

// MARK: - Donut slice model

struct DonutSlice: Identifiable, Equatable {
    let id: UUID
    let title: String
    let value: Double
    let color: Color

    init(id: UUID = UUID(), title: String, value: Double, color: Color) {
        self.id = id
        self.title = title
        self.value = value
        self.color = color
    }
}

// MARK: - Donut chart view

struct DonutChartView: View {

    let slices: [DonutSlice]

    /// Controls the hole size. 0.0 = no hole, 1.0 = invisible ring.
    let innerRadiusRatio: Double

    /// Center overlay text
    let centerTitle: String?
    let centerValueText: String?

    /// Hide legend for a “widget style” donut by default.
    let showsLegend: Bool

    init(
        slices: [DonutSlice],
        innerRadiusRatio: Double = 0.68,
        centerTitle: String? = nil,
        centerValueText: String? = nil,
        showsLegend: Bool = false
    ) {
        self.slices = slices
        self.innerRadiusRatio = min(0.95, max(0.10, innerRadiusRatio))
        self.centerTitle = centerTitle
        self.centerValueText = centerValueText
        self.showsLegend = showsLegend
    }

    var body: some View {
        ZStack {
            if totalValue <= 0 || slices.isEmpty {
                emptyState
            } else {
                chart
                    .overlay { centerOverlay }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Category breakdown")
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            ForEach(slices) { slice in
                SectorMark(
                    angle: .value("Amount", slice.value),
                    innerRadius: .ratio(innerRadiusRatio),
                    outerRadius: .ratio(1.0)
                )
                .foregroundStyle(slice.color)
                .accessibilityLabel(slice.title)
                .accessibilityValue(accessibilityValue(for: slice))
            }
        }
        .chartLegend(showsLegend ? .visible : .hidden)
        .chartPlotStyle { plotArea in
            plotArea
                .background(Color.clear)
        }
    }

    // MARK: - Center overlay

    @ViewBuilder
    private var centerOverlay: some View {
        if let centerTitle, let centerValueText {
            VStack(spacing: 4) {
                Text(centerTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(centerValueText)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.pie")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("No spending")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Text("for this range")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private var totalValue: Double {
        slices.reduce(0) { $0 + $1.value }
    }

    private func percent(for slice: DonutSlice) -> Double {
        guard totalValue > 0 else { return 0 }
        return slice.value / totalValue
    }

    private func accessibilityValue(for slice: DonutSlice) -> String {
        let pct = percent(for: slice)
        let pctText = NumberFormatter.localizedString(from: NSNumber(value: pct), number: .percent)
        let amountText = CurrencyFormatter.string(from: slice.value)
        return "\(amountText), \(pctText)"
    }
}

// MARK: - Builders (Category Spotlight helper)

extension DonutChartView {

    /// Build slices from category spend metrics, supporting Top N + optional “Other”.
    static func slicesFromCategoryMetrics(
        _ metrics: [CategorySpendMetric],
        topN: Int,
        includeOther: Bool = true
    ) -> [DonutSlice] {
        guard topN > 0 else { return [] }

        let sorted = metrics.sorted { $0.totalSpent > $1.totalSpent }
        let top = Array(sorted.prefix(topN))
        let remainder = Array(sorted.dropFirst(topN))

        var slices: [DonutSlice] = top.map { metric in
            DonutSlice(
                id: metric.categoryID,
                title: metric.categoryName,
                value: metric.totalSpent,
                color: metric.categoryColorHex.flatMap { Color(hex: $0) } ?? .secondary
            )
        }

        if includeOther {
            let otherTotal = remainder.reduce(0) { $0 + $1.totalSpent }
            if otherTotal > 0 {
                slices.append(
                    DonutSlice(
                        title: "Other",
                        value: otherTotal,
                        color: .secondary.opacity(0.5)
                    )
                )
            }
        }

        // Filter any zero/negative just to be safe
        return slices.filter { $0.value > 0 }
    }
}

// MARK: - Preview

#Preview("DonutChartView") {
    VStack(spacing: 20) {
        DonutChartView(
            slices: [
                DonutSlice(title: "Food & Drink", value: 420.55, color: .orange),
                DonutSlice(title: "Shopping", value: 310.20, color: .pink),
                DonutSlice(title: "Transportation", value: 180.00, color: .blue),
                DonutSlice(title: "Health", value: 95.75, color: .green),
                DonutSlice(title: "Other", value: 140.30, color: .secondary.opacity(0.5))
            ],
            innerRadiusRatio: 0.70,
            centerTitle: "Top: Food & Drink",
            centerValueText: CurrencyFormatter.string(from: 420.55),
            showsLegend: false
        )
        .frame(width: 220, height: 220)

        DonutChartView(
            slices: [],
            innerRadiusRatio: 0.70,
            centerTitle: "No data",
            centerValueText: nil,
            showsLegend: false
        )
        .frame(width: 220, height: 220)
    }
    .padding()
    .background(Color(.systemBackground))
}
