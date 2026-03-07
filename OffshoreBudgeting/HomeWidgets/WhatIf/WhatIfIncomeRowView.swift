//
//  WhatIfIncomeRowView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 3/2/26.
//

import SwiftUI

struct WhatIfIncomeRowView: View {

    let baselinePlannedAmount: Double
    let baselineActualAmount: Double

    @Binding var plannedAmount: Double
    @Binding var actualAmount: Double

    let currencyCode: String

    @State private var plannedText: String = ""
    @State private var actualText: String = ""
    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case planned
        case actual
    }

    private var isDirty: Bool {
        abs(plannedAmount - baselinePlannedAmount) > 0.000_1
        || abs(actualAmount - baselineActualAmount) > 0.000_1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isDirty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Spacer(minLength: 0)
                    editedBadge
                }
            }

            HStack(spacing: 10) {
                plannedField
                actualField
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            refreshTexts()
        }
        .onChange(of: plannedAmount) { _, _ in
            guard focusedField != .planned else { return }
            refreshTexts()
        }
        .onChange(of: actualAmount) { _, _ in
            guard focusedField != .actual else { return }
            refreshTexts()
        }
        .onChange(of: focusedField) { oldField, newField in
            if let oldField {
                commitField(oldField)
            }

            if let newField {
                prepareFieldForEditing(newField)
            }
        }
        .onSubmit {
            if let focusedField {
                commitField(focusedField)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "homeWidget.income", defaultValue: "Income", comment: "Pinned home widget title for income metrics."))
        .accessibilityValue(
            String(
                format: String(
                    localized: "whatIf.incomeRow.accessibilityValueFormat",
                    defaultValue: "Planned %1$@, Actual %2$@",
                    comment: "Accessibility summary for What If income row."
                ),
                locale: .current,
                formatCurrency(plannedAmount),
                formatCurrency(actualAmount)
            )
        )
    }

    private var plannedField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "common.planned", defaultValue: "Planned", comment: "Common label for planned values."))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("", text: $plannedText)
                .focused($focusedField, equals: .planned)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.automatic)
                .onChange(of: plannedText) { _, newValue in
                    guard focusedField == .planned else { return }
                    if let parsed = CurrencyFormatter.parseAmount(newValue) {
                        plannedAmount = max(0, CurrencyFormatter.roundedToCurrency(parsed))
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actualField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "common.actual", defaultValue: "Actual", comment: "Common label for actual values."))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("", text: $actualText)
                .focused($focusedField, equals: .actual)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.automatic)
                .onChange(of: actualText) { _, newValue in
                    guard focusedField == .actual else { return }
                    if let parsed = CurrencyFormatter.parseAmount(newValue) {
                        actualAmount = max(0, CurrencyFormatter.roundedToCurrency(parsed))
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Badge

    private var editedBadge: some View {
        Text(String(localized: "common.edited", defaultValue: "Edited", comment: "Badge label indicating a value has been edited."))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.thinMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.secondary.opacity(0.25), lineWidth: 1)
            }
            .accessibilityLabel(String(localized: "common.edited", defaultValue: "Edited", comment: "Badge label indicating a value has been edited."))
    }

    // MARK: - Helpers

    private func refreshTexts() {
        plannedText = CurrencyFormatter.editingString(from: plannedAmount)
        actualText = CurrencyFormatter.editingString(from: actualAmount)
    }

    private func prepareFieldForEditing(_ field: FocusField) {
        switch field {
        case .planned:
            if CurrencyFormatter.roundedToCurrency(plannedAmount) == 0 {
                plannedText = ""
            }
        case .actual:
            if CurrencyFormatter.roundedToCurrency(actualAmount) == 0 {
                actualText = ""
            }
        }
    }

    private func commitField(_ field: FocusField) {
        switch field {
        case .planned:
            plannedAmount = committedAmount(from: plannedText, currentValue: plannedAmount)
            plannedText = CurrencyFormatter.editingString(from: plannedAmount)
        case .actual:
            actualAmount = committedAmount(from: actualText, currentValue: actualAmount)
            actualText = CurrencyFormatter.editingString(from: actualAmount)
        }
    }

    private func committedAmount(from text: String, currentValue: Double) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return 0
        }

        if let parsed = CurrencyFormatter.parseAmount(trimmed) {
            return max(0, CurrencyFormatter.roundedToCurrency(parsed))
        }

        return max(0, CurrencyFormatter.roundedToCurrency(currentValue))
    }

    private func formatCurrency(_ value: Double) -> String {
        value.formatted(
            .currency(code: currencyCode)
            .presentation(.narrow)
        )
    }
}
