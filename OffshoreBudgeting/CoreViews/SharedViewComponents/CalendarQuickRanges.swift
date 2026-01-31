//
//  CalendarQuickRanges.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/31/26.
//

import SwiftUI

// MARK: - Model

struct CalendarQuickRange: Sendable {
    let start: Date
    let end: Date
}

enum CalendarQuickRangePreset: String, Identifiable, CaseIterable {
    // Daily (rolling)
    case today
    case last30Days
    case next30Days

    // Weekly
    case lastWeek
    case currentWeek
    case nextWeek

    // Monthly
    case lastMonth
    case currentMonth
    case nextMonth

    // Quarterly
    case lastQuarter
    case currentQuarter
    case nextQuarter

    // Yearly
    case lastYear
    case currentYear
    case nextYear

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .last30Days: return "Last 30 Days"
        case .next30Days: return "Next 30 Days"
        case .lastWeek: return "Last Week"
        case .currentWeek: return "Current Week"
        case .nextWeek: return "Next Week"
        case .lastMonth: return "Last Month"
        case .currentMonth: return "Current Month"
        case .nextMonth: return "Next Month"
        case .lastQuarter: return "Last Quarter"
        case .currentQuarter: return "Current Quarter"
        case .nextQuarter: return "Next Quarter"
        case .lastYear: return "Last Year"
        case .currentYear: return "Current Year"
        case .nextYear: return "Next Year"
        }
    }

    static var dailyPresets: [CalendarQuickRangePreset] { [.today, .last30Days, .next30Days] }
    static var weeklyPresets: [CalendarQuickRangePreset] { [.lastWeek, .currentWeek, .nextWeek] }
    static var monthlyPresets: [CalendarQuickRangePreset] { [.lastMonth, .currentMonth, .nextMonth] }
    static var quarterlyPresets: [CalendarQuickRangePreset] { [.lastQuarter, .currentQuarter, .nextQuarter] }
    static var yearlyPresets: [CalendarQuickRangePreset] { [.lastYear, .currentYear, .nextYear] }

    func makeRange(now: Date = Date(), calendar: Calendar = .current) -> CalendarQuickRange {
        func startOfDay(_ date: Date) -> Date {
            calendar.startOfDay(for: date)
        }

        func endOfDay(_ date: Date) -> Date {
            let start = calendar.startOfDay(for: date)
            return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
        }

        func shiftedWeekStart(from currentWeekStart: Date, byWeeks delta: Int) -> Date {
            calendar.date(byAdding: .day, value: delta * 7, to: currentWeekStart) ?? currentWeekStart
        }

        func weekRange(weekStart: Date) -> CalendarQuickRange {
            let start = startOfDay(weekStart)
            let end = calendar.date(byAdding: DateComponents(day: 7, second: -1), to: start) ?? start
            return CalendarQuickRange(start: start, end: end)
        }

        func monthRange(monthStart: Date) -> CalendarQuickRange {
            let start = startOfDay(monthStart)
            let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
            return CalendarQuickRange(start: start, end: end)
        }

        func quarterRange(quarterStart: Date) -> CalendarQuickRange {
            let start = startOfDay(quarterStart)
            let end = calendar.date(byAdding: DateComponents(month: 3, second: -1), to: start) ?? start
            return CalendarQuickRange(start: start, end: end)
        }

        func yearRange(yearStart: Date) -> CalendarQuickRange {
            let start = startOfDay(yearStart)
            let end = calendar.date(byAdding: DateComponents(year: 1, second: -1), to: start) ?? start
            return CalendarQuickRange(start: start, end: end)
        }

        switch self {
        case .today:
            return CalendarQuickRange(start: startOfDay(now), end: endOfDay(now))

        case .last30Days:
            let start = calendar.date(byAdding: .day, value: -29, to: now) ?? now
            return CalendarQuickRange(start: startOfDay(start), end: endOfDay(now))

        case .next30Days:
            let end = calendar.date(byAdding: .day, value: 29, to: now) ?? now
            return CalendarQuickRange(start: startOfDay(now), end: endOfDay(end))

        case .lastWeek, .currentWeek, .nextWeek:
            let currentWeekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? startOfDay(now)
            let weekStart: Date
            switch self {
            case .lastWeek:
                weekStart = shiftedWeekStart(from: currentWeekStart, byWeeks: -1)
            case .currentWeek:
                weekStart = currentWeekStart
            case .nextWeek:
                weekStart = shiftedWeekStart(from: currentWeekStart, byWeeks: 1)
            default:
                weekStart = currentWeekStart
            }
            return weekRange(weekStart: weekStart)

        case .lastMonth, .currentMonth, .nextMonth:
            let currentMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfDay(now)
            let monthStart: Date
            switch self {
            case .lastMonth:
                monthStart = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart
            case .currentMonth:
                monthStart = currentMonthStart
            case .nextMonth:
                monthStart = calendar.date(byAdding: .month, value: 1, to: currentMonthStart) ?? currentMonthStart
            default:
                monthStart = currentMonthStart
            }
            return monthRange(monthStart: monthStart)

        case .lastQuarter, .currentQuarter, .nextQuarter:
            let currentQuarterStart = calendar.dateInterval(of: .quarter, for: now)?.start ?? startOfDay(now)
            let quarterStart: Date
            switch self {
            case .lastQuarter:
                quarterStart = calendar.date(byAdding: .month, value: -3, to: currentQuarterStart) ?? currentQuarterStart
            case .currentQuarter:
                quarterStart = currentQuarterStart
            case .nextQuarter:
                quarterStart = calendar.date(byAdding: .month, value: 3, to: currentQuarterStart) ?? currentQuarterStart
            default:
                quarterStart = currentQuarterStart
            }
            return quarterRange(quarterStart: quarterStart)

        case .lastYear, .currentYear, .nextYear:
            let currentYearStart = calendar.dateInterval(of: .year, for: now)?.start ?? startOfDay(now)
            let yearStart: Date
            switch self {
            case .lastYear:
                yearStart = calendar.date(byAdding: .year, value: -1, to: currentYearStart) ?? currentYearStart
            case .currentYear:
                yearStart = currentYearStart
            case .nextYear:
                yearStart = calendar.date(byAdding: .year, value: 1, to: currentYearStart) ?? currentYearStart
            default:
                yearStart = currentYearStart
            }
            return yearRange(yearStart: yearStart)
        }
    }
}

// MARK: - Menu Content

struct CalendarQuickRangeMenuItems: View {
    let onSelect: (CalendarQuickRangePreset) -> Void

    var body: some View {
        Section("Daily") {
            ForEach(CalendarQuickRangePreset.dailyPresets) { preset in
                Button(preset.title) { onSelect(preset) }
            }
        }

        Divider()

        Section("Weekly") {
            ForEach(CalendarQuickRangePreset.weeklyPresets) { preset in
                Button(preset.title) { onSelect(preset) }
            }
        }

        Divider()

        Section("Monthly") {
            ForEach(CalendarQuickRangePreset.monthlyPresets) { preset in
                Button(preset.title) { onSelect(preset) }
            }
        }

        Divider()

        Section("Quarterly") {
            ForEach(CalendarQuickRangePreset.quarterlyPresets) { preset in
                Button(preset.title) { onSelect(preset) }
            }
        }

        Divider()

        Section("Yearly") {
            ForEach(CalendarQuickRangePreset.yearlyPresets) { preset in
                Button(preset.title) { onSelect(preset) }
            }
        }
    }
}

