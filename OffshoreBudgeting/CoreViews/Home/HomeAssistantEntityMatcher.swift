//
//  HomeAssistantEntityMatcher.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

struct HomeAssistantEntityMatcher {

    func bestCardMatch(in prompt: String, cards: [Card]) -> String? {
        bestMatch(in: prompt, candidates: cards.map(\.name))
    }

    func bestIncomeSourceMatch(in prompt: String, incomes: [Income]) -> String? {
        let uniqueSources = Array(Set(incomes.map(\.source)))
        return bestMatch(in: prompt, candidates: uniqueSources)
    }

    func bestCategoryMatch(in prompt: String, categories: [Category]) -> String? {
        bestMatch(in: prompt, candidates: categories.map(\.name))
    }

    func bestPresetMatch(in prompt: String, presets: [Preset]) -> String? {
        bestMatch(in: prompt, candidates: presets.map(\.title))
    }

    private func bestMatch(in prompt: String, candidates: [String]) -> String? {
        let normalizedPrompt = normalize(prompt)
        guard normalizedPrompt.isEmpty == false else { return nil }

        let normalizedCandidates = candidates
            .map { ($0, normalize($0)) }
            .filter { $0.1.isEmpty == false }

        if let exact = normalizedCandidates.first(where: { candidate in
            normalizedPrompt.contains(candidate.1)
        }) {
            return exact.0
        }

        let promptTokens = Set(normalizedPrompt.split(separator: " ").map(String.init))
        var best: (name: String, score: Int)? = nil

        for (name, normalizedCandidate) in normalizedCandidates {
            let tokens = Set(normalizedCandidate.split(separator: " ").map(String.init))
            let score = tokens.intersection(promptTokens).count
            guard score > 0 else { continue }

            if let best, best.score >= score { continue }
            best = (name, score)
        }

        return best?.name
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
