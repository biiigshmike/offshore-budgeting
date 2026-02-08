//
//  HomeQueryEngineTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import Testing
@testable import Offshore

struct HomeQueryEngineTests {

    // MARK: - Spend

    @Test func spendThisMonth_returnsMetricWithExpectedTotal() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .spendThisMonth, dateRange: range)

        let groceries = Category(name: "Groceries", hexColor: "#00AA00")
        let planned = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            actualAmount: 1_100,
            expenseDate: date(2026, 2, 2),
            category: groceries
        )
        let variable = VariableExpense(
            descriptionText: "Market",
            amount: 250,
            transactionDate: date(2026, 2, 10),
            category: groceries
        )

        let answer = engine.execute(
            query: query,
            categories: [groceries],
            plannedExpenses: [planned],
            variableExpenses: [variable],
            now: date(2026, 2, 15)
        )

        #expect(answer.kind == .metric)
        let primaryValue = answer.primaryValue ?? ""
        let firstRowValue = answer.rows.first?.value ?? ""
        #expect(primaryValue.filter(\.isNumber).contains("1350"))
        #expect(firstRowValue.filter(\.isNumber).contains("1350"))
    }

    // MARK: - Top Categories

    @Test func topCategoriesThisMonth_returnsSortedLimitedRows() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .topCategoriesThisMonth, dateRange: range, resultLimit: 2)

        let groceries = Category(name: "Groceries", hexColor: "#00AA00")
        let travel = Category(name: "Travel", hexColor: "#0000AA")
        let dining = Category(name: "Dining", hexColor: "#AA0000")

        let planned: [PlannedExpense] = [
            PlannedExpense(title: "Trip", plannedAmount: 600, expenseDate: date(2026, 2, 5), category: travel),
            PlannedExpense(title: "Food Plan", plannedAmount: 100, expenseDate: date(2026, 2, 6), category: groceries)
        ]
        let variable: [VariableExpense] = [
            VariableExpense(descriptionText: "Restaurant", amount: 400, transactionDate: date(2026, 2, 7), category: dining),
            VariableExpense(descriptionText: "Market", amount: 150, transactionDate: date(2026, 2, 8), category: groceries)
        ]

        let answer = engine.execute(
            query: query,
            categories: [groceries, travel, dining],
            plannedExpenses: planned,
            variableExpenses: variable,
            now: date(2026, 2, 15)
        )

        #expect(answer.kind == .list)
        #expect(answer.rows.count == 2)
        #expect(answer.rows[0].title == "Travel")
        #expect(answer.rows[1].title == "Dining")
    }

    // MARK: - Compare

    @Test func compareThisMonthToPreviousMonth_returnsComparisonRows() throws {
        let engine = makeEngine()
        let query = HomeQuery(intent: .compareThisMonthToPreviousMonth)

        let groceries = Category(name: "Groceries", hexColor: "#00AA00")

        let planned: [PlannedExpense] = [
            PlannedExpense(title: "Current Month Planned", plannedAmount: 300, expenseDate: date(2026, 2, 5), category: groceries),
            PlannedExpense(title: "Previous Month Planned", plannedAmount: 200, expenseDate: date(2026, 1, 10), category: groceries)
        ]
        let variable: [VariableExpense] = [
            VariableExpense(descriptionText: "Current Month Variable", amount: 100, transactionDate: date(2026, 2, 8), category: groceries),
            VariableExpense(descriptionText: "Previous Month Variable", amount: 50, transactionDate: date(2026, 1, 15), category: groceries)
        ]

        let answer = engine.execute(
            query: query,
            categories: [groceries],
            plannedExpenses: planned,
            variableExpenses: variable,
            now: date(2026, 2, 15)
        )

        #expect(answer.kind == .comparison)
        #expect((answer.primaryValue ?? "").contains("400"))
        #expect(answer.rows.count == 2)
        #expect(answer.rows[0].value.contains("400"))
        #expect(answer.rows[1].value.contains("250"))
        #expect((answer.subtitle ?? "").contains("Up"))
        #expect((answer.subtitle ?? "").contains("150"))
    }

    // MARK: - Helpers

    private func makeEngine() -> HomeQueryEngine {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.currencyCode = "USD"

        return HomeQueryEngine(
            calendar: calendar,
            currencyFormatter: formatter
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.minute = 0
        comps.second = 0
        comps.timeZone = TimeZone(secondsFromGMT: 0)

        return Calendar(identifier: .gregorian).date(from: comps) ?? .distantPast
    }

}
