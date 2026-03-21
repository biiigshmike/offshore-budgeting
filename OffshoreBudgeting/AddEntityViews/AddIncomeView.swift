//
//  AddIncomeView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct AddIncomeView: View {

    let workspace: Workspace
    let initialDate: Date
    let initialIsPlanned: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var source: String = ""
    @State private var amountText: String = ""
    @State private var date: Date
    @State private var isPlanned: Bool = false

    // Repeat (series fields)
    @State private var frequencyRaw: String = RecurrenceFrequency.none.rawValue
    @State private var interval: Int = 1
    @State private var weeklyWeekday: Int = 6
    @State private var monthlyDayOfMonth: Int = 15
    @State private var monthlyIsLastDay: Bool = false
    @State private var yearlyMonth: Int = 1
    @State private var yearlyDayOfMonth: Int = 15
    @State private var endDate: Date? = nil

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingInvalidRepeatAlert: Bool = false

    init(workspace: Workspace, initialDate: Date, initialIsPlanned: Bool = false) {
        self.workspace = workspace
        self.initialDate = initialDate
        self.initialIsPlanned = initialIsPlanned
        _date = State(initialValue: initialDate)
        _isPlanned = State(initialValue: initialIsPlanned)
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
            endDate: $endDate
        )
        .navigationTitle("Add Income")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Cancel")
            }
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { saveAndAdd() } label: {
                        Image(systemName: "checkmark.arrow.trianglehead.clockwise")
                    }
                    .accessibilityLabel("Save & Add")
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .buttonStyle(.plain)
                }

                ToolbarSpacer(.flexible, placement: .primaryAction)

                ToolbarItemGroup(placement: .primaryAction) {
                    Button { save() } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Save")
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .buttonStyle(.glassProminent)
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button { saveAndAdd() } label: {
                        Image(systemName: "checkmark.arrow.trianglehead.clockwise")
                    }
                    .accessibilityLabel("Save & Add")
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button { save() } label: {
                        Image(systemName: "checkmark")
                    }
                    .accessibilityLabel("Save")
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }
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
        .onAppear {
            guard DebugScreenshotFormDefaults.isEnabled else { return }

            if trimmedSource.isEmpty {
                source = DebugScreenshotFormDefaults.incomeSource
            }

            let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedAmount.isEmpty {
                amountText = DebugScreenshotFormDefaults.incomeAmountText
            }
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

    private var canSave: Bool {
        guard !trimmedSource.isEmpty else { return false }
        guard let amt = parsedAmount, amt > 0 else { return false }

        if frequency != .none {
            guard let endDate else { return false }
            if Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: date) { return false }
        }

        return true
    }

    // MARK: - Save

    private func save() {
        guard persistIncome() else { return }
        dismiss()
    }

    private func saveAndAdd() {
        guard persistIncome() else { return }
        resetForm()
    }

    @discardableResult
    private func persistIncome() -> Bool {
        guard let amt = parsedAmount, amt > 0 else {
            showingInvalidAmountAlert = true
            return false
        }

        // One-off
        if frequency == .none {
            let income = Income(
                source: trimmedSource,
                amount: amt,
                date: Calendar.current.startOfDay(for: date),
                isPlanned: isPlanned,
                isException: false,
                workspace: workspace,
                series: nil
            )
            modelContext.insert(income)
            return true
        }

        // Series (Option 2 requires end date)
        guard let endDate else {
            showingInvalidRepeatAlert = true
            return false
        }

        let startDay = Calendar.current.startOfDay(for: date)
        let endDay = Calendar.current.startOfDay(for: endDate)
        guard endDay >= startDay else {
            showingInvalidRepeatAlert = true
            return false
        }

        let series = IncomeSeries(
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

        modelContext.insert(series)

        let occurrenceDays = IncomeScheduleEngine.occurrences(for: series)
        for occDay in occurrenceDays {
            let income = Income(
                source: series.source,
                amount: series.amount,
                date: Calendar.current.startOfDay(for: occDay),
                isPlanned: series.isPlanned,
                isException: false,
                workspace: workspace,
                series: series
            )
            modelContext.insert(income)
        }
        return true
    }

    private func resetForm() {
        source = ""
        amountText = ""
        date = initialDate
        isPlanned = initialIsPlanned
        frequencyRaw = RecurrenceFrequency.none.rawValue
        interval = 1
        weeklyWeekday = 6
        monthlyDayOfMonth = 15
        monthlyIsLastDay = false
        yearlyMonth = 1
        yearlyDayOfMonth = 15
        endDate = nil

        guard DebugScreenshotFormDefaults.isEnabled else { return }

        source = DebugScreenshotFormDefaults.incomeSource
        amountText = DebugScreenshotFormDefaults.incomeAmountText
    }
}
