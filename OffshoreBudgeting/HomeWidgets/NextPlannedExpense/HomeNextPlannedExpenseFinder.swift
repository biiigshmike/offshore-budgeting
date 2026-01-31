//
//  HomeNextPlannedExpenseFinder.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import Foundation

enum HomeNextPlannedExpenseFinder {

    static func nextExpense(
        from plannedExpenses: [PlannedExpense],
        in startDate: Date,
        to endDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> PlannedExpense? {
        let start = normalizedStart(startDate, calendar: calendar)
        let end = normalizedEnd(endDate, calendar: calendar)

        let todayStart = calendar.startOfDay(for: now)

        let candidates = plannedExpenses
            .filter { expense in
                let d = expense.expenseDate
                return d >= start && d <= end && d >= todayStart
            }
            .sorted { $0.expenseDate < $1.expenseDate }

        return candidates.first
    }

    static func effectiveAmount(for expense: PlannedExpense) -> Double {
        expense.effectiveAmount()
    }

    private static func normalizedStart(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    private static func normalizedEnd(_ date: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? date
    }
}
