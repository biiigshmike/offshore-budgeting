//
//  DonutChartView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI
import Charts

// MARK: - Donut slice model

enum DonutSliceRole: Equatable {
    case normal
    case savings
    case over
}

struct DonutSlice: Identifiable, Equatable {
    let id: UUID
    let title: String
    let value: Double
    let color: Color
    let role: DonutSliceRole

    init(
        id: UUID = UUID(),
        title: String,
        value: Double,
        color: Color,
        role: DonutSliceRole = .normal
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.color = color
        self.role = role
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
                ZStack {
                    baseChart
                    specialOverlayChart
                }
                .overlay { centerOverlay }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Category breakdown")
    }

    // MARK: - Charts

    private var baseChart: some View {
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
            plotArea.background(Color.clear)
        }
    }

    /// Draw only the special slice(s) with a distinct fill.
    /// render a second chart with the same slices so the angles match,
    /// then make non-special slices clear.
    private var specialOverlayChart: some View {
        Chart {
            ForEach(slices) { slice in
                SectorMark(
                    angle: .value("Amount", slice.value),
                    innerRadius: .ratio(innerRadiusRatio),
                    outerRadius: .ratio(1.0)
                )
                .foregroundStyle(overlayStyle(for: slice))
                .opacity(slice.role == .normal ? 0 : 1)
            }
        }
        .chartLegend(.hidden)
        .chartPlotStyle { plotArea in
            plotArea.background(Color.clear)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Center overlay

    @ViewBuilder
    private var centerOverlay: some View {
        let hasTitle = (centerTitle?.isEmpty == false)
        let hasValue = (centerValueText?.isEmpty == false)

        if hasTitle || hasValue {
            VStack(spacing: hasTitle && hasValue ? 4 : 2) {
                if let centerTitle, hasTitle {
                    Text(centerTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                if let centerValueText, hasValue {
                    Text(centerValueText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 10)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 6) {

            Text("No spending data found in this range.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Special styles

    private func overlayStyle(for slice: DonutSlice) -> AnyShapeStyle {
        switch slice.role {
        case .normal:
            return AnyShapeStyle(Color.clear)

        case .over:
            return AnyShapeStyle(
                stripeGradient(
                    base: slice.color,
                    stripeCount: 26,        // thicker stripes
                    strongOpacity: 1.00,    // slightly softer
                    weakOpacity: 0.35       // more contrast
                )
            )

        case .savings:
            return AnyShapeStyle(savingsHighlight(base: slice.color))
        }
    }

    private func stripeGradient(
        base: Color,
        stripeCount: Int = 26,           // fewer = thicker stripes, more = thinner stripes
        strongOpacity: Double = 1.00,    // “dark” stripe opacity
        weakOpacity: Double = 0.35       // “light” stripe opacity
    ) -> LinearGradient {
        let stripes = max(2, stripeCount)
        let step = 1.0 / Double(stripes * 2)

        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(stripes * 2 + 1)

        var loc: Double = 0
        for i in 0..<(stripes * 2) {
            let isStripe = (i % 2 == 0)
            let color = isStripe ? base.opacity(strongOpacity) : base.opacity(weakOpacity)
            stops.append(.init(color: color, location: loc))
            loc += step
        }
        stops.append(.init(color: base.opacity(strongOpacity), location: 1.0))

        return LinearGradient(
            gradient: Gradient(stops: stops),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }


    private func savingsHighlight(base: Color) -> LinearGradient {
        // A gentle diagonal highlight
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: base.opacity(0.95), location: 0.00),
                .init(color: base.opacity(0.70), location: 0.45),
                .init(color: base.opacity(0.92), location: 0.70),
                .init(color: base.opacity(0.78), location: 1.00)
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
                color: metric.categoryColorHex.flatMap { Color(hex: $0) } ?? .secondary,
                role: .normal
            )
        }

        if includeOther {
            let otherTotal = remainder.reduce(0) { $0 + $1.totalSpent }
            if otherTotal > 0 {
                slices.append(
                    DonutSlice(
                        title: "Other",
                        value: otherTotal,
                        color: .secondary.opacity(0.5),
                        role: .normal
                    )
                )
            }
        }

        // Filter any zero/negative
        return slices.filter { $0.value > 0 }
    }
}
