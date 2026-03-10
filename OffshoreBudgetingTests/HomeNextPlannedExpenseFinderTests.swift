//
//  HomeNextPlannedExpenseFinderTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 3/10/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeNextPlannedExpenseFinderTests {

    // MARK: - Tests

    @Test func nextExpense_usesUnfilteredPlannedExpensesSoHiddenFutureEntriesCanStillPowerTheTile() {
        let calendar = fixedCalendar
        let now = date(year: 2026, month: 3, day: 9, hour: 10, minute: 0)

        let tomorrowExpense = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: date(year: 2026, month: 3, day: 10, hour: 9, minute: 0)
        )

        let hiddenExpenses = PlannedExpenseFuturePolicy.filteredForVisibility(
            [tomorrowExpense],
            hideFuture: true,
            now: now,
            calendar: calendar
        )

        let next = HomeNextPlannedExpenseFinder.nextExpense(
            from: [tomorrowExpense],
            in: date(year: 2026, month: 3, day: 1, hour: 0, minute: 0),
            to: date(year: 2026, month: 3, day: 31, hour: 23, minute: 59),
            now: now,
            calendar: calendar
        )

        #expect(hiddenExpenses.isEmpty)
        #expect(next?.title == "Rent")
    }

    @Test func nextExpense_respectsTodayForwardAndDateRangeRules() {
        let calendar = fixedCalendar
        let now = date(year: 2026, month: 3, day: 9, hour: 10, minute: 0)

        let yesterdayExpense = PlannedExpense(
            title: "Yesterday",
            plannedAmount: 10,
            expenseDate: date(year: 2026, month: 3, day: 8, hour: 12, minute: 0)
        )

        let tomorrowExpense = PlannedExpense(
            title: "Tomorrow",
            plannedAmount: 20,
            expenseDate: date(year: 2026, month: 3, day: 10, hour: 12, minute: 0)
        )

        let outOfRangeExpense = PlannedExpense(
            title: "Out of Range",
            plannedAmount: 30,
            expenseDate: date(year: 2026, month: 4, day: 1, hour: 12, minute: 0)
        )

        let next = HomeNextPlannedExpenseFinder.nextExpense(
            from: [outOfRangeExpense, tomorrowExpense, yesterdayExpense],
            in: date(year: 2026, month: 3, day: 1, hour: 0, minute: 0),
            to: date(year: 2026, month: 3, day: 31, hour: 23, minute: 59),
            now: now,
            calendar: calendar
        )

        #expect(next?.title == "Tomorrow")
    }

    // MARK: - Helpers

    private var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? TimeZone.current
        return calendar
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components) ?? .now
    }
}
