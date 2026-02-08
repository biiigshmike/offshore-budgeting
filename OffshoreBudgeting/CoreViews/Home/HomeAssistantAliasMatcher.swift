//
//  HomeAssistantAliasMatcher.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation

// MARK: - Alias Matcher

struct HomeAssistantAliasMatcher {
    private let entityMatcher = HomeAssistantEntityMatcher()

    func matchedTarget(
        in prompt: String,
        entityType: HomeAssistantAliasEntityType,
        rules: [AssistantAliasRule]
    ) -> String? {
        let scopedRules = rules.filter {
            $0.entityType == entityType
                && $0.aliasKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                && $0.targetValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }

        guard scopedRules.isEmpty == false else { return nil }

        let normalizedPrompt = normalize(prompt)

        let exact = scopedRules
            .sorted { $0.aliasKey.count > $1.aliasKey.count }
            .first { rule in
                let alias = normalize(rule.aliasKey)
                return alias.isEmpty == false
                    && normalizedPrompt.range(
                        of: "\\b\(NSRegularExpression.escapedPattern(for: alias))\\b",
                        options: .regularExpression
                    ) != nil
            }

        if let exact {
            return exact.targetValue
        }

        let aliases = scopedRules.map(\.aliasKey)
        guard let fuzzyAlias = entityMatcher.bestMatch(in: prompt, candidateNames: aliases) else {
            return nil
        }

        let normalizedAlias = normalize(fuzzyAlias)
        return scopedRules.first(where: { normalize($0.aliasKey) == normalizedAlias })?.targetValue
    }

    private func normalize(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
