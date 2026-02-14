//
//  PlannedExpenseFuturePolicyTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/14/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct PlannedExpenseFuturePolicyTests {

    // MARK: - Tests

    @Test func isFutureDate_TreatsTodayAsNotFuture() {
        let calendar = fixedCalendar
        let now = date(year: 2026, month: 2, day: 14, hour: 9, minute: 30)
        let laterToday = date(year: 2026, month: 2, day: 14, hour: 22, minute: 45)

        let isFuture = PlannedExpenseFuturePolicy.isFutureDate(
            laterToday,
            now: now,
            calendar: calendar
        )

        #expect(isFuture == false)
    }

    @Test func isFutureDate_TreatsTomorrowAsFuture() {
        let calendar = fixedCalendar
        let now = date(year: 2026, month: 2, day: 14, hour: 9, minute: 30)
        let tomorrow = date(year: 2026, month: 2, day: 15, hour: 0, minute: 0)

        let isFuture = PlannedExpenseFuturePolicy.isFutureDate(
            tomorrow,
            now: now,
            calendar: calendar
        )

        #expect(isFuture == true)
    }

    @Test func visibilityAndCalculationFilters_AreIndependent() {
        let calendar = fixedCalendar
        let now = date(year: 2026, month: 2, day: 14, hour: 9, minute: 30)

        let todayExpense = PlannedExpense(
            title: "Today",
            plannedAmount: 10,
            expenseDate: date(year: 2026, month: 2, day: 14, hour: 8, minute: 0)
        )

        let futureExpense = PlannedExpense(
            title: "Tomorrow",
            plannedAmount: 20,
            expenseDate: date(year: 2026, month: 2, day: 15, hour: 8, minute: 0)
        )

        let base = [todayExpense, futureExpense]

        let visibleWhenHideOn = PlannedExpenseFuturePolicy.filteredForVisibility(
            base,
            hideFuture: true,
            now: now,
            calendar: calendar
        )

        let calcWhenExcludeOff = PlannedExpenseFuturePolicy.filteredForCalculations(
            base,
            excludeFuture: false,
            now: now,
            calendar: calendar
        )

        #expect(visibleWhenHideOn.map(\.title) == ["Today"])
        #expect(calcWhenExcludeOff.map(\.title).sorted() == ["Today", "Tomorrow"])
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
