import Foundation

struct MarinaDatabaseLookupDetector {
    private let parser = HomeAssistantTextParser()

    func detect(
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaDatabaseLookupRequest? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let normalizedPrompt = normalize(trimmed)
        guard isLookupShaped(normalizedPrompt) else { return nil }

        let requestedDetail = requestedDetail(from: normalizedPrompt)
        let objectTypes = objectTypes(from: normalizedPrompt, requestedDetail: requestedDetail)
        let dateRange = parser.parseDateRange(trimmed, defaultPeriodUnit: defaultPeriodUnit)
        let searchText = extractSearchText(from: trimmed, normalizedPrompt: normalizedPrompt)

        guard isSafeLookup(searchText: searchText, objectTypes: objectTypes, dateRange: dateRange) else {
            return nil
        }

        return MarinaDatabaseLookupRequest(
            rawPrompt: prompt,
            searchText: searchText,
            objectTypes: objectTypes,
            dateRange: dateRange,
            limit: 5,
            requestedDetail: requestedDetail
        ).clamped
    }

    private func isLookupShaped(_ normalizedPrompt: String) -> Bool {
        let analyticsRankingCues = [
            "where is my money going",
            "where does my money go",
            "where did most of my money go",
            "where my money went",
            "money went",
            "total spend",
            "what i spent",
            "what i spend",
            "spend on",
            "spending on",
            "most frequent",
            "top categories",
            "top merchants",
            "biggest expense",
            "largest expense",
            "top expense",
            "top transaction",
            "spending on too often",
            "not necessarily the most money"
        ]
        if analyticsRankingCues.contains(where: { normalizedPrompt.contains($0) }) {
            return false
        }

        let prefixes = [
            "find ", "find my ", "find the ",
            "look up ", "lookup ",
            "show me ", "show me my ", "show my ", "show the ",
            "open ",
            "tell me about ",
            "what is "
        ]

        if prefixes.contains(where: { normalizedPrompt.hasPrefix($0) }) {
            return true
        }

        let transactionPrefixes = [
            "when did i buy ",
            "when did i purchase ",
            "when did i order ",
            "when did i get ",
            "what card did i use for ",
            "what category was ",
            "how much was ",
            "what did "
        ]

        if transactionPrefixes.contains(where: { normalizedPrompt.hasPrefix($0) }) {
            if normalizedPrompt.hasPrefix("what did ") {
                return normalizedPrompt.hasSuffix(" cost")
            }
            return true
        }

        return false
    }

    private func requestedDetail(from normalizedPrompt: String) -> MarinaDatabaseLookupRequest.RequestedDetail {
        if normalizedPrompt.hasPrefix("when did ") {
            return .date
        }
        if normalizedPrompt.hasPrefix("what card ") {
            return .card
        }
        if normalizedPrompt.hasPrefix("what category ") {
            return .category
        }
        if normalizedPrompt.hasPrefix("how much ") || normalizedPrompt.hasSuffix(" cost") {
            return .amount
        }
        if normalizedPrompt.contains(" balance") {
            return .balance
        }
        if normalizedPrompt.contains(" recurring") || normalizedPrompt.contains(" recurrence") {
            return .recurrence
        }
        return .general
    }

    private func objectTypes(
        from normalizedPrompt: String,
        requestedDetail: MarinaDatabaseLookupRequest.RequestedDetail
    ) -> [MarinaLookupObjectType] {
        if normalizedPrompt.contains("planned expense") || normalizedPrompt.contains("recurring bill") || normalizedPrompt.contains(" bill") {
            return [.plannedExpense]
        }
        if normalizedPrompt.contains("expense")
            || normalizedPrompt.contains("transaction")
            || normalizedPrompt.contains("purchase")
            || normalizedPrompt.contains("bought")
            || normalizedPrompt.contains("buy ")
            || normalizedPrompt.contains("order")
            || normalizedPrompt.hasPrefix("when did i get ")
            || [.date, .amount, .card, .category].contains(requestedDetail) {
            return [.variableExpense, .plannedExpense]
        }
        if normalizedPrompt.contains("budget") {
            return [.budget]
        }
        if normalizedPrompt.contains("income") || normalizedPrompt.contains("paycheck") || normalizedPrompt.contains("deposit") {
            return [.income]
        }
        if normalizedPrompt.contains("category") {
            return [.category]
        }
        if normalizedPrompt.contains("preset") || normalizedPrompt.contains("template") {
            return [.preset]
        }
        if normalizedPrompt.contains("card") {
            return [.card]
        }
        if normalizedPrompt.contains("savings ledger") {
            return [.savingsLedgerEntry]
        }
        if normalizedPrompt.contains("savings account") || normalizedPrompt.contains("true savings") {
            return [.savingsAccount]
        }
        if normalizedPrompt.contains("reconciliation") || normalizedPrompt.contains("statement") {
            return [.reconciliationAccount, .reconciliationItem]
        }
        if normalizedPrompt.contains("workspace") {
            return [.workspace]
        }
        return MarinaLookupObjectType.safeDefaultSearchTypes
    }

    private func extractSearchText(from prompt: String, normalizedPrompt: String) -> String {
        var text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "?.!"))

        let caseInsensitivePrefixes = [
            "when did i purchase ", "when did i buy ", "when did i order ", "when did i get ",
            "what card did i use for ",
            "what category was ",
            "how much was ",
            "what did ",
            "tell me about ",
            "look up ", "lookup ",
            "show me my ", "show me the ", "show me ", "show my ", "show the ",
            "find my ", "find the ", "find ",
            "open ",
            "what is ", "where is "
        ]

        for prefix in caseInsensitivePrefixes {
            if text.lowercased().hasPrefix(prefix) {
                text.removeFirst(prefix.count)
                break
            }
        }

        if normalizedPrompt.hasSuffix(" cost"), text.lowercased().hasSuffix(" cost") {
            text.removeLast(" cost".count)
        }

        text = removeDateTail(from: text)
        text = stripLeadingFiller(from: text)
        text = stripTrailingTypeClue(from: text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeDateTail(from text: String) -> String {
        let patterns = [
            "\\s+from\\s+(january|february|march|april|may|june|july|august|september|october|november|december)\\b.*$",
            "\\s+in\\s+(january|february|march|april|may|june|july|august|september|october|november|december)\\b.*$",
            "\\s+this\\s+(week|month|quarter|year)\\b.*$",
            "\\s+last\\s+(week|month|quarter|year)\\b.*$"
        ]
        var cleaned = text
        for pattern in patterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return cleaned
    }

    private func stripLeadingFiller(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["my ", "the ", "a ", "an "] {
            if cleaned.lowercased().hasPrefix(prefix) {
                cleaned.removeFirst(prefix.count)
                break
            }
        }
        return cleaned
    }

    private func stripTrailingTypeClue(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let removableSuffixes = [
            " planned expense", " recurring bill", " expense", " transaction", " purchase",
            " category", " preset", " template", " income", " budget"
        ]
        for suffix in removableSuffixes {
            if cleaned.lowercased().hasSuffix(suffix) {
                cleaned.removeLast(suffix.count)
                break
            }
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isSafeLookup(
        searchText: String,
        objectTypes: [MarinaLookupObjectType],
        dateRange: HomeQueryDateRange?
    ) -> Bool {
        let normalizedSearchText = normalize(searchText)
        if normalizedSearchText.isEmpty == false {
            return ["it", "that", "the expense"].contains(normalizedSearchText) == false
        }
        return dateRange != nil || objectTypes.allSatisfy { $0.allowsEmptySearchListing }
    }

    private func normalize(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension MarinaLookupObjectType {
    static var safeDefaultSearchTypes: [MarinaLookupObjectType] {
        [
            .budget,
            .income,
            .incomeSeries,
            .variableExpense,
            .plannedExpense,
            .category,
            .preset,
            .card,
            .savingsAccount,
            .reconciliationAccount
        ]
    }

    var allowsEmptySearchListing: Bool {
        switch self {
        case .budget, .card, .category, .preset, .incomeSeries, .savingsAccount,
             .reconciliationAccount, .importMerchantRule, .assistantAliasRule, .workspace:
            return true
        case .income, .variableExpense, .plannedExpense, .savingsLedgerEntry,
             .reconciliationItem, .expenseAllocation, .unknown:
            return false
        }
    }
}
