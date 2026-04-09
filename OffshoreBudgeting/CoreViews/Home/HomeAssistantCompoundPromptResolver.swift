//
//  HomeAssistantCompoundPromptResolver.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/8/26.
//

import Foundation

struct HomeAssistantCompoundPromptResolver {

    func isSpendAndWherePrompt(_ rawPrompt: String) -> Bool {
        let normalized = normalizedPrompt(rawPrompt)
        guard normalized.isEmpty == false else { return false }

        let spendPhrases = [
            "what did i spend",
            "how much did i spend",
            "i spent",
            "spent today",
            "spent yesterday",
            "spend today",
            "spend yesterday",
            "spending today",
            "spending yesterday"
        ]
        let locationPhrases = [
            " and where",
            "where did it go",
            "where did my money go",
            "which stores",
            "what stores",
            "which merchants",
            "what merchants",
            "where did i shop",
            "where did i spend"
        ]

        let referencesSpend = spendPhrases.contains { normalized.contains($0) }
        let referencesWhere = locationPhrases.contains { normalized.contains($0) }
            || (normalized.contains("where") && normalized.contains("spend"))

        return referencesSpend && referencesWhere
    }

    private func normalizedPrompt(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
