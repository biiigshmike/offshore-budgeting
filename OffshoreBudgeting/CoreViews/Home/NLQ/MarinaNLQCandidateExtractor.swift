import Foundation

struct MarinaNLQCandidateExtractor {
    func extractCandidates(
        from text: String,
        provider: MarinaDataProvider
    ) -> MarinaNLQTargetExtractionResult {
        let normalizedTarget = normalize(text)
        guard normalizedTarget.isEmpty == false else {
            return MarinaNLQTargetExtractionResult(rawTargetText: nil, matchesByType: [:])
        }

        var collected: [MarinaNLQCandidateMatch] = []

        for category in provider.fetchAllCategories() {
            if let match = matchCandidate(
                target: normalizedTarget,
                displayValue: category.name,
                targetType: .category,
                sourceID: category.id
            ) {
                collected.append(match)
            }
        }

        for card in provider.fetchAllCards() {
            if let match = matchCandidate(target: normalizedTarget, displayValue: card.name, targetType: .card, sourceID: card.id) {
                collected.append(match)
            }
        }

        for budget in provider.fetchAllBudgets() {
            if let match = matchCandidate(target: normalizedTarget, displayValue: budget.name, targetType: .budget, sourceID: budget.id) {
                collected.append(match)
            }
        }

        for preset in provider.fetchAllPresets() {
            if let match = matchCandidate(target: normalizedTarget, displayValue: preset.title, targetType: .preset, sourceID: preset.id) {
                collected.append(match)
            }
        }

        for income in provider.fetchAllIncomes() {
            if let match = matchCandidate(target: normalizedTarget, displayValue: income.source, targetType: .incomeSource, sourceID: income.id) {
                collected.append(match)
            }
        }

        for account in provider.fetchAllAllocationAccounts() {
            if let match = matchCandidate(target: normalizedTarget, displayValue: account.name, targetType: .allocationAccount, sourceID: account.id) {
                collected.append(match)
            }
        }

        for account in provider.fetchAllSavingsAccounts() {
            if let match = matchCandidate(target: normalizedTarget, displayValue: account.name, targetType: .savingsAccount, sourceID: account.id) {
                collected.append(match)
            }
        }

        let expenses = provider.fetchAllExpenses()
        for expense in expenses.planned {
            if let match = matchCandidate(target: normalizedTarget, displayValue: expense.title, targetType: .expense, sourceID: expense.id) {
                collected.append(match)
            }
        }

        for expense in expenses.variable {
            if let expenseMatch = matchCandidate(target: normalizedTarget, displayValue: expense.descriptionText, targetType: .expense, sourceID: expense.id) {
                collected.append(expenseMatch)
            }

            let merchantName = MerchantNormalizer.displayName(expense.descriptionText)
            if shouldOfferMerchantCandidate(merchantName),
               let merchantMatch = matchCandidate(target: normalizedTarget, displayValue: merchantName, targetType: .merchant, sourceID: expense.id) {
                collected.append(merchantMatch)
            }
        }

        let deduplicated = deduplicate(collected)
        let grouped = Dictionary(grouping: deduplicated, by: \.entityType)
        return MarinaNLQTargetExtractionResult(rawTargetText: text, matchesByType: grouped)
    }

    private func deduplicate(_ matches: [MarinaNLQCandidateMatch]) -> [MarinaNLQCandidateMatch] {
        var bestByKey: [String: MarinaNLQCandidateMatch] = [:]

        for match in matches {
            let key = "\(match.entityType.rawValue)|\(match.normalizedValue)"
            if let existing = bestByKey[key] {
                if existing.matchType == .prefix && match.matchType == .exact {
                    bestByKey[key] = match
                }
            } else {
                bestByKey[key] = match
            }
        }

        return bestByKey.values.sorted { lhs, rhs in
            if lhs.entityType.rawValue == rhs.entityType.rawValue {
                if lhs.matchType == rhs.matchType {
                    return lhs.displayValue.localizedCaseInsensitiveCompare(rhs.displayValue) == .orderedAscending
                }
                return lhs.matchType == .exact
            }
            return lhs.entityType.rawValue < rhs.entityType.rawValue
        }
    }

    private func matchCandidate(
        target: String,
        displayValue: String,
        targetType: MarinaNLQTargetType,
        sourceID: UUID
    ) -> MarinaNLQCandidateMatch? {
        let normalizedCandidate = normalize(displayValue)
        guard normalizedCandidate.isEmpty == false else { return nil }

        if normalizedCandidate == target {
            return MarinaNLQCandidateMatch(
                entityType: targetType,
                displayValue: displayValue,
                normalizedValue: normalizedCandidate,
                matchType: .exact,
                sourceID: sourceID
            )
        }

        if normalizedCandidate.hasPrefix(target) {
            return MarinaNLQCandidateMatch(
                entityType: targetType,
                displayValue: displayValue,
                normalizedValue: normalizedCandidate,
                matchType: .prefix,
                sourceID: sourceID
            )
        }

        return nil
    }

    private func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldOfferMerchantCandidate(_ displayValue: String) -> Bool {
        let normalized = normalize(displayValue)
        guard normalized.isEmpty == false else { return false }

        let tokens = normalized
            .split(separator: " ")
            .map(String.init)

        if tokens.count == 1 {
            return true
        }

        let merchantIndicators: Set<String> = [
            "bakery", "bar", "cafe", "coffee", "deli", "foods", "grocery", "market",
            "pharmacy", "restaurant", "shop", "store", "supermarket"
        ]
        return tokens.contains { merchantIndicators.contains($0) }
    }
}
