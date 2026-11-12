//
//  HomeIncomeMetricsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI
import Charts

struct HomeIncomeMetricsView: View {

    enum Period: String, CaseIterable, Identifiable {
        case period = "P"
        case oneWeek = "1W"
        case oneMonth = "1M"
        case oneYear = "1Y"
        case q = "Q"

        var id: String { rawValue }
    }

    private enum BucketGranularity {
        case day
        case week
        case month
        case quarter
    }

    private struct IncomeBarPoint: Identifiable {
        let id = UUID()
        let date: Date
        let kind: String // "Actual" / "Planned"
        let amount: Double
    }

    let workspace: Workspace
    let incomes: [Income]
    let startDate: Date
    let endDate: Date
    let initialPeriod: Period

    @State private var selectedPeriod: Period
    @State private var showingCalculationHelp: Bool = false

    init(
        workspace: Workspace,
        incomes: [Income],
        startDate: Date,
        endDate: Date,
        initialPeriod: Period = .period
    ) {
        self.workspace = workspace
        self.incomes = incomes
        self.startDate = startDate
        self.endDate = endDate
        self.initialPeriod = initialPeriod
        _selectedPeriod = State(initialValue: initialPeriod)
    }

    var body: some View {
        let resolved = resolvedRange(for: selectedPeriod)
        let plannedTotal = sum(isPlanned: true, from: resolved.start, to: resolved.end)
        let actualTotal = sum(isPlanned: false, from: resolved.start, to: resolved.end)

        let ratio: Double? = plannedTotal > 0 ? (actualTotal / plannedTotal) : nil
        let percentText: String = {
            guard let ratio else { return "—" }
            return ratio.formatted(.percent.precision(.fractionLength(0)))
        }()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                headerSummary(
                    actualTotal: actualTotal,
                    plannedTotal: plannedTotal,
                    percentText: percentText
                )

                Text("Actual income is money received. Planned income is money expected. These are compared separately, rather than added together.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Button("How is this calculated?", systemImage: "info.circle") {
                    showingCalculationHelp = true
                }

                periodPicker

                chartCard(
                    points: buildChartPoints(for: resolved),
                    granularity: resolved.granularity
                )

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .modifier(DateRangeNavigationHeader(
            title: String(
                localized: "homeWidget.income",
                defaultValue: "Income",
                comment: "Pinned home widget title for income metrics."
            ),
            startDate: resolved.start,
            endDate: resolved.end
        ))
        .appSheet(isPresented: $showingCalculationHelp) {
            FinancialCalculationHelpView(
                sections: incomeCalculationSections(from: resolved.start, to: resolved.end),
                dateRange: "\(formattedDate(resolved.start)) – \(formattedDate(resolved.end))",
                helpTopicID: "income-calculations"
            )
        }
    }

    private func incomeCalculationSections(from start: Date, to end: Date) -> [FinancialCalculationSection] {
        [false, true].map { isPlanned in
            let included = incomes.filter {
                $0.isPlanned == isPlanned && $0.date >= start && $0.date <= end
            }
            let grouped = Dictionary(grouping: included, by: \.source)
            let sourceRows = grouped.keys.sorted().map { source in
                FinancialCalculationRow(
                    id: "source-\(source)",
                    title: source,
                    amount: (grouped[source] ?? []).reduce(0) { $0 + $1.amount },
                    titleIsVerbatim: true
                )
            }
            let title = isPlanned ? "Planned Income" : "Actual Income"
            return FinancialCalculationSection(
                id: isPlanned ? "planned" : "actual", title: title,
                explanation: isPlanned
                    ? "Income you expect to receive during these dates, grouped by where it comes from."
                    : "Income you’ve received during these dates, grouped by where it comes from.",
                rows: sourceRows + [.init(id: "total", title: title, amount: sum(isPlanned: isPlanned, from: start, to: end), isTotal: true)],
                notes: isPlanned
                    ? ["Progress shows how much of your Planned Income you’ve received. Receiving half of the amount you planned means 50%. A percentage appears when Planned Income is above zero."]
                    : ["Actual Income is money you’ve received. Planned Income is money you expect. These amounts are shown separately rather than added together."]
            )
        }
    }

    // MARK: - Header

    private func headerSummary(
        actualTotal: Double,
        plannedTotal: Double,
        percentText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                summaryMetric(title: String(localized: "common.actual", defaultValue: "Actual", comment: "Common label for actual values."), value: actualTotal, color: .blue)

                Spacer(minLength: 0)

                summaryMetric(title: String(localized: "common.planned", defaultValue: "Planned", comment: "Common label for planned values."), value: plannedTotal, color: .orange)
            }

            Text(
                String(
                    format: String(
                        localized: "homeWidget.income.progressTextFormat",
                        defaultValue: "Progress: %1$@",
                        comment: "Progress text format for income metrics header."
                    ),
                    locale: .current,
                    percentText
                )
            )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func summaryMetric(title: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value, format: CurrencyFormatter.currencyStyle())
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
        }
    }

    // MARK: - Picker

    private var periodPicker: some View {
        Picker(String(localized: "homeWidget.income.period", defaultValue: "Period", comment: "Period picker label for income widget metrics."), selection: $selectedPeriod) {
            ForEach(Period.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(String(localized: "homeWidget.income.period", defaultValue: "Period", comment: "Period picker accessibility label for income widget metrics."))
    }

    // MARK: - Chart

    private func chartCard(points: [IncomeBarPoint], granularity: BucketGranularity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "homeWidget.income.trends", defaultValue: "Trends", comment: "Section title for income trends chart."))
                .font(.headline.weight(.semibold))

            if points.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "homeWidget.income.noDataInRange", defaultValue: "No income data found in this range.", comment: "Message shown when no income exists in selected range."))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
                .padding(.vertical, 18)
            } else {
                let quarterAxisDates = Array(Set(points.map(\.date))).sorted()

                Chart(points) { point in
                    BarMark(
                        x: .value(String(localized: "common.date", defaultValue: "Date", comment: "Axis label for date."), point.date, unit: chartUnit(for: granularity)),
                        y: .value(String(localized: "common.amount", defaultValue: "Amount", comment: "Axis label for amount."), point.amount)
                    )
                    .foregroundStyle(by: .value(String(localized: "common.type", defaultValue: "Type", comment: "Legend label for type."), point.kind))
                    .position(by: .value(String(localized: "common.type", defaultValue: "Type", comment: "Legend label for type."), point.kind))
                }
                .chartForegroundStyleScale([
                    String(localized: "common.planned", defaultValue: "Planned", comment: "Common label for planned values."): Color.orange,
                    String(localized: "common.actual", defaultValue: "Actual", comment: "Common label for actual values."): Color.blue
                ])
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                        AxisTick()

                        // Stable: format-based axis labels
                        AxisValueLabel(format: CurrencyFormatter.currencyStyle())
                    }
                }
                .chartXAxis {
                    if granularity == .quarter {
                        AxisMarks(values: quarterAxisDates) { value in
                            AxisGridLine()
                            AxisTick()
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(quarterLabel(for: date))
                                }
                            }
                        }
                    } else {
                        AxisMarks(values: .automatic(desiredCount: 5)) {
                            AxisGridLine()
                            AxisTick()
                            if granularity == .month {
                                AxisValueLabel(format: .dateTime.month(.abbreviated))
                            } else {
                                AxisValueLabel(format: .dateTime.month().day())
                            }
                        }
                    }
                }
                .frame(height: 240)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func chartUnit(for granularity: BucketGranularity) -> Calendar.Component {
        switch granularity {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        case .quarter: return .month
        }
    }

    // MARK: - Range + Bucketing

    private func resolvedRange(for period: Period) -> (start: Date, end: Date, granularity: BucketGranularity) {
        let calendar = Calendar.current
        let now = Date()

        switch period {
        case .period:
            let days = max(1, calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
            if days <= 45 {
                return (startDate, endDate, .day)
            }
            return (startDate, endDate, .week)

        case .oneWeek:
            let interval = calendar.dateInterval(of: .weekOfYear, for: now)
            let start = interval?.start ?? startOfWeek(containing: now)
            let end = calendar.date(byAdding: DateComponents(day: 6), to: start) ?? now
            return (startOfDay(start), endOfDay(end), .day)

        case .oneMonth:
            let interval = calendar.dateInterval(of: .month, for: now)
            let start = interval?.start ?? startOfMonth(containing: now)
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
            return (startOfDay(start), endOfDay(end), .day)

        case .oneYear:
            let interval = calendar.dateInterval(of: .year, for: now)
            let start = interval?.start ?? startOfMonth(containing: now)
            let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? now
            return (startOfDay(start), endOfDay(end), .month)

        case .q:
            let interval = calendar.dateInterval(of: .year, for: now)
            let start = interval?.start ?? startOfMonth(containing: now)
            let end = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? now
            return (startOfDay(start), endOfDay(end), .quarter)
        }
    }

    private func buildChartPoints(for range: (start: Date, end: Date, granularity: BucketGranularity)) -> [IncomeBarPoint] {
        let buckets = makeBuckets(from: range.start, to: range.end, granularity: range.granularity)
        guard !buckets.isEmpty else { return [] }

        var points: [IncomeBarPoint] = []
        points.reserveCapacity(buckets.count * 2)

        for bucket in buckets {
            let planned = sum(isPlanned: true, from: bucket.start, to: bucket.end)
            let actual = sum(isPlanned: false, from: bucket.start, to: bucket.end)

            points.append(IncomeBarPoint(date: bucket.start, kind: String(localized: "common.planned", defaultValue: "Planned", comment: "Common label for planned values."), amount: planned))
            points.append(IncomeBarPoint(date: bucket.start, kind: String(localized: "common.actual", defaultValue: "Actual", comment: "Common label for actual values."), amount: actual))
        }

        if points.allSatisfy({ $0.amount == 0 }) {
            return []
        }

        return points
    }

    private func makeBuckets(from start: Date, to end: Date, granularity: BucketGranularity) -> [(start: Date, end: Date)] {
        let calendar = Calendar.current
        var buckets: [(start: Date, end: Date)] = []

        var current: Date
        switch granularity {
        case .day:
            current = startOfDay(start)
        case .week:
            current = startOfWeek(containing: start)
        case .month:
            current = startOfMonth(containing: start)
        case .quarter:
            current = startOfQuarter(containing: start)
        }

        while current <= end {
            let next: Date
            switch granularity {
            case .day:
                next = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            case .week:
                next = calendar.date(byAdding: .day, value: 7, to: current) ?? current
            case .month:
                next = calendar.date(byAdding: .month, value: 1, to: current) ?? current
            case .quarter:
                next = calendar.date(byAdding: .month, value: 3, to: current) ?? current
            }

            let bucketEnd = min(endOfDay(calendar.date(byAdding: .second, value: -1, to: next) ?? current), end)
            let bucketStart = max(current, start)
            buckets.append((start: bucketStart, end: bucketEnd))

            current = next
        }

        return buckets
    }

    // MARK: - Summation

    private func sum(isPlanned: Bool, from start: Date, to end: Date) -> Double {
        incomes
            .filter { $0.isPlanned == isPlanned }
            .filter { $0.date >= start && $0.date <= end }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - Date Helpers

    private func formattedDate(_ date: Date) -> String {
        AppDateFormat.abbreviatedDate(date)
    }

    private func quarterLabel(for date: Date) -> String {
        let month = Calendar.current.component(.month, from: date)
        let quarter = ((month - 1) / 3) + 1
        return "Q\(quarter)"
    }

    private func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func endOfDay(_ date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private func startOfWeek(containing date: Date) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysFromStart = (weekday - calendar.firstWeekday + 7) % 7
        return calendar.date(byAdding: .day, value: -daysFromStart, to: startOfDay) ?? startOfDay
    }

    private func startOfMonth(containing date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    private func startOfQuarter(containing date: Date) -> Date {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        return calendar.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1)) ?? date
    }
}

#Preview("Income Metrics") {
    let container = PreviewSeed.makeContainer()

    PreviewHost(container: container) { ws in
        NavigationStack {
            HomeIncomeMetricsView(
                workspace: ws,
                incomes: [],
                startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31)) ?? .now,
                initialPeriod: .period
            )
        }
    }
}
