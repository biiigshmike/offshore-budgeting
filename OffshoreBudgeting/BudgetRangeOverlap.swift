//
//  BudgetRangeOverlap.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import Foundation

// MARK: - DateRange

struct DateRange: Equatable {

    let start: Date
    let end: Date

    init(start: Date, end: Date, calendar: Calendar = .current) {
        let s = calendar.startOfDay(for: start)
        let e = DateRange.normalizedEnd(end, calendar: calendar)

        // Defensive: if a caller passes end before start, clamp to a 1-day range.
        if e < s {
            self.start = s
            self.end = DateRange.normalizedEnd(s, calendar: calendar)
        } else {
            self.start = s
            self.end = e
        }
    }

    // MARK: - Public

    func overlaps(_ other: DateRange) -> Bool {
        intersection(with: other) != nil
    }

    /// Returns the intersected range if there is overlap, otherwise nil.
    func intersection(with other: DateRange) -> DateRange? {
        let intersectionStart = max(self.start, other.start)
        let intersectionEnd = min(self.end, other.end)

        guard intersectionStart <= intersectionEnd else { return nil }
        return DateRange(start: intersectionStart, end: intersectionEnd)
    }

    /// Inclusive overlap days (e.g. Jan 1..Jan 1 = 1 day).
    func overlapDays(with other: DateRange, calendar: Calendar = .current) -> Int {
        guard let i = intersection(with: other) else { return 0 }

        let startDay = calendar.startOfDay(for: i.start)
        let endDay = calendar.startOfDay(for: i.end)

        let dayDelta = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(0, dayDelta + 1)
    }

    // MARK: - Private

    private static func normalizedEnd(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}

// MARK: - Budget selection

enum BudgetRangeOverlap {

    /// Deterministic rule for selecting ONE active budget for a given Home range:
    /// - Filter budgets that overlap
    /// - Choose the one with the largest overlapDays
    /// - Tie-breaker: newest budget startDate
    static func pickActiveBudget(
        from budgets: [Budget],
        for range: DateRange,
        calendar: Calendar = .current
    ) -> Budget? {

        guard !budgets.isEmpty else { return nil }

        var best: Budget? = nil
        var bestOverlapDays: Int = 0
        var bestStartDate: Date = .distantPast

        for budget in budgets {
            let budgetRange = DateRange(start: budget.startDate, end: budget.endDate, calendar: calendar)
            let overlap = budgetRange.overlapDays(with: range, calendar: calendar)
            guard overlap > 0 else { continue }

            if overlap > bestOverlapDays {
                best = budget
                bestOverlapDays = overlap
                bestStartDate = budget.startDate
            } else if overlap == bestOverlapDays {
                // Tie-breaker: newest start date wins
                if budget.startDate > bestStartDate {
                    best = budget
                    bestStartDate = budget.startDate
                }
            }
        }

        return best
    }
}
