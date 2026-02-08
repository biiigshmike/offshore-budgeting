//
//  HomeAssistantClarificationResolver.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

// MARK: - Clarification Models

struct HomeAssistantClarificationDecision: Equatable {
    let reasons: [HomeAssistantClarificationReason]
    let subtitle: String
    let suggestions: [HomeAssistantSuggestion]
    let shouldRunBestEffort: Bool
}

typealias HomeAssistantClarificationPlan = HomeAssistantClarificationDecision

enum HomeAssistantClarificationReason: String, CaseIterable, Hashable {
    case missingDate
    case missingCategoryTarget
    case missingCardTarget
    case missingIncomeSourceTarget
    case broadPrompt
    case lowConfidenceLanguage

    var promptLine: String {
        switch self {
        case .missingDate:
            return "Choose a date window so I can scope the query."
        case .missingCategoryTarget:
            return "Choose a category, or run it across all categories."
        case .missingCardTarget:
            return "Choose a card, or run it across all cards."
        case .missingIncomeSourceTarget:
            return "Choose an income source, or run it across all sources."
        case .broadPrompt:
            return "Your request is broad, so narrowing will improve precision."
        case .lowConfidenceLanguage:
            return "Your phrasing is ambiguous, so I need one clear direction."
        }
    }
}

// MARK: - Resolver

struct HomeAssistantClarificationResolver {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func resolve(
        plan: HomeQueryPlan,
        rawPrompt: String,
        now: Date = Date()
    ) -> HomeAssistantClarificationDecision? {
        guard plan.confidenceBand != .high else { return nil }

        let normalized = normalizedPrompt(rawPrompt)
        let reasons = clarificationReasons(for: plan, normalizedPrompt: normalized)

        if reasons.isEmpty, plan.confidenceBand == .medium {
            return nil
        }

        let subtitle = clarificationSubtitle(for: reasons, confidenceBand: plan.confidenceBand)
        let suggestions = clarificationSuggestions(
            for: plan,
            reasons: reasons,
            normalizedPrompt: normalized,
            now: now
        )

        return HomeAssistantClarificationDecision(
            reasons: reasons,
            subtitle: subtitle,
            suggestions: suggestions,
            shouldRunBestEffort: plan.confidenceBand == .medium
        )
    }

    // MARK: - Reasons

    private func clarificationReasons(
        for plan: HomeQueryPlan,
        normalizedPrompt: String
    ) -> [HomeAssistantClarificationReason] {
        var reasons: [HomeAssistantClarificationReason] = []

        if plan.confidenceBand == .low {
            reasons.append(.lowConfidenceLanguage)
        }

        if plan.dateRange == nil
            && isDateExpected(for: plan.metric)
            && hasExplicitDatePhrase(in: normalizedPrompt) == false
        {
            reasons.append(.missingDate)
        }

        if plan.metric == .overview
            && plan.dateRange == nil
            && isBroadOverviewPrompt(normalizedPrompt)
        {
            reasons.append(.broadPrompt)
        }

        if plan.targetName == nil {
            if requiresCategoryTarget(plan.metric) && normalizedPrompt.contains("all categories") == false {
                reasons.append(.missingCategoryTarget)
            } else if requiresCardTarget(plan.metric) && normalizedPrompt.contains("all cards") == false {
                reasons.append(.missingCardTarget)
            } else if requiresIncomeTarget(plan.metric)
                && normalizedPrompt.contains("all income") == false
                && normalizedPrompt.contains("all sources") == false
            {
                reasons.append(.missingIncomeSourceTarget)
            }
        }

        return uniqueClarificationReasons(reasons)
    }

    // MARK: - Copy

    private func clarificationSubtitle(
        for reasons: [HomeAssistantClarificationReason],
        confidenceBand: HomeQueryConfidenceBand
    ) -> String {
        let reasonLines = reasons.map(\.promptLine).prefix(2)
        let reasonBody = reasonLines.joined(separator: " ")

        switch confidenceBand {
        case .high:
            return "I have enough detail to run this now."
        case .medium:
            if reasonBody.isEmpty {
                return "Likely match complete. If you want it tighter, pick one option below."
            }
            return "Likely match complete. \(reasonBody)"
        case .low:
            if reasonBody.isEmpty {
                return "I need one more detail before I run this. Pick an option below."
            }
            return "I need one more detail before I run this. \(reasonBody)"
        }
    }

    // MARK: - Suggestions

    private func clarificationSuggestions(
        for plan: HomeQueryPlan,
        reasons: [HomeAssistantClarificationReason],
        normalizedPrompt: String,
        now: Date
    ) -> [HomeAssistantSuggestion] {
        var suggestions: [HomeAssistantSuggestion] = []

        if reasons.contains(.missingDate) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Use this month",
                    query: queryFromPlan(plan, overridingDateRange: monthRange(containing: now))
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Use last month",
                    query: queryFromPlan(plan, overridingDateRange: previousMonthRange(from: now))
                )
            )
        }

        if reasons.contains(.missingCategoryTarget) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "All categories",
                    query: queryFromPlan(plan, overridingTargetName: nil)
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Top categories first",
                    query: HomeQuery(
                        intent: .topCategoriesThisMonth,
                        dateRange: plan.dateRange ?? monthRange(containing: now),
                        resultLimit: 3
                    )
                )
            )
        }

        if reasons.contains(.missingCardTarget) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "All cards",
                    query: queryFromPlan(plan, overridingTargetName: nil)
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Card habits (all cards)",
                    query: HomeQuery(
                        intent: .cardVariableSpendingHabits,
                        dateRange: plan.dateRange ?? monthRange(containing: now),
                        resultLimit: 3
                    )
                )
            )
        }

        if reasons.contains(.missingIncomeSourceTarget) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "All income sources",
                    query: queryFromPlan(plan, overridingTargetName: nil)
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Average actual income",
                    query: HomeQuery(intent: .incomeAverageActual, dateRange: yearRange(containing: now))
                )
            )
        }

        if reasons.contains(.broadPrompt) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Compare with last month",
                    query: HomeQuery(intent: .compareThisMonthToPreviousMonth, dateRange: monthRange(containing: now))
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Spend this month",
                    query: HomeQuery(intent: .spendThisMonth, dateRange: monthRange(containing: now))
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Top categories this month",
                    query: HomeQuery(intent: .topCategoriesThisMonth, dateRange: monthRange(containing: now), resultLimit: 3)
                )
            )
        }

        if reasons.contains(.lowConfidenceLanguage) && suggestions.isEmpty {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "How am I doing this month?",
                    query: HomeQuery(intent: .periodOverview, dateRange: monthRange(containing: now))
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Top 3 categories this month",
                    query: HomeQuery(intent: .topCategoriesThisMonth, dateRange: monthRange(containing: now), resultLimit: 3)
                )
            )
        }

        if suggestions.isEmpty {
            suggestions = fallbackClarificationSuggestions(plan: plan, now: now, normalizedPrompt: normalizedPrompt)
        }

        if reasons.contains(.broadPrompt),
           let compareIndex = suggestions.firstIndex(where: { $0.title == "Compare with last month" })
        {
            let compareSuggestion = suggestions.remove(at: compareIndex)
            suggestions.insert(compareSuggestion, at: 0)
        }

        var unique: [HomeAssistantSuggestion] = []
        var seenTitles: Set<String> = []

        for suggestion in suggestions {
            if seenTitles.insert(suggestion.title).inserted {
                unique.append(suggestion)
            }
            if unique.count == 4 {
                break
            }
        }

        return unique
    }

    private func fallbackClarificationSuggestions(
        plan: HomeQueryPlan,
        now: Date,
        normalizedPrompt: String
    ) -> [HomeAssistantSuggestion] {
        let range = plan.dateRange ?? monthRange(containing: now)
        let year = yearRange(containing: now)

        return [
            HomeAssistantSuggestion(
                title: "Use this month",
                query: queryFromPlan(plan, overridingDateRange: range)
            ),
            HomeAssistantSuggestion(
                title: "Use this year",
                query: queryFromPlan(plan, overridingDateRange: year)
            ),
            HomeAssistantSuggestion(
                title: "Spend this month",
                query: HomeQuery(intent: .spendThisMonth, dateRange: range)
            ),
            HomeAssistantSuggestion(
                title: normalizedPrompt.contains("income") ? "Income share this month" : "Top categories this month",
                query: normalizedPrompt.contains("income")
                    ? HomeQuery(intent: .incomeSourceShare, dateRange: range)
                    : HomeQuery(intent: .topCategoriesThisMonth, dateRange: range, resultLimit: 3)
            )
        ]
    }

    // MARK: - Helpers

    private func queryFromPlan(
        _ plan: HomeQueryPlan,
        overridingDateRange: HomeQueryDateRange? = nil,
        overridingTargetName: String? = nil
    ) -> HomeQuery {
        HomeQuery(
            intent: plan.metric.intent,
            dateRange: overridingDateRange ?? plan.dateRange,
            resultLimit: plan.resultLimit,
            targetName: overridingTargetName ?? plan.targetName,
            periodUnit: plan.periodUnit
        )
    }

    private func normalizedPrompt(_ rawPrompt: String) -> String {
        rawPrompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isDateExpected(for metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .presetHighestCost, .presetTopCategory, .presetCategorySpend:
            return false
        case .savingsAverageRecentPeriods, .incomeSourceShareTrend, .categorySpendShareTrend:
            return false
        case .overview, .spendTotal, .topCategories, .monthComparison, .largestTransactions, .cardSpendTotal, .cardVariableSpendingHabits, .incomeAverageActual, .savingsStatus, .incomeSourceShare, .categorySpendShare, .presetDueSoon, .categoryPotentialSavings, .categoryReallocationGuidance:
            return true
        }
    }

    private func hasExplicitDatePhrase(in normalizedPrompt: String) -> Bool {
        if normalizedPrompt.contains("today")
            || normalizedPrompt.contains("yesterday")
            || normalizedPrompt.contains("this month")
            || normalizedPrompt.contains("last month")
            || normalizedPrompt.contains("this year")
            || normalizedPrompt.contains("last year")
            || normalizedPrompt.contains("past ")
            || normalizedPrompt.contains("last ")
            || normalizedPrompt.contains("from ")
            || normalizedPrompt.contains("between ")
        {
            return true
        }

        return normalizedPrompt.range(of: "\\b\\d{4}-\\d{1,2}-\\d{1,2}\\b", options: .regularExpression) != nil
    }

    private func isBroadOverviewPrompt(_ normalizedPrompt: String) -> Bool {
        let broadOverviewPhrases = [
            "how am i doing",
            "how are we doing",
            "how did i do",
            "budget check in",
            "budget checkin",
            "overview",
            "summary",
            "snapshot"
        ]

        return broadOverviewPhrases.contains { normalizedPrompt.contains($0) }
    }

    private func requiresCategoryTarget(_ metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance, .presetCategorySpend:
            return true
        default:
            return false
        }
    }

    private func requiresCardTarget(_ metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .cardSpendTotal, .cardVariableSpendingHabits:
            return true
        default:
            return false
        }
    }

    private func requiresIncomeTarget(_ metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .incomeSourceShare, .incomeSourceShareTrend:
            return true
        default:
            return false
        }
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousMonthRange(from date: Date) -> HomeQueryDateRange {
        let currentMonth = monthRange(containing: date)
        let previousDate = calendar.date(byAdding: .month, value: -1, to: currentMonth.startDate) ?? currentMonth.startDate
        return monthRange(containing: previousDate)
    }

    private func yearRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(year: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func uniqueClarificationReasons(
        _ reasons: [HomeAssistantClarificationReason]
    ) -> [HomeAssistantClarificationReason] {
        var unique: [HomeAssistantClarificationReason] = []
        var seen: Set<HomeAssistantClarificationReason> = []

        for reason in reasons {
            if seen.insert(reason).inserted {
                unique.append(reason)
            }
        }

        return unique
    }
}
