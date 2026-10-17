import SwiftUI

/// Display-only income summary shared by Home and saved Marina answers.
struct HomeIncomeProgressContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let actualTotal: Double
    let plannedTotal: Double

    private var ratio: Double? { plannedTotal > 0 ? actualTotal / plannedTotal : nil }
    private var percentText: String {
        ratio?.formatted(.percent.precision(.fractionLength(0))) ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    actualMetric
                    plannedMetric
                }
            } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    actualMetric
                    Spacer(minLength: 0)
                    plannedMetric
                }
                VStack(alignment: .leading, spacing: 12) {
                    actualMetric
                    plannedMetric
                }
            }
            }
            HomeProgressGaugeRow(
                percentText: percentText,
                fillProgress: ratio ?? 0,
                accessibilityTitle: String(localized: "homeWidget.income.progressLabel", defaultValue: "Income progress"),
                accessibilityValue: String(format: String(localized: "homeWidget.income.progressValueFormat", defaultValue: "%1$@ of planned"), locale: .current, percentText)
            )
        }
    }

    private var actualMetric: some View {
        metric(title: String(localized: "homeWidget.income.actualIncome", defaultValue: "Actual Income"), value: actualTotal)
    }

    private var plannedMetric: some View {
        metric(title: String(localized: "homeWidget.income.plannedIncome", defaultValue: "Planned Income"), value: plannedTotal)
    }

    private func metric(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value, format: CurrencyFormatter.currencyStyle())
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
