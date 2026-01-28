//
//  SearchQuery.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/28/26.
//

import Foundation

// MARK: - SearchQuery

struct SearchQuery {

    // MARK: - Stored

    let raw: String
    let trimmed: String

    /// Search terms that should match text fields (name/title/category/card, etc.).
    let textTerms: [String]

    /// Digit-only tokens that should match amount strings (e.g. "33" matches "$12.33").
    let amountDigitTerms: [String]

    /// If present, items must be within this day-normalized range (inclusive).
    let dateRange: ClosedRange<Date>?

    // MARK: - Derived

    var isEmpty: Bool {
        trimmed.isEmpty
    }

    // MARK: - Init

    init(
        raw: String,
        textTerms: [String],
        amountDigitTerms: [String],
        dateRange: ClosedRange<Date>?
    ) {
        self.raw = raw
        self.trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        self.textTerms = textTerms
        self.amountDigitTerms = amountDigitTerms
        self.dateRange = dateRange
    }
}

// MARK: - SearchQueryParser

enum SearchQueryParser {

    // MARK: - Public

    static func parse(_ raw: String) -> SearchQuery {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SearchQuery(raw: raw, textTerms: [], amountDigitTerms: [], dateRange: nil)
        }

        let detected = detectDates(in: trimmed)
        let dateRange = makeNormalizedDateRange(from: detected)

        let excludedRanges = detected.map(\.range)
        let amountTerms = extractAmountDigitTerms(from: trimmed, excluding: excludedRanges)

        let textTerms = extractTextTerms(from: trimmed, excluding: excludedRanges)
            .filter { term in
                // If the user typed "33" or "50", treat it as amount search instead of text.
                let digitsOnly = term.filter(\.isNumber)
                if digitsOnly.count == term.count, !digitsOnly.isEmpty {
                    return false
                }
                return true
            }

        return SearchQuery(
            raw: raw,
            textTerms: textTerms,
            amountDigitTerms: amountTerms,
            dateRange: dateRange
        )
    }

    // MARK: - Date detection

    private struct DetectedDate {
        let range: NSRange
        let date: Date
        let matchedText: String
    }

    private static func detectDates(in text: String) -> [DetectedDate] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return []
        }

        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        let matches = detector.matches(in: text, options: [], range: full)

        var results: [DetectedDate] = []
        results.reserveCapacity(matches.count)

        for match in matches {
            guard let date = match.date else { continue }
            let matchedText = ns.substring(with: match.range)

            // Heuristic: avoid treating partial dates like "Jan 1" as a date filter.
            // Only activate date filtering when a year is present (2-digit or 4-digit),
            // or when the input is clearly numeric with 3 components (e.g. 1/1/26).
            guard dateMatchLooksComplete(matchedText) else { continue }

            results.append(DetectedDate(range: match.range, date: date, matchedText: matchedText))
        }

        return results.sorted { $0.range.location < $1.range.location }
    }

    private static func dateMatchLooksComplete(_ matched: String) -> Bool {
        let s = matched.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return false }

        // Accept obvious numeric forms with 3 components.
        // Examples: 1/1/26, 01-01-2026, 2026/01/01
        let numericParts = s
            .replacingOccurrences(of: "–", with: "-")
            .replacingOccurrences(of: "—", with: "-")
            .split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if numericParts.count >= 3, numericParts.contains(where: { $0.count == 2 || $0.count == 4 }) {
            return true
        }

        // Accept month-name based forms when a final year token is present.
        // Examples: Jan 1 26, January 1, 2026
        let tokens = s
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .map(String.init)

        guard let last = tokens.last else { return false }
        let lastDigits = last.filter(\.isNumber)
        if lastDigits.count == last.count, (last.count == 2 || last.count == 4) {
            return true
        }

        return false
    }

    private static func makeNormalizedDateRange(from detected: [DetectedDate]) -> ClosedRange<Date>? {
        guard !detected.isEmpty else { return nil }

        // If the user typed a range like "1/1/26 - 1/7/26", NSDataDetector typically yields 2 dates.
        // We interpret "2+ dates" as a range using the first two detected dates in the string.
        if detected.count >= 2 {
            let d1 = detected[0].date
            let d2 = detected[1].date

            let start = min(d1, d2)
            let end = max(d1, d2)

            let startDay = Calendar.current.startOfDay(for: start)
            let endDayStart = Calendar.current.startOfDay(for: end)
            let endDay = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: endDayStart) ?? endDayStart

            return startDay...endDay
        }

        let only = detected[0].date
        let startDay = Calendar.current.startOfDay(for: only)
        let endDay = Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: startDay) ?? startDay
        return startDay...endDay
    }

    // MARK: - Amount terms

    private static func extractAmountDigitTerms(from text: String, excluding excludedRanges: [NSRange]) -> [String] {
        // Pull out digit sequences, but ignore numbers that are part of detected dates.
        // Also accept ".33" by capturing the digits.
        let pattern = #"(?:(?<=^)|(?<=[^\d]))(\d+(?:[.,]\d+)?)|(?:(?<=^)|(?<=[^\d]))[.,](\d+)"#

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        var terms: [String] = []

        let matches = regex.matches(in: text, options: [], range: full)
        for m in matches {
            let r = m.range
            if rangeIntersectsAny(r, excludedRanges) { continue }

            let g1 = m.range(at: 1)
            let g2 = m.range(at: 2)

            let rawToken: String
            if g1.location != NSNotFound, g1.length > 0 {
                rawToken = ns.substring(with: g1)
            } else if g2.location != NSNotFound, g2.length > 0 {
                rawToken = ns.substring(with: g2)
            } else {
                continue
            }

            let digitsOnly = rawToken.filter(\.isNumber)
            guard !digitsOnly.isEmpty else { continue }
            terms.append(digitsOnly)
        }

        // De-dupe while preserving order
        var seen = Set<String>()
        return terms.filter { term in
            guard !seen.contains(term) else { return false }
            seen.insert(term)
            return true
        }
    }

    // MARK: - Text terms

    private static func extractTextTerms(from text: String, excluding excludedRanges: [NSRange]) -> [String] {
        // Replace excluded ranges (dates) with spaces before tokenizing.
        _ = text as NSString
        var scalars = Array(text.unicodeScalars)

        for r in excludedRanges {
            guard let start = unicodeScalarIndex(forUTF16Location: r.location, in: text),
                  let end = unicodeScalarIndex(forUTF16Location: r.location + r.length, in: text)
            else { continue }

            for i in start..<end {
                scalars[i] = UnicodeScalar(32) // space
            }
        }

        let cleaned = String(String.UnicodeScalarView(scalars))
        let tokens = cleaned
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "–", with: " ")
            .replacingOccurrences(of: "—", with: " ")
            .replacingOccurrences(of: "/", with: " ")
            .replacingOccurrences(of: ",", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        // Lowercase for case-insensitive matching, preserve original spacing behavior.
        return tokens.map { $0.lowercased() }
    }

    // MARK: - Helpers

    private static func rangeIntersectsAny(_ range: NSRange, _ excluded: [NSRange]) -> Bool {
        for e in excluded {
            if NSIntersectionRange(range, e).length > 0 { return true }
        }
        return false
    }

    private static func unicodeScalarIndex(forUTF16Location location: Int, in string: String) -> Int? {
        // Convert an NSString/UTF16 index into a unicodeScalar index.
        // This is deliberately lightweight and defensive (search text is short).
        var utf16Count = 0

        for (i, scalar) in string.unicodeScalars.enumerated() {
            utf16Count += scalar.utf16.count
            if utf16Count > location {
                return i
            }
        }

        if utf16Count == location {
            return string.unicodeScalars.count
        }

        return nil
    }
}
