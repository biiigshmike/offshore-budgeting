import SwiftUI
import Charts

struct CategoryAvailabilityRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let metric: CategoryAvailabilityMetric
    let scope: AvailabilityScope
    let currencyCode: String
    let nearThreshold: Double

    private var spent: Double { metric.spent(for: scope) }
    private var available: Double? { metric.availableRaw(for: scope) }
    private var categoryColor: Color { Color(hex: metric.colorHex) ?? .accentColor }
    private var status: CategoryAvailabilityStatus { metric.status(for: scope, nearThreshold: nearThreshold) }
    private var statusColor: Color {
        switch status {
        case .over: .red
        case .near: .orange
        case .ok: .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    categoryLabel.fixedSize()
                    Spacer(minLength: 12)
                    statusLabel.fixedSize()
                }
                VStack(alignment: .leading, spacing: 4) {
                    categoryLabel
                    statusLabel
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    availableAmount.fixedSize()
                    availableLabel.fixedSize()
                }
                VStack(alignment: .leading, spacing: 2) {
                    availableAmount
                    availableLabel
                }
            }

            limitChart

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Text("\(String(localized: "common.spent", defaultValue: "Spent")) \(formatCurrency(spent))")
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text("\(String(localized: "common.max", defaultValue: "Max")) \(maxText)")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 0.5)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.name)
        .accessibilityValue(String(
            format: String(localized: "homeWidget.categoryAvailability.accessibilityValueFormat", defaultValue: "Max %1$@, Available %2$@, Spent %3$@"),
            locale: .current, maxText, available.map(formatCurrency) ?? "∞", formatCurrency(spent)
        ))
    }

    private var categoryLabel: some View {
        HStack(spacing: 8) {
            Circle().fill(categoryColor).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(metric.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    private var availableAmount: some View {
        Text(available.map { formatCurrency(abs($0)) } ?? "∞")
            .font(.title3.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var availableLabel: some View {
        Group {
            if let available, available < 0 {
                Text(String(localized: "homeWidget.categoryAvailability.over", defaultValue: "Over"))
            } else {
                Text(String(localized: "common.available", defaultValue: "Available"))
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private var statusLabel: some View {
        Group {
            if metric.maxAmount == nil {
                Text(String(localized: "homeWidget.categoryAvailability.unlimited", defaultValue: "Unlimited"))
            } else {
                switch status {
                case .over: Text(String(localized: "homeWidget.categoryAvailability.over", defaultValue: "Over"))
                case .near: Text(String(localized: "homeWidget.categoryAvailability.near", defaultValue: "Near"))
                case .ok: Text(String(localized: "homeWidget.categoryAvailability.ok", defaultValue: "OK"))
                }
            }
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(statusColor)
    }

    /// Each category gets a local scale so even a small overspend extends past its maximum marker.
    private var limitChart: some View {
        let lower = min(0, spent)
        let upperBound = max(0, spent, metric.maxAmount ?? 0)
        // Only an entirely empty range needs a fallback; all other tracks end at their largest value.
        let upper = upperBound > lower ? upperBound : lower + 1
        return Chart {
            BarMark(xStart: .value("Start", lower), xEnd: .value("Range", upper),
                    y: .value("Category", metric.name), height: .fixed(6))
                .foregroundStyle(Color.primary.opacity(0.08))
                .cornerRadius(3)
            BarMark(xStart: .value("Start", min(0, spent)), xEnd: .value("Spent", max(0, spent)),
                    y: .value("Category", metric.name), height: .fixed(6))
                .foregroundStyle(categoryColor)
                .cornerRadius(3)
            if let maximum = metric.maxAmount, maximum >= 0 {
                RuleMark(x: .value("Maximum", maximum))
                    .foregroundStyle(Color.primary)
                    .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXScale(domain: lower...upper, range: .plotDimension(startPadding: 2, endPadding: 2))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private var maxText: String { metric.maxAmount.map(formatCurrency) ?? "∞" }

    private func formatCurrency(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).presentation(.standard))
    }
}
