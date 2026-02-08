//
//  HomeAssistantTextParser.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

// MARK: - Parser

struct HomeAssistantTextParser {
    private let calendar: Calendar
    private let nowProvider: () -> Date

    init(
        calendar: Calendar = .current,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.nowProvider = nowProvider
    }

    func parse(_ rawText: String) -> HomeQuery? {
        let normalizedText = rawText
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedText.isEmpty == false else { return nil }
        guard let intent = resolvedIntent(from: normalizedText) else { return nil }

        let limit = extractedLimit(from: normalizedText)
        let dateRange = extractedDateRange(from: normalizedText)

        switch intent {
        case .topCategoriesThisMonth, .largestRecentTransactions:
            return HomeQuery(
                intent: intent,
                dateRange: dateRange,
                resultLimit: limit
            )

        case .spendThisMonth, .compareThisMonthToPreviousMonth:
            return HomeQuery(intent: intent, dateRange: dateRange)
        }
    }

    // MARK: - Matching

    private func resolvedIntent(from text: String) -> HomeQueryIntent? {
        if matchesCompareIntent(in: text) {
            return .compareThisMonthToPreviousMonth
        }

        if matchesTopCategoriesIntent(in: text) {
            return .topCategoriesThisMonth
        }

        if matchesLargestTransactionsIntent(in: text) {
            return .largestRecentTransactions
        }

        if matchesSpendIntent(in: text) {
            return .spendThisMonth
        }

        return nil
    }

    private func matchesSpendIntent(in text: String) -> Bool {
        let spendKeywords = [
            "spend", "spent", "spending", "expense", "expenses",
            "outflow", "total", "total spend", "how much"
        ]
        return containsAny(text, keywords: spendKeywords)
    }

    private func matchesTopCategoriesIntent(in text: String) -> Bool {
        let rankingKeywords = ["top", "highest", "most", "biggest", "largest"]
        let categoryKeywords = ["category", "categories", "bucket", "buckets"]

        if containsAny(text, keywords: rankingKeywords) && containsAny(text, keywords: categoryKeywords) {
            return true
        }

        if text.contains("where am i spending most")
            || text.contains("where am i spending the most")
            || text.contains("where do i spend most")
            || (text.contains("where") && containsAny(text, keywords: ["spend most", "spending most", "most spending"])) {
            return true
        }

        return false
    }

    private func matchesCompareIntent(in text: String) -> Bool {
        let compareKeywords = [
            "compare", "comparison", "difference", "vs", "versus",
            "against", "changed", "change", "month over month", "mom"
        ]
        return containsAny(text, keywords: compareKeywords)
    }

    private func matchesLargestTransactionsIntent(in text: String) -> Bool {
        let rankingKeywords = ["largest", "biggest", "highest", "top"]
        let transactionKeywords = [
            "transaction", "transactions", "purchase", "purchases",
            "charge", "charges", "expense", "expenses"
        ]

        return containsAny(text, keywords: rankingKeywords)
            && containsAny(text, keywords: transactionKeywords)
    }

    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { keyword in
            text.contains(keyword)
        }
    }

    // MARK: - Range Extraction

    private func extractedDateRange(from text: String) -> HomeQueryDateRange? {
        let now = nowProvider()
        let startOfToday = calendar.startOfDay(for: now)

        if text.contains("today") {
            return dayRange(for: startOfToday)
        }

        if text.contains("yesterday") {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
            return dayRange(for: yesterday)
        }

        if text.contains("last month") || text.contains("previous month") {
            let thisMonthStart = monthRange(containing: now).startDate
            let previousMonthDate = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? thisMonthStart
            return monthRange(containing: previousMonthDate)
        }

        if text.contains("this month") || text.contains("current month") || text.contains("month to date") {
            return monthRange(containing: now)
        }

        if text.contains("last year") || text.contains("previous year") {
            let thisYearStart = yearRange(containing: now).startDate
            let previousYearDate = calendar.date(byAdding: .year, value: -1, to: thisYearStart) ?? thisYearStart
            return yearRange(containing: previousYearDate)
        }

        if text.contains("this year") || text.contains("current year") || text.contains("year to date") {
            return yearRange(containing: now)
        }

        if let unitRange = rollingDateRange(from: text, now: now) {
            return unitRange
        }

        return nil
    }

    private func rollingDateRange(from text: String, now: Date) -> HomeQueryDateRange? {
        guard let match = text.range(of: "\\b(last|past)\\s+(\\d{1,3})\\s+(day|days|week|weeks|month|months)\\b", options: .regularExpression) else {
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
            let dayOffset = -(quantity - 1)
            startDate = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now

        case "week", "weeks":
            let dayOffset = -((quantity * 7) - 1)
            startDate = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now)) ?? now

        case "month", "months":
            let monthDate = calendar.date(byAdding: .month, value: -quantity, to: now) ?? now
            startDate = calendar.startOfDay(for: monthDate)

        default:
            return nil
        }

        return HomeQueryDateRange(startDate: startDate, endDate: endDate)
    }

    private func dayRange(for date: Date) -> HomeQueryDateRange {
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: dayStart) ?? dayStart
        return HomeQueryDateRange(startDate: dayStart, endDate: dayEnd)
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func yearRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(year: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    // MARK: - Numeric Extraction

    private func extractedLimit(from text: String) -> Int? {
        guard let range = text.range(of: "\\b\\d+\\b", options: .regularExpression) else { return nil }
        guard let value = Int(text[range]) else { return nil }
        return value
    }
}
