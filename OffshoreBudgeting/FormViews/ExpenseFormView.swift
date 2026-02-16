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
            case .split: return "Split"
            case .offset: return "Offset"
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
    @Binding var selectedCardID: UUID?
    @Binding var selectedCategoryID: UUID?
    @Binding var selectedAllocationAccountID: UUID?
    @Binding var allocationAmountText: String
    @Binding var selectedOffsetAccountID: UUID?
    @Binding var offsetAmountText: String

    let onSharedBalanceChanged: (() -> Void)?
    @State private var draftSharedBalanceMode: SharedBalanceMode? = nil

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
            cardSection
            transactionSection
            categorySection
            sharedBalanceSection
        }
        .onAppear {
            if draftSharedBalanceMode == nil {
                draftSharedBalanceMode = activeSharedBalanceMode
            }
        }
    }

    private var cardSection: some View {
        Section("Card") {
            if cards.isEmpty {
                Text("No cards yet. Create a card first to add expenses.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(cards) { card in
                            CardTile(
                                title: card.name,
                                themeRaw: card.theme,
                                effectRaw: card.effect,
                                isSelected: selectedCardID == card.id
                            ) {
                                selectedCardID = card.id
                            }
                            .accessibilityLabel(selectedCardID == card.id ? "\(card.name), selected" : "\(card.name)")
                            .accessibilityHint("Double tap to set as the expense card.")
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 2)
                }

                if selectedCardID == nil {
                    Text("Select a card to continue.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var transactionSection: some View {
        Section("Expense") {
            TextField("Description", text: $descriptionText)

            TextField("Amount", text: $amountText)
                .keyboardType(.decimalPad)

            HStack {
                Text("Date")
                Spacer()
                PillDatePickerField(title: "Date", date: $transactionDate)
            }
        }
    }

    private var categorySection: some View {
        Section {
            Picker("Category", selection: $selectedCategoryID) {
                Text("None").tag(UUID?.none)

                ForEach(categories) { category in
                    Text(category.name).tag(Optional(category.id))
                }
            }
        } header: {
            Text("Category")
        } footer: {
            Text("If no category is set, it will default to Uncategorized.")
        }
    }

    private var sharedBalanceSection: some View {
        Section("Shared Balance") {
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
                Picker("Shared Balance", selection: accountBinding(for: mode)) {
                    Text("None").tag(UUID?.none)
                    ForEach(allocationAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
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

            if hasAnySharedBalanceAction || isLegacyDualConfiguration {
                Button("Clear Shared Balance Action", role: .destructive) {
                    draftSharedBalanceMode = nil
                    selectedAllocationAccountID = nil
                    allocationAmountText = ""
                    selectedOffsetAccountID = nil
                    offsetAmountText = ""
                    onSharedBalanceChanged?()
                }
            }

            if let sharedBalanceSummary, !isLegacyDualConfiguration {
                Text(sharedBalanceSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var sharedBalanceValidationMessage: String? {
        guard let mode = activeSharedBalanceMode else { return nil }

        guard enteredAmount > 0 else {
            return "Enter an expense amount first."
        }

        let selectedAccountID = mode == .split ? selectedAllocationAccountID : selectedOffsetAccountID
        let rawAmountText = mode == .split ? allocationAmountText : offsetAmountText

        guard selectedAccountID != nil else {
            return "Choose a Shared Balance."
        }

        let trimmedAmount = rawAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedAmount.isEmpty { return nil }

        guard let parsedAmount = CurrencyFormatter.parseAmount(trimmedAmount) else {
            return "Enter a valid amount."
        }

        guard parsedAmount > 0 else {
            return "Amount must be greater than 0."
        }

        guard parsedAmount <= enteredAmount else {
            return "Amount can't exceed the expense amount."
        }

        if mode == .offset,
           let account = allocationAccounts.first(where: { $0.id == selectedAccountID }) {
            let available = max(0, AllocationLedgerService.balance(for: account))
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
                onSharedBalanceChanged?()
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

// MARK: - Card tile ( uses CardVisualView)

private struct CardTile: View {
    let title: String
    let themeRaw: String
    let effectRaw: String
    let isSelected: Bool
    let onTap: () -> Void

    private let tileWidth: CGFloat = 160

    var body: some View {
        Button(action: onTap) {
            CardVisualView(
                title: title,
                theme: themeOption(from: themeRaw),
                effect: effectOption(from: effectRaw),
                minHeight: nil,
                showsShadow: false,
                titleFont: .headline,
                titlePadding: 12,
                titleOpacity: 0.82
            )
            .frame(width: tileWidth)
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.35) : Color.clear, lineWidth: 2)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.92))
                        .padding(10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func themeOption(from raw: String) -> CardThemeOption {
        CardThemeOption(rawValue: raw) ?? .charcoal
    }

    private func effectOption(from raw: String) -> CardEffectOption {
        CardEffectOption(rawValue: raw) ?? .plastic
    }
}
