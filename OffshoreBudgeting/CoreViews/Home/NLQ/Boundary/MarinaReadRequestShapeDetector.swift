import Foundation

struct MarinaReadRequestShapeDetector {
    private let parser = HomeAssistantTextParser()

    func detect(
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        now: Date
    ) -> MarinaQueryPlanCandidate? {
        let normalizedPrompt = normalized(prompt)
        guard normalizedPrompt.isEmpty == false else { return nil }

        if isWorkspaceLookup(normalizedPrompt) {
            return lookup(prompt: prompt, searchText: "", objectTypes: [.workspace], requestedDetail: .general, limit: 5)
        }

        if isBudgetList(normalizedPrompt) {
            return lookup(prompt: prompt, searchText: "", objectTypes: [.budget], requestedDetail: .general, limit: 10)
        }

        if isActiveBudgetLookup(normalizedPrompt) {
            return budgetRelationshipCandidate(
                prompt: prompt,
                budgetName: nil,
                defaultPeriodUnit: defaultPeriodUnit,
                requestedDetail: .status
            )
        }

        if let membership = budgetMembership(in: normalizedPrompt) {
            return budgetRelationshipCandidate(
                prompt: prompt,
                budgetName: membership.budgetName,
                defaultPeriodUnit: defaultPeriodUnit,
                requestedDetail: .membership,
                relationshipFilters: [
                    MarinaSemanticCommandFilter(rawText: membership.memberName, allowedTypes: [membership.memberType])
                ],
                relationshipMentions: [
                    MarinaUnresolvedEntityMention(
                        role: .filter,
                        rawText: membership.memberName,
                        typeHint: membership.memberType,
                        confidence: .high
                    )
                ]
            )
        }

        if let relationship = linkedBudgetRelationship(in: normalizedPrompt) {
            return budgetRelationshipCandidate(
                prompt: prompt,
                budgetName: relationship.budgetName,
                defaultPeriodUnit: defaultPeriodUnit,
                requestedDetail: relationship.requestedDetail
            )
        }

        if let budgetName = explicitBudgetName(in: normalizedPrompt) {
            return budgetRelationshipCandidate(
                prompt: prompt,
                budgetName: budgetName,
                defaultPeriodUnit: defaultPeriodUnit,
                requestedDetail: .linkedObjects
            )
        }

        if let categoryName = budgetLimitCategory(in: normalizedPrompt) {
            return MarinaQueryPlanCandidate(
                source: .heuristic,
                rawPrompt: prompt,
                operation: .lookupDetails,
                measure: .remainingBudget,
                entityMentions: [
                    MarinaUnresolvedEntityMention(
                        role: .primaryTarget,
                        rawText: categoryName,
                        typeHint: .category,
                        confidence: .high
                    )
                ],
                timeScopes: dateScopes(prompt: prompt, defaultPeriodUnit: defaultPeriodUnit),
                responseShapeHint: .summaryCard,
                confidence: .high
            )
        }

        if let cardName = listExpensesCard(in: normalizedPrompt) {
            return MarinaQueryPlanCandidate(
                source: .heuristic,
                rawPrompt: prompt,
                operation: .listRows,
                measure: .transactionAmount,
                entityMentions: [
                    MarinaUnresolvedEntityMention(
                        role: .filter,
                        rawText: cardName,
                        typeHint: .card,
                        confidence: .high
                    )
                ],
                timeScopes: dateScopes(prompt: prompt, defaultPeriodUnit: defaultPeriodUnit),
                grouping: MarinaGroupingCandidate(dimension: .transaction),
                ranking: MarinaRankingCandidate(direction: .newest, limit: explicitLimit(in: normalizedPrompt) ?? 10),
                limit: explicitLimit(in: normalizedPrompt) ?? 10,
                responseShapeHint: .rankedList,
                confidence: .high
            )
        }

        if let cardName = spendCard(in: normalizedPrompt) {
            return MarinaQueryPlanCandidate(
                source: .heuristic,
                rawPrompt: prompt,
                operation: .sum,
                measure: .spend,
                entityMentions: [
                    MarinaUnresolvedEntityMention(
                        role: .filter,
                        rawText: cardName,
                        typeHint: .card,
                        confidence: .high
                    )
                ],
                timeScopes: dateScopes(prompt: prompt, defaultPeriodUnit: defaultPeriodUnit),
                responseShapeHint: .scalarCurrency,
                confidence: .high
            )
        }

        if isCardBalanceList(normalizedPrompt) {
            return MarinaQueryPlanCandidate(
                source: .heuristic,
                rawPrompt: prompt,
                operation: .rank,
                measure: .spend,
                entityMentions: [],
                timeScopes: dateScopes(prompt: prompt, defaultPeriodUnit: defaultPeriodUnit),
                grouping: MarinaGroupingCandidate(dimension: .card),
                ranking: MarinaRankingCandidate(direction: .top, limit: 10),
                limit: 10,
                responseShapeHint: .rankedList,
                confidence: .high
            )
        }

        return nil
    }

    private func lookup(
        prompt: String,
        searchText: String,
        objectTypes: [MarinaLookupObjectType],
        requestedDetail: MarinaDatabaseLookupRequest.RequestedDetail,
        limit: Int
    ) -> MarinaQueryPlanCandidate {
        let request = MarinaDatabaseLookupRequest(
            rawPrompt: prompt,
            searchText: searchText,
            objectTypes: objectTypes,
            dateRange: nil,
            limit: limit,
            requestedDetail: requestedDetail
        ).clamped
        return MarinaQueryPlanCandidate(
            requestFamily: .databaseLookup,
            source: .heuristic,
            rawPrompt: prompt,
            operation: .lookupDetails,
            databaseLookupRequest: request,
            semanticCommand: MarinaSemanticCommand(
                family: .databaseLookup,
                action: .lookupDetails,
                datasets: objectTypes.compactMap(dataset(from:)),
                requestedDetail: requestedDetail.semanticDetail
            )
        )
    }

    private func budgetRelationshipCandidate(
        prompt: String,
        budgetName: String?,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        requestedDetail: MarinaSemanticRequestedDetail,
        relationshipFilters: [MarinaSemanticCommandFilter] = [],
        relationshipMentions: [MarinaUnresolvedEntityMention] = []
    ) -> MarinaQueryPlanCandidate {
        let filters = budgetName.map {
            [MarinaSemanticCommandFilter(rawText: $0, allowedTypes: [.budget])]
        } ?? []
        let mentions = budgetName.map {
            [
                MarinaUnresolvedEntityMention(
                    role: .primaryTarget,
                    rawText: $0,
                    typeHint: .budget,
                    confidence: .high
                )
            ]
        } ?? []
        let allFilters = filters + relationshipFilters
        let allMentions = mentions + relationshipMentions
        return MarinaQueryPlanCandidate(
            requestFamily: .analytics,
            source: .heuristic,
            rawPrompt: prompt,
            operation: .lookupDetails,
            measure: .spend,
            entityMentions: allMentions,
            timeScopes: dateScopes(prompt: prompt, defaultPeriodUnit: defaultPeriodUnit),
            responseShapeHint: responseShape(for: requestedDetail),
            confidence: .high,
            semanticCommand: MarinaSemanticCommand(
                family: .analytics,
                action: .lookupDetails,
                datasets: [.budgets],
                measure: .spend,
                includeFilters: allFilters,
                requestedDetail: requestedDetail
            )
        )
    }

    private func isWorkspaceLookup(_ prompt: String) -> Bool {
        prompt.contains("workspace")
            && (prompt.hasPrefix("what workspace")
                || prompt.contains("workspace summary")
                || prompt.contains("other workspaces"))
    }

    private func isBudgetList(_ prompt: String) -> Bool {
        prompt.contains("budget")
            && (prompt.contains("budgets do i have")
                || prompt.contains("show budgets")
                || prompt.contains("list budgets"))
    }

    private func isActiveBudgetLookup(_ prompt: String) -> Bool {
        prompt.contains("budget")
            && (prompt.contains("active budget") || prompt.contains("current budget"))
            && prompt.contains("included in this budget") == false
    }

    private func explicitBudgetName(in prompt: String) -> String? {
        if let linked = firstCapture(
            in: prompt,
            patterns: [
                #"\blinked\s+to\s+(.+?)$"#,
                #"\bopen\s+(.+?\s+budget)$"#
            ]
        ) {
            return titleCaseBudgetName(linked)
        }
        if prompt.hasPrefix("show "),
           prompt.hasPrefix("show me ") == false,
           prompt.hasPrefix("show my ") == false,
           prompt.hasSuffix(" budget") {
            return titleCaseBudgetName(prompt.replacingOccurrences(of: #"^show\s+"#, with: "", options: .regularExpression))
        }
        return nil
    }

    private func linkedBudgetRelationship(in prompt: String) -> (budgetName: String?, requestedDetail: MarinaSemanticRequestedDetail)? {
        let requestedDetail: MarinaSemanticRequestedDetail
        if prompt.contains("card") && prompt.contains("linked") {
            requestedDetail = .linkedCards
        } else if prompt.contains("preset") && prompt.contains("linked") {
            requestedDetail = .linkedPresets
        } else if (prompt.contains("category") || prompt.contains("limit")) && prompt.contains("linked") {
            requestedDetail = .categoryLimits
        } else {
            return nil
        }

        let budgetName = firstCapture(
            in: prompt,
            patterns: [
                #"\b(?:cards|presets|categories|limits)\s+(?:are\s+)?linked\s+to\s+(.+?)$"#,
                #"\blinked\s+to\s+(.+?)$"#
            ]
        ).map(titleCaseBudgetName)
        return (budgetName, requestedDetail)
    }

    private func budgetMembership(in prompt: String) -> (budgetName: String?, memberName: String, memberType: MarinaCandidateEntityTypeHint)? {
        guard prompt.contains("budget"),
              prompt.contains("included") || prompt.contains("linked") || prompt.contains("in this budget") else {
            return nil
        }

        let member: (String, MarinaCandidateEntityTypeHint)?
        if let cardName = firstCapture(in: prompt, patterns: [#"\bis\s+(.+?\s+card)\s+(?:included|linked|in)\b"#]) {
            member = (cleanObjectName(cardName), .card)
        } else if let presetName = firstCapture(in: prompt, patterns: [#"\bis\s+(.+?)\s+(?:included|linked)\s+in\s+(?:this\s+)?budget\b"#]) {
            member = (cleanObjectName(presetName), .preset)
        } else {
            member = nil
        }

        guard let member else { return nil }
        let budgetName = firstCapture(
            in: prompt,
            patterns: [
                #"\bbudget\s+(.+?)$"#,
                #"\bin\s+(.+?\s+budget)$"#
            ]
        ).map(titleCaseBudgetName)
        return (budgetName, member.0, member.1)
    }

    private func responseShape(for requestedDetail: MarinaSemanticRequestedDetail) -> MarinaResponseShapeHint {
        switch requestedDetail {
        case .linkedCards, .linkedPresets, .categoryLimits:
            return .relationshipList
        case .membership:
            return .membershipStatus
        default:
            return .summaryCard
        }
    }

    private func budgetLimitCategory(in prompt: String) -> String? {
        guard prompt.contains("budget limit") || prompt.contains("category limit") else { return nil }
        return firstCapture(
            in: prompt,
            patterns: [
                #"\bshow\s+(?:my\s+)?(.+?)\s+(?:budget|category)\s+limit\b"#,
                #"\b(.+?)\s+(?:budget|category)\s+limit\b"#
            ]
        ).map(cleanObjectName)
    }

    private func listExpensesCard(in prompt: String) -> String? {
        guard (prompt.hasPrefix("list ") || prompt.hasPrefix("show ")),
              prompt.contains("expense"),
              prompt.contains(" card") else { return nil }
        return firstCapture(
            in: prompt,
            patterns: [
                #"\b(?:list|show)(?:\s+my)?\s+expenses\s+on\s+(.+?\s+card)\b"#,
                #"\b(?:list|show)(?:\s+my)?\s+(.+?\s+card)\s+expenses\b"#
            ]
        ).map(cleanObjectName)
    }

    private func spendCard(in prompt: String) -> String? {
        guard prompt.contains("spend"),
              prompt.contains(" card") else { return nil }
        return firstCapture(
            in: prompt,
            patterns: [
                #"\bspend\s+on\s+(.+?\s+card)(?:\s+this|\s+last|\s+in\b|$)"#,
                #"\bspent\s+on\s+(.+?\s+card)(?:\s+this|\s+last|\s+in\b|$)"#
            ]
        ).map(cleanObjectName)
    }

    private func isCardBalanceList(_ prompt: String) -> Bool {
        prompt.contains("card")
            && (prompt.contains("balances") || prompt.contains("balance"))
            && (prompt.hasPrefix("show") || prompt.hasPrefix("list") || prompt.hasPrefix("what"))
    }

    private func dateScopes(prompt: String, defaultPeriodUnit: HomeQueryPeriodUnit) -> [MarinaUnresolvedTimeScope] {
        guard let range = parser.parseDateRange(prompt, defaultPeriodUnit: defaultPeriodUnit) else { return [] }
        return [
            MarinaUnresolvedTimeScope(
                role: .primary,
                rawText: nil,
                resolvedRangeHint: range,
                periodUnitHint: defaultPeriodUnit
            )
        ]
    }

    private func explicitLimit(in prompt: String) -> Int? {
        prompt.split(separator: " ").compactMap { Int($0) }.first
    }

    private func dataset(from objectType: MarinaLookupObjectType) -> MarinaSemanticCommandDataset? {
        switch objectType {
        case .budget:
            return .budgets
        case .income:
            return .income
        case .incomeSeries:
            return .incomeSeries
        case .variableExpense:
            return .variableExpenses
        case .plannedExpense:
            return .plannedExpenses
        case .category:
            return .categories
        case .preset:
            return .presets
        case .card:
            return .cards
        case .savingsLedgerEntry:
            return .savingsLedger
        case .reconciliationAccount, .reconciliationItem:
            return .reconciliation
        case .expenseAllocation:
            return .expenseAllocations
        case .importMerchantRule:
            return .importMerchantRules
        case .assistantAliasRule:
            return .assistantAliasRules
        case .savingsAccount, .workspace, .unknown:
            return nil
        }
    }

    private func firstCapture(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let capture = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if capture.isEmpty == false { return capture }
        }
        return nil
    }

    private func titleCaseBudgetName(_ value: String) -> String {
        cleanObjectName(value)
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func cleanObjectName(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^(?:my|the|a|an|is)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"\s+(?:this|last|in|for)\b.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalized(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension MarinaDatabaseLookupRequest.RequestedDetail {
    var semanticDetail: MarinaSemanticRequestedDetail {
        switch self {
        case .general:
            return .general
        case .date:
            return .date
        case .amount:
            return .amount
        case .card:
            return .card
        case .category:
            return .category
        case .status:
            return .status
        case .schedule:
            return .schedule
        case .recurrence:
            return .recurrence
        case .account:
            return .account
        case .balance:
            return .balance
        case .linkedObjects:
            return .linkedObjects
        }
    }
}
