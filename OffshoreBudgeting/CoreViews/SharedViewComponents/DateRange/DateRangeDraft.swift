import Foundation

/// A disposable editing session. Dates are compared by calendar day, not time.
struct DateRangeDraft {
    var start: Date
    var end: Date
    let originalStart: Date
    let originalEnd: Date
    var calendar: Calendar = .current

    init(start: Date, end: Date, calendar: Calendar = .current) {
        self.start = start
        self.end = end
        originalStart = start
        originalEnd = end
        self.calendar = calendar
    }

    var isValid: Bool {
        calendar.startOfDay(for: start) <= calendar.startOfDay(for: end)
    }

    var canApply: Bool {
        isValid && (!calendar.isDate(start, inSameDayAs: originalStart)
                    || !calendar.isDate(end, inSameDayAs: originalEnd))
    }

    mutating func select(_ preset: CalendarQuickRangePreset, now: Date = .now) {
        let range = preset.makeRange(now: now, calendar: calendar)
        start = range.start
        end = range.end
    }
}
