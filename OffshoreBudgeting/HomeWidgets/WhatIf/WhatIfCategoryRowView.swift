//
//  WhatIfCategoryRowView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

struct WhatIfCategoryRowView: View {

    let categoryName: String
    let categoryHex: String
    let baselineMinAmount: Double
    let baselineMaxAmount: Double
    let baselineScenarioSpendAmount: Double

    @Binding var minAmount: Double
    @Binding var maxAmount: Double
    @Binding var scenarioSpendAmount: Double

    let currencyCode: String
    let onEditingBegan: () -> Void

    @State private var minText: String = ""
    @State private var maxText: String = ""
    @State private var scenarioText: String = ""
    @FocusState private var focusedField: FocusField?

    private enum FocusField: Hashable {
        case min
        case max
        case scenario
    }

    private var dotColor: Color {
        Color(hex: categoryHex) ?? .secondary
    }

    private var isDirty: Bool {
        abs(minAmount - baselineMinAmount) > 0.000_1
        || abs(maxAmount - baselineMaxAmount) > 0.000_1
        || abs(scenarioSpendAmount - baselineScenarioSpendAmount) > 0.000_1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(categoryName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .minimumScaleFactor(0.85)

                    Text(baselineSummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)

                if isDirty {
                    editedBadge
                }
            }

            HStack(spacing: 10) {
                minField
                maxField
                scenarioField
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            refreshTexts()
        }
        .onChange(of: minAmount) { _, _ in
            guard focusedField != .min else { return }
            refreshTexts()
        }
        .onChange(of: maxAmount) { _, _ in
            guard focusedField != .max else { return }
            refreshTexts()
        }
        .onChange(of: scenarioSpendAmount) { _, _ in
            guard focusedField != .scenario else { return }
            refreshTexts()
        }
        .onChange(of: focusedField) { oldField, newField in
            if let oldField {
                commitField(oldField)
            }
            if let newField {
                prepareFieldForEditing(newField)
                onEditingBegan()
            }
        }
        .onSubmit {
            if let focusedField {
                commitField(focusedField)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(categoryName)
        .accessibilityValue(
            String(
                format: String(
                    localized: "whatIf.categoryRow.accessibilityValueFormat",
                    defaultValue: "Min %1$@, Max %2$@, Scenario %3$@",
                    comment: "Accessibility summary for What If category row."
                ),
                locale: .current,
                formatCurrency(minAmount),
                formatCurrency(maxAmount),
                formatCurrency(scenarioSpendAmount)
            )
        )
    }

    private var minField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "common.min", defaultValue: "Min", comment: "Common label for minimum value."))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("", text: $minText)
                .focused($focusedField, equals: .min)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.automatic)
                .onChange(of: minText) { _, newValue in
                    guard focusedField == .min else { return }
                    if let parsed = CurrencyFormatter.parseAmount(newValue) {
                        minAmount = max(0, CurrencyFormatter.roundedToCurrency(parsed))
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var maxField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "common.max", defaultValue: "Max", comment: "Common label for maximum value."))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("", text: $maxText)
                .focused($focusedField, equals: .max)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.automatic)
                .onChange(of: maxText) { _, newValue in
                    guard focusedField == .max else { return }
                    if let parsed = CurrencyFormatter.parseAmount(newValue) {
                        maxAmount = max(0, CurrencyFormatter.roundedToCurrency(parsed))
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scenarioField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "whatIf.scenario", defaultValue: "Scenario", comment: "Label for scenario value field in What If category row."))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField("", text: $scenarioText)
                .focused($focusedField, equals: .scenario)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.leading)
                .textFieldStyle(.automatic)
                .onChange(of: scenarioText) { _, newValue in
                    guard focusedField == .scenario else { return }
                    if let parsed = CurrencyFormatter.parseAmount(newValue) {
                        scenarioSpendAmount = max(0, CurrencyFormatter.roundedToCurrency(parsed))
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var baselineSummaryText: String {
        if abs(baselineMinAmount - baselineMaxAmount) < 0.000_1 {
            return String(
                format: String(
                    localized: "whatIf.categoryRow.actualFormat",
                    defaultValue: "Actual: %1$@",
                    comment: "Baseline summary format for actual value."
                ),
                locale: .current,
                formatCurrency(baselineMinAmount)
            )
        }

        return String(
            format: String(
                localized: "whatIf.categoryRow.minMaxFormat",
                defaultValue: "Min: %1$@ • Max: %2$@",
                comment: "Baseline summary format showing minimum and maximum values."
            ),
            locale: .current,
            formatCurrency(baselineMinAmount),
            formatCurrency(baselineMaxAmount)
        )
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
        minText = CurrencyFormatter.editingString(from: minAmount)
        maxText = CurrencyFormatter.editingString(from: maxAmount)
        scenarioText = CurrencyFormatter.editingString(from: scenarioSpendAmount)
    }

    private func prepareFieldForEditing(_ field: FocusField) {
        switch field {
        case .min:
            if CurrencyFormatter.roundedToCurrency(minAmount) == 0 {
                minText = ""
            }
        case .max:
            if CurrencyFormatter.roundedToCurrency(maxAmount) == 0 {
                maxText = ""
            }
        case .scenario:
            if CurrencyFormatter.roundedToCurrency(scenarioSpendAmount) == 0 {
                scenarioText = ""
            }
        }
    }

    private func commitField(_ field: FocusField) {
        switch field {
        case .min:
            minAmount = committedAmount(from: minText, currentValue: minAmount)
            minText = CurrencyFormatter.editingString(from: minAmount)
        case .max:
            maxAmount = committedAmount(from: maxText, currentValue: maxAmount)
            maxText = CurrencyFormatter.editingString(from: maxAmount)
        case .scenario:
            scenarioSpendAmount = committedAmount(from: scenarioText, currentValue: scenarioSpendAmount)
            scenarioText = CurrencyFormatter.editingString(from: scenarioSpendAmount)
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
            .presentation(.standard)
        )
    }
}
