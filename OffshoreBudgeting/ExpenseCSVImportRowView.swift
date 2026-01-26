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
    let onSetMerchant: (String) -> Void
    let onSetCategory: (Category?) -> Void
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

                    Text(row.finalDate, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text(row.finalAmount, format: CurrencyFormatter.currencyStyle())
                    .font(.headline)
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
                }

                if row.isMissingRequiredData {
                    Text("Add a name to import.")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            Text(csvSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var csvSummary: String {
        if let csvCategory = row.originalCategoryText, !csvCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "CSV: \(row.originalDescriptionText) • \(row.originalAmountText) • \(csvCategory)"
        }
        return "CSV: \(row.originalDescriptionText) • \(row.originalAmountText)"
    }
}
