//
//  HomeAssistantResolutionPipeline.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/16/26.
//

import Foundation

struct HomeAssistantEntityResolutionInput {
    let prompt: String
    let targetPhrase: String
    let categories: [String]
    let cards: [String]
    let merchants: [String]
    let presets: [String]
    let budgets: [String]
    let incomeSources: [String]
    let aliasRules: [AssistantAliasRule]
    let rejectedCandidateNames: [String]
}

struct HomeAssistantEntityResolver {
    private let aliasMatcher = HomeAssistantAliasMatcher()
    static let highConfidenceMarginThreshold = 0.18
    private let highConfidenceMargin = Self.highConfidenceMarginThreshold

    func resolve(input: HomeAssistantEntityResolutionInput) -> HomeAssistantEntityResolution {
        let phrase = normalizedPhrase(from: input)
        guard phrase.isEmpty == false else {
            return HomeAssistantEntityResolution(resolvedPhrase: "")
        }

        let candidates = allCandidates(from: input)
            .filter { input.rejectedCandidateNames.contains($0.name) == false }
        let ranked = rank(phrase: phrase, candidates: candidates, aliasRules: input.aliasRules)
        guard ranked.isEmpty == false else {
            return HomeAssistantEntityResolution(
                resolvedPhrase: phrase,
                confidence: .low,
                originalCandidates: [],
                rejectedCandidateNames: input.rejectedCandidateNames
            )
        }

        let originalCandidates = ranked
        let top = ranked[0]
        let second = ranked.dropFirst().first
        let margin = top.score - (second?.score ?? 0)
        let sameBandTie = second.map { $0.confidence == top.confidence && margin < highConfidenceMargin } ?? false

        if top.confidence == .exact {
            if sameBandTie {
                return HomeAssistantEntityResolution(
                    resolvedPhrase: phrase,
                    ambiguityCandidates: Array(ranked.prefix(4)),
                    rankedCandidates: ranked,
                    confidence: .medium,
                    originalCandidates: originalCandidates,
                    rejectedCandidateNames: input.rejectedCandidateNames,
                    isTieAmbiguity: true
                )
            }

            return HomeAssistantEntityResolution(
                resolvedPhrase: phrase,
                bestMatch: top,
                rankedCandidates: ranked,
                confidence: .exact,
                originalCandidates: originalCandidates,
                rejectedCandidateNames: input.rejectedCandidateNames
            )
        }

        if top.confidence == .high && margin >= highConfidenceMargin {
            return HomeAssistantEntityResolution(
                resolvedPhrase: phrase,
                bestMatch: top,
                rankedCandidates: ranked,
                confidence: .high,
                originalCandidates: originalCandidates,
                rejectedCandidateNames: input.rejectedCandidateNames
            )
        }

        let ambiguityCandidates = Array(ranked.prefix(4))
        if top.confidence == .high || top.confidence == .medium {
            return HomeAssistantEntityResolution(
                resolvedPhrase: phrase,
                bestMatch: sameBandTie ? nil : top,
                ambiguityCandidates: ambiguityCandidates,
                rankedCandidates: ranked,
                confidence: .medium,
                originalCandidates: originalCandidates,
                rejectedCandidateNames: input.rejectedCandidateNames,
                isTieAmbiguity: sameBandTie
            )
        }

        return HomeAssistantEntityResolution(
            resolvedPhrase: phrase,
            rankedCandidates: ranked,
            confidence: .low,
            originalCandidates: originalCandidates,
            rejectedCandidateNames: input.rejectedCandidateNames
        )
    }

    private func normalizedPhrase(from input: HomeAssistantEntityResolutionInput) -> String {
        let trimmedTarget = input.targetPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedTarget.isEmpty == false {
            return trimmedTarget
        }
        return input.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func allCandidates(from input: HomeAssistantEntityResolutionInput) -> [(name: String, type: HomeAssistantResolvedEntityType)] {
        let groups: [([String], HomeAssistantResolvedEntityType)] = [
            (input.categories, .category),
            (input.cards, .card),
            (input.merchants, .merchant),
            (input.presets, .preset),
            (input.budgets, .budget),
            (input.incomeSources, .incomeSource)
        ]

        return groups.flatMap { names, type in
            names
                .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
                .map { ($0, type) }
        }
    }

    private func rank(
        phrase: String,
        candidates: [(name: String, type: HomeAssistantResolvedEntityType)],
        aliasRules: [AssistantAliasRule]
    ) -> [HomeAssistantEntityMatch] {
        let normalized = normalize(phrase)
        let promptTokens = normalized.split(separator: " ").map(String.init)
        let promptTokenSet = Set(promptTokens)

        var ranked: [HomeAssistantEntityMatch] = []

        for candidate in candidates {
            let normalizedCandidate = normalize(candidate.name)
            guard normalizedCandidate.isEmpty == false else { continue }

            if normalized == normalizedCandidate || containsWholePhrase(normalizedCandidate, in: normalized) {
                ranked.append(
                    HomeAssistantEntityMatch(
                        name: candidate.name,
                        entityType: candidate.type,
                        confidence: .exact,
                        source: .exact,
                        score: 1
                    )
                )
                continue
            }

            if let aliasType = aliasEntityType(for: candidate.type),
               let aliasTarget = aliasMatcher.matchedTarget(
                in: phrase,
                entityType: aliasType,
                rules: aliasRules
               ),
               normalize(aliasTarget) == normalizedCandidate
            {
                ranked.append(
                    HomeAssistantEntityMatch(
                        name: candidate.name,
                        entityType: candidate.type,
                        confidence: .high,
                        source: .alias,
                        score: 0.95
                    )
                )
                continue
            }

            let score = fuzzyScore(
                normalizedPrompt: normalized,
                promptTokens: promptTokens,
                promptTokenSet: promptTokenSet,
                candidate: normalizedCandidate
            )
            guard score >= 0.45 else { continue }

            ranked.append(
                HomeAssistantEntityMatch(
                    name: candidate.name,
                    entityType: candidate.type,
                    confidence: confidence(for: score),
                    source: .fuzzy,
                    score: score
                )
            )
        }

        return ranked.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
            return lhs.score > rhs.score
        }
    }

    private func confidence(for score: Double) -> HomeAssistantResolutionConfidence {
        switch score {
        case 0.9...:
            return .high
        case 0.68...:
            return .medium
        default:
            return .low
        }
    }

    private func fuzzyScore(
        normalizedPrompt: String,
        promptTokens: [String],
        promptTokenSet: Set<String>,
        candidate: String
    ) -> Double {
        let candidateTokens = candidate
            .split(separator: " ")
            .map(String.init)
            .filter { informativeToken($0) }
        guard candidateTokens.isEmpty == false else { return 0 }

        var exactHits = 0
        var fuzzyHits = 0
        var similaritySum = 0.0

        for token in candidateTokens {
            if promptTokenSet.contains(token) {
                exactHits += 1
                similaritySum += 1
                continue
            }

            let bestSimilarity = promptTokens.map { similarity(token, $0) }.max() ?? 0
            if bestSimilarity >= 0.8 {
                fuzzyHits += 1
                similaritySum += bestSimilarity
            }
        }

        let hitCount = exactHits + fuzzyHits
        guard hitCount > 0 else { return 0 }

        let tokenCoverage = Double(hitCount) / Double(candidateTokens.count)
        let averageSimilarity = similaritySum / Double(hitCount)
        let compactPrompt = normalizedPrompt.replacingOccurrences(of: " ", with: "")
        let compactCandidate = candidate.replacingOccurrences(of: " ", with: "")
        let compactContains = compactPrompt.contains(compactCandidate) ? 1.0 : 0.0
        let overlap = Double(Set(candidateTokens).intersection(promptTokenSet).count) / Double(candidateTokens.count)

        return min(1, (tokenCoverage * 0.5) + (averageSimilarity * 0.25) + (compactContains * 0.2) + (overlap * 0.05))
    }

    private func aliasEntityType(for type: HomeAssistantResolvedEntityType) -> HomeAssistantAliasEntityType? {
        switch type {
        case .category:
            return .category
        case .card:
            return .card
        case .merchant:
            return .merchant
        case .preset:
            return .preset
        case .budget:
            return .budget
        case .incomeSource:
            return .incomeSource
        }
    }

    private func containsWholePhrase(_ phrase: String, in text: String) -> Bool {
        guard phrase.isEmpty == false else { return false }
        return text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b", options: .regularExpression) != nil
    }

    private func informativeToken(_ token: String) -> Bool {
        let stopWords: Set<String> = [
            "a", "an", "the", "my", "this", "that", "all",
            "card", "cards", "category", "categories",
            "income", "source", "sources", "preset", "presets",
            "budget", "budgets", "merchant", "merchants", "payment", "payments"
        ]
        return stopWords.contains(token) == false
    }

    private func similarity(_ lhs: String, _ rhs: String) -> Double {
        guard lhs.isEmpty == false, rhs.isEmpty == false else { return 0 }
        let distance = levenshtein(Array(lhs), Array(rhs))
        let denominator = Double(max(lhs.count, rhs.count))
        guard denominator > 0 else { return 0 }
        return max(0, 1 - (Double(distance) / denominator))
    }

    private func levenshtein(_ lhs: [Character], _ rhs: [Character]) -> Int {
        if lhs.isEmpty { return rhs.count }
        if rhs.isEmpty { return lhs.count }

        var previous = Array(0...rhs.count)
        var current = Array(repeating: 0, count: rhs.count + 1)

        for (i, leftChar) in lhs.enumerated() {
            current[0] = i + 1
            for (j, rightChar) in rhs.enumerated() {
                let cost = leftChar == rightChar ? 0 : 1
                let deletion = previous[j + 1] + 1
                let insertion = current[j] + 1
                let substitution = previous[j] + cost
                current[j + 1] = min(deletion, insertion, substitution)
            }
            previous = current
        }

        return previous[rhs.count]
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum HomeAssistantIntentFamily: String {
    case overview
    case spendTotal
    case comparison
    case incomeAverage
    case incomeShare
    case passthrough
}

struct HomeAssistantPlanReconciler {
    func reconcile(
        plan: HomeQueryPlan,
        resolution: HomeAssistantEntityResolution
    ) -> (plan: HomeQueryPlan, explanation: String?, didOverrideMetric: Bool) {
        guard let bestMatch = resolution.bestMatch else {
            return (plan, nil, false)
        }

        let intentFamily = self.intentFamily(for: plan.metric)
        let resolvedMetric = metric(for: intentFamily, resolvedEntityType: bestMatch.entityType, fallback: plan.metric)
        let didOverrideMetric = resolvedMetric != plan.metric

        let explanation = explanation(
            plan: plan,
            match: bestMatch,
            didOverrideMetric: didOverrideMetric
        )

        let reconciledPlan = plan.updating(
            metric: resolvedMetric,
            confidenceBand: confidenceBand(for: resolution.confidence),
            targetName: .some(bestMatch.name),
            targetTypeRaw: .some(bestMatch.entityType.rawValue)
        )

        return (reconciledPlan, explanation, didOverrideMetric)
    }

    private func intentFamily(for metric: HomeQueryMetric) -> HomeAssistantIntentFamily {
        switch metric {
        case .overview:
            return .overview
        case .spendTotal, .categorySpendTotal, .cardSpendTotal, .merchantSpendTotal:
            return .spendTotal
        case .monthComparison, .categoryMonthComparison, .cardMonthComparison, .incomeSourceMonthComparison, .merchantMonthComparison:
            return .comparison
        case .incomeAverageActual:
            return .incomeAverage
        case .incomeSourceShare, .incomeSourceShareTrend:
            return .incomeShare
        case .topCategories, .largestTransactions, .spendAveragePerPeriod, .cardVariableSpendingHabits, .savingsStatus, .savingsAverageRecentPeriods, .categorySpendShare, .categorySpendShareTrend, .presetDueSoon, .presetHighestCost, .presetTopCategory, .presetCategorySpend, .categoryPotentialSavings, .categoryReallocationGuidance, .safeSpendToday, .forecastSavings, .nextPlannedExpense, .spendTrendsSummary, .cardSnapshotSummary, .merchantSpendSummary, .topMerchants, .topCategoryChanges, .topCardChanges:
            return .passthrough
        }
    }

    private func metric(
        for family: HomeAssistantIntentFamily,
        resolvedEntityType: HomeAssistantResolvedEntityType,
        fallback: HomeQueryMetric
    ) -> HomeQueryMetric {
        switch (family, resolvedEntityType) {
        case (.overview, _):
            return .overview
        case (.spendTotal, .category):
            return .categorySpendTotal
        case (.spendTotal, .card):
            return .cardSpendTotal
        case (.spendTotal, .merchant):
            return .merchantSpendTotal
        case (.comparison, .category):
            return .categoryMonthComparison
        case (.comparison, .card):
            return .cardMonthComparison
        case (.comparison, .incomeSource):
            return .incomeSourceMonthComparison
        case (.comparison, .merchant):
            return .merchantMonthComparison
        case (.incomeAverage, .incomeSource):
            return .incomeAverageActual
        case (.incomeShare, .incomeSource):
            return .incomeSourceShare
        default:
            return fallback
        }
    }

    private func confidenceBand(for confidence: HomeAssistantResolutionConfidence) -> HomeQueryConfidenceBand {
        switch confidence {
        case .exact, .high:
            return .high
        case .medium:
            return .medium
        case .low:
            return .low
        }
    }

    private func explanation(
        plan: HomeQueryPlan,
        match: HomeAssistantEntityMatch,
        didOverrideMetric: Bool
    ) -> String? {
        if didOverrideMetric,
           let originalTargetType = plan.targetTypeRaw,
           originalTargetType.isEmpty == false,
           originalTargetType != match.entityType.rawValue {
            return "No \(originalTargetType) found, using \(match.entityType.rawValue) instead"
        }

        if didOverrideMetric || match.source == .alias || match.source == .fuzzy {
            return "Using \(match.entityType.rawValue) \(match.name)"
        }

        return nil
    }
}
