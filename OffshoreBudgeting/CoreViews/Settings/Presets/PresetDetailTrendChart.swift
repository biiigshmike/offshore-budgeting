import SwiftUI
import Charts

struct PresetDetailTrendChart: View {
    let periods: [PresetDetailCalculator.PeriodTotal]
    let grouping: BudgetingPeriod
    @ScaledMetric(relativeTo: .body) private var chartHeight = 220

    private var calendarUnit: Calendar.Component {
        switch grouping {
        case .daily: .day
        case .weekly: .weekOfYear
        case .monthly: .month
        case .quarterly: .quarter
        case .yearly: .year
        }
    }

    private var axisDates: [Date] {
        let step = max(1, Int(ceil(Double(periods.count - 1) / 4)))
        var dates = stride(from: 0, to: periods.count, by: step).map { periods[$0].startDate }
        if let last = periods.last?.startDate, dates.last != last { dates.append(last) }
        return dates
    }

    private func axisLabel(for date: Date) -> String {
        switch grouping {
        case .daily, .weekly: date.formatted(.dateTime.month(.abbreviated).day())
        case .monthly: date.formatted(.dateTime.month(.abbreviated).year(.twoDigits))
        case .quarterly: date.formatted(.dateTime.quarter(.abbreviated).year(.twoDigits))
        case .yearly: date.formatted(.dateTime.year())
        }
    }

    private func accessiblePeriod(_ period: PresetDetailCalculator.PeriodTotal) -> String {
        if grouping == .daily { return AppDateFormat.abbreviatedDate(period.startDate) }
        return "\(AppDateFormat.abbreviatedDate(period.startDate)) – \(AppDateFormat.abbreviatedDate(period.endDate))"
    }

    var body: some View {
        if periods.isEmpty {
            ContentUnavailableView("No Results Yet", systemImage: "chart.bar.xaxis",
                description: Text("Results appear after an expense date passes or an actual amount is recorded."))
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Chart(periods) { period in
                BarMark(x: .value("Period", period.startDate, unit: calendarUnit),
                        y: .value("Amount", period.plannedAmount))
                    .foregroundStyle(by: .value("Series", String(localized: "Planned")))
                    .position(by: .value("Series", String(localized: "Planned")))
                    .accessibilityLabel(Text("\(accessiblePeriod(period)), planned"))
                    .accessibilityValue(Text(period.plannedAmount, format: CurrencyFormatter.currencyStyle()))
                BarMark(x: .value("Period", period.startDate, unit: calendarUnit),
                        y: .value("Amount", period.effectiveAmount))
                    .foregroundStyle(by: .value("Series", String(localized: "Effective")))
                    .position(by: .value("Series", String(localized: "Effective")))
                    .accessibilityLabel(Text("\(accessiblePeriod(period)), effective"))
                    .accessibilityValue(Text(period.effectiveAmount, format: CurrencyFormatter.currencyStyle()))
            }
            .chartForegroundStyleScale([
                String(localized: "Planned"): Color.secondary,
                String(localized: "Effective"): Color.accentColor
            ])
            .chartXAxis {
                AxisMarks(values: axisDates) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) { Text(axisLabel(for: date)) }
                    }
                }
            }
            .chartXAxisLabel(grouping.displayTitle)
            .chartYAxisLabel(CurrencyFormatter.currencyCode)
            .frame(height: chartHeight)
            .accessibilityIdentifier("presetDetail.trendChart")
        }
    }
}
