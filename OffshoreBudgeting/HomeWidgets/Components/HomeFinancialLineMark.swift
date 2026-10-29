import SwiftUI
import Charts

/// Home's line rendering, shared by the savings chart and conversation timelines.
/// Callers supply immutable values and keep ownership of their axes and series colors.
struct HomeFinancialLineMark<HorizontalValue: Plottable>: ChartContent {
    let x: PlottableValue<HorizontalValue>
    let y: PlottableValue<Double>
    let series: String
    var dash: [CGFloat] = []

    var body: some ChartContent {
        LineMark(x: x, y: y, series: .value("Series", series))
            .lineStyle(StrokeStyle(lineWidth: 2, dash: dash))
    }
}
