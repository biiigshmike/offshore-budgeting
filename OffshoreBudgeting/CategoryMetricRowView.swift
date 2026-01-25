//
//  CategoryMetricRowView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI

struct CategoryMetricRowView: View {

    let name: String
    let color: Color
    let amountText: String
    let percentValue: Double

    var showsProgressBar: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(color)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(amountText)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)

                        Text(percentText(percentValue))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                if showsProgressBar {
                    ProgressView(value: clampedPercent)
                        .progressViewStyle(.linear)
                        .tint(color)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityValue("\(amountText), \(percentText(percentValue))")
    }

    // MARK: - Helpers

    private var clampedPercent: Double {
        max(0, min(1, percentValue))
    }

    private func percentText(_ value: Double) -> String {
        let clamped = max(0, min(1, value))
        return NumberFormatter.localizedString(from: NSNumber(value: clamped), number: .percent)
    }
}

#Preview("CategoryMetricRowView") {
    List {
        CategoryMetricRowView(
            name: "Food & Drink",
            color: .orange,
            amountText: "$420.55",
            percentValue: 0.38,
            showsProgressBar: true
        )

        CategoryMetricRowView(
            name: "Shopping",
            color: .pink,
            amountText: "$310.20",
            percentValue: 0.28,
            showsProgressBar: true
        )
    }
}
