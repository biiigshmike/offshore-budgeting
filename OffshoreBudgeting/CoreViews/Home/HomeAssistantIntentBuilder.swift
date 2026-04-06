//
//  HomeAssistantIntentBuilder.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 3/30/26.
//

import Foundation

enum HomeAssistantSignalTargetSource {
    case matchedEntity
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

        let injectedTargetName: String?
        if let signalTarget = sanitized(signals.targetName), targetName == nil {
            targetName = signalTarget
            injectedTargetName = signalTarget
        } else {
            injectedTargetName = nil
        }

        let injectedDateRange: HomeQueryDateRange?
        if dateRange == nil, let signalDateRange = signals.dateRange {
            dateRange = signalDateRange
            injectedDateRange = signalDateRange
        } else {
            injectedDateRange = nil
        }

        let injectedComparisonDateRange: HomeQueryDateRange?
        if comparisonDateRange == nil, let signalComparisonDateRange = signals.comparisonDateRange {
            comparisonDateRange = signalComparisonDateRange
            injectedComparisonDateRange = signalComparisonDateRange
        } else {
            injectedComparisonDateRange = nil
        }

        let resolvedTarget = sanitized(targetName)
        let fallbackTarget = sanitized(fallbackPlan.targetName)
        let signalTarget = sanitized(signals.targetName)
        let targetClassification = resolvedTarget.flatMap(resolvedScopedComparisonTarget(for:))
        let explicitComparisonRequested = expectsExplicitComparisonDates(in: signals.rawPrompt)
        let explicitComparisonResolved = explicitComparisonRequested && dateRange != nil && comparisonDateRange != nil
        let matchedEntityTarget = signals.targetSource == .matchedEntity
        let unresolvedComparisonTarget = signals.comparisonDetected
            && signalTarget != nil
            && signals.targetSource == .inferredComparisonText
            && targetClassification == nil

        if explicitComparisonResolved && matchedEntityTarget == false {
            metric = .monthComparison
            targetName = nil
        } else if unresolvedComparisonTarget {
            metric = .categoryMonthComparison
            targetName = nil
        } else if signals.comparisonDetected {
            if let targetClassification {
                metric = scopedComparisonMetric(for: targetClassification)
            } else {
                metric = .monthComparison
            }
        } else if let signalMetric = signals.metric, shouldOverrideMetric(current: metric, with: signalMetric) {
            metric = signalMetric
        }

        let conflictDetected = hasConflict(
            fallbackTarget: fallbackTarget,
            signalTarget: signalTarget,
            comparisonDetected: signals.comparisonDetected,
            targetClassification: targetClassification,
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
            injectedTarget: injectedTargetName != nil,
            injectedDateRange: injectedDateRange != nil,
            injectedComparisonDateRange: injectedComparisonDateRange != nil
        )

        return HomeQueryPlan(
            metric: metric,
            dateRange: dateRange,
            comparisonDateRange: comparisonDateRange,
            resultLimit: fallbackPlan.resultLimit,
            confidenceBand: confidenceBand,
            targetName: targetName,
            periodUnit: fallbackPlan.periodUnit
        )
    }

    private func shouldOverrideMetric(
        current _: HomeQueryMetric,
        with _: HomeQueryMetric
    ) -> Bool {
        true
    }

    private func hasConflict(
        fallbackTarget: String?,
        signalTarget: String?,
        comparisonDetected: Bool,
        targetClassification: ScopedComparisonTarget?,
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
        injectedTarget: Bool,
        injectedDateRange: Bool,
        injectedComparisonDateRange: Bool
    ) -> HomeQueryConfidenceBand {
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

        return nil
    }

    private func scopedComparisonMetric(for target: ScopedComparisonTarget) -> HomeQueryMetric {
        switch target {
        case .category:
            return .categoryMonthComparison
        case .card:
            return .cardMonthComparison
        case .incomeSource:
            return .incomeSourceMonthComparison
        }
    }

    private func sanitized(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), text.isEmpty == false else {
            return nil
        }
        return text
    }

    private func normalizedPrompt(_ rawPrompt: String) -> String {
        rawPrompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
