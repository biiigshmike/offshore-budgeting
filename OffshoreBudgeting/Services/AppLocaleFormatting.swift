//
//  AppLocaleFormatting.swift
//  OffshoreBudgeting
//
//  Centralized user-visible formatting that respects system Language & Region.
//

import Foundation

enum AppDateFormat {

    // MARK: - Styles

    static let abbreviatedDateStyle: Date.FormatStyle = Date.FormatStyle(date: .abbreviated, time: .omitted)
    static let abbreviatedDateTimeStyle: Date.FormatStyle = Date.FormatStyle(date: .abbreviated, time: .shortened)
    static let numericDateStyle: Date.FormatStyle = Date.FormatStyle(date: .numeric, time: .omitted)

    // MARK: - Strings

    static func abbreviatedDate(_ date: Date) -> String {
        date.formatted(abbreviatedDateStyle)
    }

    static func abbreviatedDateTime(_ date: Date) -> String {
        date.formatted(abbreviatedDateTimeStyle)
    }

    static func numericDate(_ date: Date) -> String {
        date.formatted(numericDateStyle)
    }

    static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

enum AppNumberFormat {

    // MARK: - Number

    static func integer(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func decimal(
        _ value: Double,
        minimumFractionDigits: Int = 0,
        maximumFractionDigits: Int = 2
    ) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .autoupdatingCurrent
        formatter.minimumFractionDigits = max(0, minimumFractionDigits)
        formatter.maximumFractionDigits = max(formatter.minimumFractionDigits, maximumFractionDigits)
        return formatter.string(from: NSNumber(value: value))
            ?? value.formatted(.number.precision(.fractionLength(formatter.minimumFractionDigits...formatter.maximumFractionDigits)))
    }
}

enum AppCalendarFormat {

    // MARK: - Weekdays

    static func firstWeekdayName(calendar: Calendar = .autoupdatingCurrent) -> String {
        let index = max(1, min(calendar.firstWeekday, calendar.weekdaySymbols.count)) - 1
        return calendar.weekdaySymbols[index]
    }
}
