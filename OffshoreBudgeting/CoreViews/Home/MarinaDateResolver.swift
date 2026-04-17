//
//  MarinaDateResolver.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/15/26.
//

import Foundation

struct MarinaResolvedDateRange: Equatable {
    let start: Date
    let end: Date

    var queryDateRange: HomeQueryDateRange {
        HomeQueryDateRange(startDate: start, endDate: end)
    }
}

struct MarinaDateResolver {
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func resolve(
        input: String,
        modelStartISO8601: String?,
        modelEndISO8601: String?,
        defaultPeriodUnit: HomeQueryPeriodUnit = .month
    ) -> MarinaResolvedDateRange? {
        if let modelRange = resolveExplicitRange(start: modelStartISO8601, end: modelEndISO8601) {
            logResolved(
                source: "model_iso",
                input: "\(modelStartISO8601 ?? "nil")...\(modelEndISO8601 ?? "nil")",
                range: modelRange
            )
            return modelRange
        }

        if let textRange = resolveTextRange(input, defaultPeriodUnit: defaultPeriodUnit) {
            return textRange
        }

        logUnresolved(input: input)
        return nil
    }

    func resolveTextRange(
        _ input: String,
        defaultPeriodUnit: HomeQueryPeriodUnit = .month
    ) -> MarinaResolvedDateRange? {
        let normalized = normalizedText(input)
        guard normalized.isEmpty == false else { return nil }

        let now = nowProvider()

        if let explicitRange = extractedExplicitDateRange(from: normalized, now: now) {
            logResolved(source: "explicit", input: input, range: explicitRange)
            return explicitRange
        }

        if let singleDateRange = extractedSingleDateRange(from: normalized, now: now) {
            logResolved(source: "explicit", input: input, range: singleDateRange)
            return singleDateRange
        }

        if let periodRange = extractedPastPeriodsDateRange(
            from: normalized,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        ) {
            logResolved(source: "relative", input: input, range: periodRange)
            return periodRange
        }

        if let relativeRange = resolveRelativeRange(normalized, now: now) {
            logResolved(source: "relative", input: input, range: relativeRange)
            return relativeRange
        }

        if let namedMonthRange = extractedNamedMonthRange(from: normalized, now: now) {
            logResolved(source: "explicit", input: input, range: namedMonthRange)
            return namedMonthRange
        }

        if let rollingRange = rollingDateRange(from: normalized, now: now) {
            logResolved(source: "relative", input: input, range: rollingRange)
            return rollingRange
        }

        return nil
    }

    func resolveRelativeRange(_ input: String, now: Date) -> MarinaResolvedDateRange? {
        let normalized = normalizedText(input)
        let startOfToday = calendar.startOfDay(for: now)

        if normalized.contains("today") {
            return dayRange(for: startOfToday)
        }

        if normalized.contains("yesterday") {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return dayRange(for: yesterday)
        }

        if (normalized.contains("last week") || normalized.contains("previous week")),
           let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) {
            let previousWeekAnchor = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek.start) ?? currentWeek.start
            return fullWeekRange(containing: previousWeekAnchor)
        }

        if normalized.contains("this week"),
           let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) {
            return MarinaResolvedDateRange(
                start: calendar.startOfDay(for: currentWeek.start),
                end: now
            )
        }

        if normalized.contains("last month") || normalized.contains("previous month") {
            let currentMonthStart = monthRange(containing: now).start
            let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: currentMonthStart) ?? currentMonthStart
            return monthRange(containing: previousMonthDate)
        }

        if normalized.contains("this month") || normalized.contains("current month") || normalized.contains("month to date") {
            return monthRange(containing: now)
        }

        if normalized.contains("last year") || normalized.contains("previous year") {
            let currentYearStart = yearRange(containing: now).start
            let previousYearDate = calendar.date(byAdding: .year, value: -1, to: currentYearStart) ?? currentYearStart
            return yearRange(containing: previousYearDate)
        }

        if normalized.contains("this year") || normalized.contains("current year") || normalized.contains("year to date") {
            return yearRange(containing: now)
        }

        return nil
    }

    func resolveExplicitRange(start: String?, end: String?) -> MarinaResolvedDateRange? {
        let now = nowProvider()

        guard start != nil || end != nil else { return nil }

        if let start,
           let end,
           let pair = resolvedDatePair(start: start, end: end, now: now) {
            return MarinaResolvedDateRange(
                start: calendar.startOfDay(for: pair.start),
                end: endOfDay(for: pair.end)
            )
        }

        if let single = start ?? end,
           let parsed = parsedDateCandidate(single, now: now) {
            return dayRange(for: parsed.date)
        }

        return nil
    }

    func resolveSingleDate(_ input: String) -> Date? {
        parsedDateCandidate(input, now: nowProvider())?.date
    }

    private func extractedExplicitDateRange(from text: String, now: Date) -> MarinaResolvedDateRange? {
        let patterns = [
            "\\bfrom\\s+(.{3,40}?)\\s+(?:to|and|-|through|thru)\\s+(.{3,40})\\b",
            "\\bbetween\\s+(.{3,40}?)\\s+(?:to|and|-|through|thru)\\s+(.{3,40})\\b",
            "\\b([a-z0-9,\\-/ ]{3,40}?)\\s+(?:to|and|-|through|thru)\\s+([a-z0-9,\\-/ ]{3,40})\\b"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
                  match.numberOfRanges >= 3,
                  let leftRange = Range(match.range(at: 1), in: text),
                  let rightRange = Range(match.range(at: 2), in: text) else {
                continue
            }

            let left = String(text[leftRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(text[rightRange]).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let pair = resolvedDatePair(start: left, end: right, now: now) else {
                continue
            }

            return MarinaResolvedDateRange(
                start: calendar.startOfDay(for: pair.start),
                end: endOfDay(for: pair.end)
            )
        }

        return nil
    }

    private func extractedSingleDateRange(from text: String, now: Date) -> MarinaResolvedDateRange? {
        let patterns = [
            "\\bon\\s+([a-z0-9,\\-/ ]{3,40}?)(?=\\s+\\$?[-]?[0-9]|\\s+(?:from|to|and|through|thru|at|using|with)\\b|$)",
            "\\bfor\\s+([a-z0-9,\\-/ ]{3,40}?)(?=\\s+(?:from|to|and|through|thru|at|using|with)\\b|\\s+\\$?[-]?[0-9]|$)"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: nsRange),
                  match.numberOfRanges >= 2,
                  let candidateRange = Range(match.range(at: 1), in: text) else {
                continue
            }

            let candidate = String(text[candidateRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = parsedDateCandidate(candidate, now: now) else { continue }
            return dayRange(for: parsed.date)
        }

        return nil
    }

    private func extractedPastPeriodsDateRange(
        from text: String,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaResolvedDateRange? {
        guard let range = text.range(
            of: "\\b(last|past)\\s+(\\d{1,3})\\s+(period|periods)\\b",
            options: .regularExpression
        ) else {
            return nil
        }

        let phrase = String(text[range])
        let parts = phrase.split(separator: " ")
        guard parts.count == 3 else { return nil }
        guard let quantity = Int(parts[1]), quantity > 0 else { return nil }

        return closedRangeForPastPeriods(quantity: quantity, unit: defaultPeriodUnit, endingAt: now)
    }

    private func closedRangeForPastPeriods(
        quantity: Int,
        unit: HomeQueryPeriodUnit,
        endingAt now: Date
    ) -> MarinaResolvedDateRange? {
        guard quantity > 0 else { return nil }

        let end: Date
        let start: Date

        switch unit {
        case .day:
            start = calendar.startOfDay(for: now)
            let startDay = calendar.date(byAdding: .day, value: -(quantity - 1), to: start) ?? start
            return MarinaResolvedDateRange(start: startDay, end: endOfDay(for: start))

        case .week:
            guard let currentWeek = fullWeekRange(containing: now) else { return nil }
            start = calendar.date(byAdding: .weekOfYear, value: -(quantity - 1), to: currentWeek.start) ?? currentWeek.start
            end = currentWeek.end

        case .month:
            let currentMonth = monthRange(containing: now)
            start = calendar.date(byAdding: .month, value: -(quantity - 1), to: currentMonth.start) ?? currentMonth.start
            end = currentMonth.end

        case .quarter:
            guard let quarterStart = quarterStart(containing: now) else { return nil }
            start = calendar.date(byAdding: .month, value: -((quantity - 1) * 3), to: quarterStart) ?? quarterStart
            let quarterEndBase = calendar.date(byAdding: .month, value: 3, to: quarterStart) ?? quarterStart
            end = calendar.date(byAdding: .second, value: -1, to: quarterEndBase) ?? quarterStart

        case .year:
            let currentYear = yearRange(containing: now)
            start = calendar.date(byAdding: .year, value: -(quantity - 1), to: currentYear.start) ?? currentYear.start
            end = currentYear.end
        }

        return MarinaResolvedDateRange(start: start, end: end)
    }

    private func extractedNamedMonthRange(from text: String, now: Date) -> MarinaResolvedDateRange? {
        let monthByToken: [String: Int] = [
            "jan": 1, "january": 1,
            "feb": 2, "february": 2,
            "mar": 3, "march": 3,
            "apr": 4, "april": 4,
            "may": 5,
            "jun": 6, "june": 6,
            "jul": 7, "july": 7,
            "aug": 8, "august": 8,
            "sep": 9, "sept": 9, "september": 9,
            "oct": 10, "october": 10,
            "nov": 11, "november": 11,
            "dec": 12, "december": 12
        ]

        let tokens = text.split(separator: " ").map(String.init)
        guard let monthIndex = tokens.firstIndex(where: { monthByToken[$0] != nil }),
              let month = monthByToken[tokens[monthIndex]] else {
            return nil
        }

        let nowComponents = calendar.dateComponents([.year, .month], from: now)
        guard let currentYear = nowComponents.year,
              let currentMonth = nowComponents.month else {
            return nil
        }

        let explicitYear: Int? = {
            if monthIndex + 1 < tokens.count,
               let nextYear = Int(tokens[monthIndex + 1]),
               (1900...2200).contains(nextYear) {
                return nextYear
            }

            if monthIndex > 0,
               let previousYear = Int(tokens[monthIndex - 1]),
               (1900...2200).contains(previousYear) {
                return previousYear
            }

            return nil
        }()

        let year = explicitYear ?? (month > currentMonth ? currentYear - 1 : currentYear)
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0
        components.timeZone = calendar.timeZone

        guard let date = calendar.date(from: components) else { return nil }
        return monthRange(containing: date)
    }

    private func rollingDateRange(from text: String, now: Date) -> MarinaResolvedDateRange? {
        guard let match = text.range(
            of: "\\b(last|past)\\s+(\\d{1,3})\\s+(day|days|week|weeks|month|months)\\b",
            options: .regularExpression
        ) else {
            return nil
        }

        let phrase = String(text[match])
        let parts = phrase.split(separator: " ")
        guard parts.count == 3 else { return nil }
        guard let quantity = Int(parts[1]), quantity > 0 else { return nil }

        let unit = String(parts[2])
        let endDate = now

        let startDate: Date
        switch unit {
        case "day", "days":
            startDate = calendar.date(byAdding: .day, value: -(quantity - 1), to: calendar.startOfDay(for: now)) ?? now
        case "week", "weeks":
            startDate = calendar.date(byAdding: .day, value: -((quantity * 7) - 1), to: calendar.startOfDay(for: now)) ?? now
        case "month", "months":
            let monthDate = calendar.date(byAdding: .month, value: -quantity, to: now) ?? now
            startDate = calendar.startOfDay(for: monthDate)
        default:
            return nil
        }

        return MarinaResolvedDateRange(start: startDate, end: endDate)
    }

    private func resolvedDatePair(start: String, end: String, now: Date) -> (start: Date, end: Date)? {
        let startParsed = parsedDateCandidate(start, now: now)
        let endParsed = parsedDateCandidate(end, now: now)

        if let startParsed, let endParsed {
            if startParsed.hadExplicitYear == false, endParsed.hadExplicitYear {
                guard let carried = parsedDateCandidate(start, now: now, fallbackYear: calendar.component(.year, from: endParsed.date)) else {
                    return nil
                }
                return orderedPair(start: carried.date, end: endParsed.date)
            }

            if endParsed.hadExplicitYear == false, startParsed.hadExplicitYear {
                guard let carried = parsedDateCandidate(end, now: now, fallbackYear: calendar.component(.year, from: startParsed.date)) else {
                    return nil
                }
                return orderedPair(start: startParsed.date, end: carried.date)
            }

            return orderedPair(start: startParsed.date, end: endParsed.date)
        }

        return nil
    }

    private func orderedPair(start: Date, end: Date) -> (start: Date, end: Date) {
        start <= end ? (start, end) : (end, start)
    }

    private func parsedDateCandidate(
        _ candidate: String,
        now: Date,
        fallbackYear: Int? = nil
    ) -> (date: Date, hadExplicitYear: Bool)? {
        let trimmed = candidate
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard trimmed.isEmpty == false else { return nil }

        if let isoDate = parsedISODate(trimmed) {
            return (isoDate, true)
        }

        let hadExplicitYear = trimmed.range(of: "\\b\\d{4}\\b", options: .regularExpression) != nil
        let resolvedYear = fallbackYear ?? calendar.component(.year, from: now)

        let directFormats = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "M/d/yyyy",
            "MM-dd-yyyy",
            "M-d-yyyy",
            "MMMM d yyyy",
            "MMM d yyyy",
            "d MMMM yyyy",
            "d MMM yyyy",
            "MMMM d",
            "MMM d",
            "d MMMM",
            "d MMM"
        ]

        for format in directFormats {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format

            if let date = formatter.date(from: trimmed) {
                if format.contains("yyyy") {
                    return (date, true)
                }

                if let dated = formatter.date(from: "\(trimmed) \(resolvedYear)") {
                    return (dated, hadExplicitYear)
                }
            }

            if format.contains("yyyy") == false {
                formatter.dateFormat = "\(format) yyyy"
                if let date = formatter.date(from: "\(trimmed) \(resolvedYear)") {
                    return (date, hadExplicitYear)
                }
            }
        }

        return nil
    }

    private func parsedISODate(_ value: String) -> Date? {
        let isoFullDate = ISO8601DateFormatter()
        isoFullDate.timeZone = calendar.timeZone
        isoFullDate.formatOptions = [.withFullDate]
        if let date = isoFullDate.date(from: value) {
            return date
        }

        let isoDateTime = ISO8601DateFormatter()
        isoDateTime.timeZone = calendar.timeZone
        isoDateTime.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoDateTime.date(from: value) {
            return date
        }

        let isoDateTimeNoFraction = ISO8601DateFormatter()
        isoDateTimeNoFraction.timeZone = calendar.timeZone
        isoDateTimeNoFraction.formatOptions = [.withInternetDateTime]
        return isoDateTimeNoFraction.date(from: value)
    }

    private func dayRange(for date: Date) -> MarinaResolvedDateRange {
        let dayStart = calendar.startOfDay(for: date)
        return MarinaResolvedDateRange(start: dayStart, end: endOfDay(for: dayStart))
    }

    private func fullWeekRange(containing date: Date) -> MarinaResolvedDateRange? {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else {
            return nil
        }

        let weekStart = calendar.startOfDay(for: weekInterval.start)
        let weekEnd = calendar.date(byAdding: .second, value: -1, to: weekInterval.end) ?? weekStart
        return MarinaResolvedDateRange(start: weekStart, end: weekEnd)
    }

    private func monthRange(containing date: Date) -> MarinaResolvedDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let endBase = calendar.date(byAdding: DateComponents(month: 1), to: start) ?? start
        let end = calendar.date(byAdding: .second, value: -1, to: endBase) ?? start
        return MarinaResolvedDateRange(start: start, end: end)
    }

    private func yearRange(containing date: Date) -> MarinaResolvedDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        let endBase = calendar.date(byAdding: DateComponents(year: 1), to: start) ?? start
        let end = calendar.date(byAdding: .second, value: -1, to: endBase) ?? start
        return MarinaResolvedDateRange(start: start, end: end)
    }

    private func quarterStart(containing date: Date) -> Date? {
        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else { return nil }

        let quarterStartMonth: Int
        switch month {
        case 1...3:
            quarterStartMonth = 1
        case 4...6:
            quarterStartMonth = 4
        case 7...9:
            quarterStartMonth = 7
        default:
            quarterStartMonth = 10
        }

        var quarterComponents = DateComponents()
        quarterComponents.year = year
        quarterComponents.month = quarterStartMonth
        quarterComponents.day = 1
        quarterComponents.timeZone = calendar.timeZone
        return calendar.date(from: quarterComponents)
    }

    private func endOfDay(for date: Date) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? start
    }

    private func normalizedText(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9,\\-/\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func logResolved(source: String, input: String, range: MarinaResolvedDateRange) {
        MarinaDebugLogger.log(
            "[MarinaDate] source=\(source) input='\(input)' -> \(logDate(range.start))-\(logDate(range.end))"
        )
    }

    private func logUnresolved(input: String) {
        MarinaDebugLogger.log("[MarinaDate] unresolved input='\(input)'")
    }

    private func logDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
