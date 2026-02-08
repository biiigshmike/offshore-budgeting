//
//  HomeQueryEngine.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

struct HomeQueryEngine {
    private let calendar: Calendar
    private let currencyFormatter: NumberFormatter

    init(
        calendar: Calendar = .current,
        currencyFormatter: NumberFormatter? = nil
    ) {
        self.calendar = calendar

        if let currencyFormatter {
            self.currencyFormatter = currencyFormatter
        } else {
            let formatter = NumberFormatter()
            formatter.numberStyle = .currency
            formatter.locale = .autoupdatingCurrent
            self.currencyFormatter = formatter
        }
    }

    // MARK: - Execute

    func execute(
        query: HomeQuery,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date = Date()
    ) -> HomeAnswer {
        switch query.intent {
        case .spendThisMonth:
            return spendThisMonthAnswer(
                query: query,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )

        case .topCategoriesThisMonth:
            return topCategoriesThisMonthAnswer(
                query: query,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )

        case .compareThisMonthToPreviousMonth:
            return compareThisMonthToPreviousMonthAnswer(
                query: query,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )

        case .largestRecentTransactions:
            return largestRecentTransactionsAnswer(
                query: query,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                now: now
            )
        }
    }

    // MARK: - Suggestions

    func defaultSuggestions() -> [HomeAssistantSuggestion] {
        [
            HomeAssistantSuggestion(
                title: "Spend this month",
                query: HomeQuery(intent: .spendThisMonth)
            ),
            HomeAssistantSuggestion(
                title: "Top categories this month",
                query: HomeQuery(intent: .topCategoriesThisMonth)
            ),
            HomeAssistantSuggestion(
                title: "Compare with last month",
                query: HomeQuery(intent: .compareThisMonthToPreviousMonth)
            ),
            HomeAssistantSuggestion(
                title: "Largest recent transactions",
                query: HomeQuery(intent: .largestRecentTransactions)
            )
        ]
    }

    // MARK: - Intent handlers

    private func spendThisMonthAnswer(
        query: HomeQuery,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let total = totalSpend(
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            range: range
        )

        return HomeAnswer(
            queryID: query.id,
            kind: .metric,
            title: "Spend This Month",
            subtitle: rangeLabel(for: range),
            primaryValue: currency(total),
            rows: [
                HomeAnswerRow(title: "Total", value: currency(total))
            ]
        )
    }

    private func topCategoriesThisMonthAnswer(
        query: HomeQuery,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)
        let metrics = HomeCategoryMetricsCalculator.calculate(
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            rangeStart: range.startDate,
            rangeEnd: range.endDate
        ).metrics

        let rows = Array(metrics.prefix(query.resultLimit)).map { metric in
            HomeAnswerRow(title: metric.categoryName, value: currency(metric.totalSpent))
        }

        if rows.isEmpty {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Top Categories This Month",
                subtitle: "No spending in this range yet.",
                primaryValue: nil,
                rows: []
            )
        }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Top Categories This Month",
            subtitle: rangeLabel(for: range),
            primaryValue: nil,
            rows: rows
        )
    }

    private func compareThisMonthToPreviousMonthAnswer(
        query: HomeQuery,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let currentRange = query.dateRange ?? monthRange(containing: now)
        let previousRange: HomeQueryDateRange
        if query.dateRange == nil {
            previousRange = previousMonthRange(before: currentRange.startDate)
        } else {
            previousRange = previousEquivalentRange(matching: currentRange)
        }

        let currentTotal = totalSpend(
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            range: currentRange
        )
        let previousTotal = totalSpend(
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            range: previousRange
        )

        let delta = currentTotal - previousTotal
        let deltaLabel: String
        if delta > 0 {
            deltaLabel = "Up \(currency(delta))"
        } else if delta < 0 {
            deltaLabel = "Down \(currency(abs(delta)))"
        } else {
            deltaLabel = "No change"
        }

        let currentLabel = query.dateRange == nil ? monthTitle(containing: currentRange.startDate) : rangeLabel(for: currentRange)
        let previousLabel = query.dateRange == nil ? monthTitle(containing: previousRange.startDate) : rangeLabel(for: previousRange)

        return HomeAnswer(
            queryID: query.id,
            kind: .comparison,
            title: query.dateRange == nil ? "This Month vs Last Month" : "Current Period vs Previous Period",
            subtitle: deltaLabel,
            primaryValue: currency(currentTotal),
            rows: [
                HomeAnswerRow(title: currentLabel, value: currency(currentTotal)),
                HomeAnswerRow(title: previousLabel, value: currency(previousTotal))
            ]
        )
    }

    private func largestRecentTransactionsAnswer(
        query: HomeQuery,
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        now: Date
    ) -> HomeAnswer {
        let range = query.dateRange ?? monthRange(containing: now)

        var entries: [(title: String, amount: Double)] = []
        entries.reserveCapacity(plannedExpenses.count + variableExpenses.count)

        for expense in plannedExpenses {
            guard expense.expenseDate >= range.startDate, expense.expenseDate <= range.endDate else { continue }
            entries.append((title: expense.title, amount: expense.effectiveAmount()))
        }

        for expense in variableExpenses {
            guard expense.transactionDate >= range.startDate, expense.transactionDate <= range.endDate else { continue }
            entries.append((title: expense.descriptionText, amount: expense.amount))
        }

        let rows = entries
            .sorted { $0.amount > $1.amount }
            .prefix(query.resultLimit)
            .map { HomeAnswerRow(title: $0.title, value: currency($0.amount)) }

        if rows.isEmpty {
            return HomeAnswer(
                queryID: query.id,
                kind: .message,
                title: "Largest Recent Transactions",
                subtitle: "No transactions found in this range.",
                primaryValue: nil,
                rows: []
            )
        }

        return HomeAnswer(
            queryID: query.id,
            kind: .list,
            title: "Largest Recent Transactions",
            subtitle: rangeLabel(for: range),
            primaryValue: nil,
            rows: rows
        )
    }

    // MARK: - Helpers

    private func totalSpend(
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        range: HomeQueryDateRange
    ) -> Double {
        let planned = plannedExpenses.reduce(0.0) { partial, expense in
            guard expense.expenseDate >= range.startDate, expense.expenseDate <= range.endDate else { return partial }
            return partial + expense.effectiveAmount()
        }

        let variable = variableExpenses.reduce(0.0) { partial, expense in
            guard expense.transactionDate >= range.startDate, expense.transactionDate <= range.endDate else { return partial }
            return partial + expense.amount
        }

        return planned + variable
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousMonthRange(before date: Date) -> HomeQueryDateRange {
        let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
        let previousMonthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: previousMonthStart) ?? previousMonthStart
        return HomeQueryDateRange(startDate: previousMonthStart, endDate: previousMonthEnd)
    }

    private func previousEquivalentRange(matching range: HomeQueryDateRange) -> HomeQueryDateRange {
        let startOfCurrent = calendar.startOfDay(for: range.startDate)
        let startOfEnd = calendar.startOfDay(for: range.endDate)

        let daySpan = (calendar.dateComponents([.day], from: startOfCurrent, to: startOfEnd).day ?? 0) + 1

        let previousEnd = calendar.date(byAdding: .day, value: -1, to: startOfCurrent) ?? startOfCurrent
        let previousStart = calendar.date(byAdding: .day, value: -(daySpan - 1), to: previousEnd) ?? previousEnd

        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }

    private func monthTitle(containing date: Date) -> String {
        date.formatted(.dateTime.year().month(.wide))
    }

    private func rangeLabel(for range: HomeQueryDateRange) -> String {
        if isFullMonth(range) {
            return monthTitle(containing: range.startDate)
        }

        if isFullYear(range) {
            return range.startDate.formatted(.dateTime.year())
        }

        return "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func isFullMonth(_ range: HomeQueryDateRange) -> Bool {
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: range.startDate)) ?? range.startDate
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
        return calendar.isDate(monthStart, inSameDayAs: range.startDate)
            && calendar.isDate(monthEnd, inSameDayAs: range.endDate)
    }

    private func isFullYear(_ range: HomeQueryDateRange) -> Bool {
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: range.startDate)) ?? range.startDate
        let yearEnd = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: yearStart) ?? yearStart
        return calendar.isDate(yearStart, inSameDayAs: range.startDate)
            && calendar.isDate(yearEnd, inSameDayAs: range.endDate)
    }

    private func currency(_ amount: Double) -> String {
        currencyFormatter.string(from: NSNumber(value: amount)) ?? amount.formatted(.number)
    }
}
