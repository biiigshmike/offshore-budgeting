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

        var categoryByID: [UUID: Category] = [:]
        for category in categories {
            categoryByID[category.id] = category
        }

        var plannedByCategoryID: [UUID?: Double] = [:]
        var variableByCategoryID: [UUID?: Double] = [:]

        // MARK: - Planned

        for expense in plannedExpenses {
            guard
                expense.expenseDate >= rangeStart,
                expense.expenseDate <= rangeEnd
            else { continue }

            if let category = expense.category {
                categoryByID[category.id] = category
            }
            plannedByCategoryID[expense.category?.id, default: 0] += SavingsMathService.plannedBudgetImpactAmount(for: expense)
        }

        // MARK: - Variable

        for expense in variableExpenses {
            guard
                expense.transactionDate >= rangeStart,
                expense.transactionDate <= rangeEnd
            else { continue }

            if let category = expense.category {
                categoryByID[category.id] = category
            }
            variableByCategoryID[expense.category?.id, default: 0] += SavingsMathService.variableBudgetImpactAmount(for: expense)
        }

        // MARK: - Totals

        let categoryIDs = Set(plannedByCategoryID.keys).union(variableByCategoryID.keys)
        let totalSpent = categoryIDs.reduce(0) { partial, id in
            partial + plannedByCategoryID[id, default: 0] + variableByCategoryID[id, default: 0]
        }

        // MARK: - Build per-category metrics

        var metrics: [CategorySpendMetric] = []
        metrics.reserveCapacity(categoryByID.count + 1)

        for category in categoryByID.values {
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

        let uncategorizedPlanned = plannedByCategoryID[nil, default: 0]
        let uncategorizedVariable = variableByCategoryID[nil, default: 0]
        let uncategorizedTotal = uncategorizedPlanned + uncategorizedVariable

        if uncategorizedTotal > 0 {
            let percent = (totalSpent > 0) ? (uncategorizedTotal / totalSpent) : 0
            metrics.append(
                CategorySpendMetric(
                    categoryID: nil,
                    categoryName: "Uncategorized",
                    categoryColorHex: nil,
                    totalSpent: uncategorizedTotal,
                    plannedSpent: uncategorizedPlanned,
                    variableSpent: uncategorizedVariable,
                    percentOfTotal: percent
                )
            )
        }

        // Sort descending by spend
        metrics.sort { $0.totalSpent > $1.totalSpent }

        return HomeCategoryMetricsResult(metrics: metrics, totalSpent: totalSpent)
    }
}
