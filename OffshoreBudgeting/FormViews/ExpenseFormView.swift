//
//  ExpenseFormView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

/// Shared form UI for adding and editing a VariableExpense ("Expense").
///
/// Design goals:
/// - One place for fields + validation UI
/// - Add/Edit views own navigation + save behavior
struct ExpenseFormView: View {

    private enum SharedBalanceMode: String, CaseIterable, Identifiable {
        case split
        case offset

        var id: String { rawValue }

        var title: String {
            switch self {
            case .split:
                return String(localized: "Split", defaultValue: "Split", comment: "Shared-balance action label for splitting an expense.")
            case .offset:
                return String(localized: "Offset", defaultValue: "Offset", comment: "Shared-balance action label for offsetting an expense.")
            }
        }
    }

    let workspace: Workspace
    let cards: [Card]
    let categories: [Category]
    let allocationAccounts: [AllocationAccount]

    @Binding var descriptionText: String
    @Binding var amountText: String
    @Binding var transactionDate: Date
    @Binding var transactionKind: VariableExpenseKind
    @Binding var selectedCardID: UUID?
    @Binding var selectedCategoryID: UUID?
    @Binding var selectedAllocationAccountID: UUID?
    @Binding var allocationAmountText: String
    @Binding var selectedOffsetAccountID: UUID?
    @Binding var offsetAmountText: String
    @Binding var applySavingsOffset: Bool
    @Binding var savingsOffsetAmountText: String

    let availableSavingsBalance: Double

    let onSharedBalanceChanged: (() -> Void)?
    var onOptionalActionsValidationChanged: ((Bool) -> Void)? = nil
    @State private var draftSharedBalanceMode: SharedBalanceMode? = nil
    @State private var wantsReconciliation = false
    @State private var splitPercentage: Double = 0.5
    @State private var shouldApplyInitialSplitDefault: Bool = false
    @State private var hasAppliedInitialSplitDefault: Bool = false

    private var enteredAmount: Double {
        ExpenseFormView.parseAmount(amountText) ?? 0
    }

    private var hasAllocationConfigured: Bool {
        selectedAllocationAccountID != nil && !allocationAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasOffsetConfigured: Bool {
        selectedOffsetAccountID != nil && !offsetAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasAnySharedBalanceAction: Bool {
        hasAllocationConfigured || hasOffsetConfigured
    }

    private var isLegacyDualConfiguration: Bool {
        hasAllocationConfigured && hasOffsetConfigured
    }

    private var activeSharedBalanceMode: SharedBalanceMode? {
        if let draftSharedBalanceMode {
            return draftSharedBalanceMode
        }
        if hasAllocationConfigured && !hasOffsetConfigured { return .split }
        if hasOffsetConfigured && !hasAllocationConfigured { return .offset }
        return nil
    }

    private var sharedBalanceSummary: String? {
        if isLegacyDualConfiguration {
            return "Legacy setup: Split and Offset are both present."
        }

        if hasAllocationConfigured,
           let account = allocationAccounts.first(where: { $0.id == selectedAllocationAccountID }),
           let amount = CurrencyFormatter.parseAmount(allocationAmountText) {
            return "Split \(CurrencyFormatter.string(from: amount)) to \(account.name)"
        }

        if hasOffsetConfigured,
           let account = allocationAccounts.first(where: { $0.id == selectedOffsetAccountID }),
           let amount = CurrencyFormatter.parseAmount(offsetAmountText) {
            return "Offset \(CurrencyFormatter.string(from: amount)) from \(account.name)"
        }

        return nil
    }

    private var sharedBalanceModeBinding: Binding<SharedBalanceMode?> {
        Binding(
            get: { activeSharedBalanceMode },
            set: { newMode in
                draftSharedBalanceMode = newMode

                switch newMode {
                case .split:
                    shouldApplyInitialSplitDefault = !hasAppliedInitialSplitDefault
                    if selectedAllocationAccountID == nil {
                        selectedAllocationAccountID = selectedOffsetAccountID
                    }
                    selectedOffsetAccountID = nil
                    offsetAmountText = ""
                    applyInitialSplitDefaultIfNeeded(notifySharedBalanceChanged: false)
                case .offset:
                    shouldApplyInitialSplitDefault = false
                    if selectedOffsetAccountID == nil {
                        selectedOffsetAccountID = selectedAllocationAccountID
                    }
                    selectedAllocationAccountID = nil
                    allocationAmountText = ""
                case nil:
                    shouldApplyInitialSplitDefault = false
                    selectedAllocationAccountID = nil
                    allocationAmountText = ""
                    selectedOffsetAccountID = nil
                    offsetAmountText = ""
                }

                onSharedBalanceChanged?()
            }
        )
    }

    // MARK: - Validation (shared by Add + Edit)

    static func trimmedDescription(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseAmount(_ text: String) -> Double? {
        CurrencyFormatter.parseAmount(text)
    }

    static func canSave(
        descriptionText: String,
        amountText: String,
        selectedCardID: UUID?,
        hasAtLeastOneCard: Bool
    ) -> Bool {
        let d = trimmedDescription(descriptionText)
        guard !d.isEmpty else { return false }
        guard let amt = parseAmount(amountText), amt > 0 else { return false }
        guard hasAtLeastOneCard else { return false }
        guard selectedCardID != nil else { return false }
        return true
    }

    var body: some View {
        List {
            expenseDetailsSection
            transactionTypeSection
            sharedBalanceSection
            savingsOffsetSection
        }
        .onAppear {
            if draftSharedBalanceMode == nil {
                draftSharedBalanceMode = activeSharedBalanceMode
            }
            if activeSharedBalanceMode == .split {
                applyPercentageFromSplitAmountText()
            }
            onOptionalActionsValidationChanged?(areOptionalActionsValid)
        }
        .onChange(of: areOptionalActionsValid) { _, isValid in
            onOptionalActionsValidationChanged?(isValid)
        }
        .onChange(of: amountText) { _, _ in
            handleExpenseAmountChangedForSplit()
        }
        .onChange(of: allocationAmountText) { _, _ in
            handleSplitAmountTextChanged()
        }
    }

    private var expenseDetailsSection: some View {
        Section {
            if cards.isEmpty {
                Text("No cards yet. Create a card first to add expenses.")
                    .foregroundStyle(.secondary)
            } else {
                EntityMenuPicker(title: "Card", items: cards, selection: $selectedCardID, allowsEmptySelection: false, showsTitle: false) { card in
                    CardMenuLabel(card: card)
                }
            }

            TextField("Description", text: $descriptionText)
            TextField("Amount", text: $amountText)
                .keyboardType(.decimalPad)

            HStack {
                Text("Date")
                Spacer()
                PillDatePickerField(title: "Date", date: $transactionDate)
            }

            EntityMenuPicker(title: "Category", items: categories, selection: $selectedCategoryID, showsTitle: false) { category in
                CategoryMenuLabel(category: category)
            }
        } header: {
            Text("Expense")
        }
    }

    private var transactionTypeSection: some View {
        Section {
            Picker("Transaction Type", selection: $transactionKind) {
                ForEach(VariableExpenseKind.allCases) { kind in
                    Text(kind.displayTitle).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Transaction Type")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(ExpenseEntryGuidance.transactionExplanation(for: transactionKind))
                HelpTopicLink(topicID: "accounts-transaction-types", title: "Purchases, refunds, and adjustments")
            }
        }
    }

    private var reconciliationEnabled: Binding<Bool> {
        Binding(
            get: { wantsReconciliation || activeSharedBalanceMode != nil || isLegacyDualConfiguration },
            set: { isEnabled in
                guard !isEnabled || !applySavingsOffset else { return }
                wantsReconciliation = isEnabled
                if !isEnabled {
                    sharedBalanceModeBinding.wrappedValue = nil
                } else if activeSharedBalanceMode == nil && !isLegacyDualConfiguration {
                    sharedBalanceModeBinding.wrappedValue = .split
                }
            }
        )
    }

    private var sharedBalanceSection: some View {
        Section {
            Picker("Reconciliation", selection: reconciliationEnabled) {
                Text("None").tag(false)
                Text("Choose").tag(true)
            }
            .pickerStyle(.segmented)
            .disabled(applySavingsOffset && !reconciliationEnabled.wrappedValue)

            if reconciliationEnabled.wrappedValue {
                Group {
                    if let mode = activeSharedBalanceMode {
                        Picker("Reconciliation Account", selection: accountBinding(for: mode)) {
                            Text("Choose").tag(UUID?.none)
                            ForEach(allocationAccounts) { account in
                                Text(account.name).tag(Optional(account.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    Picker("Reconciliation Action", selection: sharedBalanceModeBinding) {
                        if isLegacyDualConfiguration {
                            Text("Choose Action").tag(SharedBalanceMode?.none)
                        }
                        ForEach(SharedBalanceMode.allCases) { mode in
                            Text(mode.title).tag(Optional(mode))
                        }
                    }
                    .pickerStyle(.segmented)

                    if isLegacyDualConfiguration {
                        Text("Legacy setup detected. Choose Split or Offset to keep one action type.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let mode = activeSharedBalanceMode {
                        TextField("Amount", text: amountBinding(for: mode))
                            .keyboardType(.decimalPad)

                        if mode == .split {
                            splitPercentageControl
                        }

                        if let account = selectedAccount(for: mode) {
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

                    if let validationMessage = sharedBalanceValidationMessage {
                        Text(validationMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if hasAnySharedBalanceAction || isLegacyDualConfiguration {
                        Button("Clear Reconciliation Action", role: .destructive) {
                            reconciliationEnabled.wrappedValue = false
                        }
                    }

                    if let sharedBalanceSummary, !isLegacyDualConfiguration {
                        Text(sharedBalanceSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(applySavingsOffset)
            }
        } header: {
            Text("Reconciliation")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                switch activeSharedBalanceMode {
                case .split:
                    Text(ExpenseEntryGuidance.splitExplanation)
                case .offset:
                    Text(ExpenseEntryGuidance.offsetExplanation)
                case nil:
                    Text(ExpenseEntryGuidance.reconciliationOverview)
                }
                HelpTopicLink(topicID: "accounts-reconciliations", title: "Reconciliation guide")
            }
        }
        .onChange(of: activeSharedBalanceMode?.rawValue) { _, newValue in
            if newValue != nil && applySavingsOffset {
                applySavingsOffset = false
                savingsOffsetAmountText = ""
            }
            if newValue == SharedBalanceMode.split.rawValue {
                applyPercentageFromSplitAmountText()
            } else {
                shouldApplyInitialSplitDefault = false
            }
        }
    }

    private var splitPercentageControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Split Percentage")
                Spacer()
                Text(splitPercentage.formatted(.percent.precision(.fractionLength(0))))
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: splitPercentageBinding,
                in: 0...1,
                step: 0.01
            ) {
                Text("Split Percentage")
            } minimumValueLabel: {
                Text(0.0.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text(1.0.formatted(.percent.precision(.fractionLength(0))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .disabled(enteredAmount <= 0)
            .accessibilityValue(splitPercentage.formatted(.percent.precision(.fractionLength(0))))
        }
    }

    private var savingsOffsetSection: some View {
        Section {
            Group {
                Picker("Pay From Savings", selection: $applySavingsOffset) {
                    Text("Off").tag(false)
                    Text("Use Savings").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(reconciliationEnabled.wrappedValue && !applySavingsOffset)

                if applySavingsOffset {
                    LabeledContent {
                        TextField("Savings Amount", text: $savingsOffsetAmountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Label("Savings Amount", systemImage: "checkmark.square.fill")
                    }
                    .disabled(reconciliationEnabled.wrappedValue)

                    HStack {
                        Text("Available Savings")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(availableSavingsBalance, format: CurrencyFormatter.currencyStyle())
                            .fontWeight(.semibold)
                    }

                    if let message = savingsValidationMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Pay From Savings")
        } footer: {
            if transactionKind == .debit {
                Text(ExpenseEntryGuidance.payFromSavingsExplanation)
            } else {
                Text(ExpenseEntryGuidance.nonPurchaseSavingsExplanation)
            }
            if reconciliationEnabled.wrappedValue {
                Text("Clear Reconciliation actions to use Pay From Savings.")
            }
            HelpTopicLink(topicID: "accounts-savings-account", title: "Savings guide")
        }
        .onChange(of: applySavingsOffset) { _, isOn in
            if isOn && hasAnySharedBalanceAction {
                applySavingsOffset = false
            }
            if !isOn {
                savingsOffsetAmountText = ""
            }
        }
    }

    private var savingsValidationMessage: String? {
        guard applySavingsOffset else { return nil }

        guard enteredAmount > 0 else {
            return "Enter an expense amount first."
        }

        let trimmed = savingsOffsetAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter an amount." }

        guard let parsed = CurrencyFormatter.parseAmount(trimmed) else {
            return "Enter a valid amount."
        }

        guard parsed > 0 else {
            return "Amount must be greater than 0."
        }

        guard parsed <= enteredAmount else {
            return "Amount can't exceed the expense amount."
        }

        return nil
    }

    private var sharedBalanceValidationMessage: String? {
        guard let mode = activeSharedBalanceMode else { return nil }

        guard enteredAmount > 0 else {
            return "Enter an expense amount first."
        }

        let selectedAccountID = mode == .split ? selectedAllocationAccountID : selectedOffsetAccountID
        let rawAmountText = mode == .split ? allocationAmountText : offsetAmountText

        guard selectedAccountID != nil else {
            return "Choose a Reconciliation."
        }

        let trimmedAmount = rawAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAmount.isEmpty { return "Enter an amount." }

        guard let parsedAmount = CurrencyFormatter.parseAmount(trimmedAmount) else {
            return "Enter a valid amount."
        }

        guard parsedAmount > 0 else {
            return "Amount must be greater than 0."
        }

        guard parsedAmount <= enteredAmount else {
            return "Amount can't exceed the expense amount."
        }

        return nil
    }

    private var areOptionalActionsValid: Bool {
        guard isReconciliationValid else { return false }
        guard applySavingsOffset else { return true }
        guard !reconciliationEnabled.wrappedValue,
              let amount = CurrencyFormatter.parseAmount(savingsOffsetAmountText),
              amount > 0, amount <= enteredAmount else { return false }
        return true
    }

    private var isReconciliationValid: Bool {
        guard reconciliationEnabled.wrappedValue else { return true }
        guard let mode = activeSharedBalanceMode, !applySavingsOffset else { return false }
        let accountID = mode == .split ? selectedAllocationAccountID : selectedOffsetAccountID
        let rawAmount = mode == .split ? allocationAmountText : offsetAmountText
        guard allocationAccounts.contains(where: { $0.id == accountID }),
              let amount = CurrencyFormatter.parseAmount(rawAmount),
              amount > 0, amount <= enteredAmount else { return false }
        return true
    }

    private func accountBinding(for mode: SharedBalanceMode) -> Binding<UUID?> {
        Binding(
            get: {
                switch mode {
                case .split: return selectedAllocationAccountID
                case .offset: return selectedOffsetAccountID
                }
            },
            set: { newValue in
                switch mode {
                case .split:
                    selectedAllocationAccountID = newValue
                case .offset:
                    selectedOffsetAccountID = newValue
                }
                onSharedBalanceChanged?()
            }
        )
    }

    private var splitPercentageBinding: Binding<Double> {
        Binding(
            get: { splitPercentage },
            set: { newValue in
                splitPercentage = roundedSplitPercentage(newValue)
                shouldApplyInitialSplitDefault = false
                applySplitAmountFromPercentage(notifySharedBalanceChanged: true)
            }
        )
    }

    private func amountBinding(for mode: SharedBalanceMode) -> Binding<String> {
        Binding(
            get: {
                switch mode {
                case .split: return allocationAmountText
                case .offset: return offsetAmountText
                }
            },
            set: { newValue in
                switch mode {
                case .split:
                    allocationAmountText = newValue
                case .offset:
                    offsetAmountText = newValue
                }
                onSharedBalanceChanged?()
            }
        )
    }

    private func handleExpenseAmountChangedForSplit() {
        guard activeSharedBalanceMode == .split else { return }

        if shouldApplyInitialSplitDefault {
            applyInitialSplitDefaultIfNeeded(notifySharedBalanceChanged: true)
            return
        }

        guard enteredAmount > 0 else { return }

        let trimmedSplit = allocationAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSplit.isEmpty else { return }

        applySplitAmountFromPercentage(notifySharedBalanceChanged: true)
    }

    private func handleSplitAmountTextChanged() {
        guard activeSharedBalanceMode == .split else { return }

        let trimmedSplit = allocationAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSplit.isEmpty else { return }

        hasAppliedInitialSplitDefault = true
        shouldApplyInitialSplitDefault = false
        applyPercentageFromSplitAmountText()
    }

    private func applyInitialSplitDefaultIfNeeded(notifySharedBalanceChanged: Bool) {
        guard activeSharedBalanceMode == .split else { return }
        guard shouldApplyInitialSplitDefault else { return }
        guard enteredAmount > 0 else { return }

        let trimmedSplit = allocationAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedSplit.isEmpty else {
            hasAppliedInitialSplitDefault = true
            shouldApplyInitialSplitDefault = false
            applyPercentageFromSplitAmountText()
            return
        }

        splitPercentage = 0.5
        hasAppliedInitialSplitDefault = true
        shouldApplyInitialSplitDefault = false
        applySplitAmountFromPercentage(notifySharedBalanceChanged: notifySharedBalanceChanged)
    }

    private func applySplitAmountFromPercentage(notifySharedBalanceChanged: Bool) {
        guard activeSharedBalanceMode == .split else { return }
        guard enteredAmount > 0 else { return }

        let splitAmount = normalizedSplitAmount(baseAmount: enteredAmount, percentage: splitPercentage)
        allocationAmountText = CurrencyFormatter.editingString(from: splitAmount)

        if notifySharedBalanceChanged {
            onSharedBalanceChanged?()
        }
    }

    private func applyPercentageFromSplitAmountText() {
        guard activeSharedBalanceMode == .split else { return }
        guard enteredAmount > 0 else { return }

        let trimmedSplit = allocationAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let splitAmount = CurrencyFormatter.parseAmount(trimmedSplit) else { return }

        hasAppliedInitialSplitDefault = true
        let normalized = splitAmount / enteredAmount
        splitPercentage = roundedSplitPercentage(normalized)
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

    private func selectedAccount(for mode: SharedBalanceMode) -> AllocationAccount? {
        let accountID: UUID?
        switch mode {
        case .split:
            accountID = selectedAllocationAccountID
        case .offset:
            accountID = selectedOffsetAccountID
        }

        guard let accountID else { return nil }
        return allocationAccounts.first(where: { $0.id == accountID })
    }
}
