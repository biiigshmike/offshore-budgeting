import SwiftUI

struct MarinaMetricView: View {
    let metric: MarinaDataResult.Metric
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(metric.formatted)
                .font(prominent ? .largeTitle.weight(.semibold) : .title3.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
