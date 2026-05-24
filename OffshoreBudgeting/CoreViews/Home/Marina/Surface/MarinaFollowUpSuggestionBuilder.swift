//
//  MarinaFollowUpSuggestionBuilder.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 5/21/26.
//

import Foundation

struct MarinaFollowUpSuggestionBuilder {
    func suggestions(
        after answer: HomeAnswer,
        executedQuery: HomeQuery? = nil,
        supportsPromptBackedSuggestions: Bool = false
    ) -> [MarinaSuggestion] {
        switch confidenceCue(for: answer) {
        case .low:
            return limitedUnique([
                query("Spend this month", .spendThisMonth),
                query("Top categories this month", .topCategoriesThisMonth, resultLimit: 3)
            ], excluding: executedQuery, executedPrompt: answer.userPrompt)
        case .medium:
            return limitedUnique([
                query("Top 3 categories this month", .topCategoriesThisMonth, resultLimit: 3),
                query("Compare with last month", .compareThisMonthToPreviousMonth)
            ], excluding: executedQuery, executedPrompt: answer.userPrompt)
        case .high:
            break
        }

        let context = FollowUpContext(answer: answer, executedQuery: executedQuery)
        let suggestions = suggestions(
            for: context,
            supportsPromptBackedSuggestions: supportsPromptBackedSuggestions
        )
        if suggestions.isEmpty == false {
            return limitedUnique(suggestions, excluding: executedQuery, executedPrompt: context.executedPrompt)
        }

        return limitedUnique(fallbackSuggestions(for: answer), excluding: executedQuery, executedPrompt: answer.userPrompt)
    }

    private func suggestions(
        for context: FollowUpContext,
        supportsPromptBackedSuggestions: Bool
    ) -> [MarinaSuggestion] {
        switch context.domain {
        case .budgets:
            return budgetSuggestions(context: context, supportsPromptBackedSuggestions: supportsPromptBackedSuggestions)
        case .income:
            return incomeSuggestions(context: context, supportsPromptBackedSuggestions: supportsPromptBackedSuggestions)
        case .accounts:
            return accountSuggestions(context: context, supportsPromptBackedSuggestions: supportsPromptBackedSuggestions)
        case .expenses:
            return expenseSuggestions(context: context)
        case .trends:
            return trendSuggestions(context: context, supportsPromptBackedSuggestions: supportsPromptBackedSuggestions)
        case .planning:
            return planningSuggestions(context: context, supportsPromptBackedSuggestions: supportsPromptBackedSuggestions)
        }
    }

    private func budgetSuggestions(
        context: FollowUpContext,
        supportsPromptBackedSuggestions: Bool
    ) -> [MarinaSuggestion] {
        var suggestions: [MarinaSuggestion] = [
            query(scopedLabel("Spend", context: context), .spendThisMonth, context: context),
            query("Compare with last month", .compareThisMonthToPreviousMonth, context: context),
            query(scopedLabel("Top categories", context: context), .topCategoriesThisMonth, context: context, resultLimit: 3)
        ]
        if supportsPromptBackedSuggestions {
            suggestions.insert(prompt("What is my active budget?", fallback: .periodOverview), at: 0)
            if let target = context.targetName {
                suggestions.append(prompt("Which cards are linked to \(target)?", fallback: .periodOverview))
            }
        }
        return suggestions
    }

    private func incomeSuggestions(
        context: FollowUpContext,
        supportsPromptBackedSuggestions: Bool
    ) -> [MarinaSuggestion] {
        var suggestions: [MarinaSuggestion] = [
            query(scopedLabel("Income share by source", context: context), .incomeSourceShare, context: context),
            query(scopedLabel("Income share trend", context: context), .incomeSourceShareTrend, context: context, resultLimit: max(4, context.resultLimit)),
            query(scopedLabel("Average actual income", context: context), .incomeAverageActual, context: context)
        ]
        if let target = context.targetName {
            suggestions.append(query("Compare income source with previous period", .compareIncomeSourceThisMonthToPreviousMonth, context: context, targetName: target))
        }
        if supportsPromptBackedSuggestions {
            suggestions.insert(prompt("Compare actual vs planned income this month.", title: "Compare planned vs actual income", fallback: .incomeAverageActual), at: 1)
            suggestions.append(prompt("What upcoming expenses will hit before my next income?", title: "Expenses before next income", fallback: .nextPlannedExpense))
        }
        return suggestions
    }

    private func accountSuggestions(
        context: FollowUpContext,
        supportsPromptBackedSuggestions: Bool
    ) -> [MarinaSuggestion] {
        if context.isReconciliation {
            guard supportsPromptBackedSuggestions else {
                return [
                    query(scopedLabel("Largest expenses", context: context), .largestRecentTransactions, context: context, resultLimit: 5),
                    query(scopedLabel("Spend total", context: context), .spendThisMonth, context: context),
                    query(scopedLabel("Top categories", context: context), .topCategoriesThisMonth, context: context, resultLimit: 3)
                ]
            }
            if let target = context.targetName {
                return [
                    prompt("What is \(target)'s balance?", fallback: .savingsStatus),
                    prompt("Show \(target) allocation rows.", fallback: .largestRecentTransactions),
                    prompt("Show settlement rows.", fallback: .savingsStatus)
                ]
            }
            return [
                prompt("Show reconciliation balances.", fallback: .savingsStatus),
                prompt("Show allocation rows.", fallback: .largestRecentTransactions),
                prompt("Show settlement rows.", fallback: .savingsStatus)
            ]
        }

        if context.isSavings {
            var suggestions: [MarinaSuggestion] = [
                query(scopedLabel("Average savings", context: context), .savingsAverageRecentPeriods, context: context, resultLimit: max(6, context.resultLimit)),
                query(scopedLabel("Forecast savings", context: context), .forecastSavings, context: context),
                query("Compare with last month", .compareThisMonthToPreviousMonth, context: context)
            ]
            if supportsPromptBackedSuggestions {
                suggestions.insert(prompt("Show savings activity.", fallback: .savingsAverageRecentPeriods), at: 0)
            }
            return suggestions
        }

        if context.isCard {
            return [
                query("Compare card with previous period", .compareCardThisMonthToPreviousMonth, context: context, targetName: context.targetName),
                query(scopedLabel("Variable spending habits by card", context: context), .cardVariableSpendingHabits, context: context, targetName: context.targetName),
                query(scopedLabel("Largest expenses", context: context), .largestRecentTransactions, context: context, resultLimit: 5)
            ]
        }

        var suggestions: [MarinaSuggestion] = [
            query(scopedLabel("Variable spending habits by card", context: context), .cardVariableSpendingHabits, context: context),
            query("Savings status", .savingsStatus, context: context),
            query(scopedLabel("Largest expenses", context: context), .largestRecentTransactions, context: context, resultLimit: 5)
        ]
        if supportsPromptBackedSuggestions {
            suggestions.append(prompt("Show savings activity.", fallback: .savingsAverageRecentPeriods))
        }
        return suggestions
    }

    private func expenseSuggestions(context: FollowUpContext) -> [MarinaSuggestion] {
        switch context.intent {
        case .largestRecentTransactions, .mostFrequentTransactions:
            return [
                query(scopedLabel("Spend total", context: context), .spendThisMonth, context: context),
                query(scopedLabel("Top categories", context: context), .topCategoriesThisMonth, context: context, resultLimit: 3),
                query(scopedLabel("Most frequent expenses", context: context), .mostFrequentTransactions, context: context, resultLimit: 5)
            ]
        case .presetDueSoon, .presetHighestCost, .presetTopCategory, .presetCategorySpend, .nextPlannedExpense:
            return [
                query("Presets due soon", .presetDueSoon, context: context, resultLimit: 3),
                query("Most expensive presets", .presetHighestCost, context: context, resultLimit: 3),
                query("Preset spend by category", .presetCategorySpend, context: context, targetName: context.targetName)
            ]
        case .merchantSpendTotal, .merchantSpendSummary, .compareMerchantThisMonthToPreviousMonth, .topMerchantsThisMonth:
            return [
                query(scopedLabel("Largest expenses", context: context), .largestRecentTransactions, context: context, resultLimit: 5),
                query(scopedLabel("Top merchants", context: context), .topMerchantsThisMonth, context: context, resultLimit: 3),
                query("Compare merchant with previous period", .compareMerchantThisMonthToPreviousMonth, context: context, targetName: context.targetName)
            ]
        default:
            return [
                query(scopedLabel("Top categories", context: context), .topCategoriesThisMonth, context: context, resultLimit: 3),
                query(scopedLabel("Largest expenses", context: context), .largestRecentTransactions, context: context, resultLimit: 5),
                query(scopedLabel("Top merchants", context: context), .topMerchantsThisMonth, context: context, resultLimit: 3)
            ]
        }
    }

    private func trendSuggestions(
        context: FollowUpContext,
        supportsPromptBackedSuggestions: Bool
    ) -> [MarinaSuggestion] {
        var suggestions: [MarinaSuggestion] = [
            query("Compare with last month", .compareThisMonthToPreviousMonth, context: context),
            query(scopedLabel("Average spending", context: context), .spendAveragePerPeriod, context: context),
            query(scopedLabel("Category share trend", context: context), .categorySpendShareTrend, context: context, resultLimit: 4)
        ]
        if supportsPromptBackedSuggestions {
            suggestions.insert(prompt("Why is my spending higher this month than last month?", title: "Spending increase drivers", fallback: .compareThisMonthToPreviousMonth), at: 0)
            suggestions.append(prompt("What merchants are unusually high this month?", title: "Unusual merchant spend", fallback: .topMerchantsThisMonth))
        }
        return suggestions
    }

    private func planningSuggestions(
        context: FollowUpContext,
        supportsPromptBackedSuggestions: Bool
    ) -> [MarinaSuggestion] {
        var suggestions: [MarinaSuggestion] = [
            query("Safe spend today", .safeSpendToday, context: context),
            query(scopedLabel("Forecast savings", context: context), .forecastSavings, context: context),
            query("Next planned expense", .nextPlannedExpense, context: context)
        ]
        if supportsPromptBackedSuggestions {
            suggestions.append(prompt("What categories are over pace for this point in the month?", title: "Categories over pace", fallback: .categoryPotentialSavings))
            if let target = context.targetName {
                suggestions.append(prompt("What if I spend 200 less on \(target)?", title: "What if I cut \(target)?", fallback: .forecastSavings))
            }
        }
        return suggestions
    }

    private func fallbackSuggestions(for answer: HomeAnswer) -> [MarinaSuggestion] {
        switch answer.kind {
        case .metric:
            return [
                query("Top 3 categories this month", .topCategoriesThisMonth, resultLimit: 3),
                query("Compare with last month", .compareThisMonthToPreviousMonth)
            ]
        case .list:
            return [
                query("Spend this month", .spendThisMonth),
                query("Largest 5 expenses", .largestRecentTransactions, resultLimit: 5)
            ]
        case .comparison:
            return [
                query("Top 5 categories this month", .topCategoriesThisMonth, resultLimit: 5),
                query("Largest expenses this month", .largestRecentTransactions)
            ]
        case .message:
            return [
                query("Spend this month", .spendThisMonth),
                query("Top categories this month", .topCategoriesThisMonth)
            ]
        }
    }

    private func query(
        _ title: String,
        _ intent: HomeQueryIntent,
        context: FollowUpContext? = nil,
        targetName: String? = nil,
        resultLimit: Int? = nil,
        periodUnit: HomeQueryPeriodUnit? = nil
    ) -> MarinaSuggestion {
        MarinaSuggestion(
            title: title,
            query: HomeQuery(
                intent: intent,
                dateRange: context?.dateRange,
                comparisonDateRange: nil,
                resultLimit: resultLimit,
                targetName: targetName,
                periodUnit: periodUnit ?? context?.periodUnit
            )
        )
    }

    private func prompt(
        _ promptText: String,
        title: String? = nil,
        fallback fallbackIntent: HomeQueryIntent
    ) -> MarinaSuggestion {
        MarinaSuggestion(
            title: title ?? promptText,
            promptText: promptText,
            fallbackQuery: HomeQuery(intent: fallbackIntent)
        )
    }

    private func limitedUnique(
        _ suggestions: [MarinaSuggestion],
        excluding executedQuery: HomeQuery?,
        executedPrompt: String?
    ) -> [MarinaSuggestion] {
        var unique: [MarinaSuggestion] = []
        var seen: Set<String> = []
        let executedPromptKey = executedPrompt.map(normalized).flatMap { $0.isEmpty ? nil : $0 }
        for suggestion in suggestions {
            if let executedQuery, suggestion.isPromptBacked == false, isSameQueryShape(suggestion.query, executedQuery) {
                continue
            }
            if let executedPromptKey, suggestionActionKeys(suggestion).contains(executedPromptKey) {
                continue
            }
            let key = suggestionKey(suggestion)
            guard seen.insert(key).inserted else { continue }
            unique.append(suggestion)
            if unique.count == 3 { break }
        }
        return unique
    }

    private func suggestionActionKeys(_ suggestion: MarinaSuggestion) -> Set<String> {
        let actionTexts: [String?] = [suggestion.promptText, suggestion.title]
        return Set(actionTexts.compactMap { value in
            guard let value else { return nil }
            let key = normalized(value)
            return key.isEmpty ? nil : key
        })
    }

    private func suggestionKey(_ suggestion: MarinaSuggestion) -> String {
        if let promptText = suggestion.promptText {
            return "prompt|\(normalized(promptText))"
        }
        return "query|\(suggestionKey(suggestion.query))"
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

    private func scopedLabel(_ base: String, context: FollowUpContext) -> String {
        switch context.scope {
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

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct FollowUpContext {
    let answer: HomeAnswer
    let executedQuery: HomeQuery?
    let domain: FollowUpDomain
    let scope: FollowUpScopeUnit
    let targetName: String?
    let dateRange: HomeQueryDateRange?
    let periodUnit: HomeQueryPeriodUnit?
    let executedPrompt: String?
    let resultLimit: Int
    let intent: HomeQueryIntent?
    let isCard: Bool
    let isSavings: Bool
    let isReconciliation: Bool

    init(answer: HomeAnswer, executedQuery: HomeQuery?) {
        self.answer = answer
        self.executedQuery = executedQuery
        self.intent = executedQuery?.intent
        self.targetName = executedQuery?.targetName
        self.dateRange = executedQuery?.dateRange
        self.periodUnit = executedQuery?.periodUnit
        self.executedPrompt = answer.userPrompt
        self.resultLimit = executedQuery?.resultLimit ?? 3
        self.scope = executedQuery.map(Self.scope) ?? .month

        let normalizedTitle = Self.normalized(answer.title)
        let isCard = executedQuery?.intent.isCardIntent == true || normalizedTitle.contains("card")
        let isSavings = executedQuery?.intent.isSavingsIntent == true || normalizedTitle.contains("saving")
        let isReconciliation = normalizedTitle.contains("reconciliation")
            || normalizedTitle.contains("allocation")
            || normalizedTitle.contains("settlement")
            || normalizedTitle.contains("shared balance")
            || normalizedTitle.contains("owed")
        self.isCard = isCard
        self.isSavings = isSavings
        self.isReconciliation = isReconciliation

        if isReconciliation || isSavings || isCard {
            self.domain = .accounts
        } else if executedQuery?.intent.isIncomeIntent == true || normalizedTitle.contains("income") {
            self.domain = .income
        } else if executedQuery?.intent.isPlanningIntent == true || normalizedTitle.contains("forecast") || normalizedTitle.contains("safe spend") {
            self.domain = .planning
        } else if executedQuery?.intent.isTrendIntent == true || normalizedTitle.contains("trend") || normalizedTitle.contains("comparison") || normalizedTitle.contains("changes") {
            self.domain = .trends
        } else if executedQuery?.intent == .periodOverview || normalizedTitle.contains("budget overview") || normalizedTitle.contains("active budget") {
            self.domain = .budgets
        } else {
            self.domain = .expenses
        }
    }

    private nonisolated static func scope(for query: HomeQuery) -> FollowUpScopeUnit {
        if let periodUnit = query.periodUnit {
            switch periodUnit {
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

        guard let dateRange = query.dateRange else {
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

    private nonisolated static func isFullMonth(_ range: HomeQueryDateRange) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
        return calendar.isDate(start, inSameDayAs: monthStart)
            && calendar.isDate(end, inSameDayAs: monthEnd)
    }

    private nonisolated static func isFullYear(_ range: HomeQueryDateRange) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: start)) ?? start
        let yearEnd = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: yearStart) ?? yearStart
        return calendar.isDate(start, inSameDayAs: yearStart)
            && calendar.isDate(end, inSameDayAs: yearEnd)
    }

    private nonisolated static func isWeeklyRange(_ range: HomeQueryDateRange) -> Bool {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let span = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return span == 6
    }

    private nonisolated static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum FollowUpDomain {
    case budgets
    case income
    case accounts
    case expenses
    case trends
    case planning
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

private extension HomeQueryIntent {
    var isIncomeIntent: Bool {
        switch self {
        case .incomeAverageActual, .incomeSourceShare, .incomeSourceShareTrend, .compareIncomeSourceThisMonthToPreviousMonth:
            return true
        default:
            return false
        }
    }

    var isCardIntent: Bool {
        switch self {
        case .cardSpendTotal, .cardVariableSpendingHabits, .compareCardThisMonthToPreviousMonth, .cardSnapshotSummary, .topCardChangesThisMonth:
            return true
        default:
            return false
        }
    }

    var isSavingsIntent: Bool {
        switch self {
        case .savingsStatus, .savingsAverageRecentPeriods:
            return true
        default:
            return false
        }
    }

    var isPlanningIntent: Bool {
        switch self {
        case .safeSpendToday, .forecastSavings, .nextPlannedExpense, .categoryPotentialSavings, .categoryReallocationGuidance:
            return true
        default:
            return false
        }
    }

    var isTrendIntent: Bool {
        switch self {
        case .compareThisMonthToPreviousMonth, .compareCategoryThisMonthToPreviousMonth, .compareCardThisMonthToPreviousMonth, .compareIncomeSourceThisMonthToPreviousMonth, .compareMerchantThisMonthToPreviousMonth, .spendAveragePerPeriod, .spendTrendsSummary, .incomeSourceShareTrend, .categorySpendShareTrend, .topCategoryChangesThisMonth, .topCardChangesThisMonth:
            return true
        default:
            return false
        }
    }
}
