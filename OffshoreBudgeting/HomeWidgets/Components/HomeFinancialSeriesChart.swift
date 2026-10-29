import SwiftUI
import Charts

/// A shared renderer for movement lines and paired period bars. Values remain accessible
/// on the chart; callers can offer a collapsed text table for a detailed reading.
struct HomeFinancialSeriesChart: View {
    enum Style: Equatable { case bars, lines }

    let series: [HomeFinancialChartSeries]
    let style: Style

    var body: some View {
        Chart(series) { item in
            ForEach(item.points) { point in
                if style == .bars {
                    BarMark(x: .value("Period", point.label), y: .value("Amount", point.value))
                        .foregroundStyle(by: .value("Series", item.label))
                        .position(by: .value("Series", item.label))
                        .accessibilityLabel("\(point.label), \(item.label)")
                        .accessibilityValue(CurrencyFormatter.string(from: point.value))
                } else {
                    HomeFinancialLineMark(x: .value("Period", point.label), y: .value("Amount", point.value),
                                          series: item.label)
                        .foregroundStyle(by: .value("Series", item.label))
                        .lineStyle(by: .value("Series", item.label))
                        .accessibilityHidden(true)
                    PointMark(x: .value("Period", point.label), y: .value("Amount", point.value))
                        .foregroundStyle(by: .value("Series", item.label))
                        .symbol(by: .value("Series", item.label))
                        .accessibilityLabel("\(point.label), \(item.label)")
                        .accessibilityValue(CurrencyFormatter.string(from: point.value))
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: CurrencyFormatter.currencyStyle())
            }
        }
        .chartLegend(series.count > 1 ? .automatic : .hidden)
        .frame(height: 180)
    }
}
