//
//  HomeAssistantEntityMatcher.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

struct HomeAssistantEntityMatcher {

    func bestCardMatch(in prompt: String, cards: [Card]) -> String? {
        bestMatch(in: prompt, candidateNames: cards.map(\.name))
    }

    func bestIncomeSourceMatch(in prompt: String, incomes: [Income]) -> String? {
        let uniqueSources = Array(Set(incomes.map(\.source)))
        return bestMatch(in: prompt, candidateNames: uniqueSources)
    }

    func bestCategoryMatch(in prompt: String, categories: [Category]) -> String? {
        bestMatch(in: prompt, candidateNames: categories.map(\.name))
    }

    func bestPresetMatch(in prompt: String, presets: [Preset]) -> String? {
        bestMatch(in: prompt, candidateNames: presets.map(\.title))
    }

    func bestMatch(in prompt: String, candidateNames: [String]) -> String? {
        rankedMatches(in: prompt, candidateNames: candidateNames, limit: 1).first
    }

    func rankedMatches(
        in prompt: String,
        candidateNames: [String],
        limit: Int = 3
    ) -> [String] {
        let scored = scoredMatches(in: prompt, candidates: candidateNames)
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.score > rhs.score
            }

        return Array(scored.prefix(max(0, limit)).map(\.name))
    }

    private func scoredMatches(
        in prompt: String,
        candidates: [String]
    ) -> [(name: String, score: Double)] {
        let normalizedPrompt = normalize(prompt)
        guard normalizedPrompt.isEmpty == false else { return [] }

        let normalizedCandidates = candidates
            .map { ($0, normalize($0)) }
            .filter { $0.1.isEmpty == false }

        if let exact = normalizedCandidates.first(where: { entry in
            containsWholePhrase(entry.1, in: normalizedPrompt)
        }) {
            return [(exact.0, 200)]
        }

        let promptTokens = normalizedPrompt.split(separator: " ").map(String.init)
        guard promptTokens.isEmpty == false else { return [] }
        let promptTokenSet = Set(promptTokens)

        var scored: [(name: String, score: Double)] = []

        for (name, normalizedCandidate) in normalizedCandidates {
            let candidateTokens = normalizedCandidate
                .split(separator: " ")
                .map(String.init)
                .filter(isInformativeToken)
            guard candidateTokens.isEmpty == false else { continue }

            var exactTokenHits = 0
            var fuzzyTokenHits = 0
            var similaritySum: Double = 0

            for candidateToken in candidateTokens {
                if promptTokenSet.contains(candidateToken) {
                    exactTokenHits += 1
                    similaritySum += 1
                    continue
                }

                let bestSimilarity = promptTokens
                    .map { normalizedSimilarity(candidateToken, $0) }
                    .max() ?? 0

                if bestSimilarity >= 0.80 {
                    fuzzyTokenHits += 1
                    similaritySum += bestSimilarity
                }
            }

            let hitCount = exactTokenHits + fuzzyTokenHits
            guard hitCount > 0 else { continue }

            let tokenCoverage = Double(hitCount) / Double(candidateTokens.count)
            let averageSimilarity = similaritySum / Double(hitCount)
            let compactPrompt = normalizedPrompt.replacingOccurrences(of: " ", with: "")
            let compactCandidate = normalizedCandidate.replacingOccurrences(of: " ", with: "")
            let compactContains = compactPrompt.contains(compactCandidate) ? 1.0 : 0.0
            let overlap = Double(Set(candidateTokens).intersection(promptTokenSet).count) / Double(candidateTokens.count)

            let score =
                (tokenCoverage * 50) +
                (averageSimilarity * 25) +
                (compactContains * 20) +
                (overlap * 5)

            guard score >= 40 else { continue }
            scored.append((name, score))
        }

        return scored
    }

    private func containsWholePhrase(_ phrase: String, in text: String) -> Bool {
        guard phrase.isEmpty == false else { return false }
        return text.range(of: "\\b\(NSRegularExpression.escapedPattern(for: phrase))\\b", options: .regularExpression) != nil
    }

    private func normalizedSimilarity(_ lhs: String, _ rhs: String) -> Double {
        guard lhs.isEmpty == false, rhs.isEmpty == false else { return 0 }

        let distance = levenshteinDistance(Array(lhs), Array(rhs))
        let denominator = Double(max(lhs.count, rhs.count))
        guard denominator > 0 else { return 0 }
        return max(0, 1 - (Double(distance) / denominator))
    }

    private func isInformativeToken(_ token: String) -> Bool {
        let stopWords: Set<String> = [
            "a", "an", "the", "my", "this", "that", "all",
            "card", "cards", "category", "categories",
            "income", "source", "sources", "preset", "presets",
            "payment", "payments"
        ]

        return stopWords.contains(token) == false
    }

    private func levenshteinDistance(_ lhs: [Character], _ rhs: [Character]) -> Int {
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
