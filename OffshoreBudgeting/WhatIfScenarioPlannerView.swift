//
//  WhatIfScenarioPlannerView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

struct WhatIfScenarioPlannerView: View {

    let workspace: Workspace
    let categories: [Category]
    let incomes: [Income]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date

    @State private var scenarioByCategoryID: [UUID: Double] = [:]
    @State private var didLoadScenario: Bool = false

    @State private var baselineByCategoryID: [UUID: Double] = [:]

    @AppStorage("general_currencyCode")
    private var currencyCode: String = "USD"

    // MARK: - Derived (baseline totals)

    private var actualIncomeTotal: Double {
        incomes
            .filter { !$0.isPlanned }
            .filter { isInRange($0.date) }
            .reduce(0) { $0 + $1.amount }
    }

    private var plannedExpensesEffectiveTotal: Double {
        plannedExpenses
            .filter { isInRange($0.expenseDate) }
            .reduce(0) { $0 + effectivePlannedExpenseAmount($1) }
    }

    private var variableExpensesTotal: Double {
        variableExpenses
            .filter { isInRange($0.transactionDate) }
            .reduce(0) { $0 + $1.amount }
    }

    private var actualSavings: Double {
        actualIncomeTotal - (plannedExpensesEffectiveTotal + variableExpensesTotal)
    }

    // MARK: - Scenario totals

    private var scenarioTotalSpend: Double {
        categories.reduce(0) { partial, category in
            partial + (scenarioByCategoryID[category.id, default: 0])
        }
    }

    private var scenarioSavings: Double {
        actualIncomeTotal - scenarioTotalSpend
    }

    private var subtitleText: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    private var savingsLabel: String {
        scenarioSavings >= 0 ? "Savings" : "Over"
    }

    private var savingsIconName: String {
        scenarioSavings >= 0 ? "arrow.up.circle.fill" : "exclamationmark.triangle.fill"
    }

    private var savingsColor: Color {
        scenarioSavings >= 0 ? .green : .red
    }

    private var savingsValueMagnitude: Double {
        scenarioSavings >= 0 ? scenarioSavings : abs(scenarioSavings)
    }

    private var donutSlices: [DonutSlice] {
        // Category slices
        var slices: [DonutSlice] = categories.compactMap { category in
            let value = scenarioByCategoryID[category.id, default: 0]
            guard value > 0 else { return nil }

            let color = Color(hex: category.hexColor) ?? .secondary
            return DonutSlice(id: category.id, title: category.name, value: value, color: color)
        }

        // Special slice (Savings/Over)
        if savingsValueMagnitude > 0 {
            let role: DonutSliceRole = (scenarioSavings >= 0) ? .savings : .over

            slices.append(
                DonutSlice(
                    title: savingsLabel,
                    value: savingsValueMagnitude,
                    color: savingsColor.opacity(0.85),
                    role: role
                )
            )
        }

        // If everything is zero, DonutChartView will show its empty state.
        return slices
    }

    var body: some View {
        List {
            Section {
                headerBlock
                    .listRowSeparator(.hidden)

                DonutChartView(
                    slices: donutSlices,
                    innerRadiusRatio: 0.70,
                    centerTitle: savingsLabel,
                    centerValueText: CurrencyFormatter.string(from: savingsValueMagnitude),
                    showsLegend: false
                )
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .listRowSeparator(.hidden)

                savingsLegendRow
                    .listRowSeparator(.hidden)
            }

            Section("Categories") {
                ForEach(categories) { category in
                    WhatIfCategoryRowView(
                        categoryName: category.name,
                        categoryHex: category.hexColor,
                        baselineAmount: baselineByCategoryID[category.id, default: 0],
                        amount: bindingForCategory(category.id),
                        step: 10,
                        currencyCode: currencyCode
                    )
                }
            }

            Section {
                Button(role: .destructive) {
                    clearScenario()
                } label: {
                    Text("Clear")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("What If?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text("What If?")
                        .font(.headline)
                    Text(subtitleText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            loadOrSeedScenarioIfNeeded()
        }
        .onChange(of: scenarioByCategoryID) { _, _ in
            guard didLoadScenario else { return }
            persistScenario()
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(subtitleText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scenario • \(savingsLabel)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(scenarioSavings, format: CurrencyFormatter.currencyStyle())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(savingsColor)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Actual Savings")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(actualSavings, format: CurrencyFormatter.currencyStyle())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(actualSavings >= 0 ? .green : .red)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private var savingsLegendRow: some View {
        HStack(spacing: 10) {
            Image(systemName: savingsIconName)
                .foregroundStyle(savingsColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(savingsLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(savingsLabel)
        .accessibilityValue(CurrencyFormatter.string(from: savingsValueMagnitude))
    }

    // MARK: - Scenario binding

    private func bindingForCategory(_ id: UUID) -> Binding<Double> {
        Binding(
            get: { scenarioByCategoryID[id, default: 0] },
            set: { newValue in
                scenarioByCategoryID[id] = max(0, newValue)
            }
        )
    }

    // MARK: - Load / Seed / Persist

    private func loadOrSeedScenarioIfNeeded() {
        guard didLoadScenario == false else { return }

        // Baseline = actual per-category spend for this range (planned effective + variable combined)
        baselineByCategoryID = buildBaselineByCategoryID()

        let store = WhatIfScenarioStore(workspaceID: workspace.id)
        if let saved = store.load(startDate: startDate, endDate: endDate) {
            // Ensure all categories exist (even if 0)
            var merged: [UUID: Double] = [:]
            for c in categories {
                merged[c.id] = max(0, saved[c.id] ?? baselineByCategoryID[c.id, default: 0])
            }
            scenarioByCategoryID = merged
        } else {
            // Seed from baseline
            scenarioByCategoryID = baselineByCategoryID
        }

        didLoadScenario = true
    }

    private func persistScenario() {
        let store = WhatIfScenarioStore(workspaceID: workspace.id)
        store.save(scenarioByCategoryID, startDate: startDate, endDate: endDate)
    }

    private func clearScenario() {
        let store = WhatIfScenarioStore(workspaceID: workspace.id)
        store.clear(startDate: startDate, endDate: endDate)

        // Reset state back to baseline for this range
        baselineByCategoryID = buildBaselineByCategoryID()
        scenarioByCategoryID = baselineByCategoryID
    }

    // MARK: - Baseline builder

    private func buildBaselineByCategoryID() -> [UUID: Double] {
        var plannedByCategoryID: [UUID: Double] = [:]
        var variableByCategoryID: [UUID: Double] = [:]

        for expense in plannedExpenses {
            guard
                isInRange(expense.expenseDate),
                let category = expense.category
            else { continue }

            let effective = effectivePlannedExpenseAmount(expense)
            plannedByCategoryID[category.id, default: 0] += effective
        }

        for expense in variableExpenses {
            guard
                isInRange(expense.transactionDate),
                let category = expense.category
            else { continue }

            variableByCategoryID[category.id, default: 0] += expense.amount
        }

        // Include ALL categories, even if 0
        var result: [UUID: Double] = [:]
        result.reserveCapacity(categories.count)

        for category in categories {
            let planned = plannedByCategoryID[category.id, default: 0]
            let variable = variableByCategoryID[category.id, default: 0]
            result[category.id] = max(0, planned + variable)
        }

        return result
    }

    // MARK: - Helpers

    private func isInRange(_ date: Date) -> Bool {
        (date >= startDate) && (date <= endDate)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    private func effectivePlannedExpenseAmount(_ expense: PlannedExpense) -> Double {
        expense.actualAmount > 0 ? expense.actualAmount : expense.plannedAmount
    }
}
