import Foundation

struct MarinaFoundationModelsInterpreter {
    private let structuredInterpreter: MarinaStructuredIntentInterpreting

    init(
        structuredInterpreter: MarinaStructuredIntentInterpreting = MarinaFoundationModelsService()
    ) {
        self.structuredInterpreter = structuredInterpreter
    }

    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaQueryPlanCandidate {
        let structuredIntent = try await structuredInterpreter.interpret(prompt: prompt, context: context)
        return candidate(
            from: structuredIntent,
            prompt: prompt,
            defaultPeriodUnit: context.defaultPeriodUnit
        )
    }

    func candidate(
        from structuredIntent: MarinaStructuredIntent,
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaQueryPlanCandidate {
        if case .semanticCommand(let command) = structuredIntent {
            return candidate(
                from: command,
                prompt: prompt
            )
        }

        switch structuredIntent {
        case .semanticCommand:
            return unsupportedCandidate(
                prompt: prompt,
                confidence: .low,
                unsupportedHint: .lowConfidence
            )
        case .query(let queryIntent):
            return candidate(
                from: queryIntent,
                prompt: prompt,
                defaultPeriodUnit: defaultPeriodUnit
            )
        case .command:
            return unsupportedCandidate(
                prompt: prompt,
                confidence: .medium,
                unsupportedHint: .unsupportedOperation
            )
        case .clarification(let clarification):
            return MarinaQueryPlanCandidate(
                source: .foundationModels,
                rawPrompt: prompt,
                responseShapeHint: .clarification,
                confidence: .medium,
                unsupportedHint: unsupportedHint(from: clarification)
            )
        case .unresolved:
            return unsupportedCandidate(
                prompt: prompt,
                confidence: .low,
                unsupportedHint: .lowConfidence
            )
        }
    }

    private func candidate(
        from command: MarinaSemanticCommand,
        prompt: String
    ) -> MarinaQueryPlanCandidate {
        let operation = operation(from: command.action)
        let measure = command.measure ?? measure(from: command)
        let responseShape = responseShapeHint(from: command, operation: operation, measure: measure)

        return MarinaQueryPlanCandidate(
            requestFamily: command.family,
            source: .foundationModels,
            rawPrompt: prompt,
            operation: operation,
            measure: measure,
            entityMentions: entityMentions(from: command),
            timeScopes: timeScopes(from: command),
            grouping: command.grouping.map { MarinaGroupingCandidate(dimension: $0) },
            ranking: ranking(from: command),
            limit: command.limit,
            responseShapeHint: responseShape,
            confidence: .high,
            semanticCommand: command
        )
    }

    private func operation(from action: MarinaSemanticCommandAction) -> MarinaCandidateOperation {
        switch action {
        case .total:
            return .sum
        case .listRows:
            return .listRows
        case .rank:
            return .rank
        case .group:
            return .sum
        case .compare:
            return .compare
        case .average:
            return .average
        case .simulate:
            return .simulate
        case .lookupDetails:
            return .lookupDetails
        }
    }

    private func measure(from command: MarinaSemanticCommand) -> MarinaCandidateMeasure? {
        switch command.action {
        case .listRows:
            return .transactionAmount
        case .simulate:
            return .remainingBudget
        case .rank, .group, .total, .compare, .average:
            if command.datasets.contains(.income) {
                return .income
            }
            if command.datasets.contains(.savingsLedger) {
                return .savingsMovement
            }
            if command.datasets.contains(.reconciliation) || command.datasets.contains(.expenseAllocations) {
                return .reconciliationBalance
            }
            return .spend
        case .lookupDetails:
            return nil
        }
    }

    private func entityMentions(from command: MarinaSemanticCommand) -> [MarinaUnresolvedEntityMention] {
        let includeMentions = command.includeFilters.map { filter in
            MarinaUnresolvedEntityMention(
                role: command.action == .simulate ? .simulationInput : .filter,
                rawText: filter.rawText,
                typeHint: filter.allowedTypes.count == 1 ? filter.allowedTypes[0] : nil,
                allowedTypeHints: filter.allowedTypes.isEmpty ? nil : filter.allowedTypes,
                confidence: .high
            )
        }
        let excludeMentions = command.excludeFilters.map { filter in
            MarinaUnresolvedEntityMention(
                role: .excludeFilter,
                rawText: filter.rawText,
                typeHint: filter.allowedTypes.count == 1 ? filter.allowedTypes[0] : nil,
                allowedTypeHints: filter.allowedTypes.isEmpty ? nil : filter.allowedTypes,
                confidence: .high
            )
        }
        return includeMentions + excludeMentions
    }

    private func timeScopes(from command: MarinaSemanticCommand) -> [MarinaUnresolvedTimeScope] {
        var scopes: [MarinaUnresolvedTimeScope] = []
        if let dateRange = command.dateRange {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: command.action == .average ? .lookbackWindow : .primary,
                    rawText: nil,
                    resolvedRangeHint: dateRange,
                    periodUnitHint: command.periodUnit
                )
            )
        }
        if let comparisonDateRange = command.comparisonDateRange {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: .comparison,
                    rawText: nil,
                    resolvedRangeHint: comparisonDateRange,
                    periodUnitHint: command.periodUnit
                )
            )
        }
        return scopes
    }

    private func ranking(from command: MarinaSemanticCommand) -> MarinaRankingCandidate? {
        switch command.action {
        case .rank:
            return MarinaRankingCandidate(
                direction: rankingDirection(from: command.sort) ?? .top,
                limit: command.limit
            )
        case .listRows:
            return MarinaRankingCandidate(direction: .newest, limit: command.limit)
        default:
            return nil
        }
    }

    private func rankingDirection(from sort: MarinaSemanticCommandSort?) -> MarinaRankingDirectionCandidate? {
        switch sort {
        case .newest:
            return .newest
        case .largest:
            return .largest
        case .deltaDescending, .groupedTotalDescending:
            return .top
        case nil:
            return nil
        }
    }

    private func responseShapeHint(
        from command: MarinaSemanticCommand,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure?
    ) -> MarinaResponseShapeHint? {
        switch command.action {
        case .listRows, .rank:
            return .rankedList
        case .group:
            return .groupedBreakdown
        case .compare:
            return .comparison
        case .simulate:
            return .summaryCard
        case .lookupDetails:
            return .summaryCard
        case .total, .average:
            return measure == .categoryShare ? .groupedBreakdown : .scalarCurrency
        }
    }

    private func lookupRequest(from command: MarinaSemanticCommand, prompt: String) -> MarinaDatabaseLookupRequest? {
        guard let filter = command.includeFilters.first else { return nil }
        let objectTypes = command.datasets.compactMap(lookupObjectType)
        return MarinaDatabaseLookupRequest(
            rawPrompt: prompt,
            searchText: filter.rawText,
            objectTypes: objectTypes.isEmpty ? [.unknown] : objectTypes,
            dateRange: command.dateRange,
            limit: min(max(command.limit ?? 5, 1), 10),
            requestedDetail: lookupRequestedDetail(from: command.requestedDetail)
        )
    }

    private func lookupObjectType(from dataset: MarinaSemanticCommandDataset) -> MarinaLookupObjectType? {
        switch dataset {
        case .variableExpenses:
            return .variableExpense
        case .plannedExpenses:
            return .plannedExpense
        case .income:
            return .income
        case .incomeSeries:
            return .incomeSeries
        case .cards:
            return .card
        case .categories:
            return .category
        case .presets:
            return .preset
        case .budgets:
            return .budget
        case .savingsLedger:
            return .savingsLedgerEntry
        case .reconciliation:
            return .reconciliationAccount
        case .expenseAllocations:
            return .expenseAllocation
        case .importMerchantRules:
            return .importMerchantRule
        case .assistantAliasRules:
            return .assistantAliasRule
        }
    }

    private func lookupRequestedDetail(from detail: MarinaSemanticRequestedDetail?) -> MarinaDatabaseLookupRequest.RequestedDetail {
        switch detail {
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
        case .general, nil:
            return .general
        }
    }

    private func candidate(
        from queryIntent: MarinaStructuredQueryIntent,
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaQueryPlanCandidate {
        let metric = normalizedMetric(from: queryIntent.metricRaw, targetTypeRaw: queryIntent.targetTypeRaw)
        let operation = operation(from: metric, queryIntent: queryIntent)
        let measure = measure(from: metric, queryIntent: queryIntent)
        let confidence = confidence(from: queryIntent.confidenceRaw)
        let unsupportedHint = unsupportedHint(
            metric: metric,
            metricRaw: queryIntent.metricRaw,
            confidence: confidence,
            clarification: queryIntent.clarification
        )

        return MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            operation: operation,
            measure: measure,
            entityMentions: entityMentions(from: queryIntent, metric: metric, confidence: confidence),
            timeScopes: timeScopes(from: queryIntent, metric: metric, defaultPeriodUnit: defaultPeriodUnit),
            grouping: grouping(from: metric),
            ranking: ranking(from: metric, limit: queryIntent.resultLimit),
            limit: queryIntent.resultLimit,
            responseShapeHint: responseShapeHint(
                operation: operation,
                measure: measure,
                unsupportedHint: unsupportedHint
            ),
            confidence: confidence,
            unsupportedHint: unsupportedHint
        )
    }

    private func unsupportedCandidate(
        prompt: String,
        confidence: MarinaCandidateConfidence,
        unsupportedHint: MarinaUnsupportedHint
    ) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: prompt,
            responseShapeHint: .unsupported,
            confidence: confidence,
            unsupportedHint: unsupportedHint
        )
    }

    private func shouldPreferAnalyticsOverLookup(_ prompt: String) -> Bool {
        let prompt = prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return prompt.contains(" by source")
            || prompt.contains(" by category")
            || prompt.contains(" by card")
            || prompt.contains("list my last")
            || prompt.contains(" my last ")
            || prompt.contains(" last ")
            || prompt.hasPrefix("most recent")
            || prompt.hasPrefix("latest")
            || prompt.hasPrefix("newest")
            || prompt.contains("most recent")
            || prompt.contains("latest")
            || prompt.contains("newest")
            || prompt.contains("top ")
            || prompt.contains("biggest")
            || prompt.contains("largest")
            || prompt.contains("most expensive")
            || prompt.contains("cost the most")
            || prompt.contains("compare ")
            || prompt.contains("total income")
            || prompt.contains("income came in")
            || prompt.contains("paid me the most")
            || prompt.contains("shared balances")
            || prompt.contains("savings movements")
    }

    private func normalizedMetric(
        from rawValue: String?,
        targetTypeRaw: String?
    ) -> HomeQueryMetric? {
        guard let rawValue = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawValue.isEmpty == false else {
            return nil
        }

        if let metric = HomeQueryMetric(rawValue: rawValue) {
            return metric
        }

        let normalized = rawValue
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        let normalizedTargetType = targetTypeRaw?.lowercased()

        if let metric = HomeQueryMetric(rawValue: normalized) {
            return metric
        }

        switch normalized {
        case "total_spent", "spend_total", "spending", "spent":
            return .spendTotal
        case "total_spent_on_groceries", "expenses_groceries_total":
            return normalizedTargetType == MarinaStructuredTargetType.category.rawValue
                ? .categorySpendTotal
                : .spendTotal
        case "merchant_spend_total", "merchant_total", "spend_at_merchant", "merchant_spending":
            return .merchantSpendTotal
        case "top_expense", "largest_expense", "biggest_expense", "top_transaction", "largest_transaction":
            return .largestTransactions
        case "top_merchants", "merchant_breakdown", "spending_by_merchant", "merchant_spend_breakdown":
            return .topMerchants
        case "spending_by_category", "category_breakdown", "where_money_goes", "money_going":
            return .topCategories
        case "average_spend", "spend_average", "average_spending":
            return .spendAveragePerPeriod
        default:
            return nil
        }
    }

    private func operation(
        from metric: HomeQueryMetric?,
        queryIntent: MarinaStructuredQueryIntent
    ) -> MarinaCandidateOperation? {
        if queryIntent.comparisonDateStartISO8601 != nil || queryIntent.comparisonDateEndISO8601 != nil {
            return .compare
        }

        switch metric {
        case .spendTotal, .categorySpendTotal, .cardSpendTotal, .merchantSpendTotal,
            .incomeSourceShare, .categorySpendShare, .presetDueSoon, .presetHighestCost,
            .presetTopCategory, .presetCategorySpend:
            return .sum
        case .spendAveragePerPeriod, .incomeAverageActual, .savingsAverageRecentPeriods:
            return .average
        case .mostFrequentTransactions:
            return .count
        case .monthComparison, .categoryMonthComparison, .cardMonthComparison,
            .incomeSourceMonthComparison, .merchantMonthComparison, .topCategoryChanges,
            .topCardChanges:
            return .compare
        case .topCategories, .topMerchants, .largestTransactions:
            return .rank
        case .incomeSourceShareTrend, .categorySpendShareTrend, .spendTrendsSummary:
            return .trend
        case .forecastSavings:
            return .forecast
        case .safeSpendToday, .savingsStatus, .nextPlannedExpense:
            return .lookupDetails
        case .overview, .cardVariableSpendingHabits, .categoryPotentialSavings, .categoryReallocationGuidance,
            .cardSnapshotSummary, .merchantSpendSummary, nil:
            return nil
        }
    }

    private func measure(
        from metric: HomeQueryMetric?,
        queryIntent: MarinaStructuredQueryIntent
    ) -> MarinaCandidateMeasure? {
        switch metric {
        case .incomeAverageActual, .incomeSourceShare, .incomeSourceShareTrend,
            .incomeSourceMonthComparison:
            return .income
        case .safeSpendToday:
            return .remainingBudget
        case .savingsStatus, .savingsAverageRecentPeriods, .forecastSavings:
            return .savings
        case .categorySpendShare, .categorySpendShareTrend:
            return .categoryShare
        case .largestTransactions:
            return .transactionAmount
        case .mostFrequentTransactions:
            return .transactionFrequency
        case .presetDueSoon, .presetHighestCost, .presetTopCategory, .presetCategorySpend,
            .nextPlannedExpense:
            return .presetAmount
        case .spendTotal, .categorySpendTotal, .topCategories, .monthComparison,
            .categoryMonthComparison, .cardMonthComparison, .merchantMonthComparison,
            .spendAveragePerPeriod, .cardSpendTotal, .cardVariableSpendingHabits,
            .merchantSpendTotal, .merchantSpendSummary, .topMerchants, .cardSnapshotSummary,
            .topCategoryChanges, .topCardChanges, .spendTrendsSummary, .categoryPotentialSavings,
            .categoryReallocationGuidance:
            return .spend
        case .overview, nil:
            return queryIntent.metricRaw == nil ? nil : .spend
        }
    }

    private func entityMentions(
        from queryIntent: MarinaStructuredQueryIntent,
        metric: HomeQueryMetric?,
        confidence: MarinaCandidateConfidence
    ) -> [MarinaUnresolvedEntityMention] {
        guard let targetName = queryIntent.targetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              targetName.isEmpty == false else {
            return []
        }

        return [
            MarinaUnresolvedEntityMention(
                role: entityMentionRole(from: metric, targetTypeRaw: queryIntent.targetTypeRaw),
                rawText: targetName,
                typeHint: entityTypeHint(from: queryIntent.targetTypeRaw, metric: metric),
                confidence: confidence
            )
        ]
    }

    private func entityMentionRole(
        from metric: HomeQueryMetric?,
        targetTypeRaw: String?
    ) -> MarinaEntityMentionRole {
        if metric == .cardSpendTotal || targetTypeRaw?.lowercased() == MarinaStructuredTargetType.card.rawValue {
            return .filter
        }
        return .primaryTarget
    }

    private func entityTypeHint(
        from targetTypeRaw: String?,
        metric: HomeQueryMetric?
    ) -> MarinaCandidateEntityTypeHint? {
        if let targetTypeRaw = targetTypeRaw?.lowercased(),
           let hint = entityTypeHint(from: targetTypeRaw) {
            return hint
        }

        switch metric {
        case .categorySpendTotal, .categoryMonthComparison, .categorySpendShare,
            .categorySpendShareTrend, .presetTopCategory, .presetCategorySpend,
            .categoryPotentialSavings, .categoryReallocationGuidance:
            return .category
        case .cardSpendTotal, .cardMonthComparison, .cardVariableSpendingHabits,
            .cardSnapshotSummary, .topCardChanges:
            return .card
        case .merchantSpendTotal, .merchantMonthComparison, .merchantSpendSummary:
            return .merchant
        case .incomeAverageActual, .incomeSourceMonthComparison, .incomeSourceShare,
            .incomeSourceShareTrend:
            return .incomeSource
        case .presetDueSoon, .presetHighestCost, .nextPlannedExpense:
            return .preset
        case .largestTransactions, .mostFrequentTransactions:
            return .transaction
        default:
            return nil
        }
    }

    private func entityTypeHint(from rawValue: String) -> MarinaCandidateEntityTypeHint? {
        switch rawValue {
        case MarinaStructuredTargetType.category.rawValue:
            return .category
        case MarinaStructuredTargetType.card.rawValue:
            return .card
        case MarinaStructuredTargetType.incomeSource.rawValue.lowercased():
            return .incomeSource
        case MarinaStructuredTargetType.merchant.rawValue:
            return .merchant
        case MarinaStructuredTargetType.budget.rawValue:
            return .budget
        case MarinaStructuredTargetType.preset.rawValue,
            MarinaStructuredTargetType.plannedExpense.rawValue.lowercased():
            return .preset
        case MarinaStructuredTargetType.expense.rawValue:
            return .expense
        case MarinaStructuredTargetType.income.rawValue:
            return .incomeSource
        default:
            return nil
        }
    }

    private func timeScopes(
        from queryIntent: MarinaStructuredQueryIntent,
        metric: HomeQueryMetric?,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> [MarinaUnresolvedTimeScope] {
        var scopes: [MarinaUnresolvedTimeScope] = []
        let periodUnit = HomeQueryPeriodUnit(rawValue: queryIntent.periodUnitRaw ?? "") ?? defaultPeriodUnit

        if let primaryRange = makeDateRange(
            start: queryIntent.dateStartISO8601,
            end: queryIntent.dateEndISO8601
        ) {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: isLookbackWindow(metric) ? .lookbackWindow : .primary,
                    rawText: nil,
                    resolvedRangeHint: primaryRange,
                    periodUnitHint: periodUnit
                )
            )
        }

        if let comparisonRange = makeDateRange(
            start: queryIntent.comparisonDateStartISO8601,
            end: queryIntent.comparisonDateEndISO8601
        ) {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: .comparison,
                    rawText: nil,
                    resolvedRangeHint: comparisonRange,
                    periodUnitHint: periodUnit
                )
            )
        }

        return scopes
    }

    private func isLookbackWindow(_ metric: HomeQueryMetric?) -> Bool {
        switch metric {
        case .spendAveragePerPeriod, .incomeAverageActual, .savingsAverageRecentPeriods:
            return true
        default:
            return false
        }
    }

    private func makeDateRange(start: String?, end: String?) -> HomeQueryDateRange? {
        guard let startDate = makeDate(start),
              let endDate = makeDate(end) else {
            return nil
        }
        return HomeQueryDateRange(startDate: startDate, endDate: endDate)
    }

    private func makeDate(_ value: String?) -> Date? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private func grouping(from metric: HomeQueryMetric?) -> MarinaGroupingCandidate? {
        switch metric {
        case .topCategories, .categorySpendShare, .categorySpendShareTrend,
            .topCategoryChanges:
            return MarinaGroupingCandidate(dimension: .category)
        case .topMerchants, .merchantSpendSummary:
            return MarinaGroupingCandidate(dimension: .merchant)
        case .largestTransactions, .mostFrequentTransactions:
            return MarinaGroupingCandidate(dimension: .transaction)
        case .incomeSourceShare, .incomeSourceShareTrend:
            return MarinaGroupingCandidate(dimension: .incomeSource)
        case .presetTopCategory, .presetCategorySpend:
            return MarinaGroupingCandidate(dimension: .preset)
        case .topCardChanges, .cardSnapshotSummary:
            return MarinaGroupingCandidate(dimension: .card)
        default:
            return nil
        }
    }

    private func ranking(
        from metric: HomeQueryMetric?,
        limit: Int?
    ) -> MarinaRankingCandidate? {
        switch metric {
        case .topCategories, .topMerchants, .topCategoryChanges, .topCardChanges:
            return MarinaRankingCandidate(direction: .top, limit: limit)
        case .largestTransactions, .presetHighestCost:
            return MarinaRankingCandidate(direction: .largest, limit: limit)
        case .mostFrequentTransactions:
            return MarinaRankingCandidate(direction: .mostFrequent, limit: limit)
        default:
            return nil
        }
    }

    private func responseShapeHint(
        operation: MarinaCandidateOperation?,
        measure: MarinaCandidateMeasure?,
        unsupportedHint: MarinaUnsupportedHint?
    ) -> MarinaResponseShapeHint? {
        if unsupportedHint != nil {
            return .unsupported
        }

        switch operation {
        case .compare:
            return .comparison
        case .rank:
            return .rankedList
        case .listRows:
            return .rankedList
        case .trend:
            return .chartRows
        case .sum:
            return measure == .categoryShare ? .groupedBreakdown : .scalarCurrency
        case .average, .count, .minimum, .maximum, .forecast:
            return .scalarCurrency
        case .lookupDetails, .simulate, nil:
            return nil
        }
    }

    private func unsupportedHint(
        metric: HomeQueryMetric?,
        metricRaw: String?,
        confidence: MarinaCandidateConfidence,
        clarification: MarinaStructuredClarification?
    ) -> MarinaUnsupportedHint? {
        if clarification?.isActionable == true {
            return .missingRequiredTarget
        }

        guard metric == nil else { return nil }
        return .unsupportedOperation
    }

    private func unsupportedHint(from clarification: MarinaStructuredClarification) -> MarinaUnsupportedHint {
        if clarification.missingFields.contains(where: isTargetField) {
            return .missingRequiredTarget
        }

        return .unsupportedOperation
    }

    private func isTargetField(_ field: MarinaStructuredMissingField) -> Bool {
        switch field {
        case .targetName, .cardName, .categoryName, .entityName, .source:
            return true
        case .date, .dateRange, .comparisonDateRange, .amount, .originalAmount, .notes, .updatedEntityName,
            .plannedExpenseAmountTarget, .recurrence, .intent:
            return false
        }
    }

    private func confidence(from rawValue: String?) -> MarinaCandidateConfidence {
        switch rawValue?.lowercased() {
        case MarinaCandidateConfidence.high.rawValue:
            return .high
        case MarinaCandidateConfidence.medium.rawValue:
            return .medium
        case MarinaCandidateConfidence.low.rawValue:
            return .low
        default:
            return .medium
        }
    }
}
