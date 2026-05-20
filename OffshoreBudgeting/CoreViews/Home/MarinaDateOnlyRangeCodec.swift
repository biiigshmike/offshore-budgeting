import Foundation

enum MarinaDateSource: String, Codable, Equatable, Sendable {
    case promptExplicit
    case modelGrounded
    case homeAppliedRange
    case defaultBudgetingPeriod
    case none
}

enum MarinaDateOnlyRangeCodec {
    static func dateOnlyString(
        from date: Date,
        calendar inputCalendar: Calendar = .current
    ) -> String {
        var calendar = inputCalendar
        if calendar.timeZone.secondsFromGMT() == 0 {
            calendar.timeZone = .current
        }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func dateRange(
        start: String?,
        end: String?,
        calendar inputCalendar: Calendar = .current
    ) -> HomeQueryDateRange? {
        var calendar = inputCalendar
        if calendar.timeZone.secondsFromGMT() == 0 {
            calendar.timeZone = .current
        }
        return MarinaDateResolver(calendar: calendar).resolveExplicitRange(
            start: start,
            end: end
        )?.queryDateRange
    }

    static func aiDateRange(
        from range: HomeQueryDateRange?,
        rawText: String?,
        periodUnit: HomeQueryPeriodUnit?,
        calendar: Calendar = .current
    ) -> MarinaAIDateRangeV2? {
        guard let range else { return nil }
        return MarinaAIDateRangeV2(
            startISO8601: dateOnlyString(from: range.startDate, calendar: calendar),
            endISO8601: dateOnlyString(from: range.endDate, calendar: calendar),
            rawText: rawText,
            periodUnitRaw: periodUnit?.rawValue
        )
    }

    static func defaultRange(
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        calendar inputCalendar: Calendar = .current
    ) -> HomeQueryDateRange? {
        var calendar = inputCalendar
        if calendar.timeZone.secondsFromGMT() == 0 {
            calendar.timeZone = .current
        }
        return MarinaDateResolver(calendar: calendar, nowProvider: { now }).resolveTextRange(
            "current period",
            defaultPeriodUnit: defaultPeriodUnit
        )?.queryDateRange
    }

    static func traceSummary(
        _ range: HomeQueryDateRange?,
        calendar: Calendar = .current
    ) -> String? {
        guard let range else { return nil }
        return "\(dateOnlyString(from: range.startDate, calendar: calendar))..\(dateOnlyString(from: range.endDate, calendar: calendar))"
    }
}
