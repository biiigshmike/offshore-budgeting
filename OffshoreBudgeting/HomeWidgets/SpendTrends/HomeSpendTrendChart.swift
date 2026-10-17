import SwiftUI
import Charts

/// Home's feathered category bars rendered from immutable display values.
struct HomeSpendTrendChart: View {
    let buckets: [HomeSpendTrendBucket]
    var showsValues = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if buckets.contains(where: { $0.total < 0 || $0.slices.contains(where: { $0.amount < 0 }) }) {
                signedChart
            } else {
                positiveChart
            }
            if showsValues {
                ForEach(buckets) { bucket in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(bucket.label)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(bucket.total, format: CurrencyFormatter.currencyStyle())
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityElement(children: .combine)
                        ForEach(bucket.slices.indices, id: \.self) { index in
                            let slice = bucket.slices[index]
                            CategoryMetricRowView(
                                name: slice.name,
                                color: color(for: slice),
                                amountText: CurrencyFormatter.string(from: slice.amount),
                                percentValue: 0,
                                showsProgressBar: false,
                                showsPercentage: false
                            )
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: showsValues ? .contain : .ignore)
        .accessibilityLabel(showsValues ? "Spending trend" : buckets.map { "\($0.label), \(CurrencyFormatter.string(from: $0.total))" }.joined(separator: "; "))
    }

    private var signedChart: some View {
        Chart(buckets) { bucket in
            if bucket.slices.isEmpty {
                BarMark(x: .value("Period", bucket.label), y: .value("Amount", bucket.total))
                    .foregroundStyle(.secondary)
                    .cornerRadius(8)
                    .accessibilityLabel(bucket.label)
                    .accessibilityValue(CurrencyFormatter.string(from: bucket.total))
            } else {
                ForEach(bucket.slices.indices, id: \.self) { index in
                    let slice = bucket.slices[index]
                    BarMark(x: .value("Period", bucket.label), y: .value("Amount", slice.amount))
                        .foregroundStyle(color(for: slice))
                        .accessibilityLabel("\(bucket.label), \(slice.name)")
                        .accessibilityValue(CurrencyFormatter.string(from: slice.amount))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing) {
                AxisGridLine().foregroundStyle(.secondary.opacity(0.22))
                AxisValueLabel(format: CurrencyFormatter.currencyStyle())
            }
        }
        .frame(height: 160)
    }

    private func color(for slice: HomeSpendTrendSlice) -> Color {
        if let hex = slice.hexColor, let color = Color(hex: hex) { return color }
        return .secondary
    }

    private var positiveChart: some View {
        // This tile is primarily a preview, but yearly ranges need all 12 months to read correctly.
        // Keeping zeros in the layout avoids bar/label drift when some buckets have no spending.

        VStack(spacing: 8) {
            GeometryReader { geo in
                let maxTotal = max(1.0, buckets.map(\.total).max() ?? 1.0)
                let slotWidth = geo.size.width / CGFloat(max(1, buckets.count))
                let barWidth = min(26, slotWidth * 0.70)
                let height = geo.size.height

                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(buckets) { bucket in
                        SpendTrendsScaledPillBar(
                            bucket: bucket,
                            maxTotal: maxTotal,
                            availableHeight: height,
                            barWidth: barWidth,
                            colorForSlice: color(for:)
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .frame(height: 120)

            SpendTrendsXAxisLabels(
                labels: buckets.map(\.label)
            )
            .frame(height: 18)
        }
    }

}
