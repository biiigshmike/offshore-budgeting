//
//  IncomeScheduleEngine.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import Foundation

struct IncomeScheduleEngine {

    /// Generates occurrence dates for a series within its own [startDate, endDate] window (inclusive).
    /// Returns start-of-day dates, sorted, de-duped.
    static func occurrences(
        for series: IncomeSeries,
        calendar: Calendar = .current
    ) -> [Date] {
        occurrences(
            frequency: series.frequency,
            interval: series.interval,
            weeklyWeekday: series.weeklyWeekday,
            monthlyDayOfMonth: series.monthlyDayOfMonth,
            monthlyIsLastDay: series.monthlyIsLastDay,
            yearlyMonth: series.yearlyMonth,
            yearlyDayOfMonth: series.yearlyDayOfMonth,
            startDate: series.startDate,
            endDate: series.endDate,
            calendar: calendar
        )
    }

    /// Same engine, but callable with raw fields, useful when splitting series.
    static func occurrences(
        frequency: RecurrenceFrequency,
        interval: Int,
        weeklyWeekday: Int,
        monthlyDayOfMonth: Int,
        monthlyIsLastDay: Bool,
        yearlyMonth: Int,
        yearlyDayOfMonth: Int,
        startDate: Date,
        endDate: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        var cal = calendar
        cal.timeZone = .current

        let start = cal.startOfDay(for: startDate)
        let end = cal.startOfDay(for: endDate)

        guard start <= end else { return [] }
        guard frequency != .none else { return [start] }

        switch frequency {
        case .daily:
            return daily(start: start, end: end, interval: max(1, interval), calendar: cal)

        case .weekly:
            return weekly(start: start, end: end, intervalWeeks: max(1, interval), weekday: clamp(weeklyWeekday, 1, 7), calendar: cal)

        case .monthly:
            return monthly(
                start: start,
                end: end,
                intervalMonths: max(1, interval),
                dayOfMonth: clamp(monthlyDayOfMonth, 1, 31),
                isLastDay: monthlyIsLastDay,
                calendar: cal
            )

        case .yearly:
            return yearly(
                start: start,
                end: end,
                intervalYears: max(1, interval),
                month: clamp(yearlyMonth, 1, 12),
                day: clamp(yearlyDayOfMonth, 1, 31),
                calendar: cal
            )

        case .none:
            return [start]
        }
    }

    // MARK: - Daily

    private static func daily(start: Date, end: Date, interval: Int, calendar: Calendar) -> [Date] {
        var results: [Date] = []
        var cursor = safeNoon(on: start, calendar: calendar)

        while cursor <= safeNoon(on: end, calendar: calendar) {
            results.append(calendar.startOfDay(for: cursor))
            guard let next = calendar.date(byAdding: .day, value: interval, to: cursor) else { break }
            cursor = safeNoon(on: next, calendar: calendar)
        }

        return dedupSort(results)
    }

    // MARK: - Weekly

    private static func weekly(start: Date, end: Date, intervalWeeks: Int, weekday: Int, calendar: Calendar) -> [Date] {
        guard let first = firstWeekday(onOrAfter: safeNoon(on: start, calendar: calendar), weekday: weekday, calendar: calendar) else {
            return []
        }

        var results: [Date] = []
        var cursor = first

        while cursor <= safeNoon(on: end, calendar: calendar) {
            results.append(calendar.startOfDay(for: cursor))
            guard let next = calendar.date(byAdding: .weekOfYear, value: intervalWeeks, to: cursor) else { break }
            cursor = safeNoon(on: next, calendar: calendar)
        }

        return dedupSort(results)
    }

    private static func firstWeekday(onOrAfter date: Date, weekday: Int, calendar: Calendar) -> Date? {
        var cursor = date
        for _ in 0..<7 {
            if calendar.component(.weekday, from: cursor) == weekday {
                return safeNoon(on: cursor, calendar: calendar)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }

    // MARK: - Monthly

    private static func monthly(
        start: Date,
        end: Date,
        intervalMonths: Int,
        dayOfMonth: Int,
        isLastDay: Bool,
        calendar: Calendar
    ) -> [Date] {
        var results: [Date] = []

        var monthCursor = startOfMonth(for: safeNoon(on: start, calendar: calendar), calendar: calendar)

        while monthCursor <= safeNoon(on: end, calendar: calendar) {
            let occurrence: Date?
            if isLastDay {
                occurrence = lastDayOfMonthNoon(for: monthCursor, calendar: calendar)
            } else {
                occurrence = dayOfMonthNoon(for: monthCursor, desiredDay: dayOfMonth, calendar: calendar)
            }

            if let occurrence {
                let day = calendar.startOfDay(for: occurrence)
                if day >= start && day <= end { results.append(day) }
            }

            guard let next = calendar.date(byAdding: .month, value: intervalMonths, to: monthCursor) else { break }
            monthCursor = startOfMonth(for: safeNoon(on: next, calendar: calendar), calendar: calendar)
        }

        return dedupSort(results)
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let first = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) ?? date
        return safeNoon(on: first, calendar: calendar)
    }

    private static func lastDayOfMonthNoon(for monthDate: Date, calendar: Calendar) -> Date? {
        let comps = calendar.dateComponents([.year, .month], from: monthDate)
        guard let first = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) else { return nil }
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: first) else { return nil }
        guard let last = calendar.date(byAdding: .day, value: -1, to: nextMonth) else { return nil }
        return safeNoon(on: last, calendar: calendar)
    }

    private static func dayOfMonthNoon(for monthDate: Date, desiredDay: Int, calendar: Calendar) -> Date? {
        let comps = calendar.dateComponents([.year, .month], from: monthDate)
        guard let year = comps.year, let month = comps.month else { return nil }

        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        guard let lastNoon = lastDayOfMonthNoon(for: first, calendar: calendar) else { return nil }
        let lastDay = calendar.component(.day, from: lastNoon)

        let clamped = clamp(desiredDay, 1, lastDay)
        guard let d = calendar.date(from: DateComponents(year: year, month: month, day: clamped)) else { return nil }
        return safeNoon(on: d, calendar: calendar)
    }

    // MARK: - Yearly

    private static func yearly(
        start: Date,
        end: Date,
        intervalYears: Int,
        month: Int,
        day: Int,
        calendar: Calendar
    ) -> [Date] {
        var results: [Date] = []

        let startYear = calendar.component(.year, from: safeNoon(on: start, calendar: calendar))
        let endYear = calendar.component(.year, from: safeNoon(on: end, calendar: calendar))

        var yearCursor = startYear
        while yearCursor <= endYear {
            if let occurrence = yearlyDateNoon(year: yearCursor, month: month, day: day, calendar: calendar) {
                let occDay = calendar.startOfDay(for: occurrence)
                if occDay >= start && occDay <= end { results.append(occDay) }
            }
            yearCursor += intervalYears
        }

        return dedupSort(results)
    }

    private static func yearlyDateNoon(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        guard let lastNoon = lastDayOfMonthNoon(for: first, calendar: calendar) else { return nil }
        let lastDay = calendar.component(.day, from: lastNoon)

        let clamped = clamp(day, 1, lastDay)
        guard let d = calendar.date(from: DateComponents(year: year, month: month, day: clamped)) else { return nil }
        return safeNoon(on: d, calendar: calendar)
    }

    // MARK: - Helpers

    private static func safeNoon(on date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    private static func clamp(_ value: Int, _ minValue: Int, _ maxValue: Int) -> Int {
        Swift.max(minValue, Swift.min(maxValue, value))
    }

    private static func dedupSort(_ dates: [Date]) -> [Date] {
        Array(Set(dates)).sorted()
    }
}
