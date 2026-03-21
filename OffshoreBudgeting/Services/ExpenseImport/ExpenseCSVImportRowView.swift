//
//  ExpenseCSVImportRowView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

struct ExpenseCSVImportRowView: View {
    let row: ExpenseCSVImportRow
    let allCategories: [Category]
    let allAllocationAccounts: [AllocationAccount]
    let allowKindEditing: Bool
    let onToggleInclude: () -> Void
    let onSetDate: (Date) -> Void
    let onSetMerchant: (String) -> Void
    let onSetAmount: (String) -> Void
    let onSetCategory: (Category?) -> Void
    let onSetKind: (ExpenseCSVImportKind) -> Void
    let onSetReconciliationAction: (ExpenseCSVImportReconciliationAction) -> Void
    let onSetSplitAccount: (AllocationAccount?) -> Void
    let onSetSplitAmount: (String) -> Void
    let onSetOffsetAccount: (AllocationAccount?) -> Void
    let onSetOffsetAmount: (String) -> Void
    let onToggleRemember: () -> Void

    @State private var amountDraft: String
    @State private var splitPercentage: Double = 0.5
    @State private var shouldApplyInitialSplitDefault: Bool = false
    @State private var hasAppliedInitialSplitDefault: Bool = false
    @FocusState private var isAmountFieldFocused: Bool

    init(
        row: ExpenseCSVImportRow,
        allCategories: [Category],
        allAllocationAccounts: [AllocationAccount],
        allowKindEditing: Bool,
        onToggleInclude: @escaping () -> Void,
        onSetDate: @escaping (Date) -> Void,
        onSetMerchant: @escaping (String) -> Void,
        onSetAmount: @escaping (String) -> Void,
        onSetCategory: @escaping (Category?) -> Void,
        onSetKind: @escaping (ExpenseCSVImportKind) -> Void,
        onSetReconciliationAction: @escaping (ExpenseCSVImportReconciliationAction) -> Void,
        onSetSplitAccount: @escaping (AllocationAccount?) -> Void,
        onSetSplitAmount: @escaping (String) -> Void,
        onSetOffsetAccount: @escaping (AllocationAccount?) -> Void,
        onSetOffsetAmount: @escaping (String) -> Void,
        onToggleRemember: @escaping () -> Void
    ) {
        self.row = row
        self.allCategories = allCategories
        self.allAllocationAccounts = allAllocationAccounts
        self.allowKindEditing = allowKindEditing
        self.onToggleInclude = onToggleInclude
        self.onSetDate = onSetDate
        self.onSetMerchant = onSetMerchant
        self.onSetAmount = onSetAmount
        self.onSetCategory = onSetCategory
        self.onSetKind = onSetKind
        self.onSetReconciliationAction = onSetReconciliationAction
        self.onSetSplitAccount = onSetSplitAccount
        self.onSetSplitAmount = onSetSplitAmount
        self.onSetOffsetAccount = onSetOffsetAccount
        self.onSetOffsetAmount = onSetOffsetAmount
        self.onToggleRemember = onToggleRemember
        _amountDraft = State(initialValue: CurrencyFormatter.editingString(from: row.finalAmount))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row1Header
            row2DateAndKind

            if !row.isBlocked && row.kind == .expense {
                row3Category
                row4SharedBalance
            }

            if let errorText {
                row5Error(errorText)
            }

            Divider()

            Text(importSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            if !row.isBlocked {
                row9SaveForFutureImports
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            syncSplitPercentageFromRow()
            if row.reconciliationAction == .split {
                applyInitialSplitDefaultIfNeeded()
            }
        }
        .onChange(of: row.id) { _, _ in
            amountDraft = CurrencyFormatter.editingString(from: row.finalAmount)
            splitPercentage = 0.5
            shouldApplyInitialSplitDefault = false
            hasAppliedInitialSplitDefault = false
            syncSplitPercentageFromRow()
        }
        .onChange(of: row.finalAmount) { _, newValue in
            if !isAmountFieldFocused {
                amountDraft = CurrencyFormatter.editingString(from: newValue)
            }
            handleExpenseAmountChangedForSplit()
        }
        .onChange(of: row.splitAmountText) { _, _ in
            handleSplitAmountTextChanged()
        }
        .onChange(of: row.reconciliationAction) { _, newValue in
            if newValue == .split {
                shouldApplyInitialSplitDefault = !hasAppliedInitialSplitDefault
                applyInitialSplitDefaultIfNeeded()
            } else {
                shouldApplyInitialSplitDefault = false
            }
        }
    }

    // MARK: - Rows

    private var row1Header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                onToggleInclude()
            } label: {
                Image(systemName: row.includeInImport ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.includeInImport ? "Included" : "Excluded")
            .disabled(row.isBlocked)

            TextField(
                "Merchant",
                text: Binding(
                    get: { row.finalMerchant },
                    set: { onSetMerchant($0) }
                )
            )
            .font(.headline)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()

            TextField("Amount", text: $amountDraft)
                .font(.headline)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 120)
                .focused($isAmountFieldFocused)
                .onChange(of: amountDraft) { _, newValue in
                    onSetAmount(newValue)
                }
                .onSubmit {
                    onSetAmount(amountDraft)
                }
        }
    }

    private var row2DateAndKind: some View {
        HStack(spacing: 10) {
            Text("Date")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            DatePicker(
                "",
                selection: Binding(
                    get: { row.finalDate },
                    set: { onSetDate($0) }
                ),
                displayedComponents: [.date]
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .layoutPriority(0)

            Spacer(minLength: 0)

            Text("Type")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if allowKindEditing {
                Picker("Type", selection: Binding(
                    get: { row.kind },
                    set: { onSetKind($0) }
                )) {
                    Text("Expense").tag(ExpenseCSVImportKind.expense)
                    Text("Income").tag(ExpenseCSVImportKind.income)
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
            } else {
                Text(row.kind == .income ? "Income" : "Expense")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var row3Category: some View {
        HStack(spacing: 10) {
            Text("Category")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Picker("Category", selection: Binding(
                get: { row.selectedCategory?.id },
                set: { newID in
                    let match = allCategories.first(where: { $0.id == newID })
                    onSetCategory(match)
                }
            )) {
                Text("Uncategorized").tag(UUID?.none)
                ForEach(allCategories, id: \.id) { cat in
                    Text(cat.name).tag(Optional(cat.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
        }
    }

    private var row4SharedBalance: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("Reconciliation")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            Picker("Action", selection: Binding(
                get: { row.reconciliationAction },
                set: { onSetReconciliationAction($0) }
            )) {
                Text("None").tag(ExpenseCSVImportReconciliationAction.none)
                Text("Split").tag(ExpenseCSVImportReconciliationAction.split)
                Text("Offset").tag(ExpenseCSVImportReconciliationAction.offset)
            }
            .pickerStyle(.segmented)

            if row.reconciliationAction == .split {
                Picker("Reconciliation", selection: Binding(
                    get: { row.selectedSplitAccount?.id },
                    set: { newID in
                        let match = allAllocationAccounts.first(where: { $0.id == newID })
                        onSetSplitAccount(match)
                    }
                )) {
                    Text("None").tag(UUID?.none)
                    ForEach(allAllocationAccounts, id: \.id) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }

                TextField(
                    "Amount",
                    text: Binding(
                        get: { row.splitAmountText },
                        set: { onSetSplitAmount($0) }
                    )
                )
                .keyboardType(.decimalPad)

                splitPercentageControl
            }

            if row.reconciliationAction == .offset {
                Picker("Reconciliation", selection: Binding(
                    get: { row.selectedOffsetAccount?.id },
                    set: { newID in
                        let match = allAllocationAccounts.first(where: { $0.id == newID })
                        onSetOffsetAccount(match)
                    }
                )) {
                    Text("None").tag(UUID?.none)
                    ForEach(allAllocationAccounts, id: \.id) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }

                TextField(
                    "Amount",
                    text: Binding(
                        get: { row.offsetAmountText },
                        set: { onSetOffsetAmount($0) }
                    )
                )
                .keyboardType(.decimalPad)

                if let account = row.selectedOffsetAccount {
                    HStack {
                        Text("Available Balance")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(
                            CurrencyFormatter.normalizedCurrencyDisplayValue(AllocationLedgerService.balance(for: account)),
                            format: CurrencyFormatter.currencyStyle()
                        )
                        .fontWeight(.semibold)
                    }
                }
            }

            if let validationMessage = reconciliationValidationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func row5Error(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.red)
    }

    private var row9SaveForFutureImports: some View {
        HStack(spacing: 10) {
            Text("Save for Future Imports")
                .font(.subheadline)

            Spacer(minLength: 0)

            Toggle(isOn: Binding(
                get: { row.rememberMapping },
                set: { _ in onToggleRemember() }
            )) {
                Text("Save for Future Imports")
            }
            .labelsHidden()
            .tint(Color("AccentColor"))
        }
    }

    // MARK: - Derived Values

    private var errorText: String? {
        if row.isBlocked {
            return row.blockedReason
        }

        guard row.isMissingRequiredData else { return nil }
        if row.finalMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return row.kind == .income
                ? "Add a name to import."
                : "Add a merchant name to import."
        }

        if row.kind == .expense {
            return "Choose a category to import."
        }

        return nil
    }

    private var reconciliationValidationMessage: String? {
        switch row.reconciliationAction {
        case .none:
            return nil
        case .split:
            guard row.finalAmount > 0 else {
                return "Enter an expense amount first."
            }
            guard row.selectedSplitAccount != nil else {
                return "Choose a Reconciliation."
            }
            let trimmed = row.splitAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            guard let parsed = CurrencyFormatter.parseAmount(trimmed) else {
                return "Enter a valid amount."
            }
            guard parsed > 0 else {
                return "Amount must be greater than 0."
            }
            guard parsed <= row.finalAmount else {
                return "Amount can't exceed the expense amount."
            }
            return nil
        case .offset:
            guard row.finalAmount > 0 else {
                return "Enter an expense amount first."
            }
            guard row.selectedOffsetAccount != nil else {
                return "Choose a Reconciliation."
            }
            let trimmed = row.offsetAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return nil }
            guard let parsed = CurrencyFormatter.parseAmount(trimmed) else {
                return "Enter a valid amount."
            }
            guard parsed > 0 else {
                return "Amount must be greater than 0."
            }
            guard parsed <= row.finalAmount else {
                return "Amount can't exceed the expense amount."
            }
            return nil
        }
    }

    private var importSummary: String {
        if let csvCategory = row.originalCategoryText, !csvCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Imported: \(row.originalDescriptionText) • \(row.originalAmountText) • \(csvCategory)"
        }
        return "Imported: \(row.originalDescriptionText) • \(row.originalAmountText)"
    }

    private var splitPercentageControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Split Percentage")
                Spacer()
                Text(splitPercentage.formatted(.percent.precision(.fractionLength(0))))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { splitPercentage },
                    set: { newValue in
                        splitPercentage = roundedSplitPercentage(newValue)
                        shouldApplyInitialSplitDefault = false
                        applySplitAmountFromPercentage()
                    }
                ),
                in: 0...1,
                step: 0.01
            ) {
                Text("Split Percentage")
            } minimumValueLabel: {
                Text("0%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("100%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .disabled(row.finalAmount <= 0)
            .accessibilityValue(splitPercentage.formatted(.percent.precision(.fractionLength(0))))
        }
    }

    private func handleExpenseAmountChangedForSplit() {
        guard row.reconciliationAction == .split else { return }

        if shouldApplyInitialSplitDefault {
            applyInitialSplitDefaultIfNeeded()
            return
        }

        guard row.finalAmount > 0 else { return }

        let trimmed = row.splitAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        applySplitAmountFromPercentage()
    }

    private func handleSplitAmountTextChanged() {
        guard row.reconciliationAction == .split else { return }

        let trimmed = row.splitAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        hasAppliedInitialSplitDefault = true
        shouldApplyInitialSplitDefault = false
        syncSplitPercentageFromRow()
    }

    private func applyInitialSplitDefaultIfNeeded() {
        guard row.reconciliationAction == .split else { return }
        guard shouldApplyInitialSplitDefault else { return }
        guard row.finalAmount > 0 else { return }

        let trimmed = row.splitAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty else {
            hasAppliedInitialSplitDefault = true
            shouldApplyInitialSplitDefault = false
            syncSplitPercentageFromRow()
            return
        }

        splitPercentage = 0.5
        hasAppliedInitialSplitDefault = true
        shouldApplyInitialSplitDefault = false
        applySplitAmountFromPercentage()
    }

    private func applySplitAmountFromPercentage() {
        guard row.reconciliationAction == .split else { return }
        guard row.finalAmount > 0 else { return }

        let splitAmount = normalizedSplitAmount(baseAmount: row.finalAmount, percentage: splitPercentage)
        onSetSplitAmount(CurrencyFormatter.editingString(from: splitAmount))
    }

    private func syncSplitPercentageFromRow() {
        guard row.reconciliationAction == .split else { return }
        guard row.finalAmount > 0 else { return }

        let trimmed = row.splitAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let splitAmount = CurrencyFormatter.parseAmount(trimmed) else { return }

        hasAppliedInitialSplitDefault = true
        splitPercentage = roundedSplitPercentage(splitAmount / row.finalAmount)
    }

    private func normalizedSplitAmount(baseAmount: Double, percentage: Double) -> Double {
        let safeBaseAmount = max(0, baseAmount)
        let clampedPercentage = min(max(percentage, 0), 1)
        let rawSplitAmount = safeBaseAmount * clampedPercentage
        let cappedSplitAmount = min(safeBaseAmount, max(0, rawSplitAmount))
        return CurrencyFormatter.roundedToCurrency(cappedSplitAmount)
    }

    private func roundedSplitPercentage(_ value: Double) -> Double {
        let clamped = min(max(value, 0), 1)
        return (clamped * 100).rounded() / 100
    }
}
