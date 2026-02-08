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

    // MARK: - Cards

    @Test func cardSpendTotal_forSpecificCard_filtersAndTotals() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .cardSpendTotal, dateRange: range, targetName: "Blue Card")

        let category = Category(name: "General", hexColor: "#00AA00")
        let blueCard = Card(name: "Blue Card")
        let redCard = Card(name: "Red Card")

        let planned: [PlannedExpense] = [
            PlannedExpense(title: "Blue Planned", plannedAmount: 300, expenseDate: date(2026, 2, 4), card: blueCard, category: category),
            PlannedExpense(title: "Red Planned", plannedAmount: 500, expenseDate: date(2026, 2, 5), card: redCard, category: category)
        ]

        let variable: [VariableExpense] = [
            VariableExpense(descriptionText: "Blue Variable", amount: 120, transactionDate: date(2026, 2, 8), card: blueCard, category: category),
            VariableExpense(descriptionText: "Red Variable", amount: 250, transactionDate: date(2026, 2, 9), card: redCard, category: category)
        ]

        let answer = engine.execute(
            query: query,
            categories: [category],
            plannedExpenses: planned,
            variableExpenses: variable,
            now: date(2026, 2, 15)
        )

        #expect(answer.kind == .metric)
        #expect((answer.primaryValue ?? "").filter(\.isNumber).contains("420"))
        #expect(answer.rows.contains(where: { $0.title == "Total" && $0.value.filter(\.isNumber).contains("420") }))
    }

    @Test func cardVariableSpendingHabits_forSpecificCard_returnsTransactionPatternRows() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .cardVariableSpendingHabits, dateRange: range, targetName: "Blue Card")

        let category = Category(name: "General", hexColor: "#00AA00")
        let blueCard = Card(name: "Blue Card")
        let redCard = Card(name: "Red Card")

        let variable: [VariableExpense] = [
            VariableExpense(descriptionText: "Blue #1", amount: 120, transactionDate: date(2026, 2, 8), card: blueCard, category: category),
            VariableExpense(descriptionText: "Blue #2", amount: 80, transactionDate: date(2026, 2, 10), card: blueCard, category: category),
            VariableExpense(descriptionText: "Red #1", amount: 300, transactionDate: date(2026, 2, 9), card: redCard, category: category)
        ]

        let answer = engine.execute(
            query: query,
            categories: [category],
            plannedExpenses: [],
            variableExpenses: variable,
            now: date(2026, 2, 15)
        )

        #expect(answer.kind == .metric)
        #expect(answer.title.contains("Card Spending Habits"))
        #expect((answer.primaryValue ?? "").filter(\.isNumber).contains("200"))
        #expect(answer.rows.contains(where: { $0.title == "Transactions" && $0.value == "2" }))
        #expect(answer.rows.contains(where: { $0.title == "Largest variable transaction" && $0.value.filter(\.isNumber).contains("120") }))
    }

    // MARK: - Income

    @Test func incomeAverageActual_returnsMonthlyAverage() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 1, 1), endDate: date(2026, 3, 31))
        let query = HomeQuery(intent: .incomeAverageActual, dateRange: range, targetName: "Salary")

        let incomes: [Income] = [
            Income(source: "Salary", amount: 2_000, date: date(2026, 1, 5), isPlanned: false),
            Income(source: "Salary", amount: 2_200, date: date(2026, 2, 5), isPlanned: false),
            Income(source: "Salary", amount: 2_400, date: date(2026, 3, 5), isPlanned: false),
            Income(source: "Freelance", amount: 999, date: date(2026, 3, 10), isPlanned: false),
            Income(source: "Salary", amount: 1_000, date: date(2026, 3, 15), isPlanned: true)
        ]

        let answer = engine.execute(
            query: query,
            categories: [],
            plannedExpenses: [],
            variableExpenses: [],
            incomes: incomes,
            now: date(2026, 3, 20)
        )

        #expect(answer.kind == .metric)
        #expect((answer.primaryValue ?? "").filter(\.isNumber).contains("2200"))
        #expect(answer.rows.contains(where: { $0.title == "Months sampled" && $0.value == "3" }))
    }

    @Test func incomeSourceShare_forSpecificSource_returnsPercentage() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .incomeSourceShare, dateRange: range, targetName: "Salary")

        let incomes: [Income] = [
            Income(source: "Salary", amount: 3_000, date: date(2026, 2, 3), isPlanned: false),
            Income(source: "Freelance", amount: 1_000, date: date(2026, 2, 6), isPlanned: false)
        ]

        let answer = engine.execute(
            query: query,
            categories: [],
            plannedExpenses: [],
            variableExpenses: [],
            incomes: incomes,
            now: date(2026, 2, 10)
        )

        #expect(answer.kind == .metric)
        #expect(answer.title.contains("Income Share"))
        #expect((answer.primaryValue ?? "").contains("75"))
    }

    @Test func categorySpendShare_forSpecificCategory_returnsPercentage() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .categorySpendShare, dateRange: range, targetName: "Groceries")

        let groceries = Category(name: "Groceries", hexColor: "#00AA00")
        let travel = Category(name: "Travel", hexColor: "#0000AA")

        let planned: [PlannedExpense] = [
            PlannedExpense(title: "Groceries Plan", plannedAmount: 300, expenseDate: date(2026, 2, 5), category: groceries),
            PlannedExpense(title: "Trip", plannedAmount: 700, expenseDate: date(2026, 2, 7), category: travel)
        ]
        let variable: [VariableExpense] = []

        let answer = engine.execute(
            query: query,
            categories: [groceries, travel],
            plannedExpenses: planned,
            variableExpenses: variable,
            now: date(2026, 2, 10)
        )

        #expect(answer.kind == .metric)
        #expect(answer.title.contains("Category Spend Share"))
        #expect((answer.primaryValue ?? "").contains("30"))
    }

    @Test func incomeSourceShareTrend_forSpecificSource_returnsAverageShare() throws {
        let engine = makeEngine()
        let query = HomeQuery(intent: .incomeSourceShareTrend, resultLimit: 3, targetName: "Salary")

        let incomes: [Income] = [
            Income(source: "Salary", amount: 3_000, date: date(2025, 12, 2), isPlanned: false),
            Income(source: "Side Gig", amount: 1_000, date: date(2025, 12, 5), isPlanned: false),
            Income(source: "Salary", amount: 4_000, date: date(2026, 1, 2), isPlanned: false),
            Income(source: "Salary", amount: 2_000, date: date(2026, 2, 2), isPlanned: false),
            Income(source: "Side Gig", amount: 2_000, date: date(2026, 2, 5), isPlanned: false)
        ]

        let answer = engine.execute(
            query: query,
            categories: [],
            plannedExpenses: [],
            variableExpenses: [],
            incomes: incomes,
            now: date(2026, 2, 20)
        )

        #expect(answer.kind == .metric)
        #expect(answer.title.contains("Income Share Trend"))
        #expect((answer.primaryValue ?? "").contains("75"))
    }

    @Test func categorySpendShareTrend_forSpecificCategory_returnsAverageShare() throws {
        let engine = makeEngine()
        let query = HomeQuery(intent: .categorySpendShareTrend, resultLimit: 3, targetName: "Groceries")

        let groceries = Category(name: "Groceries", hexColor: "#00AA00")
        let travel = Category(name: "Travel", hexColor: "#0000AA")
        let planned: [PlannedExpense] = [
            PlannedExpense(title: "Groceries", plannedAmount: 200, expenseDate: date(2025, 12, 3), category: groceries),
            PlannedExpense(title: "Travel", plannedAmount: 300, expenseDate: date(2025, 12, 4), category: travel),
            PlannedExpense(title: "Groceries", plannedAmount: 500, expenseDate: date(2026, 1, 3), category: groceries),
            PlannedExpense(title: "Travel", plannedAmount: 500, expenseDate: date(2026, 1, 4), category: travel),
            PlannedExpense(title: "Groceries", plannedAmount: 800, expenseDate: date(2026, 2, 3), category: groceries),
            PlannedExpense(title: "Travel", plannedAmount: 200, expenseDate: date(2026, 2, 4), category: travel)
        ]

        let answer = engine.execute(
            query: query,
            categories: [groceries, travel],
            plannedExpenses: planned,
            variableExpenses: [],
            now: date(2026, 2, 20)
        )

        #expect(answer.kind == .metric)
        #expect(answer.title.contains("Category Share Trend"))
        #expect((answer.primaryValue ?? "").contains("56"))
    }

    @Test func categorySpendShareTrend_withWeeklyUnit_usesWeeklyPeriods() throws {
        let engine = makeEngine()
        let query = HomeQuery(intent: .categorySpendShareTrend, resultLimit: 3, targetName: "Groceries", periodUnit: .week)

        let groceries = Category(name: "Groceries", hexColor: "#00AA00")
        let travel = Category(name: "Travel", hexColor: "#0000AA")
        let planned: [PlannedExpense] = [
            PlannedExpense(title: "W1 Groceries", plannedAmount: 200, expenseDate: date(2026, 2, 2), category: groceries),
            PlannedExpense(title: "W2 Groceries", plannedAmount: 100, expenseDate: date(2026, 2, 10), category: groceries),
            PlannedExpense(title: "W2 Travel", plannedAmount: 100, expenseDate: date(2026, 2, 11), category: travel),
            PlannedExpense(title: "W3 Travel", plannedAmount: 200, expenseDate: date(2026, 2, 18), category: travel)
        ]

        let answer = engine.execute(
            query: query,
            categories: [groceries, travel],
            plannedExpenses: planned,
            variableExpenses: [],
            now: date(2026, 2, 20)
        )

        #expect(answer.kind == .metric)
        #expect(answer.title.contains("Category Share Trend"))
        #expect((answer.primaryValue ?? "").contains("50"))
        #expect((answer.subtitle ?? "").contains("weeks"))
    }

    @Test func categoryPotentialSavings_forSpecificCategory_returnsScenarioRows() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .categoryPotentialSavings, dateRange: range, targetName: "Groceries")

        let groceries = Category(name: "Groceries", hexColor: "#00AA00")
        let travel = Category(name: "Travel", hexColor: "#0000AA")
        let planned: [PlannedExpense] = [
            PlannedExpense(title: "Groceries", plannedAmount: 400, expenseDate: date(2026, 2, 3), category: groceries),
            PlannedExpense(title: "Travel", plannedAmount: 600, expenseDate: date(2026, 2, 4), category: travel)
        ]

        let answer = engine.execute(
            query: query,
            categories: [groceries, travel],
            plannedExpenses: planned,
            variableExpenses: [],
            now: date(2026, 2, 20)
        )

        #expect(answer.kind == .list)
        #expect(answer.title.contains("Potential Savings"))
        #expect(answer.rows.contains(where: { $0.title == "Current spend" && $0.value.filter(\.isNumber).contains("400") }))
        #expect(answer.rows.contains(where: { $0.title.contains("10%") && $0.value.filter(\.isNumber).contains("40") }))
    }

    @Test func categoryReallocationGuidance_forSpecificCategory_returnsAdjustedOtherCategoryRows() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .categoryReallocationGuidance, dateRange: range, targetName: "Groceries")

        let groceries = Category(name: "Groceries", hexColor: "#00AA00")
        let travel = Category(name: "Travel", hexColor: "#0000AA")
        let dining = Category(name: "Dining", hexColor: "#AA0000")
        let planned: [PlannedExpense] = [
            PlannedExpense(title: "Groceries", plannedAmount: 400, expenseDate: date(2026, 2, 3), category: groceries),
            PlannedExpense(title: "Travel", plannedAmount: 300, expenseDate: date(2026, 2, 4), category: travel),
            PlannedExpense(title: "Dining", plannedAmount: 300, expenseDate: date(2026, 2, 5), category: dining)
        ]

        let answer = engine.execute(
            query: query,
            categories: [groceries, travel, dining],
            plannedExpenses: planned,
            variableExpenses: [],
            now: date(2026, 2, 20)
        )

        #expect(answer.kind == .list)
        #expect(answer.title.contains("Reallocation Guidance"))
        #expect((answer.primaryValue ?? "").filter(\.isNumber).contains("40"))
        #expect(answer.rows.contains(where: { $0.title == "Reduce other categories by" && $0.value.filter(\.isNumber).contains("40") }))
    }

    // MARK: - Presets

    @Test func presetDueSoon_returnsUpcomingPresetRows() throws {
        let engine = makeEngine()
        let query = HomeQuery(intent: .presetDueSoon)

        let category = Category(name: "Bills", hexColor: "#00AA00")
        let netflix = Preset(title: "Netflix", plannedAmount: 20, defaultCategory: category)
        let rent = Preset(title: "Rent", plannedAmount: 1_500, defaultCategory: category)

        let plannedExpenses: [PlannedExpense] = [
            PlannedExpense(
                title: "Netflix Expense",
                plannedAmount: 20,
                expenseDate: date(2026, 2, 21),
                category: category,
                sourcePresetID: netflix.id
            ),
            PlannedExpense(
                title: "Rent Expense",
                plannedAmount: 1_500,
                expenseDate: date(2026, 2, 25),
                category: category,
                sourcePresetID: rent.id
            ),
            PlannedExpense(
                title: "Outside Window",
                plannedAmount: 50,
                expenseDate: date(2026, 4, 1),
                category: category,
                sourcePresetID: netflix.id
            )
        ]

        let answer = engine.execute(
            query: query,
            categories: [category],
            presets: [netflix, rent],
            plannedExpenses: plannedExpenses,
            variableExpenses: [],
            now: date(2026, 2, 20)
        )

        #expect(answer.kind == .list)
        #expect(answer.title == "Presets Due Soon")
        #expect(answer.rows.contains(where: { $0.title == "Netflix" && $0.value.contains("1 due") }))
        #expect(answer.rows.contains(where: { $0.title == "Rent" && $0.value.contains("1 due") }))
    }

    @Test func presetHighestCost_returnsRankedPresets() throws {
        let engine = makeEngine()
        let query = HomeQuery(intent: .presetHighestCost, resultLimit: 2)

        let housing = Category(name: "Housing", hexColor: "#00AA00")
        let rent = Preset(title: "Rent", plannedAmount: 1_800, defaultCategory: housing)
        let phone = Preset(title: "Phone", plannedAmount: 90, defaultCategory: housing)
        let internet = Preset(title: "Internet", plannedAmount: 120, defaultCategory: housing)

        let answer = engine.execute(
            query: query,
            categories: [housing],
            presets: [rent, phone, internet],
            plannedExpenses: [],
            variableExpenses: [],
            now: date(2026, 2, 20)
        )

        #expect(answer.kind == .list)
        #expect(answer.title == "Highest Preset Costs")
        #expect(answer.rows.count == 2)
        #expect(answer.rows.first?.title == "Rent")
    }

    @Test func presetTopCategory_returnsCategoryWithMostAssignedPresets() throws {
        let engine = makeEngine()
        let query = HomeQuery(intent: .presetTopCategory)

        let bills = Category(name: "Bills", hexColor: "#00AA00")
        let leisure = Category(name: "Leisure", hexColor: "#0000AA")

        let presets: [Preset] = [
            Preset(title: "Rent", plannedAmount: 1_500, defaultCategory: bills),
            Preset(title: "Power", plannedAmount: 150, defaultCategory: bills),
            Preset(title: "Netflix", plannedAmount: 20, defaultCategory: leisure)
        ]

        let answer = engine.execute(
            query: query,
            categories: [bills, leisure],
            presets: presets,
            plannedExpenses: [],
            variableExpenses: [],
            now: date(2026, 2, 20)
        )

        #expect(answer.kind == .list)
        #expect(answer.title == "Categories Assigned to Presets")
        #expect(answer.rows.first?.title == "Bills")
        #expect(answer.rows.first?.value.contains("2") == true)
    }

    @Test func presetCategorySpend_forSpecificCategory_returnsTotalAndShare() throws {
        let engine = makeEngine()
        let query = HomeQuery(intent: .presetCategorySpend, targetName: "Bills")

        let bills = Category(name: "Bills", hexColor: "#00AA00")
        let leisure = Category(name: "Leisure", hexColor: "#0000AA")

        let presets: [Preset] = [
            Preset(title: "Rent", plannedAmount: 1_500, defaultCategory: bills),
            Preset(title: "Power", plannedAmount: 150, defaultCategory: bills),
            Preset(title: "Netflix", plannedAmount: 20, defaultCategory: leisure)
        ]

        let answer = engine.execute(
            query: query,
            categories: [bills, leisure],
            presets: presets,
            plannedExpenses: [],
            variableExpenses: [],
            now: date(2026, 2, 20)
        )

        #expect(answer.kind == .metric)
        #expect(answer.title.contains("Preset Spend by Category"))
        #expect((answer.primaryValue ?? "").filter(\.isNumber).contains("1650"))
        #expect(answer.rows.contains(where: { $0.title == "Share" }))
    }

    // MARK: - Savings

    @Test func savingsStatus_returnsProjectedAndActualRows() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .savingsStatus, dateRange: range)

        let category = Category(name: "General", hexColor: "#00AA00")
        let incomes = [
            Income(source: "Paycheck", amount: 5_000, date: date(2026, 2, 1), isPlanned: true),
            Income(source: "Paycheck", amount: 4_800, date: date(2026, 2, 2), isPlanned: false)
        ]
        let plannedExpenses = [
            PlannedExpense(title: "Rent", plannedAmount: 2_000, actualAmount: 1_900, expenseDate: date(2026, 2, 3), category: category)
        ]
        let variableExpenses = [
            VariableExpense(descriptionText: "Groceries", amount: 300, transactionDate: date(2026, 2, 4), category: category)
        ]

        let answer = engine.execute(
            query: query,
            categories: [category],
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            incomes: incomes,
            now: date(2026, 2, 15)
        )

        #expect(answer.kind == .metric)
        #expect(answer.title == "Savings Status")
        #expect((answer.primaryValue ?? "").filter(\.isNumber).contains("2600"))
        #expect(answer.rows.contains(where: { $0.title == "Projected savings" }))
        #expect(answer.rows.contains(where: { $0.title == "Actual savings" }))
    }

    @Test func savingsAverageRecentPeriods_returnsAverageAcrossMonths() throws {
        let engine = makeEngine()
        let query = HomeQuery(intent: .savingsAverageRecentPeriods, resultLimit: 3)
        let category = Category(name: "General", hexColor: "#00AA00")

        let incomes = [
            Income(source: "Paycheck", amount: 4_000, date: date(2025, 12, 2), isPlanned: false),
            Income(source: "Paycheck", amount: 4_200, date: date(2026, 1, 2), isPlanned: false),
            Income(source: "Paycheck", amount: 4_400, date: date(2026, 2, 2), isPlanned: false)
        ]
        let plannedExpenses = [
            PlannedExpense(title: "Rent", plannedAmount: 0, actualAmount: 2_500, expenseDate: date(2025, 12, 5), category: category),
            PlannedExpense(title: "Rent", plannedAmount: 0, actualAmount: 2_700, expenseDate: date(2026, 1, 5), category: category),
            PlannedExpense(title: "Rent", plannedAmount: 0, actualAmount: 2_900, expenseDate: date(2026, 2, 5), category: category)
        ]
        let variableExpenses: [VariableExpense] = []

        let answer = engine.execute(
            query: query,
            categories: [category],
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            incomes: incomes,
            now: date(2026, 2, 20)
        )

        #expect(answer.kind == .metric)
        #expect(answer.title.contains("Average Savings"))
        #expect((answer.primaryValue ?? "").filter(\.isNumber).contains("1500"))
        #expect(answer.rows.contains(where: { $0.title == "Periods sampled" && $0.value == "3" }))
    }

    // MARK: - Overview

    @Test func periodOverview_returnsAggregateRowsAndHighlights() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .periodOverview, dateRange: range)

        let groceries = Category(name: "Groceries", hexColor: "#00AA00")
        let travel = Category(name: "Travel", hexColor: "#0000AA")

        let planned: [PlannedExpense] = [
            PlannedExpense(title: "Airfare", plannedAmount: 700, expenseDate: date(2026, 2, 5), category: travel)
        ]
        let variable: [VariableExpense] = [
            VariableExpense(descriptionText: "Market", amount: 250, transactionDate: date(2026, 2, 10), category: groceries),
            VariableExpense(descriptionText: "Hotel", amount: 300, transactionDate: date(2026, 2, 11), category: travel),
            VariableExpense(descriptionText: "Previous Month", amount: 100, transactionDate: date(2026, 1, 15), category: groceries)
        ]

        let answer = engine.execute(
            query: query,
            categories: [groceries, travel],
            plannedExpenses: planned,
            variableExpenses: variable,
            now: date(2026, 2, 15)
        )

        #expect(answer.kind == .list)
        #expect(answer.title == "Budget Overview")
        #expect((answer.primaryValue ?? "").filter(\.isNumber).contains("1250"))
        #expect(answer.rows.contains(where: { $0.title == "Total spend" && $0.value.filter(\.isNumber).contains("1250") }))
        #expect(answer.rows.contains(where: { $0.title == "Top category" && $0.value.contains("Travel") }))
        #expect(answer.rows.contains(where: { $0.title == "Largest transaction" && $0.value.contains("Airfare") }))
    }

    @Test func periodOverview_withNoData_returnsMessage() throws {
        let engine = makeEngine()
        let range = HomeQueryDateRange(startDate: date(2026, 2, 1), endDate: date(2026, 2, 28))
        let query = HomeQuery(intent: .periodOverview, dateRange: range)

        let groceries = Category(name: "Groceries", hexColor: "#00AA00")

        let answer = engine.execute(
            query: query,
            categories: [groceries],
            plannedExpenses: [],
            variableExpenses: [],
            now: date(2026, 2, 15)
        )

        #expect(answer.kind == .message)
        #expect(answer.title == "Budget Overview")
        #expect((answer.subtitle ?? "").contains("No spending"))
        #expect(answer.rows.contains(where: { $0.title == "Range" }))
    }

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
