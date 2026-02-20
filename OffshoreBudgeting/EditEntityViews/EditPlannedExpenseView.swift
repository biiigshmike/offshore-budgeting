//
//  EditPlannedExpenseView.swift
//  OffshoreBudgeting
//
//  Created by Codex on 1/27/26.
//

import SwiftUI
import SwiftData

struct EditPlannedExpenseView: View {

    private enum SharedBalanceMode: String, CaseIterable, Identifiable {
        case split
        case offset

        var id: String { rawValue }

        var title: String {
            switch self {
            case .split: return "Split"
            case .offset: return "Offset"
            }
        }
    }

    let workspace: Workspace
    let plannedExpense: PlannedExpense

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]
    @Query private var categories: [Category]
    @Query private var allocationAccounts: [AllocationAccount]
    @Query private var savingsAccounts: [SavingsAccount]

    // MARK: - Form State

    @State private var title: String = ""
    @State private var plannedAmountText: String = ""
    @State private var actualAmountText: String = ""
    @State private var expenseDate: Date = .now
    @State private var selectedCardID: UUID? = nil
    @State private var selectedCategoryID: UUID? = nil

    @State private var draftSharedBalanceMode: SharedBalanceMode? = nil
    @State private var selectedAllocationAccountID: UUID? = nil
    @State private var allocationAmountText: String = ""
    @State private var selectedOffsetAccountID: UUID? = nil
    @State private var offsetAmountText: String = ""
    @State private var applySavingsOffset: Bool = false
    @State private var savingsOffsetAmountText: String = ""

    @State private var isProgrammaticSync: Bool = false

    // MARK: - Alerts

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false
    @State private var showingInvalidSplitAmountAlert: Bool = false
    @State private var showingInvalidOffsetAmountAlert: Bool = false
    @State private var showingInvalidSavingsOffsetAmountAlert: Bool = false

    init(workspace: Workspace, plannedExpense: PlannedExpense) {
        self.workspace = workspace
        self.plannedExpense = plannedExpense

        let workspaceID = workspace.id
        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )

        _allocationAccounts = Query(
            filter: #Predicate<AllocationAccount> {
                $0.workspace?.id == workspaceID && $0.isArchived == false
            },
            sort: [SortDescriptor(\AllocationAccount.name, order: .forward)]
        )

        _savingsAccounts = Query(
            filter: #Predicate<SavingsAccount> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\SavingsAccount.createdAt, order: .forward)]
        )
    }

    private var isSharedBalanceEnabled: Bool {
        plannedExpense.sourcePresetID != nil
    }

    private var hasAllocationConfigured: Bool {
        selectedAllocationAccountID != nil && !allocationAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasOffsetConfigured: Bool {
        selectedOffsetAccountID != nil && !offsetAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

    private var availableSavingsBalance: Double {
        let current = max(0, savingsAccounts.first?.total ?? 0)
        let existingOffset = max(0, -(plannedExpense.savingsLedgerEntry?.amount ?? 0))
        return current + existingOffset
    }

    private var canSave: Bool {
        let trimmedTitle = PresetFormView.trimmedTitle(title)
        guard !trimmedTitle.isEmpty else { return false }

        guard let plannedAmount = PresetFormView.parsePlannedAmount(plannedAmountText),
              plannedAmount > 0
        else { return false }

        let trimmedActual = actualAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedActual.isEmpty {
            guard let actual = PresetFormView.parsePlannedAmount(actualAmountText),
                  actual >= 0
            else { return false }
        }

        if isSharedBalanceEnabled, let mode = activeSharedBalanceMode {
            let selectedAccountID = mode == .split ? selectedAllocationAccountID : selectedOffsetAccountID
            let rawAmountText = mode == .split ? allocationAmountText : offsetAmountText

            guard selectedAccountID != nil else { return false }

            let trimmedSharedAmount = rawAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSharedAmount.isEmpty {
                guard let parsedSharedAmount = CurrencyFormatter.parseAmount(trimmedSharedAmount), parsedSharedAmount >= 0 else {
                    return false
                }

                guard parsedSharedAmount <= plannedAmount else {
                    return false
                }

                if mode == .offset,
                   let selectedOffsetAccount = allocationAccounts.first(where: { $0.id == selectedAccountID }) {
                    let available = availableOffsetBalance(for: selectedOffsetAccount)
                    guard parsedSharedAmount <= available else {
                        return false
                    }
                }
            }
        }

        if applySavingsOffset {
            if activeSharedBalanceMode != nil {
                return false
            }

            let trimmedSavings = savingsOffsetAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedSavings.isEmpty {
                guard let parsed = CurrencyFormatter.parseAmount(trimmedSavings), parsed >= 0 else {
                    return false
                }

                guard parsed <= plannedAmount else {
                    return false
                }

                guard parsed <= availableSavingsBalance else {
                    return false
                }
            }
        }

        guard selectedCardID != nil else { return false }
        return true
    }

    var body: some View {
        List {
            Section("Details") {
                TextField("Title", text: $title)

                TextField("Planned Amount", text: $plannedAmountText)
                    .keyboardType(.decimalPad)

                TextField("Actual Amount (optional)", text: $actualAmountText)
                    .keyboardType(.decimalPad)

                HStack {
                    Text("Date")
                    Spacer()
                    PillDatePickerField(title: "Date", date: $expenseDate)
                }
            }

            Section("Card") {
                Picker("Card", selection: $selectedCardID) {
                    Text("Select").tag(UUID?.none)
                    ForEach(cards) { card in
                        Text(card.name).tag(UUID?.some(card.id))
                    }
                }
            }

            Section("Category") {
                Picker("Category", selection: $selectedCategoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
            }

            if isSharedBalanceEnabled {
                sharedBalanceSection
            }

            savingsOffsetSection
        }
        .navigationTitle("Edit Planned Expense")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.glassProminent)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
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
            Text("Please enter a planned amount greater than 0, and an actual amount that is 0 or greater.")
        }
        .alert("Select a Card", isPresented: $showingMissingCardAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Choose a card for this planned expense.")
        }
        .alert("Invalid Split Amount", isPresented: $showingInvalidSplitAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Split amount must be 0 or greater and cannot exceed the planned amount.")
        }
        .alert("Invalid Offset Amount", isPresented: $showingInvalidOffsetAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Offset amount must be 0 or greater, cannot exceed the planned amount, and cannot exceed the selected account balance.")
        }
        .alert("Invalid Savings Offset Amount", isPresented: $showingInvalidSavingsOffsetAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Savings offset amount must be 0 or greater, cannot exceed planned amount, and cannot exceed available savings.")
        }
        .onAppear {
            title = plannedExpense.title
            plannedAmountText = CurrencyFormatter.editingString(from: plannedExpense.plannedAmount)
            actualAmountText = plannedExpense.actualAmount > 0 ? CurrencyFormatter.editingString(from: plannedExpense.actualAmount) : ""
            expenseDate = plannedExpense.expenseDate
            selectedCardID = plannedExpense.card?.id
            selectedCategoryID = plannedExpense.category?.id

            selectedAllocationAccountID = plannedExpense.allocation?.account?.id
            if let allocation = plannedExpense.allocation, allocation.allocatedAmount > 0 {
                allocationAmountText = CurrencyFormatter.editingString(from: allocation.allocatedAmount)
            } else {
                allocationAmountText = ""
            }

            selectedOffsetAccountID = plannedExpense.offsetSettlement?.account?.id
            if let settlement = plannedExpense.offsetSettlement, settlement.amount < 0 {
                offsetAmountText = CurrencyFormatter.editingString(from: -settlement.amount)
            } else {
                offsetAmountText = ""
            }

            if let savingsEntry = plannedExpense.savingsLedgerEntry,
               savingsEntry.kind == .expenseOffset,
               savingsEntry.amount < 0 {
                applySavingsOffset = true
                savingsOffsetAmountText = CurrencyFormatter.editingString(from: -savingsEntry.amount)
            } else {
                applySavingsOffset = false
                savingsOffsetAmountText = ""
            }

            if hasAllocationConfigured && !hasOffsetConfigured {
                draftSharedBalanceMode = .split
            } else if hasOffsetConfigured && !hasAllocationConfigured {
                draftSharedBalanceMode = .offset
            } else {
                draftSharedBalanceMode = nil
            }
        }
        .onChange(of: plannedAmountText) { _, _ in
            syncActualFromActiveSharedAmountIfNeeded()
        }
        .onChange(of: allocationAmountText) { _, _ in
            guard activeSharedBalanceMode == .split else { return }
            syncActualFromActiveSharedAmountIfNeeded()
        }
        .onChange(of: offsetAmountText) { _, _ in
            guard activeSharedBalanceMode == .offset else { return }
            syncActualFromActiveSharedAmountIfNeeded()
        }
        .onChange(of: actualAmountText) { _, newValue in
            syncSharedAmountFromActual(newValue)
        }
    }

    private var sharedBalanceSection: some View {
        Section("Reconciliation") {
            Picker("Action", selection: sharedBalanceModeBinding) {
                Text("None").tag(SharedBalanceMode?.none)
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
                Picker("Reconciliation", selection: accountBinding(for: mode)) {
                    Text("None").tag(UUID?.none)
                    ForEach(allocationAccounts) { account in
                        Text(account.name).tag(UUID?.some(account.id))
                    }
                }

                TextField("Amount", text: amountBinding(for: mode))
                    .keyboardType(.decimalPad)

                if let account = selectedAccount(for: mode) {
                    HStack {
                        Text("Available Balance")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(AllocationLedgerService.balance(for: account), format: CurrencyFormatter.currencyStyle())
                            .fontWeight(.semibold)
                    }
                }
            }

            if let validationMessage = sharedBalanceValidationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if hasAllocationConfigured || hasOffsetConfigured || isLegacyDualConfiguration {
                Button("Clear Reconciliation Action", role: .destructive) {
                    clearSharedBalanceAction()
                }
            }
        }
        .disabled(applySavingsOffset)
    }

    private var savingsOffsetSection: some View {
        Section {
            Toggle("Pay From Savings", isOn: $applySavingsOffset)

            if applySavingsOffset {
                TextField("Savings Amount", text: $savingsOffsetAmountText)
                    .keyboardType(.decimalPad)

                HStack {
                    Text("Available Savings")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(availableSavingsBalance, format: CurrencyFormatter.currencyStyle())
                        .fontWeight(.semibold)
                }
            }
        } header: {
            Text("Savings Offset")
        } footer: {
            if activeSharedBalanceMode != nil {
                Text("Clear Reconciliation actions to use Savings Offset.")
            }
        }
        .disabled(activeSharedBalanceMode != nil)
    }

    private var sharedBalanceModeBinding: Binding<SharedBalanceMode?> {
        Binding(
            get: { activeSharedBalanceMode },
            set: { newMode in
                draftSharedBalanceMode = newMode

                switch newMode {
                case .split:
                    if selectedAllocationAccountID == nil {
                        selectedAllocationAccountID = selectedOffsetAccountID
                    }
                    selectedOffsetAccountID = nil
                    offsetAmountText = ""
                case .offset:
                    if selectedOffsetAccountID == nil {
                        selectedOffsetAccountID = selectedAllocationAccountID
                    }
                    selectedAllocationAccountID = nil
                    allocationAmountText = ""
                case nil:
                    selectedAllocationAccountID = nil
                    allocationAmountText = ""
                    selectedOffsetAccountID = nil
                    offsetAmountText = ""
                }

                let trimmedActual = actualAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedActual.isEmpty {
                    syncSharedAmountFromActual(actualAmountText)
                }
            }
        )
    }

    private var sharedBalanceValidationMessage: String? {
        guard let mode = activeSharedBalanceMode else { return nil }

        guard let planned = PresetFormView.parsePlannedAmount(plannedAmountText), planned > 0 else {
            return "Enter a planned amount first."
        }

        let selectedAccountID = mode == .split ? selectedAllocationAccountID : selectedOffsetAccountID
        let rawAmountText = mode == .split ? allocationAmountText : offsetAmountText

        guard selectedAccountID != nil else {
            return "Choose a Reconciliation."
        }

        let trimmedAmount = rawAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAmount.isEmpty { return nil }

        guard let parsedAmount = CurrencyFormatter.parseAmount(trimmedAmount) else {
            return "Enter a valid amount."
        }

        guard parsedAmount >= 0 else {
            return "Amount must be 0 or greater."
        }

        guard parsedAmount <= planned else {
            return "Amount can't exceed the planned amount."
        }

        if mode == .offset,
           let account = allocationAccounts.first(where: { $0.id == selectedAccountID }) {
            let available = availableOffsetBalance(for: account)
            guard parsedAmount <= available else {
                return "Amount can't exceed available balance."
            }
        }

        return nil
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
            }
        )
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

    private func clearSharedBalanceAction() {
        draftSharedBalanceMode = nil
        selectedAllocationAccountID = nil
        allocationAmountText = ""
        selectedOffsetAccountID = nil
        offsetAmountText = ""
    }

    private func syncActualFromActiveSharedAmountIfNeeded() {
        guard !isProgrammaticSync else { return }
        guard let mode = activeSharedBalanceMode else { return }
        guard let planned = PresetFormView.parsePlannedAmount(plannedAmountText), planned > 0 else { return }

        let rawAmountText = mode == .split ? allocationAmountText : offsetAmountText
        let trimmedShared = rawAmountText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedShared.isEmpty,
              let sharedAmount = CurrencyFormatter.parseAmount(trimmedShared),
              sharedAmount >= 0
        else {
            return
        }

        let adjustedActual = max(0, planned - sharedAmount)

        isProgrammaticSync = true
        actualAmountText = liveEditingAmountString(from: adjustedActual)
        isProgrammaticSync = false
    }

    private func syncSharedAmountFromActual(_ newValue: String) {
        guard !isProgrammaticSync else { return }
        guard let mode = activeSharedBalanceMode else { return }

        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clearSharedBalanceAction()
            return
        }

        guard let planned = PresetFormView.parsePlannedAmount(plannedAmountText), planned > 0 else { return }
        guard let actual = PresetFormView.parsePlannedAmount(newValue), actual >= 0 else { return }

        let shared = max(0, planned - actual)
        let sharedText = shared > 0 ? liveEditingAmountString(from: shared) : ""

        isProgrammaticSync = true
        switch mode {
        case .split:
            allocationAmountText = sharedText
        case .offset:
            offsetAmountText = sharedText
        }
        isProgrammaticSync = false
    }

    private func save() {
        let trimmedTitle = PresetFormView.trimmedTitle(title)
        guard !trimmedTitle.isEmpty else { return }

        guard let planned = PresetFormView.parsePlannedAmount(plannedAmountText), planned > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        let parsedActual: Double
        let actualTrimmed = actualAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if actualTrimmed.isEmpty {
            parsedActual = 0
        } else {
            guard let actual = PresetFormView.parsePlannedAmount(actualAmountText), actual >= 0 else {
                showingInvalidAmountAlert = true
                return
            }
            parsedActual = actual
        }

        guard let selectedCard = cards.first(where: { $0.id == selectedCardID }) else {
            showingMissingCardAlert = true
            return
        }

        let selectedCategory = categories.first(where: { $0.id == selectedCategoryID })
        var resolvedAllocationAccount = allocationAccounts.first(where: { $0.id == selectedAllocationAccountID })
        var resolvedOffsetAccount = allocationAccounts.first(where: { $0.id == selectedOffsetAccountID })

        if let mode = activeSharedBalanceMode {
            switch mode {
            case .split:
                resolvedOffsetAccount = nil
            case .offset:
                resolvedAllocationAccount = nil
            }
        } else {
            resolvedAllocationAccount = nil
            resolvedOffsetAccount = nil
        }

        let allocationAmount: Double
        if resolvedAllocationAccount != nil {
            let trimmed = allocationAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                allocationAmount = 0
            } else {
                guard let parsed = CurrencyFormatter.parseAmount(trimmed), parsed >= 0, parsed <= planned else {
                    showingInvalidSplitAmountAlert = true
                    return
                }
                allocationAmount = parsed
            }
        } else {
            allocationAmount = 0
        }

        let offsetAmount: Double
        if let selectedOffsetAccount = resolvedOffsetAccount {
            let trimmed = offsetAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                offsetAmount = 0
            } else {
                guard let parsed = CurrencyFormatter.parseAmount(trimmed), parsed >= 0, parsed <= planned else {
                    showingInvalidOffsetAmountAlert = true
                    return
                }
                let available = availableOffsetBalance(for: selectedOffsetAccount)
                guard parsed <= available else {
                    showingInvalidOffsetAmountAlert = true
                    return
                }
                offsetAmount = parsed
            }
        } else {
            offsetAmount = 0
        }

        let savingsOffsetAmount: Double
        if applySavingsOffset {
            let trimmed = savingsOffsetAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                savingsOffsetAmount = 0
            } else {
                guard let parsed = CurrencyFormatter.parseAmount(trimmed), parsed >= 0, parsed <= planned else {
                    showingInvalidSavingsOffsetAmountAlert = true
                    return
                }
                guard parsed <= availableSavingsBalance else {
                    showingInvalidSavingsOffsetAmountAlert = true
                    return
                }
                savingsOffsetAmount = parsed
            }
        } else {
            savingsOffsetAmount = 0
        }

        let hasSplit = resolvedAllocationAccount != nil && allocationAmount > 0
        let hasOffset = resolvedOffsetAccount != nil && offsetAmount > 0

        let actualToSave: Double
        if hasSplit {
            actualToSave = max(0, planned - allocationAmount)
        } else if hasOffset {
            actualToSave = max(0, planned - offsetAmount)
        } else {
            actualToSave = parsedActual
        }

        plannedExpense.title = trimmedTitle
        plannedExpense.plannedAmount = planned
        plannedExpense.actualAmount = actualToSave
        plannedExpense.expenseDate = expenseDate
        plannedExpense.workspace = workspace
        plannedExpense.card = selectedCard
        plannedExpense.category = selectedCategory

        if hasSplit, let account = resolvedAllocationAccount {
            if let existingOffset = plannedExpense.offsetSettlement {
                plannedExpense.offsetSettlement = nil
                modelContext.delete(existingOffset)
            }

            if let existingAllocation = plannedExpense.allocation {
                existingAllocation.allocatedAmount = AllocationLedgerService.cappedAllocationAmount(allocationAmount, expenseAmount: planned)
                existingAllocation.updatedAt = .now
                existingAllocation.workspace = workspace
                existingAllocation.account = account
                existingAllocation.plannedExpense = plannedExpense
            } else {
                let allocation = ExpenseAllocation(
                    allocatedAmount: AllocationLedgerService.cappedAllocationAmount(allocationAmount, expenseAmount: planned),
                    createdAt: .now,
                    updatedAt: .now,
                    workspace: workspace,
                    account: account,
                    expense: nil,
                    plannedExpense: plannedExpense
                )
                modelContext.insert(allocation)
                plannedExpense.allocation = allocation
            }
        } else if let existingAllocation = plannedExpense.allocation {
            plannedExpense.allocation = nil
            modelContext.delete(existingAllocation)
        }

        if hasOffset, let account = resolvedOffsetAccount {
            if let existingAllocation = plannedExpense.allocation {
                plannedExpense.allocation = nil
                modelContext.delete(existingAllocation)
            }

            if let existingOffset = plannedExpense.offsetSettlement {
                existingOffset.date = expenseDate
                existingOffset.note = offsetNote(for: trimmedTitle)
                existingOffset.amount = -offsetAmount
                existingOffset.workspace = workspace
                existingOffset.account = account
                existingOffset.expense = nil
                existingOffset.plannedExpense = plannedExpense
            } else {
                let settlement = AllocationSettlement(
                    date: expenseDate,
                    note: offsetNote(for: trimmedTitle),
                    amount: -offsetAmount,
                    workspace: workspace,
                    account: account,
                    expense: nil,
                    plannedExpense: plannedExpense
                )
                modelContext.insert(settlement)
                plannedExpense.offsetSettlement = settlement
            }
        } else if let existingOffset = plannedExpense.offsetSettlement {
            plannedExpense.offsetSettlement = nil
            modelContext.delete(existingOffset)
        }

        if savingsOffsetAmount > 0 {
            SavingsAccountService.upsertSavingsOffset(
                workspace: workspace,
                plannedExpense: plannedExpense,
                offsetAmount: savingsOffsetAmount,
                note: savingsOffsetNote(for: trimmedTitle),
                date: expenseDate,
                modelContext: modelContext
            )
        } else {
            SavingsAccountService.removeSavingsOffset(for: plannedExpense, modelContext: modelContext)
        }

        try? modelContext.save()
        dismiss()
    }

    private func availableOffsetBalance(for account: AllocationAccount) -> Double {
        let currentBalance = max(0, AllocationLedgerService.balance(for: account))
        guard let existing = plannedExpense.offsetSettlement else { return currentBalance }
        guard existing.account?.id == account.id else { return currentBalance }
        return max(0, currentBalance + max(0, -existing.amount))
    }

    private func offsetNote(for title: String) -> String {
        "Offset applied to \(title)"
    }

    private func savingsOffsetNote(for title: String) -> String {
        "Savings offset applied to \(title)"
    }

    private func liveEditingAmountString(from value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .autoupdatingCurrent
        formatter.usesGroupingSeparator = true
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
