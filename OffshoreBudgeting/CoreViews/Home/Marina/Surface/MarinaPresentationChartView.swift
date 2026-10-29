import SwiftUI
import Charts

struct MarinaPresentationChartView: View {
    let operation: MarinaDataRequest.Operation
    let points: [MarinaPresentation.ChartPoint]
    var chartIntent: MarinaDataRequest.ChartIntent? = nil

    private var usesDonut: Bool {
        operation == .share && !points.isEmpty && points.allSatisfy { $0.value >= 0 }
            && points.contains { $0.value > 0 }
    }

    private var valueDomain: ClosedRange<Double> {
        let lower = min(0, points.map(\.value).min() ?? 0)
        let upper = max(0, points.map(\.value).max() ?? 0)
        return lower == upper ? 0...1 : lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if points.isEmpty {
                Text("No matching data for this period.")
                    .foregroundStyle(.secondary)
            } else {
                if operation == .trend {
                    HomeFinancialSeriesChart(series: [.init(id: "amount", label: "Amount", points: points.map {
                        .init(id: $0.id, label: $0.label, value: $0.value, date: $0.date)
                    })], style: chartIntent == .movementOverTime ? .lines : .bars)
                } else if usesDonut {
                    DonutChartView(slices: points.map { point in
                        DonutSlice(
                            id: UUID(uuidString: point.id) ?? stableSliceID(point.id),
                            title: point.label,
                            value: point.value,
                            color: point.colorHex.flatMap { Color(hex: $0) } ?? .accentColor
                        )
                    })
                    .frame(height: 180)
                    .accessibilityHidden(true)
                }

                ForEach(points) { point in
                    VStack(alignment: .leading, spacing: 5) {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(point.label)
                                Spacer(minLength: 12)
                                Text(CurrencyFormatter.string(from: point.value))
                                    .monospacedDigit()
                            }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(point.label)
                                Text(CurrencyFormatter.string(from: point.value))
                                    .monospacedDigit()
                            }
                        }
                        .font(.subheadline)
                        .accessibilityElement(children: .combine)

                        if operation != .trend && !usesDonut {
                            Chart {
                                BarMark(
                                    xStart: .value("Zero", 0),
                                    xEnd: .value("Amount", point.value),
                                    y: .value("Category", point.id)
                                )
                                .foregroundStyle(point.colorHex.flatMap { Color(hex: $0) } ?? .accentColor)
                                .cornerRadius(3)
                                RuleMark(x: .value("Zero", 0))
                                    .foregroundStyle(.secondary.opacity(0.3))
                            }
                            .chartXScale(domain: valueDomain)
                            .chartXAxis(.hidden)
                            .chartYAxis(.hidden)
                            .frame(height: 12)
                            .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }

    /// Stable slice identity avoids rebuilding charts on every streamed text update.
    private func stableSliceID(_ key: String) -> UUID {
        let index = points.firstIndex { $0.id == key } ?? 0
        return UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           UInt8(truncatingIfNeeded: index >> 24), UInt8(truncatingIfNeeded: index >> 16),
                           UInt8(truncatingIfNeeded: index >> 8), UInt8(truncatingIfNeeded: index)))
    }
}
