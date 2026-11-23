//
//  AddIncomeView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct AddIncomeView: View {

    private struct ExistingIncomeSelection: Identifiable {
        let id = UUID()
        let incomes: [Income]
    }

    let workspace: Workspace
    private let plannedIncome: Income?
    private let canUseExistingIncome: Bool
    private var isRecordingReceipt: Bool { plannedIncome != nil }

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
    @State private var showingPossibleDuplicate = false
    @State private var duplicateDetails = ""
    @State private var showingReceiptSaveError = false
    @State private var receiptValidationError: TransactionEntryService.ValidationError?
    @State private var isSavingReceipt = false
    @State private var existingIncomeSelection: ExistingIncomeSelection?
    @State private var didLinkExistingIncome = false

    init(workspace: Workspace, initialDate: Date, initialIsPlanned: Bool = false) {
        self.workspace = workspace
        plannedIncome = nil
        canUseExistingIncome = false
        _date = State(initialValue: initialDate)
        _isPlanned = State(initialValue: initialIsPlanned)
    }

    init(workspace: Workspace, plannedIncome: Income, canUseExistingIncome: Bool) {
        self.workspace = workspace
        self.plannedIncome = plannedIncome
        self.canUseExistingIncome = canUseExistingIncome
        _source = State(initialValue: plannedIncome.source)
        _amountText = State(initialValue: CurrencyFormatter.editingString(from: plannedIncome.amount))
        _date = State(initialValue: Calendar.current.startOfDay(for: .now))
    }

    private var incomeForm: some View {
        IncomeFormView(
            detailsTitle: "Details",
            mode: isRecordingReceipt ? .receipt : .standard,
            onUseExistingIncome: canUseExistingIncome ? { openExistingIncomePicker() } : nil,
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
    }

    var body: some View {
        incomeForm
        .navigationTitle(isRecordingReceipt ? Text("Record Income") : Text("Add Income"))
        .appSheet(item: $existingIncomeSelection, onDismiss: {
            if didLinkExistingIncome { dismiss() }
        }) { selection in
            existingIncomePicker(selection.incomes)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(saveDisabled)
                        .tint(.accentColor)
                        .glassProminentButtonStyleCompat()
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(saveDisabled)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }
            }
        }
        .blocksAutomaticExpenseReview(while: showingInvalidAmountAlert)
        .alert("Invalid Amount", isPresented: $showingInvalidAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter a valid amount greater than 0.")
        }
        .blocksAutomaticExpenseReview(while: showingInvalidRepeatAlert)
        .alert("Repeat Requires an End Date", isPresented: $showingInvalidRepeatAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("When Repeat is set, you must also set an End Date (and it cannot be before the start date).")
        }
        .blocksAutomaticExpenseReview(while: showingPossibleDuplicate || showingReceiptSaveError)
        .alert("Possible duplicate", isPresented: $showingPossibleDuplicate) {
            Button("Cancel", role: .cancel) { }
            Button("Record Anyway") { saveReceipt() }
        } message: {
            Text("Actual income with the same source or amount is already recorded on this date.\n\n\(duplicateDetails)")
        }
        .alert("Couldn’t save received income", isPresented: $showingReceiptSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let receiptValidationError {
                Text(receiptValidationError.localizedDescription)
            } else {
                Text("Your entries are still in the form. Try saving again.")
            }
        }
        .onAppear {
            guard !isRecordingReceipt, DebugScreenshotFormDefaults.isEnabled else { return }

            if trimmedSource.isEmpty {
                source = DebugScreenshotFormDefaults.incomeSource
            }

            let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedAmount.isEmpty {
                amountText = DebugScreenshotFormDefaults.incomeAmountText
            }
        }
    }

    @ViewBuilder
    private func existingIncomePicker(_ incomes: [Income]) -> some View {
        if let plannedIncome {
            NavigationStack {
                ExistingReceivedIncomeView(
                    workspaceID: workspace.id, plannedIncome: plannedIncome, incomes: incomes
                ) {
                    didLinkExistingIncome = true
                    existingIncomeSelection = nil
                }
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
        if isRecordingReceipt { return amt.isFinite }

        if frequency != .none {
            guard let endDate else { return false }
            if Calendar.current.startOfDay(for: endDate) < Calendar.current.startOfDay(for: date) { return false }
        }

        return true
    }

    private var saveDisabled: Bool {
        !canSave || isSavingReceipt || showingPossibleDuplicate || showingReceiptSaveError
    }

    // MARK: - Save

    private func save() {
        guard !saveDisabled else { return }
        if isRecordingReceipt {
            checkForDuplicateReceipt()
            return
        }

        guard let amt = parsedAmount, amt > 0 else {
            showingInvalidAmountAlert = true
            return
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
            WorkspaceProgressService.markCompleted(.income, in: workspace)
            dismiss()
            return
        }

        // Series (Option 2 requires end date)
        guard let endDate else {
            showingInvalidRepeatAlert = true
            return
        }

        let startDay = Calendar.current.startOfDay(for: date)
        let endDay = Calendar.current.startOfDay(for: endDate)
        guard endDay >= startDay else {
            showingInvalidRepeatAlert = true
            return
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

        if !occurrenceDays.isEmpty {
            WorkspaceProgressService.markCompleted(.income, in: workspace)
        }

        dismiss()
    }

    private func openExistingIncomePicker() {
        guard let plannedIncome else { return }
        do {
            let workspaceID = workspace.id
            let descriptor = FetchDescriptor<Income>(predicate: #Predicate {
                $0.workspace?.id == workspaceID && !$0.isPlanned
            })
            let candidates = try ExistingReceivedIncomeView.candidates(
                in: modelContext.fetch(descriptor), around: plannedIncome.date
            )
            existingIncomeSelection = ExistingIncomeSelection(incomes: candidates)
        } catch {
            receiptValidationError = nil
            showingReceiptSaveError = true
        }
    }

    private func checkForDuplicateReceipt() {
        guard let amount = parsedAmount else { return }
        do {
            let matches = try TransactionEntryService().possibleReceivedIncomeDuplicates(
                source: trimmedSource, amount: amount, date: date,
                workspaceID: workspace.id, modelContext: modelContext
            )
            if matches.isEmpty {
                saveReceipt()
            } else {
                duplicateDetails = matches.map { income in
                    let day = income.date.formatted(.dateTime.month(.abbreviated).day().year())
                    let amount = CurrencyFormatter.string(from: income.amount)
                    return String(localized: "\(income.source) · \(day) · \(amount)")
                }.joined(separator: "\n")
                showingPossibleDuplicate = true
            }
        } catch {
            receiptValidationError = nil
            showingReceiptSaveError = true
        }
    }

    private func saveReceipt() {
        guard !isSavingReceipt, let plannedIncome, let amount = parsedAmount, amount.isFinite, amount > 0 else { return }
        isSavingReceipt = true
        do {
            try TransactionEntryService().addIncome(
                source: trimmedSource, amount: amount, date: date, isPlanned: false,
                workspace: workspace, plannedIncome: plannedIncome, modelContext: modelContext
            )
            dismiss()
        } catch {
            isSavingReceipt = false
            receiptValidationError = error as? TransactionEntryService.ValidationError
            showingReceiptSaveError = true
        }
    }
}
