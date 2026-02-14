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

    func parse(
        _ rawText: String,
        defaultPeriodUnit: HomeQueryPeriodUnit = .month
    ) -> HomeQuery? {
        parsePlan(rawText, defaultPeriodUnit: defaultPeriodUnit)?.query
    }

    func parsePlan(
        _ rawText: String,
        defaultPeriodUnit: HomeQueryPeriodUnit = .month
    ) -> HomeQueryPlan? {
        let normalizedText = normalize(rawText)

        guard normalizedText.isEmpty == false else { return nil }
        guard let intent = resolvedIntent(from: normalizedText) else { return nil }

        let limit = extractedLimit(from: normalizedText)
        let dateRange = extractedDateRange(from: normalizedText, defaultPeriodUnit: defaultPeriodUnit)
        let periodUnit = extractedPeriodsUnit(from: normalizedText, defaultPeriodUnit: defaultPeriodUnit)

        let confidenceBand = confidenceBand(for: intent, text: normalizedText)
        let metric = intent.metric

        switch intent {
        case .periodOverview, .spendThisMonth, .compareThisMonthToPreviousMonth, .cardSpendTotal, .incomeAverageActual, .savingsStatus, .incomeSourceShare, .categorySpendShare, .presetCategorySpend:
            return HomeQueryPlan(
                metric: metric,
                dateRange: dateRange,
                resultLimit: nil,
                confidenceBand: confidenceBand,
                periodUnit: periodUnit
            )
        case .savingsAverageRecentPeriods, .incomeSourceShareTrend, .categorySpendShareTrend:
            let periodCount = extractedPeriodsLookback(from: normalizedText) ?? limit
            return HomeQueryPlan(
                metric: metric,
                dateRange: nil,
                resultLimit: periodCount,
                confidenceBand: confidenceBand,
                periodUnit: periodUnit
            )
        case .topCategoriesThisMonth, .largestRecentTransactions, .cardVariableSpendingHabits, .presetDueSoon, .presetHighestCost, .presetTopCategory, .categoryPotentialSavings, .categoryReallocationGuidance:
            return HomeQueryPlan(
                metric: metric,
                dateRange: dateRange,
                resultLimit: limit,
                confidenceBand: confidenceBand,
                periodUnit: periodUnit
            )
        }
    }

    func parseDateRange(
        _ rawText: String,
        defaultPeriodUnit: HomeQueryPeriodUnit = .month
    ) -> HomeQueryDateRange? {
        let normalizedText = normalize(rawText)
        guard normalizedText.isEmpty == false else { return nil }
        return extractedDateRange(from: normalizedText, defaultPeriodUnit: defaultPeriodUnit)
    }

    func parseLimit(_ rawText: String) -> Int? {
        let normalizedText = normalize(rawText)
        guard normalizedText.isEmpty == false else { return nil }
        return extractedLimit(from: normalizedText)
    }

    // MARK: - Matching

    private func resolvedIntent(from text: String) -> HomeQueryIntent? {
        if matchesCompareIntent(in: text) {
            return .compareThisMonthToPreviousMonth
        }

        if matchesSavingsAverageIntent(in: text) {
            return .savingsAverageRecentPeriods
        }

        if matchesSavingsStatusIntent(in: text) {
            return .savingsStatus
        }

        if matchesIncomeSourceShareTrendIntent(in: text) {
            return .incomeSourceShareTrend
        }

        if matchesCategorySpendShareTrendIntent(in: text) {
            return .categorySpendShareTrend
        }

        if matchesIncomeSourceShareIntent(in: text) {
            return .incomeSourceShare
        }

        if matchesCategorySpendShareIntent(in: text) {
            return .categorySpendShare
        }

        if matchesPresetDueIntent(in: text) {
            return .presetDueSoon
        }

        if matchesPresetHighestCostIntent(in: text) {
            return .presetHighestCost
        }

        if matchesPresetTopCategoryIntent(in: text) {
            return .presetTopCategory
        }

        if matchesPresetCategorySpendIntent(in: text) {
            return .presetCategorySpend
        }

        if matchesCategoryPotentialSavingsIntent(in: text) {
            return .categoryPotentialSavings
        }

        if matchesCategoryReallocationIntent(in: text) {
            return .categoryReallocationGuidance
        }

        if matchesOverviewIntent(in: text) {
            return .periodOverview
        }

        if matchesTopCategoriesIntent(in: text) {
            return .topCategoriesThisMonth
        }

        if matchesLargestTransactionsIntent(in: text) {
            return .largestRecentTransactions
        }

        if matchesCardSpendingHabitsIntent(in: text) {
            return .cardVariableSpendingHabits
        }

        if matchesCardSpendIntent(in: text) {
            return .cardSpendTotal
        }

        if matchesIncomeAverageIntent(in: text) {
            return .incomeAverageActual
        }

        if matchesSpendIntent(in: text) {
            return .spendThisMonth
        }

        return nil
    }

    private func matchesOverviewIntent(in text: String) -> Bool {
        if text.contains("how am i doing")
            || text.contains("how are we doing")
            || text.contains("how did i do")
            || text.contains("how is my budget")
            || text.contains("how s my budget looking")
            || text.contains("how is my budget looking")
            || text.contains("how are my finances")
            || text.contains("how are my finances looking")
            || text.contains("budget check in")
            || text.contains("budget checkin")
            || text.contains("total available")
            || text.contains("projected savings")
            || text.contains("left after planned expenses")
            || text.contains("current balance")
            || text.contains("over budget")
        {
            return true
        }

        let overviewKeywords = ["overview", "summary", "snapshot", "status", "health", "performance", "check in", "checkin"]
        let financeContextKeywords = ["budget", "spend", "spending", "expense", "expenses", "month", "year", "finances", "money"]

        return containsAny(text, keywords: overviewKeywords)
            && containsAny(text, keywords: financeContextKeywords)
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
            || text.contains("where do i spend the most")
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

    private func matchesCardSpendIntent(in text: String) -> Bool {
        let spendKeywords = ["spend", "spent", "spending", "total spent", "charges"]
        let cardKeywords = ["card", "cards", "all cards"]

        return containsAny(text, keywords: spendKeywords)
            && containsAny(text, keywords: cardKeywords)
    }

    private func matchesCardSpendingHabitsIntent(in text: String) -> Bool {
        let cardKeywords = ["card", "cards", "all cards"]
        let habitKeywords = ["habits", "habit", "patterns", "pattern", "behavior", "trends", "trend"]
        let variableKeywords = ["variable spend", "variable spending", "spending habits"]

        return (containsAny(text, keywords: cardKeywords) && containsAny(text, keywords: habitKeywords))
            || containsAny(text, keywords: variableKeywords)
    }

    private func matchesIncomeAverageIntent(in text: String) -> Bool {
        let incomeKeywords = ["income", "actual income"]
        let averageKeywords = ["average", "avg", "mean"]

        return containsAny(text, keywords: incomeKeywords)
            && containsAny(text, keywords: averageKeywords)
    }

    private func matchesSavingsStatusIntent(in text: String) -> Bool {
        let savingsKeywords = ["savings", "save", "saved"]
        let statusKeywords = ["how am i doing", "how are we doing", "status", "outlook", "doing"]

        return containsAny(text, keywords: savingsKeywords)
            && containsAny(text, keywords: statusKeywords)
    }

    private func matchesSavingsAverageIntent(in text: String) -> Bool {
        let savingsKeywords = ["savings", "save", "saved"]
        let averageKeywords = ["average", "avg", "mean"]
        let periodKeywords = ["period", "periods", "month", "months", "last", "past"]

        return containsAny(text, keywords: savingsKeywords)
            && containsAny(text, keywords: averageKeywords)
            && containsAny(text, keywords: periodKeywords)
    }

    private func matchesIncomeSourceShareIntent(in text: String) -> Bool {
        let incomeKeywords = ["income", "paycheck", "paychecks", "source", "sources", "salary", "wages"]
        let shareKeywords = ["how much", "share", "comes from", "from", "percent", "percentage", "portion", "split", "contribution", "received", "scheduled", "recurring", "planned income", "total income"]

        return containsAny(text, keywords: incomeKeywords)
            && containsAny(text, keywords: shareKeywords)
    }

    private func matchesIncomeSourceShareTrendIntent(in text: String) -> Bool {
        let trendKeywords = ["last", "past", "period", "periods", "day", "days", "week", "weeks", "month", "months", "quarter", "quarters", "year", "years"]
        return matchesIncomeSourceShareIntent(in: text)
            && containsAny(text, keywords: trendKeywords)
            && extractedPeriodsLookback(from: text) != nil
    }

    private func matchesCategorySpendShareIntent(in text: String) -> Bool {
        let categoryKeywords = ["category", "categories"]
        let spendKeywords = ["spend", "spent", "spending", "expenses"]
        let shareKeywords = ["share", "how much", "percent", "percentage", "portion", "split", "contribution", "of my"]
        let incomeKeywords = ["income", "source", "paycheck", "salary"]
        let cardKeywords = ["card", "cards"]

        let explicitCategoryShare = containsAny(text, keywords: categoryKeywords)
            && containsAny(text, keywords: spendKeywords)
            && containsAny(text, keywords: shareKeywords)

        // This catches natural phrasing like "What share of my spending is groceries this month?"
        // even when users do not include the word "category".
        let implicitSpendShare = containsAny(text, keywords: spendKeywords)
            && containsAny(text, keywords: shareKeywords)
            && containsAny(text, keywords: [" is ", " in ", " from "])
            && containsAny(text, keywords: incomeKeywords) == false
            && containsAny(text, keywords: cardKeywords) == false

        return explicitCategoryShare || implicitSpendShare
    }

    private func matchesCategorySpendShareTrendIntent(in text: String) -> Bool {
        let trendKeywords = ["last", "past", "period", "periods", "day", "days", "week", "weeks", "month", "months", "quarter", "quarters", "year", "years"]
        return matchesCategorySpendShareIntent(in: text)
            && containsAny(text, keywords: trendKeywords)
            && extractedPeriodsLookback(from: text) != nil
    }

    private func matchesPresetDueIntent(in text: String) -> Bool {
        let presetKeywords = ["preset", "presets", "recurring", "autopay", "auto pay", "scheduled payment", "scheduled payments"]
        let dueKeywords = ["due", "coming up", "upcoming", "due soon", "next due", "planned expenses are coming up", "owe in planned expenses", "overdue"]

        return containsAny(text, keywords: presetKeywords)
            && containsAny(text, keywords: dueKeywords)
    }

    private func matchesPresetHighestCostIntent(in text: String) -> Bool {
        let presetKeywords = ["preset", "presets", "recurring", "autopay", "auto pay", "planned expense", "planned expenses"]
        let costKeywords = ["costs me the most", "most expensive", "highest cost", "costliest", "cost me the most"]

        return containsAny(text, keywords: presetKeywords)
            && containsAny(text, keywords: costKeywords)
    }

    private func matchesPresetTopCategoryIntent(in text: String) -> Bool {
        let presetKeywords = ["preset", "presets", "recurring", "autopay", "auto pay"]
        let categoryKeywords = ["category", "categories"]
        let assignmentKeywords = ["assigned", "most presets", "most preset", "most recurring", "most recurring charges", "most autopay"]

        return containsAny(text, keywords: presetKeywords)
            && containsAny(text, keywords: categoryKeywords)
            && containsAny(text, keywords: assignmentKeywords)
    }

    private func matchesPresetCategorySpendIntent(in text: String) -> Bool {
        let presetKeywords = ["preset", "presets", "recurring", "autopay", "auto pay"]
        let categoryKeywords = ["category", "categories"]
        let spendKeywords = ["how much", "spend", "cost", "per period", "each period", "per month", "monthly"]
        let naturalCategoryReferenceKeywords = [" on ", " for "]

        let mentionsPreset = containsAny(text, keywords: presetKeywords)
        let mentionsCategoryScope = containsAny(text, keywords: categoryKeywords)
            || containsAny(text, keywords: naturalCategoryReferenceKeywords)

        return mentionsPreset
            && mentionsCategoryScope
            && containsAny(text, keywords: spendKeywords)
    }

    private func matchesCategoryPotentialSavingsIntent(in text: String) -> Bool {
        let categoryKeywords = ["category", "categories", "this category", "groceries", "shopping", "dining", "transportation", "utilities", "rent", "travel", "entertainment"]
        let reductionKeywords = ["reduce", "cut", "lower", "decrease"]
        let savingsKeywords = ["savings", "save", "potential savings"]

        return containsAny(text, keywords: categoryKeywords)
            && containsAny(text, keywords: reductionKeywords)
            && containsAny(text, keywords: savingsKeywords)
    }

    private func matchesCategoryReallocationIntent(in text: String) -> Bool {
        let categoryKeywords = ["category", "categories", "this category", "other categories", "groceries", "shopping", "dining", "transportation", "utilities", "rent", "travel", "entertainment"]
        let allocationKeywords = ["realistically spend", "what could i spend", "what can i spend", "other categories", "reallocate", "allocation", "rebalance", "redistribute"]
        let spendKeywords = ["spend", "spending"]
        let reductionKeywords = ["reduce", "cut", "lower", "decrease"]

        return containsAny(text, keywords: categoryKeywords)
            && containsAny(text, keywords: allocationKeywords)
            && (containsAny(text, keywords: spendKeywords) || containsAny(text, keywords: reductionKeywords))
    }

    private func containsAny(_ text: String, keywords: [String]) -> Bool {
        keywords.contains { keyword in
            text.contains(keyword)
        }
    }

    private func confidenceBand(for intent: HomeQueryIntent, text: String) -> HomeQueryConfidenceBand {
        if containsAny(text, keywords: ["maybe", "roughly", "kind of", "not sure", "i guess"]) {
            return .low
        }

        switch intent {
        case .periodOverview:
            // Broad overview prompts are inherently less specific than direct metric requests.
            return .medium
        case .spendThisMonth, .topCategoriesThisMonth, .compareThisMonthToPreviousMonth, .largestRecentTransactions, .cardSpendTotal, .cardVariableSpendingHabits, .incomeAverageActual, .savingsStatus, .savingsAverageRecentPeriods, .incomeSourceShare, .categorySpendShare, .incomeSourceShareTrend, .categorySpendShareTrend, .presetDueSoon, .presetHighestCost, .presetTopCategory, .presetCategorySpend, .categoryPotentialSavings, .categoryReallocationGuidance:
            return .high
        }
    }

    private func normalize(_ rawText: String) -> String {
        var text = rawText
            .replacingOccurrences(of: "%", with: " percent ")
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s\\-/]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let typoReplacements: [(from: String, to: String)] = [
            ("spnd", "spend"),
            ("spnding", "spending"),
            ("spnt", "spent"),
            ("spening", "spending"),
            ("expnse", "expense"),
            ("expnses", "expenses"),
            ("catgory", "category"),
            ("catgories", "categories"),
            ("grocereis", "groceries"),
            ("incom", "income"),
            ("salery", "salary"),
            ("paychek", "paycheck"),
            ("paymnt", "payment"),
            ("recuring", "recurring"),
            ("recurrng", "recurring"),
            ("budjet", "budget")
        ]

        for replacement in typoReplacements {
            text = text.replacingOccurrences(
                of: "\\b\(replacement.from)\\b",
                with: replacement.to,
                options: .regularExpression
            )
        }

        return text
    }

    // MARK: - Range Extraction

    private func extractedDateRange(
        from text: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange? {
        let now = nowProvider()
        let startOfToday = calendar.startOfDay(for: now)

        if let explicitRange = extractedExplicitDateRange(from: text) {
            return explicitRange
        }

        if let singleDateRange = extractedSingleDateRange(from: text) {
            return singleDateRange
        }

        if let periodRange = extractedPastPeriodsDateRange(from: text, now: now, defaultPeriodUnit: defaultPeriodUnit) {
            return periodRange
        }

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

        if let namedMonthRange = extractedNamedMonthRange(from: text, now: now) {
            return namedMonthRange
        }

        if let unitRange = rollingDateRange(from: text, now: now) {
            return unitRange
        }

        return nil
    }

    private func extractedExplicitDateRange(from text: String) -> HomeQueryDateRange? {
        guard
            let range = text.range(
                of: "\\b(from|between)\\s+([a-z0-9\\-/ ]{3,40}?)\\s+(to|and|-|through|thru)\\s+([a-z0-9\\-/ ]{3,40})\\b",
                options: .regularExpression
            )
        else {
            return nil
        }

        let phrase = String(text[range])

        guard
            let separatorRange = phrase.range(
                of: "\\s+(to|and|-|through|thru)\\s+",
                options: .regularExpression
            )
        else {
            return nil
        }

        let left = phrase[..<separatorRange.lowerBound]
            .replacingOccurrences(of: "from ", with: "")
            .replacingOccurrences(of: "between ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let right = phrase[separatorRange.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard
            let startDate = parsedDateCandidate(String(left)),
            let endDate = parsedDateCandidate(String(right))
        else {
            return nil
        }

        let startOfStart = calendar.startOfDay(for: startDate)
        let startOfEnd = calendar.startOfDay(for: endDate)
        let endOfEnd = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: startOfEnd) ?? startOfEnd
        return HomeQueryDateRange(startDate: startOfStart, endDate: endOfEnd)
    }

    private func extractedSingleDateRange(from text: String) -> HomeQueryDateRange? {
        guard
            let range = text.range(
                of: "\\b(on|for)\\s+([a-z0-9\\-/ ]{3,40}?)(?=\\s+(from|to|and|through|thru|at|using|with)\\b|$)",
                options: .regularExpression
            )
        else {
            return nil
        }

        let phrase = String(text[range])
        let candidate = phrase
            .replacingOccurrences(of: "on ", with: "")
            .replacingOccurrences(of: "for ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let date = parsedDateCandidate(candidate) else { return nil }
        return dayRange(for: date)
    }

    private func parsedDateCandidate(_ candidate: String) -> Date? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let directFormats = [
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "M/d/yyyy",
            "MM-dd-yyyy",
            "M-d-yyyy",
            "MMMM d yyyy",
            "MMM d yyyy",
            "d MMMM yyyy",
            "d MMM yyyy"
        ]

        for format in directFormats {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }

        let inferredYearText: String = {
            if trimmed.range(of: "\\b\\d{4}\\b", options: .regularExpression) != nil {
                return trimmed
            }

            let year = calendar.component(.year, from: nowProvider())
            return "\(trimmed) \(year)"
        }()

        let inferredFormats = ["MMMM d yyyy", "MMM d yyyy", "d MMMM yyyy", "d MMM yyyy", "M/d/yyyy", "M-d-yyyy"]
        for format in inferredFormats {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: inferredYearText) {
                return date
            }
        }

        return nil
    }

    private func extractedPastPeriodsDateRange(
        from text: String,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange? {
        guard let range = text.range(of: "\\b(last|past)\\s+(\\d{1,3})\\s+(period|periods)\\b", options: .regularExpression) else {
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
    ) -> HomeQueryDateRange? {
        guard quantity > 0 else { return nil }

        let end: Date
        let start: Date

        switch unit {
        case .day:
            end = calendar.startOfDay(for: now)
            start = calendar.date(byAdding: .day, value: -(quantity - 1), to: end) ?? end

        case .week:
            guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now) else { return nil }
            let weekStart = calendar.startOfDay(for: currentWeek.start)
            end = calendar.date(byAdding: DateComponents(day: 6), to: weekStart) ?? weekStart
            start = calendar.date(byAdding: .weekOfYear, value: -(quantity - 1), to: weekStart) ?? weekStart

        case .month:
            let currentMonth = monthRange(containing: now)
            end = currentMonth.endDate
            start = calendar.date(byAdding: .month, value: -(quantity - 1), to: currentMonth.startDate) ?? currentMonth.startDate

        case .quarter:
            guard let quarterStart = quarterStart(containing: now) else { return nil }
            end = calendar.date(byAdding: DateComponents(month: 3, second: -1), to: quarterStart) ?? quarterStart
            start = calendar.date(byAdding: .month, value: -((quantity - 1) * 3), to: quarterStart) ?? quarterStart

        case .year:
            let currentYear = yearRange(containing: now)
            end = currentYear.endDate
            start = calendar.date(byAdding: .year, value: -(quantity - 1), to: currentYear.startDate) ?? currentYear.startDate
        }

        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func extractedNamedMonthRange(from text: String, now: Date) -> HomeQueryDateRange? {
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
        guard let monthIndex = tokens.firstIndex(where: { monthByToken[$0] != nil }) else {
            return nil
        }

        guard let month = monthByToken[tokens[monthIndex]] else { return nil }

        let nowComponents = calendar.dateComponents([.year, .month], from: now)
        guard let currentYear = nowComponents.year, let currentMonth = nowComponents.month else { return nil }

        let explicitYear: Int? = {
            if monthIndex + 1 < tokens.count, let nextYear = Int(tokens[monthIndex + 1]), (1900...2200).contains(nextYear) {
                return nextYear
            }

            if monthIndex > 0, let previousYear = Int(tokens[monthIndex - 1]), (1900...2200).contains(previousYear) {
                return previousYear
            }

            return nil
        }()

        let year: Int
        if let explicitYear {
            year = explicitYear
        } else {
            year = month > currentMonth ? currentYear - 1 : currentYear
        }

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        components.hour = 0
        components.minute = 0
        components.second = 0

        guard let date = calendar.date(from: components) else { return nil }
        return monthRange(containing: date)
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

        return calendar.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1))
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

    private func extractedPeriodsLookback(from text: String) -> Int? {
        guard let range = text.range(of: "\\b(last|past)\\s+(\\d{1,2})\\s+(period|periods|day|days|week|weeks|month|months|quarter|quarters|year|years)\\b", options: .regularExpression) else {
            return nil
        }

        let phrase = String(text[range])
        let parts = phrase.split(separator: " ")
        guard parts.count == 3 else { return nil }
        return Int(parts[1])
    }

    private func extractedPeriodsUnit(
        from text: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> HomeQueryPeriodUnit? {
        guard let range = text.range(of: "\\b(last|past)\\s+(\\d{1,2})\\s+(period|periods|day|days|week|weeks|month|months|quarter|quarters|year|years)\\b", options: .regularExpression) else {
            return nil
        }

        let phrase = String(text[range])
        let parts = phrase.split(separator: " ")
        guard parts.count == 3 else { return nil }

        switch parts[2] {
        case "day", "days":
            return .day
        case "week", "weeks":
            return .week
        case "month", "months":
            return .month
        case "quarter", "quarters":
            return .quarter
        case "year", "years":
            return .year
        case "period", "periods":
            return defaultPeriodUnit
        default:
            return nil
        }
    }
}

// MARK: - Command Parser

struct HomeAssistantCommandParser {
    private let parser: HomeAssistantTextParser

    init(
        parser: HomeAssistantTextParser = HomeAssistantTextParser()
    ) {
        self.parser = parser
    }

    func parse(
        _ rawText: String,
        defaultPeriodUnit: HomeQueryPeriodUnit = .month
    ) -> HomeAssistantCommandPlan? {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let normalized = normalizedText(trimmed)
        guard let intent = resolvedIntent(from: normalized) else { return nil }

        let parsedRange = parser.parseDateRange(trimmed, defaultPeriodUnit: defaultPeriodUnit)
        let date = parsedRange?.startDate
        let amounts = extractedAmounts(from: trimmed)
        let amountPair = extractedFromToAmounts(from: trimmed)

        let amount: Double?
        let originalAmount: Double?
        switch intent {
        case .editExpense, .editIncome, .updatePlannedExpenseAmount:
            originalAmount = amountPair?.from ?? amounts.first
            amount = amountPair?.to ?? amounts.last
        case .addExpense, .addIncome, .addPreset, .markIncomeReceived:
            originalAmount = nil
            amount = amounts.first
        case .deleteExpense, .deleteIncome, .moveExpenseCategory, .deleteLastExpense, .deleteLastIncome:
            originalAmount = nil
            amount = amounts.first
        case .addBudget, .addCard, .addCategory:
            originalAmount = nil
            amount = nil
        }

        let notes = extractedExpenseNotes(from: trimmed)
        let source = extractedIncomeSource(from: trimmed)
        let cardName = extractedCardName(from: trimmed)
        let categoryName = extractedCategoryName(from: trimmed)
        let entityName = extractedEntityName(from: trimmed, intent: intent)
        let incomeKind = extractedIncomeKind(from: normalized)
        let categoryColor = extractedCategoryColor(from: trimmed)
        let cardTheme = extractedCardTheme(from: normalized)
        let cardEffect = extractedCardEffect(from: normalized)
        let plannedExpenseAmountTarget = extractedPlannedExpenseAmountTarget(from: normalized)
        let attachAllCards = extractedAttachAllCards(from: normalized)
        let attachAllPresets = extractedAttachAllPresets(from: normalized)

        return HomeAssistantCommandPlan(
            intent: intent,
            confidenceBand: .high,
            rawPrompt: trimmed,
            amount: amount,
            originalAmount: originalAmount,
            date: date,
            dateRange: parsedRange,
            notes: notes,
            source: source,
            cardName: cardName,
            categoryName: categoryName,
            entityName: entityName,
            isPlannedIncome: incomeKind,
            categoryColorHex: categoryColor.hex,
            categoryColorName: categoryColor.name,
            cardThemeRaw: cardTheme?.rawValue,
            cardEffectRaw: cardEffect?.rawValue,
            plannedExpenseAmountTarget: plannedExpenseAmountTarget,
            attachAllCards: attachAllCards,
            attachAllPresets: attachAllPresets
        )
    }

    func isCardCrudPrompt(_ rawText: String) -> Bool {
        let normalized = normalizedText(rawText)
        let hasMutationVerb = normalized.contains("delete") || normalized.contains("edit") || normalized.contains("add")
        return hasMutationVerb && normalized.contains("card")
    }

    private func resolvedIntent(from normalized: String) -> HomeAssistantCommandIntent? {
        if normalized.contains("mark")
            && normalized.contains("income")
            && (normalized.contains("received") || normalized.contains("as received"))
        {
            return .markIncomeReceived
        }

        if (normalized.contains("delete last expense")
            || normalized.contains("delete my last expense")
            || normalized.contains("remove my last expense"))
        {
            return .deleteLastExpense
        }

        if (normalized.contains("delete last income")
            || normalized.contains("delete my last income")
            || normalized.contains("remove my last income"))
        {
            return .deleteLastIncome
        }

        if (normalized.contains("move this expense") || normalized.contains("move expense"))
            && normalized.contains("category")
        {
            return .moveExpenseCategory
        }

        if matchesPlannedExpenseAmountUpdateIntent(in: normalized) {
            return .updatePlannedExpenseAmount
        }

        if matchesCreateEntityIntent(in: normalized, entityKeyword: "budget") {
            return .addBudget
        }

        if matchesCreateEntityIntent(in: normalized, entityKeyword: "preset") {
            return .addPreset
        }

        if matchesCreateEntityIntent(in: normalized, entityKeyword: "card")
            && normalized.contains("expense") == false
            && normalized.contains("transaction") == false
        {
            return .addCard
        }

        if matchesCreateEntityIntent(in: normalized, entityKeyword: "category") {
            return .addCategory
        }

        if normalized.contains("income") {
            if normalized.contains("delete") || normalized.contains("remove") {
                return .deleteIncome
            }
            if normalized.contains("edit") || normalized.contains("update") || normalized.contains("change") {
                return .editIncome
            }
            if normalized.contains("add") || normalized.contains("log") || normalized.contains("create") {
                return .addIncome
            }
        }

        if normalized.contains("expense")
            || normalized.contains("transaction")
            || normalized.contains("purchase")
            || normalized.contains("charge")
            || normalized.contains("$")
        {
            if normalized.contains("delete") || normalized.contains("remove") {
                return .deleteExpense
            }
            if normalized.contains("edit") || normalized.contains("update") || normalized.contains("change") {
                return .editExpense
            }
            if normalized.contains("add") || normalized.contains("log") || normalized.contains("create") {
                return .addExpense
            }
        }

        return nil
    }

    private func matchesCreateEntityIntent(in normalized: String, entityKeyword: String) -> Bool {
        let creationVerbs = ["add", "create", "new", "make"]
        let hasVerb = creationVerbs.contains { normalized.contains($0) }
        return hasVerb && normalized.contains(entityKeyword)
    }

    private func extractedFromToAmounts(from text: String) -> (from: Double, to: Double)? {
        guard
            let range = text.range(
                of: "\\bfrom\\s+\\$?[-]?[0-9][0-9,]*(?:\\.[0-9]{1,2})?\\s+to\\s+\\$?[-]?[0-9][0-9,]*(?:\\.[0-9]{1,2})?\\b",
                options: .regularExpression
            )
        else {
            return nil
        }

        let phrase = String(text[range])
        let parts = phrase.split(separator: " ")
        guard parts.count == 4 else { return nil }

        guard
            let from = parseAmountToken(String(parts[1])),
            let to = parseAmountToken(String(parts[3]))
        else {
            return nil
        }

        return (from: from, to: to)
    }

    private func extractedAmounts(from text: String) -> [Double] {
        guard let regex = try? NSRegularExpression(pattern: "\\$?[-]?[0-9][0-9,]*(?:\\.[0-9]{1,2})?") else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: range)

        return matches.compactMap { match -> Double? in
            guard let r = Range(match.range, in: text) else { return nil }
            return parseAmountToken(String(text[r]))
        }
    }

    private func parseAmountToken(_ token: String) -> Double? {
        let cleaned = token
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CurrencyFormatter.parseAmount(cleaned)
    }

    private func extractedExpenseNotes(from text: String) -> String? {
        if let forRange = text.range(of: "\\bfor\\s+(.+)$", options: .regularExpression) {
            let value = String(text[forRange]).replacingOccurrences(of: "for", with: "")
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return stripTrailingPunctuation(trimmed)
            }
        }

        if let merchantRange = text.range(of: "\\bat\\s+(.+)$", options: .regularExpression) {
            let value = String(text[merchantRange]).replacingOccurrences(of: "at", with: "")
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return stripTrailingPunctuation(trimmed)
            }
        }

        return nil
    }

    private func extractedIncomeSource(from text: String) -> String? {
        if let fromRange = text.range(of: "\\bfrom\\s+(.+)$", options: .regularExpression) {
            let value = String(text[fromRange]).replacingOccurrences(of: "from", with: "")
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return sanitizedIncomeSource(trimmed)
            }
        }

        if let forRange = text.range(of: "\\bfor\\s+(.+)$", options: .regularExpression) {
            let value = String(text[forRange]).replacingOccurrences(of: "for", with: "")
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                return sanitizedIncomeSource(trimmed)
            }
        }

        return extractedIncomeSourceFallback(from: text)
    }

    private func extractedIncomeSourceFallback(from text: String) -> String? {
        var value = text
            .replacingOccurrences(of: "\\$?[-]?[0-9][0-9,]*(?:\\.[0-9]{1,2})?", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\b(add|log|create|income|mark|as|received|entry|new|my|an|a)\\b", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard value.isEmpty == false else { return nil }
        value = sanitizedIncomeSource(value) ?? ""
        return value.isEmpty ? nil : value
    }

    private func sanitizedIncomeSource(_ raw: String) -> String? {
        var source = raw
            .replacingOccurrences(of: "\\$?[-]?[0-9][0-9,]*(?:\\.[0-9]{1,2})?", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\b(planned|actual|income|received)\\b", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        source = sanitizeCreationPhrase(stripTrailingPunctuation(source))
        return source.isEmpty ? nil : source
    }

    private func extractedCardName(from text: String) -> String? {
        let patterns = [
            "\\bon\\s+([A-Za-z0-9 '\\-]+?)\\s+card\\b",
            "\\bto\\s+([A-Za-z0-9 '\\-]+?)\\s+card\\b",
            "\\busing\\s+([A-Za-z0-9 '\\-]+?)\\s+card\\b"
        ]

        for pattern in patterns {
            guard
                let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive])
            else {
                continue
            }

            var value = String(text[range])
            value = value
                .replacingOccurrences(of: "on ", with: "")
                .replacingOccurrences(of: "to ", with: "")
                .replacingOccurrences(of: "using ", with: "")
                .replacingOccurrences(of: " card", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if value.isEmpty == false {
                return stripTrailingPunctuation(value)
            }
        }

        return nil
    }

    private func extractedCategoryName(from text: String) -> String? {
        let patterns = [
            "\\bcategory\\s+([A-Za-z0-9 '&\\-]+)\\b",
            "\\bto\\s+([A-Za-z0-9 '&\\-]+)\\s+category\\b"
        ]

        for pattern in patterns {
            guard let range = text.range(of: pattern, options: .regularExpression) else {
                continue
            }

            let phrase = String(text[range])
                .replacingOccurrences(of: "category", with: "")
                .replacingOccurrences(of: "to", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if phrase.isEmpty == false {
                return stripTrailingPunctuation(phrase)
            }
        }

        return nil
    }

    private func extractedEntityName(
        from text: String,
        intent: HomeAssistantCommandIntent
    ) -> String? {
        let compactText = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let patterns: [String]
        switch intent {
        case .addCard:
            patterns = [
                "\\b(?:called|named)\\s+([A-Za-z0-9 '&\\-]+)$",
                "\\bcard\\s+([A-Za-z0-9 '&\\-]+)$"
            ]
        case .addCategory:
            patterns = [
                "\\b(?:called|named)\\s+([A-Za-z0-9 '&\\-]+)$",
                "\\bcategory\\s+([A-Za-z0-9 '&\\-]+)$"
            ]
        case .addPreset:
            patterns = [
                "\\b(?:called|named)\\s+([A-Za-z0-9 '&\\-]+)$",
                "\\bpreset\\s+([A-Za-z0-9 '&\\-]+)$"
            ]
        case .addBudget:
            patterns = [
                "\\b(?:called|named)\\s+([A-Za-z0-9 '&\\-]+)$",
                "\\bbudget\\s+([A-Za-z0-9 '&\\-]+)$"
            ]
        case .addExpense, .addIncome, .editExpense, .deleteExpense, .editIncome, .deleteIncome, .markIncomeReceived, .moveExpenseCategory, .updatePlannedExpenseAmount, .deleteLastExpense, .deleteLastIncome:
            return nil
        }

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let nsrange = NSRange(compactText.startIndex..<compactText.endIndex, in: compactText)
            guard let match = regex.firstMatch(in: compactText, options: [], range: nsrange),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: compactText)
            else {
                continue
            }

            var raw = String(compactText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            raw = stripTrailingPunctuation(raw)
            if intent == .addPreset {
                raw = raw.replacingOccurrences(
                    of: "\\s+\\$?[-]?[0-9][0-9,]*(?:\\.[0-9]{1,2})?$",
                    with: "",
                    options: .regularExpression
                ).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            raw = sanitizeCreationPhrase(raw)
            if raw.isEmpty == false {
                return raw
            }
        }

        return nil
    }

    private func extractedCategoryColor(from text: String) -> (hex: String?, name: String?) {
        let lowered = normalizedText(text)

        let extractedName: String? = {
            if let range = lowered.range(of: "\\b(?:color|colour)\\s+([a-z\\s]{3,30})\\b", options: .regularExpression) {
                let phrase = String(lowered[range])
                    .replacingOccurrences(of: "color", with: "")
                    .replacingOccurrences(of: "colour", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return phrase.isEmpty ? nil : phrase
            }
            return marinaColorAliases.keys.first(where: { lowered.contains($0) })
        }()

        guard let extractedName else { return (nil, nil) }
        if let hex = marinaColorAliases[extractedName] {
            return (hex, extractedName)
        }

        let compact = extractedName.replacingOccurrences(of: " ", with: "")
        if let key = marinaColorAliases.keys.first(where: { $0.replacingOccurrences(of: " ", with: "") == compact }),
           let hex = marinaColorAliases[key] {
            return (hex, key)
        }

        return (nil, extractedName)
    }

    private func extractedCardTheme(from normalized: String) -> CardThemeOption? {
        for option in CardThemeOption.allCases where normalized.contains(option.rawValue) {
            return option
        }
        return nil
    }

    private func extractedCardEffect(from normalized: String) -> CardEffectOption? {
        for option in CardEffectOption.allCases where normalized.contains(option.rawValue) {
            return option
        }
        return nil
    }

    private func extractedAttachAllCards(from normalized: String) -> Bool? {
        if normalized.contains("all cards") || normalized.contains("attach every card") {
            return true
        }
        if normalized.contains("no cards") || normalized.contains("without cards") || normalized.contains("skip cards") {
            return false
        }
        return nil
    }

    private func extractedAttachAllPresets(from normalized: String) -> Bool? {
        if normalized.contains("all presets") || normalized.contains("attach every preset") {
            return true
        }
        if normalized.contains("no presets") || normalized.contains("without presets") || normalized.contains("skip presets") {
            return false
        }
        return nil
    }

    private func matchesPlannedExpenseAmountUpdateIntent(in normalized: String) -> Bool {
        let hasUpdateVerb = normalized.range(
            of: "\\b(update|edit|change|set)\\b",
            options: .regularExpression
        ) != nil
        guard hasUpdateVerb else { return false }

        guard normalized.range(of: "\\$?[-]?[0-9][0-9,]*(?:\\.[0-9]{1,2})?", options: .regularExpression) != nil else {
            return false
        }

        if normalized.contains("income") {
            return false
        }

        if normalized.contains("planned expense")
            || normalized.contains("planned")
            || normalized.contains("preset")
            || normalized.contains("rent")
            || normalized.contains("mortgage")
            || normalized.contains("subscription")
        {
            return true
        }

        return normalized.contains(" to ")
    }

    private func extractedPlannedExpenseAmountTarget(from normalized: String) -> HomeAssistantPlannedExpenseAmountTarget? {
        if normalized.contains("actual") || normalized.contains("effective") {
            return .actual
        }
        if normalized.contains("planned") {
            return .planned
        }
        return nil
    }

    private func sanitizeCreationPhrase(_ input: String) -> String {
        var phrase = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phrase.isEmpty == false else { return phrase }

        let removalPatterns = [
            "\\b(actual|planned)\\b$",
            "\\bon\\s+[a-z0-9 '&\\-]+\\s+card\\b$",
            "\\bcategory\\s+[a-z0-9 '&\\-]+\\b$"
        ]

        for pattern in removalPatterns {
            phrase = phrase.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return stripTrailingPunctuation(phrase)
    }

    private var marinaColorAliases: [String: String] {
        [
            "blue": "#3B82F6",
            "green": "#22C55E",
            "forest green": "#228B22",
            "red": "#EF4444",
            "orange": "#F97316",
            "yellow": "#EAB308",
            "purple": "#8B5CF6",
            "pink": "#EC4899",
            "mauve": "#B784A7",
            "periwinkle": "#8FA6FF",
            "perriwinkle": "#8FA6FF",
            "cafe": "#6F4E37",
            "brown": "#8B5A2B",
            "teal": "#14B8A6",
            "mint": "#10B981",
            "gray": "#6B7280",
            "grey": "#6B7280",
            "black": "#111827",
            "white": "#E5E7EB"
        ]
    }

    private func extractedIncomeKind(from normalized: String) -> Bool? {
        if normalized.contains("planned") {
            return true
        }
        if normalized.contains("actual") {
            return false
        }
        return nil
    }

    private func normalizedText(_ rawText: String) -> String {
        rawText
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripTrailingPunctuation(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
    }
}
