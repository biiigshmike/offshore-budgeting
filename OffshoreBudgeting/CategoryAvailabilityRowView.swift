//
//  CategoryAvailabilityRowView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI

struct CategoryAvailabilityRowView: View {

    let metric: CategoryAvailabilityMetric
    let scope: AvailabilityScope
    let currencyCode: String
    let nearThreshold: Double

    var body: some View {
        HStack(alignment: .center, spacing: 12) {

            // Left: name + labels
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: metric.colorHex) ?? .primary)
                        .frame(width: 8, height: 8)

                    Text(metric.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 4) {
                    labelLine(title: "Max", value: maxText)
                    labelLine(title: "Available", value: availableText)
                    labelLine(title: "Spent", value: spentText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            // Right: progress always reserves height/space
            VStack(alignment: .trailing, spacing: 6) {
                AvailabilityProgressBar(
                    progress: progressValue,
                    isUnlimited: metric.maxAmount == nil,
                    status: status
                )
                .frame(width: 110)

                statusTag
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(borderTint, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.name)
        .accessibilityValue(accessibilityValueText)
        .accessibilityHint(accessibilityHintText)
    }

    // MARK: - Derived

    private var status: CategoryAvailabilityStatus {
        metric.status(for: scope, nearThreshold: nearThreshold)
    }

    private var borderTint: Color {
        // Soft border, but a tiny nudge if over/near.
        switch status {
        case .over:
            return Color.red.opacity(0.22)
        case .near:
            return Color.orange.opacity(0.20)
        case .ok:
            return Color.primary.opacity(0.10)
        }
    }

    private var maxText: String {
        if metric.maxAmount == nil { return "∞" }
        return formatCurrency(metric.maxAmount ?? 0)
    }

    private var spentText: String {
        formatCurrency(metric.spent(for: scope))
    }

    private var availableText: String {
        if metric.maxAmount == nil { return "∞" }

        let raw = metric.availableRaw(for: scope) ?? 0
        return formatCurrency(raw)
    }

    private var progressValue: Double? {
        // For limited categories, show progress
        if let pct = metric.percentUsed(for: scope) {
            return min(max(pct, 0), 1)
        }
        // Unlimited: we still render a track-only bar (nil progress)
        return nil
    }

    private var statusTag: some View {
        Group {
            if metric.maxAmount == nil {
                Text("Unlimited")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            } else {
                switch status {
                case .over:
                    Text("Over")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                case .near:
                    Text("Near")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                case .ok:
                    Text("OK")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .monospacedDigit()
    }

    private func labelLine(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text("\(title):")
                .frame(width: 62, alignment: .leading)

            Text(value)
                .foregroundStyle(.primary)
                .monospacedDigit()

            Spacer(minLength: 0)
        }
    }

    // MARK: - Currency formatting

    private func formatCurrency(_ value: Double) -> String {
        value.formatted(
            .currency(code: currencyCode)
            .presentation(.standard)
        )
    }

    // MARK: - Accessibility

    private var accessibilityValueText: String {
        "Max \(maxText), Available \(availableText), Spent \(spentText)"
    }

    private var accessibilityHintText: String {
        if metric.maxAmount == nil {
            return "No maximum set for this category."
        }

        switch status {
        case .over:
            return "You are over the maximum for this category."
        case .near:
            return "You are close to the maximum for this category."
        case .ok:
            return "Spending is within the maximum for this category."
        }
    }
}

// MARK: - Progress bar (consistent height)

private struct AvailabilityProgressBar: View {

    let progress: Double?          // nil means unlimited track-only
    let isUnlimited: Bool
    let status: CategoryAvailabilityStatus

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(trackColor)
                .frame(height: 8)

            if let progress {
                Capsule()
                    .fill(fillColor)
                    .frame(width: max(0, min(1, progress)) * 110, height: 8)
            } else {
                // Unlimited: render nothing on top, but keep exact height.
                Color.clear.frame(height: 8)
            }
        }
        .accessibilityHidden(true)
    }

    private var trackColor: Color {
        // Subtle track. A tiny hint for over/near, but still very soft.
        switch status {
        case .over:
            return Color.red.opacity(0.12)
        case .near:
            return Color.orange.opacity(0.12)
        case .ok:
            return Color.primary.opacity(0.08)
        }
    }

    private var fillColor: Color {
        switch status {
        case .over:
            return Color.red.opacity(0.55)
        case .near:
            return Color.orange.opacity(0.55)
        case .ok:
            return Color.primary.opacity(0.28)
        }
    }
}
