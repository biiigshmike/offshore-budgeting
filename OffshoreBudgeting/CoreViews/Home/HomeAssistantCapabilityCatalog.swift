//
//  HomeAssistantCapabilityCatalog.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 4/9/26.
//

import Foundation

enum HomeAssistantQuestionFamily: String, Equatable {
    case who
    case what
    case when
    case location
    case why
    case howMuch
    case unknown
}

struct HomeAssistantCapabilityResolution: Equatable {
    let family: HomeAssistantQuestionFamily
    let shape: HomeAssistantRequestShape
    let fallbackMetric: HomeQueryMetric
}

struct HomeAssistantCapabilityCatalog {

    func resolve(prompt rawPrompt: String) -> HomeAssistantCapabilityResolution? {
        let prompt = normalized(rawPrompt)
        guard prompt.isEmpty == false else { return nil }

        let family = questionFamily(for: prompt)

        if isSpendAndWhere(prompt) {
            return resolution(family, .spendAndWhere, .spendTotal)
        }

        if isMerchantPayeeDiscovery(prompt) {
            return resolution(family, .single, .topMerchants)
        }

        if isMerchantSpendSummary(prompt) {
            return resolution(family, .single, .merchantSpendSummary)
        }

        if isSpendAverage(prompt) {
            return resolution(family, .single, .spendAveragePerPeriod)
        }

        if isSpendByTime(prompt) {
            return resolution(family, .spendByDay, .spendTotal)
        }

        if isCategoryAvailability(prompt) {
            return resolution(family, .categoryAvailability, .topCategories)
        }

        if isIncomeSummary(prompt) {
            return resolution(family, .incomePeriodSummary, .incomeAverageActual)
        }

        if isSavingsDiagnostic(prompt) {
            return resolution(family, .savingsDiagnostic, .savingsStatus)
        }

        if isSpendDriverDiagnostic(prompt) {
            return resolution(family, .spendDrivers, .topCategoryChanges)
        }

        if isCardSummary(prompt) {
            return resolution(family, .cardSummary, .cardSnapshotSummary)
        }

        return nil
    }

    private func resolution(
        _ family: HomeAssistantQuestionFamily,
        _ shape: HomeAssistantRequestShape,
        _ fallbackMetric: HomeQueryMetric
    ) -> HomeAssistantCapabilityResolution {
        HomeAssistantCapabilityResolution(
            family: family,
            shape: shape,
            fallbackMetric: fallbackMetric
        )
    }

    private func questionFamily(for prompt: String) -> HomeAssistantQuestionFamily {
        if prompt.hasPrefix("why ") || prompt.contains(" why ") {
            return .why
        }
        if prompt.hasPrefix("where ") || prompt.contains(" where ") {
            return .location
        }
        if prompt.hasPrefix("when ") || prompt.contains(" when ") {
            return .when
        }
        if prompt.hasPrefix("who ") || prompt.contains(" who ") {
            return .who
        }
        if prompt.contains("how much") || prompt.contains("how many") {
            return .howMuch
        }
        if prompt.hasPrefix("what ") || prompt.contains(" what ") || prompt.contains("which ") {
            return .what
        }
        return .unknown
    }

    private func isSpendAndWhere(_ prompt: String) -> Bool {
        let spend = containsAny(prompt, [
            "what did i spend",
            "how much did i spend",
            "how much have i spent",
            "what have i spent"
        ])
        let whereScope = containsAny(prompt, [
            "and where",
            "which stores",
            "what stores",
            "which merchants",
            "what merchants",
            "where did it go",
            "where did my money go"
        ])
        return spend && whereScope
    }

    private func isSpendByTime(_ prompt: String) -> Bool {
        let spend = containsAny(prompt, ["spend", "spent", "spending", "expenses", "money"])
        let timeBreakdown = containsAny(prompt, [
            "by day",
            "per day",
            "daily",
            "day by day",
            "when did i spend",
            "when did i spend money",
            "which day",
            "what day"
        ])
        return spend && timeBreakdown
    }

    private func isMerchantPayeeDiscovery(_ prompt: String) -> Bool {
        containsAny(prompt, [
            "who did i pay the most",
            "who did i pay most",
            "who got the most",
            "who took the most"
        ])
    }

    private func isMerchantSpendSummary(_ prompt: String) -> Bool {
        let spend = containsAny(prompt, ["spend", "spent", "spending", "expense", "expenses"])
        let summary = containsAny(prompt, ["average", "avg", "mean", "summary", "summarize", "how often"])
        guard spend && summary else { return false }

        if prompt.contains(" at ") || prompt.contains(" merchant ") || prompt.contains(" store ") {
            return true
        }

        let summaryMerchantPattern = "\\b(?:summarize|summary of)\\s+(?:my\\s+)?[a-z0-9 '&\\-\\.]+\\s+(?:spend|spending|expenses)\\b"
        return prompt.range(of: summaryMerchantPattern, options: .regularExpression) != nil
    }

    private func isSpendAverage(_ prompt: String) -> Bool {
        guard containsAny(prompt, ["average", "avg", "mean"]) else { return false }
        guard containsAny(prompt, ["spend", "spent", "spending", "expense", "expenses"]) else { return false }
        guard containsAny(prompt, ["income", "savings", "save", "card", "cards"]) == false else { return false }
        return true
    }

    private func isCategoryAvailability(_ prompt: String) -> Bool {
        if containsAny(prompt, ["over budget", "near budget", "close to budget"])
            && containsAny(prompt, ["category", "categories", "budget"])
        {
            return true
        }

        return containsAny(prompt, [
            "where do i still have room",
            "where do i have room",
            "which categories have room",
            "which categories are available",
            "which categories have money left",
            "categories have money left",
            "category availability",
            "room in my budget",
            "available in my budget",
            "left in my budget",
            "remaining in my budget"
        ])
    }

    private func isIncomeSummary(_ prompt: String) -> Bool {
        let income = containsAny(prompt, ["income", "paycheck", "paid me", "pay me", "get paid", "got paid", "came in"])
        let summary = containsAny(prompt, [
            "what income came in",
            "income came in",
            "actual income",
            "planned income",
            "vs planned",
            "versus planned",
            "who paid me",
            "who has paid me",
            "when did i get paid",
            "when did i got paid",
            "did i hit income"
        ])
        return income && summary
    }

    private func isSavingsDiagnostic(_ prompt: String) -> Bool {
        let savings = containsAny(prompt, ["savings", "save", "saving"])
        let diagnostic = containsAny(prompt, [
            "why",
            "behind",
            "ahead",
            "off track",
            "on track",
            "gap"
        ])
        return savings && diagnostic
    }

    private func isSpendDriverDiagnostic(_ prompt: String) -> Bool {
        let spend = containsAny(prompt, ["spend", "spent", "spending", "expenses", "budget"])
        let driver = containsAny(prompt, [
            "why",
            "driver",
            "driving",
            "higher",
            "lower",
            "spike",
            "increased",
            "changed"
        ])
        return spend && driver
    }

    private func isCardSummary(_ prompt: String) -> Bool {
        if containsAny(prompt, [
            "changed most",
            "change most",
            "increased most",
            "decreased most",
            "biggest change",
            "largest change",
            "top changes",
            "vs last",
            "versus last"
        ]) {
            return false
        }

        let card = containsAny(prompt, ["card", "cards"])
        let summary = containsAny(prompt, [
            "which card",
            "card summary",
            "card snapshot",
            "use the most",
            "used most",
            "spent most",
            "most activity",
            "average charge",
            "average spend",
            "planned and variable",
            "why is",
            "higher",
            "lower"
        ])
        return card && summary
    }

    private func containsAny(_ text: String, _ keywords: [String]) -> Bool {
        keywords.contains { text.contains($0) }
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
