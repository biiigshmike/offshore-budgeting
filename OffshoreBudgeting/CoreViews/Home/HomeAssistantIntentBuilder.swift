//
//  HomeAssistantIntentBuilder.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 3/30/26.
//

import Foundation

enum HomeAssistantSignalTargetSource {
    case matchedEntity
    case merchantPhrase
    case weakMerchantPhrase
    case inferredComparisonText
}

struct HomeAssistantParsedSignals {
    let metric: HomeQueryMetric?
    let targetName: String?
    let targetSource: HomeAssistantSignalTargetSource?
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let comparisonDetected: Bool
    let rawPrompt: String
}

struct HomeAssistantIntentBuilder {
    private enum ScopedComparisonTarget {
        case category
        case card
        case incomeSource
        case merchant
    }

    private let categoryNames: [String]
    private let cardNames: [String]
    private let incomeSourceNames: [String]

    init(
        categoryNames: [String] = [],
        cardNames: [String] = [],
        incomeSourceNames: [String] = []
    ) {
        self.categoryNames = categoryNames
        self.cardNames = cardNames
        self.incomeSourceNames = incomeSourceNames
    }

    func buildPlan(
        from signals: HomeAssistantParsedSignals,
        fallbackPlan: HomeQueryPlan
    ) -> HomeQueryPlan {
        var metric = fallbackPlan.metric
        var targetName = fallbackPlan.targetName
        var dateRange = fallbackPlan.dateRange
        var comparisonDateRange = fallbackPlan.comparisonDateRange
        var confidenceBand = fallbackPlan.confidenceBand
        let promptHasExplicitDate = containsExplicitDateLanguage(in: signals.rawPrompt)
        MarinaDebugLogger.log(
            "[MarinaIntentBuilder] rawPrompt='\(signals.rawPrompt)' fallbackDate=\(String(describing: fallbackPlan.dateRange)) fallbackComparison=\(String(describing: fallbackPlan.comparisonDateRange)) signalDate=\(String(describing: signals.dateRange)) signalComparison=\(String(describing: signals.comparisonDateRange)) explicitDate=\(promptHasExplicitDate)"
        )

        let injectedTargetName: String?
        if let signalTarget = sanitizedTargetOrNil(signals.targetName), targetName == nil {
            targetName = signalTarget
            injectedTargetName = signalTarget
        } else {
            injectedTargetName = nil
        }

        let injectedDateRange: HomeQueryDateRange?
        if let signalDateRange = signals.dateRange,
           dateRange == nil || promptHasExplicitDate {
            dateRange = signalDateRange
            injectedDateRange = signalDateRange
        } else {
            injectedDateRange = nil
        }

        let injectedComparisonDateRange: HomeQueryDateRange?
        if let signalComparisonDateRange = signals.comparisonDateRange,
           comparisonDateRange == nil || promptHasExplicitDate {
            comparisonDateRange = signalComparisonDateRange
            injectedComparisonDateRange = signalComparisonDateRange
        } else {
            injectedComparisonDateRange = nil
        }

        targetName = sanitizedTargetOrNil(targetName)

        let resolvedTarget = sanitizedTargetOrNil(targetName)
        let fallbackTarget = sanitizedTargetOrNil(fallbackPlan.targetName)
        let signalTarget = sanitizedTargetOrNil(signals.targetName)
        let targetClassification = resolvedTarget.flatMap(resolvedScopedComparisonTarget(for:))
        let explicitComparisonRequested = expectsExplicitComparisonDates(in: signals.rawPrompt)
        let explicitComparisonResolved = explicitComparisonRequested && dateRange != nil && comparisonDateRange != nil
        let matchedEntityTarget = signals.targetSource == .matchedEntity
        let weakMerchantTarget = signals.targetSource == .weakMerchantPhrase
        if weakMerchantTarget && signals.comparisonDetected {
            metric = .merchantMonthComparison
            targetName = nil
        } else if explicitComparisonResolved
            && (signals.targetSource == .inferredComparisonText || (matchedEntityTarget == false && targetClassification != .merchant))
        {
            metric = .monthComparison
            targetName = nil
        } else if signals.comparisonDetected {
            if let targetClassification {
                metric = scopedComparisonMetric(for: targetClassification)
            } else if let signalTarget, signals.targetSource == .inferredComparisonText || signals.targetSource == .merchantPhrase {
                metric = .merchantMonthComparison
                targetName = signalTarget
            } else {
                metric = .monthComparison
            }
        } else if let signalMetric = signals.metric,
                  shouldOverrideMetric(
                    current: metric,
                    currentTarget: targetName,
                    currentDateRange: dateRange,
                    with: signalMetric,
                    signalTarget: signalTarget
                  ) {
            metric = signalMetric
            if targetName == nil {
                targetName = signalTarget
            }
        }

        let conflictDetected = hasConflict(
            fallbackTarget: fallbackTarget,
            signalTarget: signalTarget,
            comparisonDetected: signals.comparisonDetected,
            targetClassification: targetClassification,
            weakMerchantTarget: weakMerchantTarget,
            explicitComparisonRequested: explicitComparisonRequested,
            comparisonDateRange: comparisonDateRange
        )

        confidenceBand = adjustedConfidenceBand(
            fallback: fallbackPlan.confidenceBand,
            conflictDetected: conflictDetected,
            comparisonDetected: signals.comparisonDetected,
            explicitComparisonRequested: explicitComparisonRequested,
            explicitComparisonResolved: explicitComparisonResolved,
            scopedComparisonResolved: signals.comparisonDetected && targetClassification != nil,
            weakMerchantTarget: weakMerchantTarget,
            injectedTarget: injectedTargetName != nil,
            injectedDateRange: injectedDateRange != nil,
            injectedComparisonDateRange: injectedComparisonDateRange != nil
        )

        let resolvedPlan = HomeQueryPlan(
            metric: metric,
            dateRange: dateRange,
            comparisonDateRange: comparisonDateRange,
            resultLimit: fallbackPlan.resultLimit,
            confidenceBand: confidenceBand,
            targetName: targetName,
            periodUnit: fallbackPlan.periodUnit
        )
        MarinaDebugLogger.log(
            "[MarinaIntentBuilder] resolved metric=\(resolvedPlan.metric.rawValue) date=\(String(describing: resolvedPlan.dateRange)) comparison=\(String(describing: resolvedPlan.comparisonDateRange)) target=\(resolvedPlan.targetName ?? "nil") confidence=\(resolvedPlan.confidenceBand.rawValue)"
        )
        return resolvedPlan
    }

    private func shouldOverrideMetric(
        current: HomeQueryMetric,
        currentTarget: String?,
        currentDateRange: HomeQueryDateRange?,
        with candidate: HomeQueryMetric,
        signalTarget: String?
    ) -> Bool {
        guard current != candidate else { return false }

        if protectsTargetlessRankingFallback(
            current: current,
            currentTarget: currentTarget,
            currentDateRange: currentDateRange,
            candidate: candidate,
            signalTarget: signalTarget
        ) {
            MarinaDebugLogger.log(
                "[MarinaIntentBuilder] kept fallback ranking metric=\(current.rawValue) over aggregate candidate=\(candidate.rawValue)"
            )
            return false
        }

        let candidateStrength = metricSpecificityScore(metric: candidate, hasScopedTarget: signalTarget != nil)
        let currentStrength = metricSpecificityScore(metric: current, hasScopedTarget: false)

        guard candidateStrength > currentStrength else {
            MarinaDebugLogger.log(
                "[MarinaIntentBuilder] kept fallback metric=\(current.rawValue) candidate=\(candidate.rawValue) (candidateStrength=\(candidateStrength), currentStrength=\(currentStrength))"
            )
            return false
        }

        if metricsConflict(current: current, candidate: candidate) {
            MarinaDebugLogger.log(
                "[MarinaIntentBuilder] kept fallback metric due to conflict current=\(current.rawValue) candidate=\(candidate.rawValue)"
            )
            return false
        }

        return true
    }

    private func protectsTargetlessRankingFallback(
        current: HomeQueryMetric,
        currentTarget: String?,
        currentDateRange: HomeQueryDateRange?,
        candidate: HomeQueryMetric,
        signalTarget: String?
    ) -> Bool {
        let protectedRankingMetrics: Set<HomeQueryMetric> = [
            .topCategories,
            .topMerchants,
            .largestTransactions
        ]
        let aggregateMetrics: Set<HomeQueryMetric> = [
            .merchantSpendTotal,
            .categorySpendTotal,
            .cardSpendTotal
        ]

        guard protectedRankingMetrics.contains(current),
              aggregateMetrics.contains(candidate),
              currentTarget == nil,
              currentDateRange != nil,
              signalTarget == nil else {
            return false
        }

        return true
    }

    private func hasConflict(
        fallbackTarget: String?,
        signalTarget: String?,
        comparisonDetected: Bool,
        targetClassification: ScopedComparisonTarget?,
        weakMerchantTarget: Bool,
        explicitComparisonRequested: Bool,
        comparisonDateRange: HomeQueryDateRange?
    ) -> Bool {
        if let fallbackTarget, let signalTarget,
           fallbackTarget.caseInsensitiveCompare(signalTarget) != .orderedSame {
            return true
        }

        if explicitComparisonRequested, comparisonDateRange == nil {
            return true
        }

        if weakMerchantTarget {
            return true
        }

        if explicitComparisonRequested && signalTarget != nil && targetClassification == nil {
            return false
        }

        if comparisonDetected, signalTarget != nil, targetClassification == nil {
            return true
        }

        return false
    }

    private func adjustedConfidenceBand(
        fallback: HomeQueryConfidenceBand,
        conflictDetected: Bool,
        comparisonDetected: Bool,
        explicitComparisonRequested: Bool,
        explicitComparisonResolved: Bool,
        scopedComparisonResolved: Bool,
        weakMerchantTarget: Bool,
        injectedTarget: Bool,
        injectedDateRange: Bool,
        injectedComparisonDateRange: Bool
    ) -> HomeQueryConfidenceBand {
        if weakMerchantTarget {
            return .medium
        }

        if explicitComparisonResolved {
            return .high
        }

        if scopedComparisonResolved {
            return .high
        }

        if conflictDetected {
            return .medium
        }

        if comparisonDetected {
            return .high
        }

        if explicitComparisonRequested && injectedComparisonDateRange {
            return .high
        }

        if injectedTarget && injectedDateRange {
            return .high
        }

        if injectedTarget || injectedDateRange {
            return fallback
        }

        return fallback
    }

    private func expectsExplicitComparisonDates(in rawPrompt: String) -> Bool {
        let normalized = normalizedPrompt(rawPrompt)
        let explicitDateTokenPattern = "\\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december|q[1-4]|\\d{4}-\\d{1,2}-\\d{1,2}|\\d{4})\\b"
        let hasExplicitDateToken = normalized.range(
            of: explicitDateTokenPattern,
            options: .regularExpression
        ) != nil
        let explicitDateTokenCount = regexMatchCount(
            pattern: explicitDateTokenPattern,
            in: normalized
        )
        let hasComparisonVerb = normalized.contains("compare")
        let hasComparisonBridge = normalized.range(
            of: "\\b(from .+ to|between .+ and|vs|versus)\\b",
            options: .regularExpression
        ) != nil
        let hasToBridge = hasComparisonVerb
            && normalized.contains(" to ")
            && explicitDateTokenCount >= 2
        return hasExplicitDateToken && (hasComparisonBridge || hasToBridge)
    }

    private func containsExplicitDateLanguage(in rawPrompt: String) -> Bool {
        let normalized = normalizedPrompt(rawPrompt)
        let phrases = [
            "today", "yesterday", "this week", "current week", "last week", "previous week",
            "this month", "current month", "month to date", "last month", "previous month",
            "this year", "current year", "year to date", "last year", "previous year",
            "from ", "between "
        ]
        if phrases.contains(where: normalized.contains) {
            return true
        }

        let explicitDateTokenPattern = "\\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december|q[1-4]|\\d{4}-\\d{1,2}-\\d{1,2}|\\d{4})\\b"
        return normalized.range(of: explicitDateTokenPattern, options: .regularExpression) != nil
    }

    private func regexMatchCount(
        pattern: String,
        in text: String
    ) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return 0
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    private func resolvedScopedComparisonTarget(for targetName: String) -> ScopedComparisonTarget? {
        let normalizedTarget = normalizedPrompt(targetName)

        if categoryNames.contains(where: { normalizedPrompt($0) == normalizedTarget }) {
            return .category
        }

        if cardNames.contains(where: { normalizedPrompt($0) == normalizedTarget }) {
            return .card
        }

        if incomeSourceNames.contains(where: { normalizedPrompt($0) == normalizedTarget }) {
            return .incomeSource
        }

        return .merchant
    }

    private func scopedComparisonMetric(for target: ScopedComparisonTarget) -> HomeQueryMetric {
        switch target {
        case .category:
            return .categoryMonthComparison
        case .card:
            return .cardMonthComparison
        case .incomeSource:
            return .incomeSourceMonthComparison
        case .merchant:
            return .merchantMonthComparison
        }
    }

    private func sanitizedTargetOrNil(_ text: String?) -> String? {
        guard var value = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }

        value = stripExplicitTemporalFragments(from: value)
        value = value.replacingOccurrences(
            of: "\\s+(?:in|from)\\s+(?:jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december|\\d{4}|this\\s+(?:month|period|week|year)|last\\s+(?:month|period|week|year)|previous\\s+(?:month|period|week|year)).*$",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        guard value.isEmpty == false else { return nil }
        let normalized = normalizedPrompt(value)
        guard normalized.isEmpty == false else { return nil }

        let blockedPhrases: Set<String> = [
            "what is my current",
            "how much did i spend",
            "show me",
            "tell me",
            "in march",
            "last",
            "last period",
            "this month",
            "this period"
        ]
        if blockedPhrases.contains(normalized) {
            return nil
        }

        let tokens = normalized.split(separator: " ").map(String.init)
        guard tokens.isEmpty == false else { return nil }

        let fillerTokens: Set<String> = [
            "what", "is", "my", "how", "much", "did", "i", "show", "me", "tell", "current",
            "in", "on", "for", "from", "to", "between", "and", "compare", "compared", "vs", "versus",
            "this", "last", "period", "month", "week", "year", "spend", "spending", "expense", "expenses"
        ]

        let hasMeaningfulToken = tokens.contains { token in
            fillerTokens.contains(token) == false && isDateLikeToken(token) == false
        }
        guard hasMeaningfulToken else { return nil }

        return value
    }

    private func stripExplicitTemporalFragments(from text: String) -> String {
        let fragments = [
            "\\bof\\s+all\\s+time\\b",
            "\\ball\\s*[- ]time\\b",
            "\\bever\\b"
        ]

        var output = text
        for fragment in fragments {
            output = output.replacingOccurrences(
                of: fragment,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
        }

        return output
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isDateLikeToken(_ token: String) -> Bool {
        let dateTokens: Set<String> = [
            "jan", "january", "feb", "february", "mar", "march", "apr", "april", "may", "jun",
            "june", "jul", "july", "aug", "august", "sep", "sept", "september", "oct", "october",
            "nov", "november", "dec", "december", "today", "yesterday", "current", "previous"
        ]
        if dateTokens.contains(token) {
            return true
        }
        return token.range(of: "^\\d{4}$", options: .regularExpression) != nil
    }

    private func metricSpecificityScore(
        metric: HomeQueryMetric,
        hasScopedTarget: Bool
    ) -> Int {
        switch metric {
        case .spendTotal, .monthComparison:
            return 1
        case .merchantSpendTotal, .merchantMonthComparison,
            .categorySpendTotal, .categoryMonthComparison,
            .cardSpendTotal, .cardMonthComparison,
            .incomeSourceMonthComparison:
            return hasScopedTarget ? 3 : 1
        default:
            return 2
        }
    }

    private func metricsConflict(
        current: HomeQueryMetric,
        candidate: HomeQueryMetric
    ) -> Bool {
        let comparisonMetrics: Set<HomeQueryMetric> = [
            .monthComparison, .categoryMonthComparison, .cardMonthComparison,
            .incomeSourceMonthComparison, .merchantMonthComparison
        ]
        let spendMetrics: Set<HomeQueryMetric> = [
            .spendTotal, .categorySpendTotal, .cardSpendTotal, .merchantSpendTotal
        ]

        if comparisonMetrics.contains(current) && spendMetrics.contains(candidate) {
            return true
        }

        if spendMetrics.contains(current) && comparisonMetrics.contains(candidate) {
            return false
        }

        return false
    }

    private func normalizedPrompt(_ rawPrompt: String) -> String {
        rawPrompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
