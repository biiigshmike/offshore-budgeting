//
//  PresetScheduleEngine.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import Foundation

struct PresetScheduleEngine {

    static func occurrences(for preset: Preset, in budget: Budget, calendar: Calendar = .current) -> [Date] {
        var cal = calendar
        cal.timeZone = .current

        let windowStart = cal.startOfDay(for: budget.startDate)
        let windowEnd = cal.startOfDay(for: budget.endDate)

        guard windowStart <= windowEnd else { return [] }

        switch preset.frequency {
        case .none:
            return []

        case .daily:
            return dailyOccurrences(preset: preset, windowStart: windowStart, windowEnd: windowEnd, calendar: cal)

        case .weekly:
            return weeklyOccurrences(preset: preset, windowStart: windowStart, windowEnd: windowEnd, calendar: cal)

        case .monthly:
            return monthlyOccurrences(preset: preset, windowStart: windowStart, windowEnd: windowEnd, calendar: cal)

        case .yearly:
            return yearlyOccurrences(preset: preset, windowStart: windowStart, windowEnd: windowEnd, calendar: cal)
        }
    }

    // MARK: - Daily

    private static func dailyOccurrences(
        preset: Preset,
        windowStart: Date,
        windowEnd: Date,
        calendar: Calendar
    ) -> [Date] {
        let interval = max(1, preset.interval)

        var results: [Date] = []
        var cursor = safeNoon(on: windowStart, calendar: calendar)

        while cursor <= safeNoon(on: windowEnd, calendar: calendar) {
            results.append(calendar.startOfDay(for: cursor))

            guard let next = calendar.date(byAdding: .day, value: interval, to: cursor) else { break }
            cursor = safeNoon(on: next, calendar: calendar)
        }

        return dedupAndSort(results, calendar: calendar)
    }

    // MARK: - Weekly (budget-anchored)

    private static func weeklyOccurrences(
        preset: Preset,
        windowStart: Date,
        windowEnd: Date,
        calendar: Calendar
    ) -> [Date] {
        let intervalWeeks = max(1, preset.interval)
        let targetWeekday = clamp(preset.weeklyWeekday, min: 1, max: 7)

        let startNoon = safeNoon(on: windowStart, calendar: calendar)
        let endNoon = safeNoon(on: windowEnd, calendar: calendar)

        guard let first = firstWeekday(onOrAfter: startNoon, weekday: targetWeekday, calendar: calendar) else {
            return []
        }

        var results: [Date] = []
        var cursor = first

        while cursor <= endNoon {
            let day = calendar.startOfDay(for: cursor)
            if day >= windowStart && day <= windowEnd {
                results.append(day)
            }

            guard let next = calendar.date(byAdding: .weekOfYear, value: intervalWeeks, to: cursor) else { break }
            cursor = safeNoon(on: next, calendar: calendar)
        }

        return dedupAndSort(results, calendar: calendar)
    }

    private static func firstWeekday(onOrAfter date: Date, weekday: Int, calendar: Calendar) -> Date? {
        var cursor = date
        for _ in 0..<7 {
            let currentWeekday = calendar.component(.weekday, from: cursor)
            if currentWeekday == weekday {
                return safeNoon(on: cursor, calendar: calendar)
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
        }
        return nil
    }

    // MARK: - Monthly

    private static func monthlyOccurrences(
        preset: Preset,
        windowStart: Date,
        windowEnd: Date,
        calendar: Calendar
    ) -> [Date] {
        let intervalMonths = max(1, preset.interval)
        let startNoon = safeNoon(on: windowStart, calendar: calendar)
        let endNoon = safeNoon(on: windowEnd, calendar: calendar)

        var monthCursor = startOfMonth(for: startNoon, calendar: calendar)

        var results: [Date] = []

        while monthCursor <= endNoon {
            let occurrenceNoon: Date?

            if preset.monthlyIsLastDay {
                occurrenceNoon = lastDayOfMonthNoon(for: monthCursor, calendar: calendar)
            } else {
                let desiredDay = clamp(preset.monthlyDayOfMonth, min: 1, max: 31)
                occurrenceNoon = dayOfMonthNoon(for: monthCursor, desiredDay: desiredDay, calendar: calendar)
            }

            if let occurrenceNoon {
                let occurrenceDay = calendar.startOfDay(for: occurrenceNoon)
                if occurrenceDay >= windowStart && occurrenceDay <= windowEnd {
                    results.append(occurrenceDay)
                }
            }

            guard let nextMonth = calendar.date(byAdding: .month, value: intervalMonths, to: monthCursor) else { break }
            monthCursor = startOfMonth(for: safeNoon(on: nextMonth, calendar: calendar), calendar: calendar)
        }

        return dedupAndSort(results, calendar: calendar)
    }

    private static func startOfMonth(for date: Date, calendar: Calendar) -> Date {
        let comps = calendar.dateComponents([.year, .month], from: date)
        let first = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) ?? date
        return safeNoon(on: first, calendar: calendar)
    }

    private static func lastDayOfMonthNoon(for monthDate: Date, calendar: Calendar) -> Date? {
        let comps = calendar.dateComponents([.year, .month], from: monthDate)
        guard let firstOfMonth = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)) else {
            return nil
        }

        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) else { return nil }
        guard let lastDay = calendar.date(byAdding: .day, value: -1, to: nextMonth) else { return nil }

        return safeNoon(on: lastDay, calendar: calendar)
    }

    private static func dayOfMonthNoon(for monthDate: Date, desiredDay: Int, calendar: Calendar) -> Date? {
        let comps = calendar.dateComponents([.year, .month], from: monthDate)
        guard let year = comps.year, let month = comps.month else { return nil }

        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        guard let lastDayNoon = lastDayOfMonthNoon(for: firstOfMonth, calendar: calendar) else { return nil }
        let lastDay = calendar.component(.day, from: lastDayNoon)

        let clampedDay = clamp(desiredDay, min: 1, max: lastDay)

        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: clampedDay)) else { return nil }
        return safeNoon(on: date, calendar: calendar)
    }

    // MARK: - Yearly

    private static func yearlyOccurrences(
        preset: Preset,
        windowStart: Date,
        windowEnd: Date,
        calendar: Calendar
    ) -> [Date] {
        let intervalYears = max(1, preset.interval)
        let startNoon = safeNoon(on: windowStart, calendar: calendar)
        let endNoon = safeNoon(on: windowEnd, calendar: calendar)

        let targetMonth = clamp(preset.yearlyMonth, min: 1, max: 12)
        let targetDay = clamp(preset.yearlyDayOfMonth, min: 1, max: 31)

        var yearCursor = calendar.component(.year, from: startNoon)
        let endYear = calendar.component(.year, from: endNoon)

        var results: [Date] = []

        while yearCursor <= endYear {
            if let occurrenceNoon = yearlyDateNoon(year: yearCursor, month: targetMonth, day: targetDay, calendar: calendar) {
                let occurrenceDay = calendar.startOfDay(for: occurrenceNoon)
                if occurrenceDay >= windowStart && occurrenceDay <= windowEnd {
                    results.append(occurrenceDay)
                }
            }

            yearCursor += intervalYears
        }

        return dedupAndSort(results, calendar: calendar)
    }

    private static func yearlyDateNoon(year: Int, month: Int, day: Int, calendar: Calendar) -> Date? {
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return nil }
        guard let lastDayNoon = lastDayOfMonthNoon(for: firstOfMonth, calendar: calendar) else { return nil }
        let lastDay = calendar.component(.day, from: lastDayNoon)

        let clampedDay = clamp(day, min: 1, max: lastDay)

        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: clampedDay)) else { return nil }
        return safeNoon(on: date, calendar: calendar)
    }

    // MARK: - Helpers

    private static func safeNoon(on date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
    }

    private static func clamp(_ value: Int, min: Int, max: Int) -> Int {
        Swift.max(min, Swift.min(max, value))
    }

    private static func dedupAndSort(_ dates: [Date], calendar: Calendar) -> [Date] {
        var set = Set<Date>()
        for d in dates {
            set.insert(calendar.startOfDay(for: d))
        }
        return set.sorted()
    }
}
