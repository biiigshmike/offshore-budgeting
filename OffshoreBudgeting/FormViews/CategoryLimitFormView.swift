//
//  CategoryLimitFormView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI

/// Shared form UI for editing a budget-scoped category spending limit.
///
/// This view is intentionally "dumb" (pure UI). Validation + persistence
/// live in `EditCategoryLimitView`.
struct CategoryLimitFormView: View {

    let categoryName: String
    let tint: Color

    let plannedAmount: Double
    let variableAmount: Double
    let totalAmount: Double

    let gaugeMin: Double
    let gaugeMax: Double?

    @Binding var minText: String
    @Binding var maxText: String

    let validationMessage: String?

    var body: some View {
        Form {
            Section {
                summaryGaugeCard
            }

            Section("Set Spending Limits") {
                TextField("Minimum", text: $minText)
                    .keyboardType(.decimalPad)

                TextField("Maximum", text: $maxText)
                    .keyboardType(.decimalPad)

                if let validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Gauge

    private var summaryGaugeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Total (Planned + Variable)")
                .font(.headline.weight(.semibold))

            if let gaugeMax, gaugeMax > gaugeMin {
                Gauge(value: min(totalAmount, gaugeMax), in: gaugeMin...gaugeMax) {
                    EmptyView()
                } currentValueLabel: {
                    Text(totalAmount, format: CurrencyFormatter.currencyStyle())
                        .font(.headline.weight(.semibold))
                } minimumValueLabel: {
                    Text(gaugeMin, format: CurrencyFormatter.currencyStyle())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text(gaugeMax, format: CurrencyFormatter.currencyStyle())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tint(tint)
            } else {
                Text(totalAmount, format: CurrencyFormatter.currencyStyle())
                    .font(.title3.weight(.semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                amountLine(label: "Planned", amount: plannedAmount)
                amountLine(label: "Variable", amount: variableAmount)
                amountLine(label: "Total", amount: totalAmount)
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }

    private func amountLine(label: String, amount: Double) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(amount, format: CurrencyFormatter.currencyStyle())
                .font(.footnote.weight(.semibold))
        }
    }
}
