import SwiftUI

struct MarinaBudgetPaceView: View {
    let pace: MarinaPresentation.BudgetPaceSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MarinaMetricView(metric: .init(label: "Spending to date", value: pace.actual), prominent: true)
            MarinaMetricView(metric: .init(label: "Expected by today", value: pace.expected))
            MarinaMetricView(metric: .init(label: "Difference from expected", value: pace.difference))
            if pace.planned > 0 {
                let ratio = pace.actual / pace.planned
                HomeProgressGaugeRow(
                    percentText: ratio.formatted(.percent.precision(.fractionLength(0))),
                    fillProgress: min(max(ratio, 0), 1),
                    accessibilityTitle: "Spending against the period plan",
                    accessibilityValue: ratio.formatted(.percent.precision(.fractionLength(0)))
                )
                Text("Of planned spending · \(pace.elapsedPercent.formatted(.percent.precision(.fractionLength(0)))) of the period elapsed")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("There is no planned spending baseline for a progress percentage.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
