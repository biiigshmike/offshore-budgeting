//
//  HomeCategoryMetricsCalculatorTests.swift
//  OffshoreBudgetingTests
//
//  Created by Codex on 5/28/26.
//

import Foundation
import Testing
@testable import Offshore

struct HomeCategoryMetricsCalculatorTests {

    @Test func categorySpotlight_splitExpensesUseOwnedBudgetImpactAndKeepGrossLedger() throws {
        let travel = Category(name: "Travel", hexColor: "#0066AA")
        let account = AllocationAccount(name: "Shared")
        let planned = PlannedExpense(
            title: "Hotel",
            plannedAmount: 120,
            actualAmount: 100,
            expenseDate: date(2026, 4, 5),
            category: travel
        )
        let plannedAllocation = ExpenseAllocation(
            allocatedAmount: 30,
            preservesGrossAmount: true,
            account: account,
            plannedExpense: planned
        )
        planned.allocation = plannedAllocation

        let variable = VariableExpense(
            descriptionText: "Dinner",
            amount: 100,
            transactionDate: date(2026, 4, 6),
            category: travel
        )
        let variableAllocation = ExpenseAllocation(
            allocatedAmount: 40,
            preservesGrossAmount: true,
            account: account,
            expense: variable
        )
        variable.allocation = variableAllocation

        let result = HomeCategoryMetricsCalculator.calculate(
            categories: [travel],
            plannedExpenses: [planned],
            variableExpenses: [variable],
            rangeStart: date(2026, 4, 1),
            rangeEnd: date(2026, 4, 30)
        )
        let metric = try #require(result.metrics.first)

        #expect(SavingsMathService.grossEffectiveAmount(for: planned) == 100)
        #expect(SavingsMathService.variableGrossAmount(for: variable) == 100)
        #expect(metric.plannedSpent == 70)
        #expect(metric.variableSpent == 60)
        #expect(metric.totalSpent == 130)
        #expect(result.totalSpent == 130)
    }

    @Test func categorySpotlight_totalSpentMatchesSpendTrendsIncludingSplitsAndUncategorized() throws {
        let groceries = Category(name: "Groceries", hexColor: "#00AA00")
        let account = AllocationAccount(name: "Shared")
        let groceriesExpense = VariableExpense(
            descriptionText: "Market",
            amount: 100,
            transactionDate: date(2026, 4, 5),
            category: groceries
        )
        let allocation = ExpenseAllocation(
            allocatedAmount: 40,
            preservesGrossAmount: true,
            account: account,
            expense: groceriesExpense
        )
        groceriesExpense.allocation = allocation

        let uncategorizedPlanned = PlannedExpense(
            title: "Misc plan",
            plannedAmount: 25,
            expenseDate: date(2026, 4, 6)
        )
        let uncategorizedVariable = VariableExpense(
            descriptionText: "Misc",
            amount: 15,
            transactionDate: date(2026, 4, 7)
        )

        let spotlight = HomeCategoryMetricsCalculator.calculate(
            categories: [groceries],
            plannedExpenses: [uncategorizedPlanned],
            variableExpenses: [groceriesExpense, uncategorizedVariable],
            rangeStart: date(2026, 4, 1),
            rangeEnd: date(2026, 4, 30)
        )
        let trends = HomeSpendTrendsAggregator.calculate(
            period: .period,
            categories: [groceries],
            plannedExpenses: [uncategorizedPlanned],
            variableExpenses: [groceriesExpense, uncategorizedVariable],
            rangeStart: date(2026, 4, 1),
            rangeEnd: date(2026, 4, 30),
            cardFilter: nil
        )
        let uncategorized = try #require(spotlight.metrics.first { $0.categoryID == nil })
        let groceriesMetric = try #require(spotlight.metrics.first { $0.categoryID == groceries.id })

        #expect(uncategorized.categoryName == "Uncategorized")
        #expect(uncategorized.id == CategorySpendMetric.uncategorizedID)
        #expect(uncategorized.totalSpent == 40)
        #expect(groceriesMetric.totalSpent == 60)
        #expect(spotlight.totalSpent == trends.totalSpent)
        #expect(spotlight.totalSpent == 100)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }
}
