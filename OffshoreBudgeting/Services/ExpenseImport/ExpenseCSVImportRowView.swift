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
    let onSetAllocationAccount: (AllocationAccount?) -> Void
    let onSetAllocationAmount: (String) -> Void
    let onToggleRemember: () -> Void

    @State private var amountDraft: String
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
        onSetAllocationAccount: @escaping (AllocationAccount?) -> Void,
        onSetAllocationAmount: @escaping (String) -> Void,
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
        self.onSetAllocationAccount = onSetAllocationAccount
        self.onSetAllocationAmount = onSetAllocationAmount
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
        .onChange(of: row.id) { _, _ in
            amountDraft = CurrencyFormatter.editingString(from: row.finalAmount)
        }
        .onChange(of: row.finalAmount) { _, newValue in
            if !isAmountFieldFocused {
                amountDraft = CurrencyFormatter.editingString(from: newValue)
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
        HStack(spacing: 10) {
            Text("Shared Balance")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Shared Balance", selection: Binding(
                get: { row.selectedAllocationAccount?.id },
                set: { newID in
                    let match = allAllocationAccounts.first(where: { $0.id == newID })
                    onSetAllocationAccount(match)
                }
            )) {
                Text("None").tag(UUID?.none)
                ForEach(allAllocationAccounts, id: \.id) { account in
                    Text(account.name).tag(Optional(account.id))
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            TextField(
                "Split",
                text: Binding(
                    get: { row.allocationAmountText },
                    set: { onSetAllocationAmount($0) }
                )
            )
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .disabled(row.selectedAllocationAccount == nil)
            .frame(maxWidth: 110)
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

    private var importSummary: String {
        if let csvCategory = row.originalCategoryText, !csvCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Imported: \(row.originalDescriptionText) • \(row.originalAmountText) • \(csvCategory)"
        }
        return "Imported: \(row.originalDescriptionText) • \(row.originalAmountText)"
    }
}
