import SwiftUI

struct MarinaMetricView: View {
    let metric: MarinaDataResult.Metric
    var prominent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(metric.formatted)
                .font(prominent ? .largeTitle.weight(.semibold) : .title3.weight(.semibold))
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
