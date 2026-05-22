import Foundation

#if DEBUG
struct MarinaTypedFixtureAvailability: MarinaModelAvailabilityProviding {
    func currentStatus() -> MarinaModelAvailability.Status { .available }
}

struct MarinaTypedFixtureInterpreter: MarinaCanonicalAIInterpreting {
    enum FixtureError: Error {
        case missingInterpretation(String)
    }

    static var isEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let rawValue = environment[MarinaRuntimeSettings.uiFakeAIInterpreterEnvironmentKey] else {
            return false
        }
        return ["1", "true", "yes", "on"].contains(rawValue.lowercased())
    }

    private let adapter = MarinaSemanticQueryAdapter()

    func interpretCanonical(
        prompt: String,
        context: MarinaInterpretationContext
    ) async throws -> MarinaCanonicalReadInterpretation {
        guard let interpretation = interpretation(for: prompt, context: context) else {
            throw FixtureError.missingInterpretation(prompt)
        }
        return interpretation
    }

    private func interpretation(
        for prompt: String,
        context: MarinaInterpretationContext
    ) -> MarinaCanonicalReadInterpretation? {
        switch canonicalPrompt(prompt) {
        case "show me my apple card", "show apple card":
            return databaseLookup(
                prompt: prompt,
                searchText: "Apple Card",
                objectTypes: [.card],
                lookupMode: .entityDetail
            )
        case "what workspace am i in":
            return databaseLookup(
                prompt: prompt,
                searchText: "",
                objectTypes: [.workspace],
                requestShape: .objectInventoryList
            )
        case "what is my active budget":
            return candidate(
                prompt: prompt,
                operation: .lookupDetails,
                measure: .remainingBudget,
                responseShape: .summaryCard,
                semanticCommand: MarinaSemanticCommand(
                    family: .analytics,
                    action: .lookupDetails,
                    datasets: [.budgets],
                    measure: .remainingBudget,
                    requestedDetail: .status
                )
            )
        case "show my groceries budget limit", "how much do i have left in groceries":
            return candidate(
                prompt: prompt,
                operation: .lookupDetails,
                measure: .remainingBudget,
                mentions: [mention("Groceries", .category, role: .primaryTarget)],
                responseShape: .summaryCard,
                semanticCommand: MarinaSemanticCommand(
                    family: .analytics,
                    action: .lookupDetails,
                    datasets: [.budgets],
                    measure: .remainingBudget,
                    includeFilters: [filter("Groceries", [.category])],
                    requestedDetail: .categoryLimits
                )
            )
        case "what did i spend on apple card this month":
            return candidate(
                prompt: prompt,
                operation: .sum,
                measure: .spend,
                mentions: [mention("Apple Card", .card)],
                timeScopes: [timeScope("this month", monthRange(2026, 5), .month)],
                responseShape: .scalarCurrency
            )
        case "which cards are linked to may budget", "which cards are in may budget":
            return candidate(
                prompt: prompt,
                operation: .lookupDetails,
                measure: .spend,
                mentions: [mention("May Budget", .budget, role: .primaryTarget)],
                responseShape: .relationshipList,
                requestShape: .relationshipList,
                semanticCommand: MarinaSemanticCommand(
                    family: .analytics,
                    action: .lookupDetails,
                    datasets: [.budgets],
                    measure: .spend,
                    includeFilters: [filter("May Budget", [.budget])],
                    requestedDetail: .linkedCards
                )
            )
        case "what is my actual income this month":
            return candidate(
                prompt: prompt,
                operation: .sum,
                measure: .income,
                timeScopes: [timeScope("this month", monthRange(2026, 5), .month)],
                responseShape: .summaryCard,
                semanticCommand: MarinaSemanticCommand(
                    family: .analytics,
                    action: .total,
                    datasets: [.income],
                    measure: .income,
                    dateRange: monthRange(2026, 5),
                    periodUnit: .month,
                    incomeStatusScope: .actual
                )
            )
        case "what did i spend at apple", "tell me about apple":
            return clarification(
                prompt: prompt,
                target: "Apple",
                operation: .sum,
                measure: .spend,
                choices: [
                    clarificationChoice(title: "Apple", rawValue: "Apple", type: .category),
                    clarificationChoice(title: "Apple", rawValue: "Apple", type: .merchant),
                    clarificationChoice(title: "Apple Card", rawValue: "Apple Card", type: .card)
                ]
            )
        case "show groceries":
            return clarification(
                prompt: prompt,
                target: "Groceries",
                operation: .sum,
                measure: .spend,
                choices: [
                    clarificationChoice(title: "Groceries", rawValue: "Groceries", type: .category),
                    clarificationChoice(title: "Groceries purchases", rawValue: "Groceries", type: .merchant)
                ]
            )
        case "where did my money go this month":
            return candidate(
                prompt: prompt,
                operation: .rank,
                measure: .spend,
                timeScopes: [timeScope("this month", monthRange(2026, 5), .month)],
                grouping: MarinaGroupingCandidate(dimension: .category, rawText: "category"),
                ranking: MarinaRankingCandidate(direction: .largest, limit: 5, rawText: "top"),
                limit: 5,
                responseShape: .rankedList
            )
        case "compare to last month", "compare this to last month":
            let target = context.priorQueryContext.lastTargetName?.trimmingCharacters(in: .whitespacesAndNewlines)
            return candidate(
                prompt: prompt,
                operation: .compare,
                measure: .spend,
                mentions: target.map { [mention($0, .category)] } ?? [],
                timeScopes: [
                    timeScope("this month", monthRange(2026, 5), .month),
                    timeScope("last month", monthRange(2026, 4), .month, role: .comparison)
                ],
                responseShape: .comparison
            )
        case "how much have i saved", "how much do i have in savings":
            return candidate(
                prompt: prompt,
                operation: .lookupDetails,
                measure: .savings,
                responseShape: .summaryCard,
                semanticCommand: MarinaSemanticCommand(
                    family: .analytics,
                    action: .lookupDetails,
                    datasets: [.savingsLedger],
                    measure: .savings,
                    requestedDetail: .balance
                )
            )
        case "what is my roommate balance", "show my roommate reconciliation account":
            return candidate(
                prompt: prompt,
                operation: .rank,
                measure: .reconciliationBalance,
                mentions: [mention("Roommate", .allocationAccount)],
                grouping: MarinaGroupingCandidate(dimension: .allocationAccount, rawText: "account"),
                ranking: MarinaRankingCandidate(direction: .largest, limit: 5, rawText: "balance"),
                responseShape: .summaryCard
            )
        case "show allocations this month":
            return candidate(
                prompt: prompt,
                operation: .rank,
                measure: .reconciliationBalance,
                timeScopes: [timeScope("this month", monthRange(2026, 5), .month)],
                grouping: MarinaGroupingCandidate(dimension: .allocationAccount, rawText: "allocations"),
                ranking: MarinaRankingCandidate(direction: .newest, limit: 10, rawText: "newest"),
                limit: 10,
                responseShape: .rankedList
            )
        default:
            return nil
        }
    }

    private func databaseLookup(
        prompt: String,
        searchText: String,
        objectTypes: [MarinaLookupObjectType],
        lookupMode: MarinaLookupMode = .broadSearch,
        requestShape: MarinaRequestShape? = nil
    ) -> MarinaCanonicalReadInterpretation {
        let request = MarinaDatabaseLookupRequest(
            rawPrompt: prompt,
            searchText: searchText,
            objectTypes: objectTypes,
            dateRange: nil,
            limit: 10,
            requestedDetail: .general,
            lookupMode: lookupMode
        )
        let candidate = MarinaQueryPlanCandidate(
            requestFamily: .databaseLookup,
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .lookupDetails,
            measure: .transactionAmount,
            responseShapeHint: .summaryCard,
            confidence: .high,
            databaseLookupRequest: request,
            requestShape: requestShape
        )
        return MarinaCanonicalReadInterpretation(
            result: adapter.interpretationResult(from: candidate),
            compatibilityCandidate: candidate
        )
    }

    private func candidate(
        prompt: String,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        mentions: [MarinaUnresolvedEntityMention] = [],
        timeScopes: [MarinaUnresolvedTimeScope] = [],
        grouping: MarinaGroupingCandidate? = nil,
        ranking: MarinaRankingCandidate? = nil,
        limit: Int? = nil,
        responseShape: MarinaResponseShapeHint? = nil,
        requestShape: MarinaRequestShape? = nil,
        semanticCommand: MarinaSemanticCommand? = nil
    ) -> MarinaCanonicalReadInterpretation {
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: operation,
            measure: measure,
            entityMentions: mentions,
            timeScopes: timeScopes,
            grouping: grouping,
            ranking: ranking,
            limit: limit,
            responseShapeHint: responseShape,
            confidence: .high,
            semanticCommand: semanticCommand,
            requestShape: requestShape
        )
        return MarinaCanonicalReadInterpretation(
            result: adapter.interpretationResult(from: candidate),
            compatibilityCandidate: candidate
        )
    }

    private func clarification(
        prompt: String,
        target: String,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        choices: [MarinaClarificationChoice]
    ) -> MarinaCanonicalReadInterpretation {
        let mentionID = UUID()
        let targetMention = MarinaUnresolvedEntityMention(
            id: mentionID,
            role: .filter,
            rawText: target,
            typeHint: nil,
            allowedTypeHints: [.category, .merchant, .card],
            confidence: .medium
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: operation,
            measure: measure,
            entityMentions: [targetMention],
            timeScopes: [],
            responseShapeHint: .clarification,
            confidence: .medium
        )
        let patchedChoices = choices.map { choice in
            MarinaClarificationChoice(
                id: choice.id,
                title: choice.title,
                subtitle: choice.subtitle,
                entityRole: choice.entityRole,
                entityTypeHint: choice.entityTypeHint,
                patchSlot: choice.patchSlot,
                rawValue: choice.rawValue,
                sourceID: choice.sourceID,
                mentionID: mentionID
            )
        }
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "I found more than one way to read that target.",
            candidate: candidate,
            patchSlot: .target,
            choices: patchedChoices
        )
        return MarinaCanonicalReadInterpretation(
            result: .clarification(clarification),
            compatibilityCandidate: candidate
        )
    }

    private func mention(
        _ rawText: String,
        _ typeHint: MarinaCandidateEntityTypeHint,
        role: MarinaEntityMentionRole = .filter
    ) -> MarinaUnresolvedEntityMention {
        MarinaUnresolvedEntityMention(
            role: role,
            rawText: rawText,
            typeHint: typeHint,
            allowedTypeHints: [typeHint],
            confidence: .high
        )
    }

    private func filter(
        _ rawText: String,
        _ allowedTypes: [MarinaCandidateEntityTypeHint]
    ) -> MarinaSemanticCommandFilter {
        MarinaSemanticCommandFilter(rawText: rawText, allowedTypes: allowedTypes)
    }

    private func clarificationChoice(
        title: String,
        rawValue: String,
        type: MarinaCandidateEntityTypeHint
    ) -> MarinaClarificationChoice {
        MarinaClarificationChoice(
            title: title,
            subtitle: type.rawValue,
            entityRole: .filter,
            entityTypeHint: type,
            patchSlot: .target,
            rawValue: rawValue
        )
    }

    private func timeScope(
        _ rawText: String,
        _ range: HomeQueryDateRange,
        _ periodUnit: HomeQueryPeriodUnit,
        role: MarinaTimeScopeRole = .primary
    ) -> MarinaUnresolvedTimeScope {
        MarinaUnresolvedTimeScope(
            role: role,
            rawText: rawText,
            resolvedRangeHint: range,
            periodUnitHint: periodUnit
        )
    }

    private func monthRange(_ year: Int, _ month: Int) -> HomeQueryDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let end = calendar.date(
            byAdding: DateComponents(month: 1, second: -1),
            to: start
        )!
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func canonicalPrompt(_ prompt: String) -> String {
        prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
#endif
