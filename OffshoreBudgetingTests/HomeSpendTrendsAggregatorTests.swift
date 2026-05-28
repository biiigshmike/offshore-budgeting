//
//  HomeSpendTrendsAggregatorTests.swift
//  OffshoreBudgetingTests
//
//  Created by Codex on 5/27/26.
//

import Foundation
import Testing
@testable import Offshore

struct HomeSpendTrendsAggregatorTests {

    @Test func bucketExpenseItems_includePlannedAndVariableRowsInBucket() throws {
        let category = Category(name: "Food", hexColor: "#00AA00")
        let card = Card(name: "Everyday")
        let planned = PlannedExpense(
            title: "Meal plan",
            plannedAmount: 100,
            actualAmount: 75,
            expenseDate: date(2026, 1, 2, hour: 9),
            card: card,
            category: category
        )
        let variable = VariableExpense(
            descriptionText: "Market",
            amount: 25,
            transactionDate: date(2026, 1, 2, hour: 15),
            card: card,
            category: category
        )

        let result = HomeSpendTrendsAggregator.calculate(
            period: .period,
            categories: [category],
            plannedExpenses: [planned],
            variableExpenses: [variable],
            rangeStart: date(2026, 1, 1),
            rangeEnd: date(2026, 1, 3),
            cardFilter: nil
        )

        let bucket = try #require(bucketFor(date(2026, 1, 2), in: result))
        #expect(bucket.expenseItems.map(\.id) == [
            "variable-\(variable.id.uuidString)",
            "planned-\(planned.id.uuidString)"
        ])
        #expect(abs(bucket.total - 100) < 0.001)
    }

    @Test func bucketExpenseItems_respectDateRangeAndCardFilter() throws {
        let category = Category(name: "General", hexColor: "#3366FF")
        let blueCard = Card(name: "Blue Card")
        let redCard = Card(name: "Red Card")

        let includedPlanned = PlannedExpense(
            title: "Blue planned",
            plannedAmount: 40,
            expenseDate: date(2026, 1, 2, hour: 8),
            card: blueCard,
            category: category
        )
        let includedVariable = VariableExpense(
            descriptionText: "Blue variable",
            amount: 60,
            transactionDate: date(2026, 1, 2, hour: 12),
            card: blueCard,
            category: category
        )
        let wrongCard = VariableExpense(
            descriptionText: "Red variable",
            amount: 90,
            transactionDate: date(2026, 1, 2, hour: 13),
            card: redCard,
            category: category
        )
        let outOfRange = PlannedExpense(
            title: "Later blue planned",
            plannedAmount: 120,
            expenseDate: date(2026, 1, 4, hour: 8),
            card: blueCard,
            category: category
        )

        let result = HomeSpendTrendsAggregator.calculate(
            period: .period,
            categories: [category],
            plannedExpenses: [includedPlanned, outOfRange],
            variableExpenses: [includedVariable, wrongCard],
            rangeStart: date(2026, 1, 1),
            rangeEnd: date(2026, 1, 3),
            cardFilter: blueCard
        )

        let bucket = try #require(bucketFor(date(2026, 1, 2), in: result))
        #expect(Set(bucket.expenseItems.map(\.id)) == Set([
            "planned-\(includedPlanned.id.uuidString)",
            "variable-\(includedVariable.id.uuidString)"
        ]))
        #expect(abs(bucket.total - 100) < 0.001)
    }

    @Test func bucketExpenseItems_useActualAndSignedAmountsForBucketTotals() throws {
        let category = Category(name: "Shopping", hexColor: "#AA00AA")
        let card = Card(name: "Everyday")
        let actualPlanned = PlannedExpense(
            title: "Recorded plan",
            plannedAmount: 100,
            actualAmount: 80,
            expenseDate: date(2026, 1, 2, hour: 9),
            card: card,
            category: category
        )
        let debit = VariableExpense(
            descriptionText: "Purchase",
            amount: 50,
            transactionDate: date(2026, 1, 2, hour: 13),
            card: card,
            category: category
        )
        let credit = VariableExpense(
            descriptionText: "Return",
            amount: 20,
            kindRaw: VariableExpenseKind.credit.rawValue,
            transactionDate: date(2026, 1, 2, hour: 16),
            card: card,
            category: category
        )

        let result = HomeSpendTrendsAggregator.calculate(
            period: .period,
            categories: [category],
            plannedExpenses: [actualPlanned],
            variableExpenses: [debit, credit],
            rangeStart: date(2026, 1, 1),
            rangeEnd: date(2026, 1, 3),
            cardFilter: nil
        )

        let bucket = try #require(bucketFor(date(2026, 1, 2), in: result))
        let plannedItem = bucket.expenseItems.first { $0.id == "planned-\(actualPlanned.id.uuidString)" }
        let debitItem = bucket.expenseItems.first { $0.id == "variable-\(debit.id.uuidString)" }
        let creditItem = bucket.expenseItems.first { $0.id == "variable-\(credit.id.uuidString)" }

        #expect(abs((plannedItem?.amount ?? 0) - 80) < 0.001)
        #expect(abs((debitItem?.amount ?? 0) - 50) < 0.001)
        #expect(abs((creditItem?.amount ?? 0) - (-20)) < 0.001)
        #expect(abs(bucket.expenseItems.reduce(0) { $0 + $1.amount } - bucket.total) < 0.001)
        #expect(abs(bucket.total - 110) < 0.001)
    }

    @Test func bucketExpenseItems_useOwnedBudgetImpactForSplitExpenses() throws {
        let category = Category(name: "Travel", hexColor: "#0066AA")
        let card = Card(name: "Everyday")
        let account = AllocationAccount(name: "Shared")
        let planned = PlannedExpense(
            title: "Hotel",
            plannedAmount: 100,
            actualAmount: 100,
            expenseDate: date(2026, 1, 2, hour: 9),
            card: card,
            category: category
        )
        let plannedAllocation = ExpenseAllocation(
            allocatedAmount: 40,
            preservesGrossAmount: true,
            account: account,
            plannedExpense: planned
        )
        planned.allocation = plannedAllocation

        let variable = VariableExpense(
            descriptionText: "Dinner",
            amount: 100,
            transactionDate: date(2026, 1, 2, hour: 15),
            card: card,
            category: category
        )
        let variableAllocation = ExpenseAllocation(
            allocatedAmount: 50,
            preservesGrossAmount: true,
            account: account,
            expense: variable
        )
        variable.allocation = variableAllocation

        let result = HomeSpendTrendsAggregator.calculate(
            period: .period,
            categories: [category],
            plannedExpenses: [planned],
            variableExpenses: [variable],
            rangeStart: date(2026, 1, 1),
            rangeEnd: date(2026, 1, 3),
            cardFilter: nil
        )

        let bucket = try #require(bucketFor(date(2026, 1, 2), in: result))
        let plannedItem = bucket.expenseItems.first { $0.id == "planned-\(planned.id.uuidString)" }
        let variableItem = bucket.expenseItems.first { $0.id == "variable-\(variable.id.uuidString)" }

        #expect(abs((plannedItem?.amount ?? 0) - 60) < 0.001)
        #expect(abs((variableItem?.amount ?? 0) - 50) < 0.001)
        #expect(abs(bucket.total - 110) < 0.001)
        #expect(abs(result.totalSpent - 110) < 0.001)
    }

    private func bucketFor(
        _ date: Date,
        in result: HomeSpendTrendsAggregator.Result
    ) -> HomeSpendTrendsAggregator.Bucket? {
        result.buckets.first { bucket in
            date >= bucket.start && date <= bucket.end
        }
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 12
    ) -> Date {
        Calendar.current.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour
            )
        ) ?? Date()
    }
}
