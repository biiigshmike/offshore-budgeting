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

    // MARK: - Totals (confirmed formula)

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

    // MARK: - Styling

    private var valueColor: Color {
        actualSavings >= 0 ? .green : .red
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
                title: "What If?",
                subtitle: subtitleText,
                accent: valueColor,
                showsChevron: true
            ) {
                VStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .center, spacing: 6) {
                        Text("Actual Savings")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(actualSavings, format: CurrencyFormatter.currencyStyle())
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
        .accessibilityLabel("What If?")
        .accessibilityValue(CurrencyFormatter.string(from: actualSavings))
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
}
