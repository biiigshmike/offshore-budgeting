//
//  HomeSavingsOutlookMetricsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import SwiftUI
import Charts

struct HomeSavingsOutlookMetricsView: View {

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

    private struct SavingsPoint: Identifiable {
        let id = UUID()
        let date: Date
        let actualRunning: Double
        let projectedRunning: Double
    }

    let workspace: Workspace
    let incomes: [Income]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date
    let initialPeriod: Period

    @State private var selectedPeriod: Period

    init(
        workspace: Workspace,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        startDate: Date,
        endDate: Date,
        initialPeriod: Period = .period
    ) {
        self.workspace = workspace
        self.incomes = incomes
        self.plannedExpenses = plannedExpenses
        self.variableExpenses = variableExpenses
        self.startDate = startDate
        self.endDate = endDate
        self.initialPeriod = initialPeriod
        _selectedPeriod = State(initialValue: initialPeriod)
    }

    var body: some View {
        let resolved = resolvedRange(for: selectedPeriod)

        let projectedTotal = projectedSavingsTotal(from: resolved.start, to: resolved.end)
        let actualTotal = actualSavingsTotal(from: resolved.start, to: resolved.end)

        let progressInfo = progressSummary(projected: projectedTotal, actual: actualTotal)
        let accent = accentColor(for: projectedTotal)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                headerSummary(
                    projectedTotal: projectedTotal,
                    actualTotal: actualTotal,
                    progressLine: progressInfo.lineText
                )

                periodPicker

                chartCard(
                    points: buildChartPoints(for: resolved),
                    granularity: resolved.granularity,
                    accent: accent
                )

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("") // we render a custom title + subtitle in the navigation area
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("Savings Outlook")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text("\(formattedDate(resolved.start)) - \(formattedDate(resolved.end))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Header

    private func headerSummary(
        projectedTotal: Double,
        actualTotal: Double,
        progressLine: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                summaryMetric(title: "Projected", value: projectedTotal)

                Spacer(minLength: 0)

                summaryMetric(title: "Actual", value: actualTotal)
            }

            Text(progressLine)
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

    private func chartCard(points: [SavingsPoint], granularity: BucketGranularity, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Trends")
                .font(.headline.weight(.semibold))

            if points.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No savings data in this range.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
                .padding(.vertical, 18)
            } else {
                Chart(points) { point in
                    RuleMark(y: .value("Baseline", 0))
                        .foregroundStyle(.secondary.opacity(0.35))

                    BarMark(
                        x: .value("Date", point.date, unit: chartUnit(for: granularity)),
                        y: .value("Actual", point.actualRunning)
                    )
                    .foregroundStyle(point.actualRunning >= 0 ? Color.green.opacity(0.85) : Color.red.opacity(0.85))

                    LineMark(
                        x: .value("Date", point.date, unit: chartUnit(for: granularity)),
                        y: .value("Projected", point.projectedRunning)
                    )
                    .foregroundStyle(accent.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: CurrencyFormatter.currencyStyle())
                    }
                }
                .chartXAxis {
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

    private func buildChartPoints(for range: (start: Date, end: Date, granularity: BucketGranularity)) -> [SavingsPoint] {
        let buckets = makeBuckets(from: range.start, to: range.end, granularity: range.granularity)
        guard !buckets.isEmpty else { return [] }

        var points: [SavingsPoint] = []
        points.reserveCapacity(buckets.count)

        var projectedRunning: Double = 0
        var actualRunning: Double = 0

        for bucket in buckets {
            // Event-based projection deltas
            let plannedIncomeDelta = sumPlannedIncome(from: bucket.start, to: bucket.end)
            let plannedExpensePlannedDelta = sumPlannedExpensesPlanned(from: bucket.start, to: bucket.end)

            let projectedDelta = plannedIncomeDelta - plannedExpensePlannedDelta
            projectedRunning += projectedDelta

            let actualIncomeDelta = sumActualIncome(from: bucket.start, to: bucket.end)
            let plannedExpenseEffectiveActualDelta = sumPlannedExpensesEffectiveActual(from: bucket.start, to: bucket.end)
            let variableExpenseDelta = sumVariableExpenses(from: bucket.start, to: bucket.end)

            let actualDelta = actualIncomeDelta - (plannedExpenseEffectiveActualDelta + variableExpenseDelta)
            actualRunning += actualDelta

            points.append(
                SavingsPoint(
                    date: bucket.start,
                    actualRunning: actualRunning,
                    projectedRunning: projectedRunning
                )
            )
        }

        if points.allSatisfy({ $0.actualRunning == 0 && $0.projectedRunning == 0 }) {
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

    // MARK: - Totals

    private func projectedSavingsTotal(from start: Date, to end: Date) -> Double {
        sumPlannedIncome(from: start, to: end) - sumPlannedExpensesPlanned(from: start, to: end)
    }

    private func actualSavingsTotal(from start: Date, to end: Date) -> Double {
        let actualIncome = sumActualIncome(from: start, to: end)
        let plannedEffective = sumPlannedExpensesEffectiveActual(from: start, to: end)
        let variableTotal = sumVariableExpenses(from: start, to: end)
        return actualIncome - (plannedEffective + variableTotal)
    }

    // MARK: - Summation

    private func sumPlannedIncome(from start: Date, to end: Date) -> Double {
        incomes
            .filter { $0.isPlanned }
            .filter { $0.date >= start && $0.date <= end }
            .reduce(0) { $0 + $1.amount }
    }

    private func sumActualIncome(from start: Date, to end: Date) -> Double {
        incomes
            .filter { !$0.isPlanned }
            .filter { $0.date >= start && $0.date <= end }
            .reduce(0) { $0 + $1.amount }
    }

    private func sumPlannedExpensesPlanned(from start: Date, to end: Date) -> Double {
        plannedExpenses
            .filter { $0.expenseDate >= start && $0.expenseDate <= end }
            .reduce(0) { $0 + $1.plannedAmount }
    }

    private func sumPlannedExpensesEffectiveActual(from start: Date, to end: Date) -> Double {
        plannedExpenses
            .filter { $0.expenseDate >= start && $0.expenseDate <= end }
            .reduce(0) { $0 + effectivePlannedExpenseAmount($1) }
    }

    private func sumVariableExpenses(from start: Date, to end: Date) -> Double {
        variableExpenses
            .filter { $0.transactionDate >= start && $0.transactionDate <= end }
            .reduce(0) { $0 + $1.amount }
    }

    private func effectivePlannedExpenseAmount(_ expense: PlannedExpense) -> Double {
        // Planned by default, unless edited, then actualAmount is used.
        return expense.actualAmount > 0 ? expense.actualAmount : expense.plannedAmount
    }

    // MARK: - Progress Summary

    private func progressSummary(projected: Double, actual: Double) -> (lineText: String, percentText: String) {
        guard projected != 0 else {
            return (lineText: "Progress: —", percentText: "—")
        }

        if projected > 0 {
            let ratio = max(0, actual / projected)
            let pct = Int((ratio * 100).rounded())
            return (lineText: "Progress: \(pct)% of projection", percentText: "\(pct)%")
        }

        // Negative projection mode, progress toward break-even (0).
        let progressToBreakeven = max(0, (actual - projected) / abs(projected))
        let pct = Int((progressToBreakeven * 100).rounded())
        return (lineText: "Progress: \(pct)% toward break-even", percentText: "\(pct)%")
    }

    private func accentColor(for projected: Double) -> Color {
        if projected == 0 { return .secondary }
        return projected > 0 ? .green : .red
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

#Preview("Savings Outlook Metrics") {
    let container = PreviewSeed.makeContainer()

    PreviewHost(container: container) { ws in
        NavigationStack {
            HomeSavingsOutlookMetricsView(
                workspace: ws,
                incomes: ws.incomes ?? [],
                plannedExpenses: ws.plannedExpenses ?? [],
                variableExpenses: ws.variableExpenses ?? [],
                startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31)) ?? .now,
                initialPeriod: .period
            )
        }
    }
}
