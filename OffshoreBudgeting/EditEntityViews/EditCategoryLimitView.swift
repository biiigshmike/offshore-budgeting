//
//  EditCategoryLimitView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI
import SwiftData

struct EditCategoryLimitView: View {
    let budget: Budget
    let category: Category

    /// Already-filtered contributions from BudgetDetailView (within budget window + category filter).
    let plannedContribution: Double
    let variableContribution: Double

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var minText: String = ""
    @State private var maxText: String = ""

    @State private var limit: BudgetCategoryLimit? = nil

    private var total: Double { plannedContribution + variableContribution }

    private var categoryColor: Color {
        Color(hex: category.hexColor) ?? Color.accentColor
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    capGaugeSection
                }

                Section("Set Spending Limits") {
                    TextField("Minimum", text: $minText)
                        .keyboardType(.decimalPad)

                    TextField("Maximum", text: $maxText)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            save()
                            dismiss()
                        }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.glassProminent)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") {
                            save()
                            dismiss()
                        }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                    }
                }
            }
            .onAppear {
                loadExisting()
                applyScreenshotPrefillIfNeeded()
            }
        }
    }

    // MARK: - Gauge

    private var capGaugeSection: some View {
        
        VStack(alignment: .leading, spacing: 12) {
            if let capMax = parsedMax {
                let safeMin = min(gaugeMin, capMax)
                let safeMax = Swift.max(gaugeMin, capMax)
                let safeValue = Swift.min(Swift.max(total, safeMin), safeMax)

                Gauge(value: safeValue, in: safeMin...safeMax) {
                    Text("Total")
                } currentValueLabel: {
                    Text(total, format: CurrencyFormatter.currencyStyle())
                } minimumValueLabel: {
                    Text(safeMin, format: CurrencyFormatter.currencyStyle())
                } maximumValueLabel: {
                    Text(safeMax, format: CurrencyFormatter.currencyStyle())
                }
                .tint(categoryColor)
            } else {
                // No max cap, keep it useful but visually neutral.
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.secondary.opacity(0.12))
                        .frame(height: 14)

                    Text(total, format: CurrencyFormatter.currencyStyle())
                        .font(.headline.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Planned")
                    Spacer()
                    Text(plannedContribution, format: CurrencyFormatter.currencyStyle())
                }

                HStack {
                    Text("Variable")
                    Spacer()
                    Text(variableContribution, format: CurrencyFormatter.currencyStyle())
                }

                Divider()

                HStack {
                    Text("Total")
                        .font(.body.weight(.semibold))
                    Spacer()
                    Text(total, format: CurrencyFormatter.currencyStyle())
                        .font(.body.weight(.semibold))
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    private var gaugeMin: Double {
        parsedMin ?? 0
    }

    // MARK: - Parsing

    private var parsedMin: Double? { parseMoney(minText) }
    private var parsedMax: Double? { parseMoney(maxText) }

    private func parseMoney(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return CurrencyFormatter.parseAmount(trimmed)
    }

    // MARK: - Load / Save

    private func loadExisting() {
        if let existing = (budget.categoryLimits ?? []).first(where: { $0.category?.id == category.id }) {
            limit = existing
            if let min = existing.minAmount {
                minText = CurrencyFormatter.editingString(from: min)
            }
            if let max = existing.maxAmount {
                maxText = CurrencyFormatter.editingString(from: max)
            }
        } else {
            limit = nil
            minText = ""
            maxText = ""
        }
    }

    private func applyScreenshotPrefillIfNeeded() {
        guard DebugScreenshotFormDefaults.isEnabled else { return }

        let trimmedMin = minText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedMax = maxText.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedMin.isEmpty && trimmedMax.isEmpty {
            minText = DebugScreenshotFormDefaults.categoryLimitMinText
            maxText = DebugScreenshotFormDefaults.categoryLimitMaxText
        }
    }

    private var canSave: Bool {
        // Allow empty fields (clears values), but if both are provided ensure min <= max.
        if let min = parsedMin, let max = parsedMax {
            return min <= max
        }
        return true
    }

    private func save() {
        let min = parsedMin
        let max = parsedMax

        if let limit {
            limit.minAmount = min
            limit.maxAmount = max

            // If both nil, remove the record to keep the graph clean.
            if min == nil && max == nil {
                modelContext.delete(limit)
            }
        } else {
            // Only create a record if actually needed to have at least one bound.
            guard min != nil || max != nil else { return }

            let newLimit = BudgetCategoryLimit(minAmount: min, maxAmount: max, budget: budget, category: category)
            modelContext.insert(newLimit)
        }
    }
}
