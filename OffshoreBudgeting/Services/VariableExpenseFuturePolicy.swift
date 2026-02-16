//
//  VariableExpenseFuturePolicy.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/16/26.
//

import Foundation

enum VariableExpenseFuturePolicy {

    // MARK: - Date Classification

    static func isFutureVariableExpense(
        _ expense: VariableExpense,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        isFutureDate(expense.transactionDate, now: now, calendar: calendar)
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
        _ expenses: [VariableExpense],
        hideFuture: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [VariableExpense] {
        guard hideFuture else { return expenses }
        return expenses.filter { !isFutureVariableExpense($0, now: now, calendar: calendar) }
    }

    static func filteredForCalculations(
        _ expenses: [VariableExpense],
        excludeFuture: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [VariableExpense] {
        guard excludeFuture else { return expenses }
        return expenses.filter { !isFutureVariableExpense($0, now: now, calendar: calendar) }
    }
}
