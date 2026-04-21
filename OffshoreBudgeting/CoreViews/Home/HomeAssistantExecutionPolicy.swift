//
//  HomeAssistantExecutionPolicy.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/21/26.
//

import Foundation

enum HomeAssistantMetricTargetRequirement: Equatable {
    case none
    case category
    case card
    case incomeSource
    case merchant
}

struct HomeAssistantMetricExecutionPolicy: Equatable {
    let requiresTarget: Bool
    let targetRequirement: HomeAssistantMetricTargetRequirement
    let supportsBroadExecution: Bool
    let requiresDateScope: Bool
    let isComparisonFamily: Bool
}

extension HomeQueryMetric {
    var executionPolicy: HomeAssistantMetricExecutionPolicy {
        let targetRequirement: HomeAssistantMetricTargetRequirement = switch self {
        case .categorySpendTotal, .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance, .presetCategorySpend, .categoryMonthComparison:
            .category
        case .cardSpendTotal, .cardVariableSpendingHabits, .cardMonthComparison:
            .card
        case .incomeSourceShare, .incomeSourceShareTrend, .incomeSourceMonthComparison:
            .incomeSource
        case .merchantSpendTotal, .merchantSpendSummary, .merchantMonthComparison:
            .merchant
        default:
            .none
        }

        let supportsBroadExecution: Bool = switch self {
        case .topMerchants, .topCategories, .largestTransactions, .mostFrequentTransactions, .spendTotal:
            true
        default:
            false
        }

        let requiresDateScope: Bool = switch self {
        case .presetHighestCost, .presetTopCategory, .presetCategorySpend, .savingsAverageRecentPeriods, .incomeSourceShareTrend, .categorySpendShareTrend:
            false
        default:
            true
        }

        let isComparisonFamily: Bool = switch self {
        case .monthComparison, .categoryMonthComparison, .cardMonthComparison, .incomeSourceMonthComparison, .merchantMonthComparison:
            true
        default:
            false
        }

        return HomeAssistantMetricExecutionPolicy(
            requiresTarget: targetRequirement != .none,
            targetRequirement: targetRequirement,
            supportsBroadExecution: supportsBroadExecution,
            requiresDateScope: requiresDateScope,
            isComparisonFamily: isComparisonFamily
        )
    }
}

enum HomeAssistantExecutionRequirement: Equatable {
    case target
    case dateScope
    case comparisonDateScope
}

struct HomeAssistantExecutionEligibility: Equatable {
    let planWithDateFallback: HomeQueryPlan
    let unresolvedRequirements: [HomeAssistantExecutionRequirement]
    let comparisonSecondScopeRequired: Bool
}

enum HomeAssistantExecutionEligibilityEvaluator {
    static func evaluate(
        plan: HomeQueryPlan,
        normalizedPrompt: String,
        activeBudgetDateRange: HomeQueryDateRange?,
        now: Date
    ) -> HomeAssistantExecutionEligibility {
        let policy = plan.metric.executionPolicy
        let resolvedDateRange = resolvedDateScope(
            for: plan,
            policy: policy,
            activeBudgetDateRange: activeBudgetDateRange,
            now: now
        )
        let planWithDateFallback = plan.updating(dateRange: .some(resolvedDateRange))

        let comparisonSecondScopeRequired = policy.isComparisonFamily
            && appearsToRequestExplicitComparisonDates(in: normalizedPrompt)

        var unresolved: [HomeAssistantExecutionRequirement] = []

        if policy.requiresTarget && (plan.targetName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false) {
            unresolved.append(.target)
        }

        if policy.requiresDateScope && resolvedDateRange == nil {
            unresolved.append(.dateScope)
        }

        if comparisonSecondScopeRequired {
            if plan.comparisonDateRange == nil || plan.comparisonDateRange == resolvedDateRange {
                unresolved.append(.comparisonDateScope)
            }
        }

        return HomeAssistantExecutionEligibility(
            planWithDateFallback: planWithDateFallback,
            unresolvedRequirements: unresolved,
            comparisonSecondScopeRequired: comparisonSecondScopeRequired
        )
    }

    private static func resolvedDateScope(
        for plan: HomeQueryPlan,
        policy: HomeAssistantMetricExecutionPolicy,
        activeBudgetDateRange: HomeQueryDateRange?,
        now: Date
    ) -> HomeQueryDateRange? {
        if policy.requiresDateScope == false {
            return plan.dateRange
        }

        if let explicit = plan.dateRange {
            return explicit
        }

        if let activeBudgetDateRange {
            return activeBudgetDateRange
        }

        return monthRange(containing: now)
    }

    private static func monthRange(containing date: Date) -> HomeQueryDateRange {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private static func appearsToRequestExplicitComparisonDates(in normalizedPrompt: String) -> Bool {
        let explicitDateTokenPattern = "\\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december|q[1-4]|\\d{4}-\\d{1,2}-\\d{1,2}|\\d{4})\\b"
        let explicitDateTokenCount = regexMatchCount(
            pattern: explicitDateTokenPattern,
            in: normalizedPrompt
        )
        let hasComparisonVerb = normalizedPrompt.contains("compare")
        let hasComparisonBridge = normalizedPrompt.range(
            of: "\\b(from .+ to|between .+ and|vs|versus)\\b",
            options: .regularExpression
        ) != nil
        let hasToBridge = hasComparisonVerb
            && normalizedPrompt.contains(" to ")
            && explicitDateTokenCount >= 2
        return explicitDateTokenCount > 0 && (hasComparisonBridge || hasToBridge)
    }

    private static func regexMatchCount(
        pattern: String,
        in text: String
    ) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return 0
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }
}
