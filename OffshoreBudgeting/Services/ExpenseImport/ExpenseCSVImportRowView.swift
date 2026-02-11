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
    let onToggleInclude: () -> Void
    let onSetDate: (Date) -> Void
    let onSetMerchant: (String) -> Void
    let onSetCategory: (Category?) -> Void
    let onSetKind: (ExpenseCSVImportKind) -> Void
    let onToggleRemember: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            HStack(alignment: .firstTextBaseline) {
                Button {
                    onToggleInclude()
                } label: {
                    Image(systemName: row.includeInImport ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.includeInImport ? "Included" : "Excluded")

                VStack(alignment: .leading, spacing: 2) {
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

                    HStack(spacing: 6) {
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
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(row.finalAmount, format: CurrencyFormatter.currencyStyle())
                        .font(.headline)

                    Picker("Type", selection: Binding(
                        get: { row.kind },
                        set: { onSetKind($0) }
                    )) {
                        Text("Expense").tag(ExpenseCSVImportKind.expense)
                        Text("Income").tag(ExpenseCSVImportKind.income)
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            if row.kind == .expense {
                HStack(spacing: 10) {
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

                    Toggle(isOn: Binding(
                        get: { row.rememberMapping },
                        set: { _ in onToggleRemember() }
                    )) {
                        Text("Remember")
                    }
                    .labelsHidden()
                    .tint(Color("AccentColor"))
                }

                if row.isMissingRequiredData {
                    Text(row.finalMerchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "Add a merchant name to import."
                         : "Choose a category to import.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            } else {
                HStack(spacing: 10) {
                    Text("Imports as Income (linked to this card)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Toggle(isOn: Binding(
                        get: { row.rememberMapping },
                        set: { _ in onToggleRemember() }
                    )) {
                        Text("Remember")
                    }
                    .labelsHidden()
                    .tint(Color("AccentColor"))
                }

                if row.isMissingRequiredData {
                    Text("Add a name to import.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Text(importSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var importSummary: String {
        if let csvCategory = row.originalCategoryText, !csvCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Imported: \(row.originalDescriptionText) • \(row.originalAmountText) • \(csvCategory)"
        }
        return "Imported: \(row.originalDescriptionText) • \(row.originalAmountText)"
    }
}
