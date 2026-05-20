import Foundation

struct MarinaLiveIntentNormalizer {
    private let semanticAdapter = MarinaSemanticQueryAdapter()

    func normalized(
        _ interpretation: MarinaCanonicalReadInterpretation,
        prompt: String,
        context: MarinaLanguageRouterContext,
        defaultPeriodUnit _: HomeQueryPeriodUnit
    ) -> MarinaCanonicalReadInterpretation {
        var repairs: [String] = []

        if shouldRecoverIncomeQuery(interpretation: interpretation, prompt: prompt) {
            repairs.append("recoveredGenericIncomeIntent")
            return incomeInterpretation(
                prompt: prompt,
                status: inferredIncomeStatus(from: prompt) ?? .all,
                repairSummary: summary(repairs, prior: interpretation.repairSummary)
            )
        }

        var candidate = interpretation.compatibilityCandidate
        let filteredMentions = candidate.entityMentions.filter { mention in
            isGenericSubjectTarget(
                rawText: mention.rawText,
                typeHint: mention.typeHint,
                context: context
            ) == false
        }
        if filteredMentions.count != candidate.entityMentions.count {
            repairs.append("droppedGenericEntityTarget")
            candidate = copy(
                candidate,
                entityMentions: filteredMentions
            )
        }

        if let command = candidate.semanticCommand {
            let normalizedCommand = normalized(
                command,
                prompt: prompt,
                context: context,
                repairs: &repairs
            )
            if normalizedCommand != command {
                candidate = copy(candidate, semanticCommand: normalizedCommand)
            }
        }

        var result = interpretation.result
        if case .query(let query) = result {
            let normalizedQuery = normalized(
                query,
                prompt: prompt,
                context: context,
                repairs: &repairs
            )
            result = .query(normalizedQuery)
        } else if candidate != interpretation.compatibilityCandidate {
            result = semanticAdapter.interpretationResult(from: candidate)
        }

        let repairSummary = summary(repairs, prior: interpretation.repairSummary)
        guard repairSummary != interpretation.repairSummary || candidate != interpretation.compatibilityCandidate || result != interpretation.result else {
            return interpretation
        }

        return MarinaCanonicalReadInterpretation(
            result: result,
            compatibilityCandidate: candidate,
            repairSummary: repairSummary
        )
    }

    private func shouldRecoverIncomeQuery(
        interpretation: MarinaCanonicalReadInterpretation,
        prompt: String
    ) -> Bool {
        let normalizedPrompt = normalizedText(prompt)
        guard normalizedPrompt.contains("income") else { return false }

        switch interpretation.result {
        case .clarification(let clarification):
            return clarification.choices.count <= 1
        case .unsupported:
            return false
        case .query:
            return false
        }
    }

    private func incomeInterpretation(
        prompt: String,
        status: MarinaIncomeStatusScope,
        repairSummary: String?
    ) -> MarinaCanonicalReadInterpretation {
        let command = MarinaSemanticCommand(
            family: .analytics,
            action: .total,
            datasets: [.income],
            measure: .income,
            incomeStatusScope: status,
            requestedDetail: .amount
        )
        let candidate = MarinaQueryPlanCandidate(
            requestFamily: .analytics,
            source: .foundationModels,
            rawPrompt: prompt,
            operation: .sum,
            measure: .income,
            responseShapeHint: .scalarCurrency,
            confidence: .medium,
            semanticCommand: command
        )
        return MarinaCanonicalReadInterpretation(
            result: semanticAdapter.interpretationResult(from: candidate),
            compatibilityCandidate: candidate,
            repairSummary: repairSummary
        )
    }

    private func normalized(
        _ command: MarinaSemanticCommand,
        prompt: String,
        context: MarinaLanguageRouterContext,
        repairs: inout [String]
    ) -> MarinaSemanticCommand {
        var includeFilters = command.includeFilters.filter { filter in
            isGenericSubjectTarget(
                rawText: filter.rawText,
                typeHint: filter.allowedTypes.first,
                context: context
            ) == false
        }
        if includeFilters.count != command.includeFilters.count {
            repairs.append("droppedGenericCommandFilter")
        }

        let excludeFilters = command.excludeFilters.filter { filter in
            isGenericSubjectTarget(
                rawText: filter.rawText,
                typeHint: filter.allowedTypes.first,
                context: context
            ) == false
        }
        if excludeFilters.count != command.excludeFilters.count {
            repairs.append("droppedGenericExcludeFilter")
        }

        var action = command.action
        var measure = command.measure
        var grouping = command.grouping
        var sort = command.sort
        var limit = command.limit
        var incomeStatus = command.incomeStatusScope
        var requestedDetail = command.requestedDetail

        if command.datasets.contains(.income), incomeStatus == nil,
           let inferred = inferredIncomeStatus(from: prompt) {
            incomeStatus = inferred
            repairs.append("incomeStatus=\(inferred.rawValue)")
        }

        if isRecentRowsPrompt(prompt), action != .listRows {
            action = .listRows
            sort = sort ?? .newest
            limit = limit ?? 5
            measure = measure ?? .transactionAmount
            grouping = grouping ?? .transaction
            includeFilters = includeFilters.filter { isGenericIncomeText($0.rawText) == false }
            repairs.append("recentRowsIntent")
        }

        if requestedDetail == nil, let detail = inferredRequestedDetail(from: prompt) {
            requestedDetail = detail
            repairs.append("detail=\(detail.rawValue)")
        }

        return MarinaSemanticCommand(
            family: command.family,
            action: action,
            datasets: command.datasets,
            measure: measure,
            includeFilters: includeFilters,
            excludeFilters: excludeFilters,
            grouping: grouping,
            sort: sort,
            dateRange: command.dateRange,
            comparisonDateRange: command.comparisonDateRange,
            periodUnit: command.periodUnit,
            limit: limit,
            incomeStatusScope: incomeStatus,
            requestedDetail: requestedDetail,
            insightIntent: command.insightIntent,
            softTimeHint: command.softTimeHint
        )
    }

    private func normalized(
        _ query: MarinaSemanticQuery,
        prompt: String,
        context: MarinaLanguageRouterContext,
        repairs: inout [String]
    ) -> MarinaSemanticQuery {
        let filters = query.filters.filter { filter in
            isGenericSubjectTarget(
                rawText: filter.value,
                typeHint: filter.entityTypeHint,
                context: context
            ) == false
        }
        if filters.count != query.filters.count {
            repairs.append("droppedGenericSemanticFilter")
        }

        let incomeStatus: MarinaIncomeStatusScope?
        if query.subject == .income, query.incomeStatusScope == nil,
           let inferred = inferredIncomeStatus(from: prompt) {
            incomeStatus = inferred
            repairs.append("semanticIncomeStatus=\(inferred.rawValue)")
        } else {
            incomeStatus = query.incomeStatusScope
        }

        let requestedDetail = query.requestedDetail ?? inferredRequestedDetail(from: prompt)
        if query.requestedDetail == nil, requestedDetail != nil {
            repairs.append("semanticDetail=\(requestedDetail?.rawValue ?? "nil")")
        }

        return MarinaSemanticQuery(
            id: query.id,
            subject: query.subject,
            operation: query.operation,
            filters: filters,
            amountField: query.amountField,
            dateRange: query.dateRange,
            comparisonDateRange: query.comparisonDateRange,
            grouping: query.grouping,
            ranking: query.ranking,
            limit: query.limit,
            averageBasis: query.averageBasis,
            incomeStatusScope: incomeStatus,
            responseShape: query.responseShape,
            requestedDetail: requestedDetail,
            routeIntent: query.routeIntent
        )
    }

    private func inferredIncomeStatus(from prompt: String) -> MarinaIncomeStatusScope? {
        let normalized = normalizedText(prompt)
        if normalized.contains("actual income")
            || normalized.contains("received income")
            || normalized.contains("income received")
            || normalized.contains("income so far") {
            return .actual
        }
        if normalized.contains("planned income")
            || normalized.contains("expected income")
            || normalized.contains("projected income") {
            return .planned
        }
        return nil
    }

    private func inferredRequestedDetail(from prompt: String) -> MarinaSemanticRequestedDetail? {
        let normalized = normalizedText(prompt)
        if normalized.contains("linked cards") || normalized.contains("cards linked") {
            return .linkedCards
        }
        if normalized.contains("linked presets") || normalized.contains("presets linked") {
            return .linkedPresets
        }
        if normalized.contains("category limits")
            || normalized.contains("category limit")
            || normalized.contains("budget limit")
            || normalized.contains("limit") {
            return .categoryLimits
        }
        if normalized.contains("balance") {
            return .balance
        }
        if normalized.contains("status") {
            return .status
        }
        if normalized.contains("linked to") || normalized.contains("belongs to") {
            return .membership
        }
        return nil
    }

    private func isRecentRowsPrompt(_ prompt: String) -> Bool {
        let normalized = normalizedText(prompt)
        return normalized.contains("recent")
            || normalized.contains("latest")
            || normalized.contains("last transaction")
            || normalized.contains("last purchase")
            || normalized.contains("newest")
    }

    private func isGenericSubjectTarget(
        rawText: String?,
        typeHint: MarinaCandidateEntityTypeHint?,
        context: MarinaLanguageRouterContext
    ) -> Bool {
        guard let rawText else { return false }
        let normalized = normalizedText(rawText)
        guard normalized.isEmpty == false else { return false }
        if isKnownEntityName(normalized, context: context) {
            return false
        }

        switch typeHint {
        case .incomeSource:
            return isGenericIncomeText(normalized)
        case .savingsAccount:
            return ["savings", "saving", "savings account", "actual savings"].contains(normalized)
        case .budget:
            return ["budget", "active budget", "current budget", "remaining budget"].contains(normalized)
        case .allocationAccount:
            return ["reconciliation", "reconciliation balance", "allocation", "allocation account"].contains(normalized)
        case .merchant, .expense, .transaction:
            return ["spending", "spend", "expense", "expenses", "transaction", "transactions", "purchase", "purchases"].contains(normalized)
        case .category:
            return ["category", "categories", "uncategorized"].contains(normalized)
        case .card:
            return ["card", "cards"].contains(normalized)
        case .preset:
            return ["preset", "presets", "planned expense", "planned expenses"].contains(normalized)
        case .workspace:
            return ["workspace", "workspaces"].contains(normalized)
        case nil:
            return [
                "income", "actual income", "planned income", "received income", "expected income",
                "savings", "budget", "spending", "expenses", "transactions", "reconciliation"
            ].contains(normalized)
        }
    }

    private func isGenericIncomeText(_ rawText: String?) -> Bool {
        guard let rawText else { return false }
        return isGenericIncomeText(normalizedText(rawText))
    }

    private func isGenericIncomeText(_ normalized: String) -> Bool {
        [
            "income",
            "actual income",
            "planned income",
            "expected income",
            "projected income",
            "received income",
            "income source"
        ].contains(normalized)
    }

    private func isKnownEntityName(
        _ normalized: String,
        context: MarinaLanguageRouterContext
    ) -> Bool {
        let names = context.cardNames
            + context.categoryNames
            + context.incomeSourceNames
            + context.presetTitles
            + context.budgetNames
        return names.contains { normalizedText($0) == normalized }
    }

    private func copy(
        _ candidate: MarinaQueryPlanCandidate,
        entityMentions: [MarinaUnresolvedEntityMention]? = nil,
        semanticCommand: MarinaSemanticCommand? = nil
    ) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            requestFamily: candidate.requestFamily,
            source: candidate.source,
            rawPrompt: candidate.rawPrompt,
            operation: candidate.operation,
            measure: candidate.measure,
            entityMentions: entityMentions ?? candidate.entityMentions,
            timeScopes: candidate.timeScopes,
            grouping: candidate.grouping,
            ranking: candidate.ranking,
            limit: candidate.limit,
            responseShapeHint: candidate.responseShapeHint,
            confidence: candidate.confidence,
            unsupportedHint: candidate.unsupportedHint,
            databaseLookupRequest: candidate.databaseLookupRequest,
            semanticCommand: semanticCommand ?? candidate.semanticCommand,
            requestShape: candidate.requestShape,
            insightIntent: candidate.insightIntent,
            softTimeHint: candidate.softTimeHint
        )
    }

    private func summary(_ repairs: [String], prior: String?) -> String? {
        let merged = [prior]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            + repairs.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return merged.isEmpty ? nil : merged.joined(separator: ";")
    }

    private func normalizedText(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
