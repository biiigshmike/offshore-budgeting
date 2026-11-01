import SwiftUI

struct SpendTrendsScaledPillBar: View {
    let bucket: HomeSpendTrendBucket
    let maxTotal: Double
    let availableHeight: CGFloat
    let barWidth: CGFloat
    let colorForSlice: (HomeSpendTrendSlice) -> Color

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            if bucket.total > 0 {
                SpendTrendsSatinBar(
                    segments: bucket.slices.map {
                        SpendTrendsBarSegment(amount: $0.amount, color: colorForSlice($0))
                    },
                    width: barWidth,
                    height: SpendTrendsBarStyle.barHeight(
                        total: bucket.total, maximum: maxTotal, availableHeight: availableHeight
                    )
                )
            } else {
                // Reserve the slot so zero buckets and their labels remain aligned.
                Color.clear.frame(width: barWidth, height: 2)
            }
        }
    }
}
