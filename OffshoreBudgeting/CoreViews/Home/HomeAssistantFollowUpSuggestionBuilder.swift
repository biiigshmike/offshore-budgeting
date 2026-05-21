//
//  HomeAssistantFollowUpSuggestionBuilder.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/21/26.
//

import Foundation

struct HomeAssistantFollowUpSuggestionBuilder {
    func suggestions(
        after answer: HomeAnswer,
        executedQuery: HomeQuery? = nil
    ) -> [HomeAssistantSuggestion] {
        let confidenceCue = confidenceCue(for: answer)

        func makeSuggestion(_ action: String, query: HomeQuery) -> HomeAssistantSuggestion {
            HomeAssistantSuggestion(
                title: action,
                query: query
            )
        }

        func contextSuggestions(_ suggestions: [HomeAssistantSuggestion], excluding executedQuery: HomeQuery) -> [HomeAssistantSuggestion] {
            var unique: [HomeAssistantSuggestion] = []
            var seen: Set<String> = []
            for suggestion in suggestions where isSameQueryShape(suggestion.query, executedQuery) == false {
                let key = suggestionKey(suggestion.query)
                guard seen.insert(key).inserted else { continue }
                unique.append(suggestion)
                if unique.count == 3 { break }
            }
            return unique
        }

        switch confidenceCue {
        case .low:
            return [
                makeSuggestion("Spend this month", query: HomeQuery(intent: .spendThisMonth)),
                makeSuggestion("Top categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 3))
            ]
        case .medium:
            return [
                makeSuggestion("Top 3 categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 3)),
                makeSuggestion("Compare with last month", query: HomeQuery(intent: .compareThisMonthToPreviousMonth))
            ]
        case .high:
            break
        }

        if let executedQuery {
            let range = executedQuery.dateRange
            let target = executedQuery.targetName
            let period = executedQuery.periodUnit
            let scopedTopCategories = makeSuggestion(
                scopedFollowUpLabel(base: "Top categories", for: executedQuery),
                query: HomeQuery(intent: .topCategoriesThisMonth, dateRange: range, resultLimit: 3, periodUnit: period)
            )
            let scopedTop3Categories = makeSuggestion(
                scopedFollowUpLabel(base: "Top 3 categories", for: executedQuery),
                query: HomeQuery(intent: .topCategoriesThisMonth, dateRange: range, resultLimit: 3, periodUnit: period)
            )
            let scopedLargestExpenses = makeSuggestion(
                scopedFollowUpLabel(base: "Largest expenses", for: executedQuery),
                query: HomeQuery(intent: .largestRecentTransactions, dateRange: range, resultLimit: 5, periodUnit: period)
            )

            switch executedQuery.intent {
            case .incomeAverageActual:
                var suggestions = [
                    makeSuggestion(scopedFollowUpLabel(base: "Income share by source", for: executedQuery), query: HomeQuery(intent: .incomeSourceShare, dateRange: range, periodUnit: period)),
                    makeSuggestion(scopedFollowUpLabel(base: "Income share trend", for: executedQuery), query: HomeQuery(intent: .incomeSourceShareTrend, dateRange: range, resultLimit: 4, periodUnit: period ?? .month))
                ]
                if target != nil {
                    suggestions.append(
                        makeSuggestion("Compare income source with previous period", query: HomeQuery(intent: .compareIncomeSourceThisMonthToPreviousMonth, dateRange: range, targetName: target, periodUnit: period))
                    )
                }
                return contextSuggestions(suggestions, excluding: executedQuery)
            case .incomeSourceShare, .incomeSourceShareTrend, .compareIncomeSourceThisMonthToPreviousMonth:
                return contextSuggestions([
                    makeSuggestion(scopedFollowUpLabel(base: "Average actual income", for: executedQuery), query: HomeQuery(intent: .incomeAverageActual, dateRange: range, targetName: target, periodUnit: period)),
                    makeSuggestion(scopedFollowUpLabel(base: "Income share trend", for: executedQuery), query: HomeQuery(intent: .incomeSourceShareTrend, dateRange: range, resultLimit: max(4, executedQuery.resultLimit), targetName: target, periodUnit: period ?? .month)),
                    makeSuggestion("Compare income with previous period", query: HomeQuery(intent: .compareIncomeSourceThisMonthToPreviousMonth, dateRange: range, targetName: target, periodUnit: period))
                ], excluding: executedQuery)
            case .savingsStatus, .savingsAverageRecentPeriods, .forecastSavings:
                return contextSuggestions([
                    makeSuggestion(scopedFollowUpLabel(base: "Average savings", for: executedQuery), query: HomeQuery(intent: .savingsAverageRecentPeriods, dateRange: range, resultLimit: max(6, executedQuery.resultLimit), periodUnit: period)),
                    makeSuggestion(scopedFollowUpLabel(base: "Forecast savings", for: executedQuery), query: HomeQuery(intent: .forecastSavings, dateRange: range, periodUnit: period)),
                    makeSuggestion(comparisonFollowUpLabel(for: executedQuery), query: HomeQuery(intent: .compareThisMonthToPreviousMonth, dateRange: range, periodUnit: period))
                ], excluding: executedQuery)
            case .presetDueSoon, .presetHighestCost, .presetTopCategory, .presetCategorySpend, .nextPlannedExpense:
                return contextSuggestions([
                    makeSuggestion("Presets due soon", query: HomeQuery(intent: .presetDueSoon, dateRange: range, resultLimit: 3, periodUnit: period)),
                    makeSuggestion("Most expensive presets", query: HomeQuery(intent: .presetHighestCost, dateRange: range, resultLimit: 3, periodUnit: period)),
                    makeSuggestion("Preset spend by category", query: HomeQuery(intent: .presetCategorySpend, dateRange: range, targetName: target, periodUnit: period))
                ], excluding: executedQuery)
            case .categorySpendTotal, .categorySpendShare, .categorySpendShareTrend, .compareCategoryThisMonthToPreviousMonth, .categoryPotentialSavings, .categoryReallocationGuidance, .topCategoriesThisMonth, .topCategoryChangesThisMonth:
                return contextSuggestions([
                    makeSuggestion(comparisonFollowUpLabel(for: executedQuery), query: HomeQuery(intent: .compareCategoryThisMonthToPreviousMonth, dateRange: range, targetName: target, periodUnit: period)),
                    scopedTopCategories,
                    scopedLargestExpenses
                ], excluding: executedQuery)
            case .merchantSpendTotal, .merchantSpendSummary, .compareMerchantThisMonthToPreviousMonth, .topMerchantsThisMonth:
                return contextSuggestions([
                    scopedLargestExpenses,
                    makeSuggestion(scopedFollowUpLabel(base: "Top merchants", for: executedQuery), query: HomeQuery(intent: .topMerchantsThisMonth, dateRange: range, resultLimit: 3, periodUnit: period)),
                    makeSuggestion(comparisonFollowUpLabel(for: executedQuery), query: HomeQuery(intent: .compareMerchantThisMonthToPreviousMonth, dateRange: range, targetName: target, periodUnit: period))
                ], excluding: executedQuery)
            case .cardSpendTotal, .cardVariableSpendingHabits, .compareCardThisMonthToPreviousMonth, .cardSnapshotSummary, .topCardChangesThisMonth:
                return contextSuggestions([
                    makeSuggestion(comparisonFollowUpLabel(for: executedQuery), query: HomeQuery(intent: .compareCardThisMonthToPreviousMonth, dateRange: range, targetName: target, periodUnit: period)),
                    makeSuggestion(scopedFollowUpLabel(base: "Variable spending habits by card", for: executedQuery), query: HomeQuery(intent: .cardVariableSpendingHabits, dateRange: range, targetName: target, periodUnit: period)),
                    scopedLargestExpenses
                ], excluding: executedQuery)
            case .compareThisMonthToPreviousMonth, .spendThisMonth, .periodOverview, .spendAveragePerPeriod, .spendTrendsSummary, .safeSpendToday:
                return contextSuggestions([
                    scopedTop3Categories,
                    makeSuggestion(comparisonFollowUpLabel(for: executedQuery), query: HomeQuery(intent: .compareThisMonthToPreviousMonth, dateRange: range, periodUnit: period)),
                    makeSuggestion(scopedFollowUpLabel(base: "Average spending", for: executedQuery), query: HomeQuery(intent: .spendAveragePerPeriod, dateRange: range, periodUnit: period))
                ], excluding: executedQuery)
            case .largestRecentTransactions, .mostFrequentTransactions:
                return contextSuggestions([
                    makeSuggestion(scopedFollowUpLabel(base: "Spend total", for: executedQuery), query: HomeQuery(intent: .spendThisMonth, dateRange: range, periodUnit: period)),
                    scopedTopCategories,
                    makeSuggestion(scopedFollowUpLabel(base: "Most frequent expenses", for: executedQuery), query: HomeQuery(intent: .mostFrequentTransactions, dateRange: range, resultLimit: 5, periodUnit: period))
                ], excluding: executedQuery)
            }
        }

        if answer.title.localizedCaseInsensitiveContains("Savings") {
            return [
                makeSuggestion("Compare with last month", query: HomeQuery(intent: .compareThisMonthToPreviousMonth)),
                makeSuggestion("Average savings for last 6 months", query: HomeQuery(intent: .savingsAverageRecentPeriods, resultLimit: 6))
            ]
        }

        if answer.title.localizedCaseInsensitiveContains("Income Share") {
            return [
                makeSuggestion("Income share this month", query: HomeQuery(intent: .incomeSourceShare)),
                makeSuggestion("Average actual income this year", query: HomeQuery(intent: .incomeAverageActual))
            ]
        }

        if answer.title.localizedCaseInsensitiveContains("Category Spend Share") {
            return [
                makeSuggestion("Top categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 5)),
                makeSuggestion("Largest expenses this month", query: HomeQuery(intent: .largestRecentTransactions, resultLimit: 5))
            ]
        }

        if answer.title.localizedCaseInsensitiveContains("Budget Overview") {
            return [
                makeSuggestion("Variable spending habits by card", query: HomeQuery(intent: .cardVariableSpendingHabits)),
                makeSuggestion("Top categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 5))
            ]
        }

        switch answer.kind {
        case .metric:
            return [
                makeSuggestion("Top 3 categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 3)),
                makeSuggestion("Compare with last month", query: HomeQuery(intent: .compareThisMonthToPreviousMonth))
            ]
        case .list:
            return [
                makeSuggestion("Spend this month", query: HomeQuery(intent: .spendThisMonth)),
                makeSuggestion("Largest 5 expenses", query: HomeQuery(intent: .largestRecentTransactions, resultLimit: 5))
            ]
        case .comparison:
            return [
                makeSuggestion("Top 5 categories this month", query: HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 5)),
                makeSuggestion("Largest expenses this month", query: HomeQuery(intent: .largestRecentTransactions))
            ]
        case .message:
            return [
                makeSuggestion("Spend this month", query: HomeQuery(intent: .spendThisMonth)),
                makeSuggestion("Top categories this month", query: HomeQuery(intent: .topCategoriesThisMonth))
            ]
        }
    }

    private func confidenceCue(for answer: HomeAnswer) -> ConfidenceCue {
        let subtitle = answer.subtitle ?? ""
        if subtitle.localizedCaseInsensitiveContains("best-effort") {
            return .low
        }
        if subtitle.localizedCaseInsensitiveContains("likely match") {
            return .medium
        }
        return .high
    }

    private func suggestionKey(_ query: HomeQuery) -> String {
        [
            query.intent.rawValue,
            query.dateRange?.traceSummary ?? "nil",
            query.comparisonDateRange?.traceSummary ?? "nil",
            "\(query.resultLimit)",
            query.targetName ?? "nil",
            query.periodUnit?.rawValue ?? "nil"
        ].joined(separator: "|")
    }

    private func isSameQueryShape(_ lhs: HomeQuery, _ rhs: HomeQuery) -> Bool {
        lhs.intent == rhs.intent
            && lhs.dateRange == rhs.dateRange
            && lhs.comparisonDateRange == rhs.comparisonDateRange
            && lhs.resultLimit == rhs.resultLimit
            && lhs.targetName == rhs.targetName
            && lhs.periodUnit == rhs.periodUnit
    }

    private func comparisonFollowUpLabel(for executedQuery: HomeQuery) -> String {
        switch followUpScope(for: executedQuery) {
        case .week:
            return "Compare with previous week"
        case .month:
            return "Compare with last month"
        case .year:
            return "Compare with last year"
        case .period:
            return "Compare with previous period"
        }
    }

    private func scopedFollowUpLabel(base: String, for executedQuery: HomeQuery) -> String {
        switch followUpScope(for: executedQuery) {
        case .week:
            return "\(base) this week"
        case .month:
            return "\(base) this month"
        case .year:
            return "\(base) this year"
        case .period:
            return "\(base) this period"
        }
    }

    private func followUpScope(for executedQuery: HomeQuery) -> FollowUpScopeUnit {
        if let periodUnit = executedQuery.periodUnit {
            return scope(for: periodUnit)
        }

        guard let dateRange = executedQuery.dateRange else {
            return .month
        }

        if isFullYear(dateRange) {
            return .year
        }

        if isFullMonth(dateRange) {
            return .month
        }

        if isWeeklyRange(dateRange) {
            return .week
        }

        return .period
    }

    private func scope(for unit: HomeQueryPeriodUnit) -> FollowUpScopeUnit {
        switch unit {
        case .week:
            return .week
        case .month:
            return .month
        case .year:
            return .year
        case .day, .quarter:
            return .period
        }
    }

    private func isFullMonth(_ range: HomeQueryDateRange) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
        return calendar.isDate(start, inSameDayAs: monthStart)
            && calendar.isDate(end, inSameDayAs: monthEnd)
    }

    private func isFullYear(_ range: HomeQueryDateRange) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: start)) ?? start
        let yearEnd = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: yearStart) ?? yearStart
        return calendar.isDate(start, inSameDayAs: yearStart)
            && calendar.isDate(end, inSameDayAs: yearEnd)
    }

    private func isWeeklyRange(_ range: HomeQueryDateRange) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let span = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return span == 6
    }
}

private enum FollowUpScopeUnit {
    case week
    case month
    case year
    case period
}

private enum ConfidenceCue {
    case high
    case medium
    case low
}
