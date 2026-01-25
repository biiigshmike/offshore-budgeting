//
//  HomeWhatIfTile.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI

struct HomeWhatIfTile: View {

    let workspace: Workspace
    let categories: [Category]
    let incomes: [Income]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let startDate: Date
    let endDate: Date

    // MARK: - Store (global scenarios)

    private var scenarioStore: WhatIfScenarioStore {
        WhatIfScenarioStore(workspaceID: workspace.id)
    }

    // MARK: - Totals (baseline)

    private var actualIncomeTotal: Double {
        incomes
            .filter { !$0.isPlanned && isInRange($0.date) }
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

    // MARK: - Scenario (pinned global)

    private var pinnedScenarioInfo: WhatIfScenarioStore.GlobalScenarioInfo? {
        guard let pinnedID = scenarioStore.loadPinnedGlobalScenarioID() else { return nil }
        return scenarioStore.listGlobalScenarios().first(where: { $0.id == pinnedID })
    }

    private var pinnedOverridesByCategoryID: [UUID: Double]? {
        guard let pinnedID = scenarioStore.loadPinnedGlobalScenarioID() else { return nil }
        return scenarioStore.loadGlobalScenario(scenarioID: pinnedID)
    }

    private var baselineByCategoryID: [UUID: Double] {
        buildBaselineByCategoryID()
    }

    private var scenarioByCategoryID: [UUID: Double]? {
        guard let overrides = pinnedOverridesByCategoryID else { return nil }
        let ids = categories.map { $0.id }
        return scenarioStore.applyGlobalScenario(
            overrides: overrides,
            baselineByCategoryID: baselineByCategoryID,
            categories: ids
        )
    }

    private var scenarioTotalSpend: Double? {
        guard let scenario = scenarioByCategoryID else { return nil }
        return categories.reduce(0) { $0 + (scenario[$1.id, default: 0]) }
    }

    private var scenarioSavings: Double? {
        guard let spend = scenarioTotalSpend else { return nil }
        return actualIncomeTotal - spend
    }

    private var displayTitle: String {
        pinnedScenarioInfo?.name ?? "What If?"
    }

    private var displayValue: Double {
        // If a pinned scenario exists, show its savings; otherwise show actual savings.
        scenarioSavings ?? actualSavings
    }

    private var valueColor: Color {
        displayValue >= 0 ? .green : .red
    }

    private var subtitleText: String {
        "\(formattedDate(startDate)) - \(formattedDate(endDate))"
    }

    var body: some View {
        NavigationLink {
            WhatIfScenarioPlannerView(
                workspace: workspace,
                categories: categories,
                incomes: incomes,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                startDate: startDate,
                endDate: endDate
            )
        } label: {
            HomeTileContainer(
                title: displayTitle,
                subtitle: subtitleText,
                accent: valueColor,
                showsChevron: true
            ) {
                VStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .center, spacing: 6) {
                        Text(pinnedScenarioInfo == nil ? "Actual Savings" : "Scenario Savings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(displayValue, format: CurrencyFormatter.currencyStyle())
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(valueColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Text("Tap to plan scenarios and see how much you can potentially save.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(displayTitle)
        .accessibilityValue(CurrencyFormatter.string(from: displayValue))
        .accessibilityHint("Opens the scenario planner")
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

    private func buildBaselineByCategoryID() -> [UUID: Double] {
        var plannedByCategoryID: [UUID: Double] = [:]
        var variableByCategoryID: [UUID: Double] = [:]

        for expense in plannedExpenses {
            guard isInRange(expense.expenseDate), let category = expense.category else { continue }
            plannedByCategoryID[category.id, default: 0] += effectivePlannedExpenseAmount(expense)
        }

        for expense in variableExpenses {
            guard isInRange(expense.transactionDate), let category = expense.category else { continue }
            variableByCategoryID[category.id, default: 0] += expense.amount
        }

        var result: [UUID: Double] = [:]
        result.reserveCapacity(categories.count)

        for category in categories {
            let planned = plannedByCategoryID[category.id, default: 0]
            let variable = variableByCategoryID[category.id, default: 0]
            result[category.id] = max(0, planned + variable)
        }

        return result
    }
}
