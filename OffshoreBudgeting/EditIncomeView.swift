//
//  EditIncomeView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct EditIncomeView: View {

    let workspace: Workspace
    let income: Income

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var source: String
    @State private var amountText: String
    @State private var date: Date
    @State private var isPlanned: Bool

    // Repeat fields (these represent either a new series to create, or edits to an existing series)
    @State private var frequencyRaw: String
    @State private var interval: Int
    @State private var weeklyWeekday: Int
    @State private var monthlyDayOfMonth: Int
    @State private var monthlyIsLastDay: Bool
    @State private var yearlyMonth: Int
    @State private var yearlyDayOfMonth: Int
    @State private var endDate: Date?

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingInvalidRepeatAlert: Bool = false

    @State private var showingSeriesApplyDialog: Bool = false

    init(workspace: Workspace, income: Income) {
        self.workspace = workspace
        self.income = income

        _source = State(initialValue: income.source)
        _amountText = State(initialValue: CurrencyFormatter.editingString(from: income.amount))
        _date = State(initialValue: income.date)
        _isPlanned = State(initialValue: income.isPlanned)

        if let series = income.series {
            _frequencyRaw = State(initialValue: series.frequencyRaw)
            _interval = State(initialValue: max(1, series.interval))
            _weeklyWeekday = State(initialValue: series.weeklyWeekday)
            _monthlyDayOfMonth = State(initialValue: series.monthlyDayOfMonth)
            _monthlyIsLastDay = State(initialValue: series.monthlyIsLastDay)
            _yearlyMonth = State(initialValue: series.yearlyMonth)
            _yearlyDayOfMonth = State(initialValue: series.yearlyDayOfMonth)
            _endDate = State(initialValue: series.endDate)
        } else {
            _frequencyRaw = State(initialValue: RecurrenceFrequency.none.rawValue)
            _interval = State(initialValue: 1)
            _weeklyWeekday = State(initialValue: 6)
            _monthlyDayOfMonth = State(initialValue: 15)
            _monthlyIsLastDay = State(initialValue: false)
            _yearlyMonth = State(initialValue: 1)
            _yearlyDayOfMonth = State(initialValue: 15)
            _endDate = State(initialValue: nil)
        }
    }

    var body: some View {
        IncomeFormView(
            detailsTitle: "Details",
            source: $source,
            amountText: $amountText,
            date: $date,
            isPlanned: $isPlanned,
            frequencyRaw: $frequencyRaw,
            interval: $interval,
            weeklyWeekday: $weeklyWeekday,
            monthlyDayOfMonth: $monthlyDayOfMonth,
            monthlyIsLastDay: $monthlyIsLastDay,
            yearlyMonth: $yearlyMonth,
            yearlyDayOfMonth: $yearlyDayOfMonth,
            endDate: $endDate,
            footerText: "Editing income inside “\(workspace.name)”."
        )
        .navigationTitle("Edit Income")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Update") { onTapUpdate() }
                    .disabled(!canSave)
            }
        }
        .alert("Invalid Amount", isPresented: $showingInvalidAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter a valid amount greater than 0.")
        }
        .alert("Repeat Requires an End Date", isPresented: $showingInvalidRepeatAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("When Repeat is set, you must also set an End Date (and it cannot be before the start date).")
        }
        .confirmationDialog(
            "Apply changes to…",
            isPresented: $showingSeriesApplyDialog,
            titleVisibility: .visible
        ) {
            Button("Just This Income") { applyJustThis() }
            Button("This and Future") { applyThisAndFuture() }
            Button("All in Series") { applyAllInSeries() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This income is part of a repeating series.")
        }
    }

    // MARK: - Validation

    private var trimmedSource: String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var parsedAmount: Double? {
        return CurrencyFormatter.parseAmount(amountText)
    }

    private var frequency: RecurrenceFrequency {
        RecurrenceFrequency(rawValue: frequencyRaw) ?? .none
    }

    private var startDay: Date {
        Calendar.current.startOfDay(for: date)
    }

    private var endDay: Date? {
        endDate.map { Calendar.current.startOfDay(for: $0) }
    }

    private var canSave: Bool {
        guard !trimmedSource.isEmpty else { return false }
        guard let amt = parsedAmount, amt > 0 else { return false }

        if frequency != .none {
            guard let endDay else { return false }
            if endDay < startDay { return false }
        }

        return true
    }

    // MARK: - Update flow

    private func onTapUpdate() {
        guard let _ = parsedAmount else {
            showingInvalidAmountAlert = true
            return
        }

        if frequency != .none && endDate == nil {
            showingInvalidRepeatAlert = true
            return
        }

        if income.series != nil {
            showingSeriesApplyDialog = true
        } else {
            applyNonSeriesUpdateOrConvert()
        }
    }

    // MARK: - Apply: Non-series

    private func applyNonSeriesUpdateOrConvert() {
        guard let amt = parsedAmount, amt > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        // If user set Repeat, convert this single income into a new series (and replace it).
        if frequency != .none {
            guard let endDay else {
                showingInvalidRepeatAlert = true
                return
            }

            let newSeries = IncomeSeries(
                source: trimmedSource,
                amount: amt,
                isPlanned: isPlanned,
                frequencyRaw: frequencyRaw,
                interval: interval,
                weeklyWeekday: weeklyWeekday,
                monthlyDayOfMonth: monthlyDayOfMonth,
                monthlyIsLastDay: monthlyIsLastDay,
                yearlyMonth: yearlyMonth,
                yearlyDayOfMonth: yearlyDayOfMonth,
                startDate: startDay,
                endDate: endDay,
                workspace: workspace
            )

            modelContext.insert(newSeries)

            let occurrences = IncomeScheduleEngine.occurrences(for: newSeries)
            for occ in occurrences {
                let created = Income(
                    source: newSeries.source,
                    amount: newSeries.amount,
                    date: Calendar.current.startOfDay(for: occ),
                    isPlanned: newSeries.isPlanned,
                    isException: false,
                    workspace: workspace,
                    series: newSeries
                )
                modelContext.insert(created)
            }

            // Remove the original one-off
            modelContext.delete(income)

            dismiss()
            return
        }

        // Otherwise, normal one-off edit.
        income.source = trimmedSource
        income.amount = amt
        income.date = startDay
        income.isPlanned = isPlanned

        dismiss()
    }

    // MARK: - Apply: Series choices

    private func applyJustThis() {
        guard let amt = parsedAmount, amt > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        income.source = trimmedSource
        income.amount = amt
        income.date = startDay
        income.isPlanned = isPlanned

        income.isException = true

        dismiss()
    }

    private func applyAllInSeries() {
        guard let series = income.series else {
            applyNonSeriesUpdateOrConvert()
            return
        }
        guard let amt = parsedAmount, amt > 0 else {
            showingInvalidAmountAlert = true
            return
        }
        guard let endDay else {
            showingInvalidRepeatAlert = true
            return
        }

        // Update series defaults/rule
        series.source = trimmedSource
        series.amount = amt
        series.isPlanned = isPlanned

        series.frequencyRaw = frequencyRaw
        series.interval = max(1, interval)
        series.weeklyWeekday = min(7, max(1, weeklyWeekday))
        series.monthlyDayOfMonth = min(31, max(1, monthlyDayOfMonth))
        series.monthlyIsLastDay = monthlyIsLastDay
        series.yearlyMonth = min(12, max(1, yearlyMonth))
        series.yearlyDayOfMonth = min(31, max(1, yearlyDayOfMonth))

        // Start stays as-is to preserve the historical anchor.
        series.endDate = endDay

        regenerateSeries(series, preserveExceptions: true)

        dismiss()
    }

    private func applyThisAndFuture() {
        guard let series = income.series else {
            applyNonSeriesUpdateOrConvert()
            return
        }
        guard let amt = parsedAmount, amt > 0 else {
            showingInvalidAmountAlert = true
            return
        }
        guard let endDay else {
            showingInvalidRepeatAlert = true
            return
        }

        let splitDay = startDay
        let originalSeriesEnd = Calendar.current.startOfDay(for: series.endDate)

        // If split day is after original end, treat as "just this" (nothing future exists).
        if splitDay > originalSeriesEnd {
            applyJustThis()
            return
        }

        // 1) Shorten existing (past) series to end the day before split
        if let dayBeforeSplit = Calendar.current.date(byAdding: .day, value: -1, to: splitDay) {
            let pastEnd = Calendar.current.startOfDay(for: dayBeforeSplit)
            if pastEnd >= Calendar.current.startOfDay(for: series.startDate) {
                series.endDate = pastEnd
            } else {
                // Past series would become invalid, so just convert to "future-only" by keeping start=end=split?
                series.endDate = Calendar.current.startOfDay(for: series.startDate)
            }
        }

        // 2) Create a new series for split...originalEnd with the edited settings
        let futureSeries = IncomeSeries(
            source: trimmedSource,
            amount: amt,
            isPlanned: isPlanned,
            frequencyRaw: frequencyRaw,
            interval: interval,
            weeklyWeekday: weeklyWeekday,
            monthlyDayOfMonth: monthlyDayOfMonth,
            monthlyIsLastDay: monthlyIsLastDay,
            yearlyMonth: yearlyMonth,
            yearlyDayOfMonth: yearlyDayOfMonth,
            startDate: splitDay,
            endDate: endDay,
            workspace: workspace
        )

        modelContext.insert(futureSeries)

        // 3) Move existing exceptions in the future range to the new series, delete non-exceptions
        let oldIncomes = series.incomes ?? []
        for item in oldIncomes {
            let itemDay = Calendar.current.startOfDay(for: item.date)
            guard itemDay >= splitDay else { continue }

            if item.isException {
                item.series = futureSeries
            } else {
                modelContext.delete(item)
            }
        }

        // 4) Regenerate both series, preserving exceptions
        regenerateSeries(series, preserveExceptions: true)
        regenerateSeries(futureSeries, preserveExceptions: true)

        dismiss()
    }

    // MARK: - Regeneration

    private func regenerateSeries(_ series: IncomeSeries, preserveExceptions: Bool) {
        let cal = Calendar.current
        let start = cal.startOfDay(for: series.startDate)
        let end = cal.startOfDay(for: series.endDate)
        guard end >= start else { return }

        // Map exception days so we do not overwrite user edits
        var exceptionDays = Set<Date>()
        if preserveExceptions {
            for item in (series.incomes ?? []) where item.isException {
                exceptionDays.insert(cal.startOfDay(for: item.date))
            }
        }

        // Delete non-exception incomes
        for item in series.incomes ?? [] {
            if preserveExceptions && item.isException { continue }
            modelContext.delete(item)
        }

        // Recreate occurrences, skipping exception days
        let occurrences = IncomeScheduleEngine.occurrences(for: series)
        for occ in occurrences {
            let occDay = cal.startOfDay(for: occ)
            if preserveExceptions && exceptionDays.contains(occDay) {
                continue
            }

            let created = Income(
                source: series.source,
                amount: series.amount,
                date: occDay,
                isPlanned: series.isPlanned,
                isException: false,
                workspace: series.workspace,
                series: series
            )
            modelContext.insert(created)
        }
    }

}
