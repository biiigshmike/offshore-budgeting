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
        case q = "Q"

        var id: String { rawValue }
    }

    private enum BucketGranularity {
        case day
        case week
        case month
        case quarter
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
    let savingsEntries: [SavingsLedgerEntry]
    let startDate: Date
    let endDate: Date
    let initialPeriod: Period

    @State private var selectedPeriod: Period

    init(
        workspace: Workspace,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        savingsEntries: [SavingsLedgerEntry],
        startDate: Date,
        endDate: Date,
        initialPeriod: Period = .period
    ) {
        self.workspace = workspace
        self.incomes = incomes
        self.plannedExpenses = plannedExpenses
        self.variableExpenses = variableExpenses
        self.savingsEntries = savingsEntries
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

                if #available(iOS 26.0, macCatalyst 26.0, *) {
                    Button {
                        routeToAccountsSavings()
                    } label: {
                        openSavingsAccountLabel
                    }
                    .glassProminentButtonStyleCompat()
                    .tint(Color("AccentColor"))
                } else {
                    Button {
                        routeToAccountsSavings()
                    } label: {
                        openSavingsAccountLabel
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color("AccentColor"))
                }

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
                    Text(String(localized: "homeWidget.savingsOutlook", defaultValue: "Savings Outlook", comment: "Pinned home widget title for savings outlook."))
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
                summaryMetric(title: String(localized: "homeSavingsOutlook.projected", defaultValue: "Projected", comment: "Short label for projected value."), value: projectedTotal)

                Spacer(minLength: 0)

                summaryMetric(title: String(localized: "homeSavingsOutlook.actual", defaultValue: "Actual", comment: "Short label for actual value."), value: actualTotal)
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

    private var openSavingsAccountLabel: some View {
        HStack {
            Text(String(localized: "homeSavingsOutlook.openSavingsAccount", defaultValue: "Open Savings Account", comment: "Button title to open savings account screen."))
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func routeToAccountsSavings() {
        UserDefaults.standard.set(
            AppShortcutNavigationStore.PendingAccountsSegment.savings.rawValue,
            forKey: AppShortcutNavigationStore.pendingAccountsSegmentKey
        )
        UserDefaults.standard.set(
            AppSection.cards.rawValue,
            forKey: AppShortcutNavigationStore.pendingSectionKey
        )
    }

    // MARK: - Picker

    private var periodPicker: some View {
        Picker(String(localized: "common.period", defaultValue: "Period", comment: "Label for period picker."), selection: $selectedPeriod) {
            ForEach(Period.allCases) { p in
                Text(p.rawValue).tag(p)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(String(localized: "common.period", defaultValue: "Period", comment: "Label for period picker."))
    }

    // MARK: - Chart

    private func chartCard(points: [SavingsPoint], granularity: BucketGranularity, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "homeSavingsOutlook.trends", defaultValue: "Trends", comment: "Section title for savings outlook trend chart."))
                .font(.headline.weight(.semibold))

            if points.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "homeSavingsOutlook.noData", defaultValue: "No savings data found in this range.", comment: "Message shown when no savings data is available for the selected period."))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
                .padding(.vertical, 18)
            } else {
                let quarterAxisDates = Array(Set(points.map(\.date))).sorted()

                Chart(points) { point in
                    RuleMark(y: .value("Baseline", 0))
                        .foregroundStyle(.secondary.opacity(0.35))

                    BarMark(
                        x: .value("Date", point.date, unit: chartUnit(for: granularity)),
                        y: .value("Actual", point.actualRunning)
                    )
                    .foregroundStyle(point.actualRunning >= 0 ? Color.green.opacity(0.85) : Color.red.opacity(0.85))

                    HomeFinancialLineMark(
                        x: .value("Date", point.date, unit: chartUnit(for: granularity)),
                        y: .value("Projected", point.projectedRunning),
                        series: "Projected",
                        dash: [6, 4]
                    )
                    .foregroundStyle(accent.opacity(0.75))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                        AxisTick()
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

    private func buildChartPoints(for range: (start: Date, end: Date, granularity: BucketGranularity)) -> [SavingsPoint] {
        let ranges = makeBuckets(from: range.start, to: range.end, granularity: range.granularity)
            .map { SavingsOutlookDateRange(startDate: $0.start, endDate: $0.end) }
        let points = SavingsOutlookCalculator.cumulativePoints(ranges: ranges, incomes: incomes,
            plannedExpenses: plannedExpenses, variableExpenses: variableExpenses, savingsEntries: savingsEntries)
            .map { SavingsPoint(date: $0.startDate, actualRunning: $0.actual, projectedRunning: $0.projected) }
        return points.allSatisfy { $0.actualRunning == 0 && $0.projectedRunning == 0 } ? [] : points
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

    // MARK: - Totals

    private func projectedSavingsTotal(from start: Date, to end: Date) -> Double {
        outlook(from: start, to: end).projected
    }

    private func actualSavingsTotal(from start: Date, to end: Date) -> Double {
        outlook(from: start, to: end).actual
    }

    private func outlook(from start: Date, to end: Date) -> SavingsOutlookCalculator.Summary {
        SavingsOutlookCalculator.totals(incomes: incomes, plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses, savingsEntries: savingsEntries,
            startDate: start, endDate: end)
    }

    private func progressSummary(projected: Double, actual: Double) -> (lineText: String, percentText: String) {
        let progress = SavingsOutlookCalculator.progress(projected: projected, actual: actual)
        switch progress.mode {
        case .projection: return ("Progress: \(progress.formatted) of projection", progress.formatted)
        case .breakEven: return ("Progress: \(progress.formatted) toward break-even", progress.formatted)
        case .unavailable: return ("Progress: —", "—")
        }
    }

    private func accentColor(for projected: Double) -> Color {
        if projected == 0 { return .secondary }
        return projected > 0 ? .green : .red
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

#Preview("Savings Outlook Metrics") {
    let container = PreviewSeed.makeContainer()

    PreviewHost(container: container) { ws in
        NavigationStack {
            HomeSavingsOutlookMetricsView(
                workspace: ws,
                incomes: ws.incomes ?? [],
                plannedExpenses: ws.plannedExpenses ?? [],
                variableExpenses: ws.variableExpenses ?? [],
                savingsEntries: (ws.savingsAccounts ?? []).flatMap { $0.entries ?? [] },
                startDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .now,
                endDate: Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31)) ?? .now,
                initialPeriod: .period
            )
        }
    }
}
