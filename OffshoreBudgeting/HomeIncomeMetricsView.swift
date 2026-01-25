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
        case q1 = "Q1"
        case q2 = "Q2"
        case q3 = "Q3"
        case q4 = "Q4"

        var id: String { rawValue }
    }

    private enum BucketGranularity {
        case day
        case week
        case month
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
            return "\(Int((ratio * 100).rounded()))%"
        }()

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                headerSummary(
                    rangeSubtitle: "\(formattedDate(resolved.start)) - \(formattedDate(resolved.end))",
                    actualTotal: actualTotal,
                    plannedTotal: plannedTotal,
                    percentText: percentText
                )

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
        .navigationTitle("Income")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    private func headerSummary(
        rangeSubtitle: String,
        actualTotal: Double,
        plannedTotal: Double,
        percentText: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(rangeSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                summaryMetric(title: "Actual", value: actualTotal)

                Spacer(minLength: 0)

                summaryMetric(title: "Planned", value: plannedTotal)
            }

            Text("Progress: \(percentText)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private func summaryMetric(title: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(value, format: CurrencyFormatter.currencyStyle())
                .font(.title3.weight(.semibold))
        }
    }

    // MARK: - Picker

    private var periodPicker: some View {
        Picker("Period", selection: $selectedPeriod) {
            ForEach(Period.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Period")
    }

    // MARK: - Chart

    private func chartCard(points: [IncomeBarPoint], granularity: BucketGranularity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trends")
                .font(.headline.weight(.semibold))

            if points.isEmpty {
                Text("No income data in this range.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 18)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Date", point.date, unit: chartUnit(for: granularity)),
                        y: .value("Amount", point.amount)
                    )
                    .foregroundStyle(by: .value("Type", point.kind))
                    .position(by: .value("Type", point.kind))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                        AxisTick()

                        // ✅ Stable: format-based axis labels (no closure overload weirdness)
                        AxisValueLabel(format: CurrencyFormatter.currencyStyle())
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine()
                        AxisTick()

                        // ✅ Stable: format-based date labels, based on granularity
                        if granularity == .month {
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                        } else {
                            AxisValueLabel(format: .dateTime.month().day())
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
        }
    }

    // MARK: - Range + Bucketing

    private func resolvedRange(for period: Period) -> (start: Date, end: Date, granularity: BucketGranularity) {
        let calendar = Calendar.current
        let anchorEnd = endDate

        switch period {
        case .period:
            let days = max(1, calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1)
            if days <= 45 {
                return (startDate, endDate, .day)
            }
            return (startDate, endDate, .week)

        case .oneWeek:
            let start = calendar.date(byAdding: .day, value: -6, to: anchorEnd) ?? anchorEnd
            return (startOfDay(start), endOfDay(anchorEnd), .day)

        case .oneMonth:
            let start = calendar.date(byAdding: .day, value: -29, to: anchorEnd) ?? anchorEnd
            return (startOfDay(start), endOfDay(anchorEnd), .day)

        case .oneYear:
            let start = calendar.date(byAdding: .month, value: -11, to: anchorEnd) ?? anchorEnd
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
            return (monthStart, endOfDay(anchorEnd), .month)

        case .q1, .q2, .q3, .q4:
            let year = calendar.component(.year, from: anchorEnd)
            let quarterIndex: Int = {
                switch period {
                case .q1: return 0
                case .q2: return 1
                case .q3: return 2
                case .q4: return 3
                default: return 0
                }
            }()

            let startMonth = (quarterIndex * 3) + 1
            let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? anchorEnd
            let endMonth = startMonth + 2
            let endStart = calendar.date(from: DateComponents(year: year, month: endMonth, day: 1)) ?? anchorEnd
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: endStart) ?? anchorEnd
            return (startOfDay(start), endOfDay(end), .month)
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

            points.append(IncomeBarPoint(date: bucket.start, kind: "Planned", amount: planned))
            points.append(IncomeBarPoint(date: bucket.start, kind: "Actual", amount: actual))
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
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
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
