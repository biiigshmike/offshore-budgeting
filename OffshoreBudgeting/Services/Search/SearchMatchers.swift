//
//  SearchMatchers.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/28/26.
//

import Foundation

// MARK: - SearchMatch

enum SearchMatch {

    // MARK: - Text

    static func matchesTextTerms(_ query: SearchQuery, in fields: [String?]) -> Bool {
        guard !query.textTerms.isEmpty else { return true }

        let haystacks: [String] = fields
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { $0.lowercased() }

        // AND across terms (each term must appear somewhere), OR across fields.
        for term in query.textTerms {
            guard haystacks.contains(where: { $0.contains(term) }) else { return false }
        }

        return true
    }

    // MARK: - Amount (contains)

    static func matchesAmountDigitTerms(_ query: SearchQuery, amounts: [Double]) -> Bool {
        guard !query.amountDigitTerms.isEmpty else { return true }
        guard !amounts.isEmpty else { return false }

        let normalizedDigits: [String] = amounts.map { amount in
            amountDigitsOnlyString(from: amount)
        }

        // AND across query digit terms, OR across amount fields.
        for term in query.amountDigitTerms {
            guard normalizedDigits.contains(where: { $0.contains(term) }) else { return false }
        }

        return true
    }

    private static let amountDigitsFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .autoupdatingCurrent
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 6
        return formatter
    }()

    private static func amountDigitsOnlyString(from value: Double) -> String {
        let absVal = abs(value)
        let s = amountDigitsFormatter.string(from: NSNumber(value: absVal)) ?? "\(absVal)"
        return s.filter(\.isNumber)
    }

    // MARK: - Date

    static func matchesDateRange(_ query: SearchQuery, date: Date) -> Bool {
        guard let range = query.dateRange else { return true }
        return range.contains(date)
    }

    static func matchesDateRange(_ query: SearchQuery, startDate: Date, endDate: Date) -> Bool {
        guard let queryRange = query.dateRange else { return true }

        let cal = Calendar.current
        let start = cal.startOfDay(for: startDate)

        let endStart = cal.startOfDay(for: endDate)
        let end = cal.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) ?? endStart

        // Overlap (inclusive)
        return start <= queryRange.upperBound && end >= queryRange.lowerBound
    }
}
