//
//  PlannedExpenseFuturePolicy.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/14/26.
//

import Foundation

enum PlannedExpenseFuturePolicy {

    // MARK: - Date Classification

    static func isFuturePlannedExpense(
        _ expense: PlannedExpense,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        isFutureDate(expense.expenseDate, now: now, calendar: calendar)
    }

    static func isFutureDate(
        _ date: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let todayStart = calendar.startOfDay(for: now)
        let dateStart = calendar.startOfDay(for: date)
        return dateStart > todayStart
    }

    // MARK: - Filters

    static func filteredForVisibility(
        _ expenses: [PlannedExpense],
        hideFuture: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedExpense] {
        guard hideFuture else { return expenses }
        return expenses.filter { !isFuturePlannedExpense($0, now: now, calendar: calendar) }
    }

    static func filteredForCalculations(
        _ expenses: [PlannedExpense],
        excludeFuture: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedExpense] {
        guard excludeFuture else { return expenses }
        return expenses.filter { !isFuturePlannedExpense($0, now: now, calendar: calendar) }
    }
}
