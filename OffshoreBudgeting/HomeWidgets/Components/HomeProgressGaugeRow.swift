import SwiftUI

// MARK: - Gauge Row

struct HomeProgressGaugeRow: View {

    let percentText: String
    let fillProgress: Double
    let accessibilityTitle: String
    let accessibilityValue: String

    private let barHeight: CGFloat = 12
    
    var body: some View {
        HStack(spacing: 10) {
            Text(percentText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 40, alignment: .leading)

            HomeProgressGaugeBar(
                progress: fillProgress,
                barHeight: barHeight
            )
            .frame(height: barHeight)

            Text(1.0, format: .percent.precision(.fractionLength(0)))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilityValue)
    }
}

