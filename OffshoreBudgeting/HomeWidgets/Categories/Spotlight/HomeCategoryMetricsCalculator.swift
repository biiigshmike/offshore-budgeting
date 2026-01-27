//
//  HomeCategoryMetricsCalculator.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import Foundation

struct HomeCategoryMetricsCalculator {

    // MARK: - Public

    static func calculate(
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        rangeStart: Date,
        rangeEnd: Date
    ) -> HomeCategoryMetricsResult {

        var plannedByCategoryID: [UUID: Double] = [:]
        var variableByCategoryID: [UUID: Double] = [:]

        // MARK: - Planned (effective amount)

        for expense in plannedExpenses {
            guard
                expense.expenseDate >= rangeStart,
                expense.expenseDate <= rangeEnd,
                let category = expense.category
            else { continue }

            let effectiveAmount: Double = (expense.actualAmount > 0) ? expense.actualAmount : expense.plannedAmount
            plannedByCategoryID[category.id, default: 0] += effectiveAmount
        }

        // MARK: - Variable

        for expense in variableExpenses {
            guard
                expense.transactionDate >= rangeStart,
                expense.transactionDate <= rangeEnd,
                let category = expense.category
            else { continue }

            variableByCategoryID[category.id, default: 0] += expense.amount
        }

        // MARK: - Totals

        let totalSpent: Double = categories.reduce(0) { partial, category in
            let planned = plannedByCategoryID[category.id, default: 0]
            let variable = variableByCategoryID[category.id, default: 0]
            return partial + planned + variable
        }

        // MARK: - Build per-category metrics

        var metrics: [CategorySpendMetric] = []
        metrics.reserveCapacity(categories.count)

        for category in categories {
            let planned = plannedByCategoryID[category.id, default: 0]
            let variable = variableByCategoryID[category.id, default: 0]
            let total = planned + variable

            // Spotlight ignores zero-spend categories by default
            guard total > 0 else { continue }

            let percent: Double = (totalSpent > 0) ? (total / totalSpent) : 0

            metrics.append(
                CategorySpendMetric(
                    categoryID: category.id,
                    categoryName: category.name,
                    categoryColorHex: category.hexColor,
                    totalSpent: total,
                    plannedSpent: planned,
                    variableSpent: variable,
                    percentOfTotal: percent
                )
            )
        }

        // Sort descending by spend
        metrics.sort { $0.totalSpent > $1.totalSpent }

        return HomeCategoryMetricsResult(metrics: metrics, totalSpent: totalSpent)
    }
}
