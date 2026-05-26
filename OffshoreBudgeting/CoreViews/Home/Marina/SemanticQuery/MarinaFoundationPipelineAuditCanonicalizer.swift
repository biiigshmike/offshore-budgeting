import Foundation

@MainActor
struct MarinaFoundationPipelineAuditCanonicalizer {
    static let generatedSchemaName = "MarinaPipelineAuditCanonicalizer"

    private let semanticAdapter = MarinaSemanticQueryAdapter()
    private var calendar: Calendar

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
        if self.calendar.timeZone.secondsFromGMT() == 0 {
            self.calendar.timeZone = .current
        }
    }

    func interpretation(
        prompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard MarinaRoutePatternRegistry.isReadOnlyStep5Mutation(prompt) == nil,
              MarinaMutationIntentGuard().isMutationPrompt(prompt) == false else {
            return nil
        }

        let normalizedPrompt = normalized(prompt)
        guard normalizedPrompt.isEmpty == false else { return nil }

        if let interpretation = cardActivityInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = cardInventoryInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt) {
            return interpretation
        }

        if let interpretation = presetCategoryCountInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = recordedPresetActualRowsInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = nextPlannedExpenseInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = cardSpendComparisonInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = recentCardExpenseRowsInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = allocatedCategorySpendInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = latestMerchantRowsInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = categorySpendInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = actualIncomeComparisonInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = budgetPeriodComparisonInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = cardSpendInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        if let interpretation = topCategorySpendInterpretation(prompt: prompt, normalizedPrompt: normalizedPrompt, context: context) {
            return interpretation
        }

        return nil
    }

    private func cardInventoryInterpretation(
        prompt: String,
        normalizedPrompt: String
    ) -> MarinaTurnInterpretation? {
        guard containsWord("card", in: normalizedPrompt) || containsWord("cards", in: normalizedPrompt) else { return nil }
        guard containsAnyWholePhrase(["how many", "count", "list", "show"], in: normalizedPrompt) else { return nil }
        guard containsAnyWholePhrase(["spend", "spending", "balance", "activity", "expense", "expenses"], in: normalizedPrompt) == false else {
            return nil
        }

        let isCount = containsAnyWholePhrase(["how many", "count"], in: normalizedPrompt)
        let query = MarinaSemanticQuery(
            subject: .cards,
            operation: isCount ? .count : .list,
            responseShape: isCount ? .summaryCard : .relationshipList,
            routeIntent: MarinaRouteIntent(
                kind: .generic,
                subject: .cards,
                operation: isCount ? .count : .listRows,
                measure: isCount ? .transactionFrequency : .transactionAmount,
                grouping: nil,
                targetTypes: [.card],
                requestedDetail: .general,
                responseShape: isCount ? .summaryCard : .relationshipList,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "cardInventory")
    }

    private func cardActivityInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsWord("activity", in: normalizedPrompt) else { return nil }
        guard let card = matchedCards(in: normalizedPrompt, provider: context.provider).first else { return nil }
        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .list,
            filters: [cardFilter(card, displayName: cardDisplayName(card, in: normalizedPrompt))],
            amountField: .budgetImpactAmount,
            grouping: MarinaGrouping(dimension: .transaction, rawText: "activity"),
            ranking: MarinaRanking(direction: .newest, limit: 10, rawText: "activity"),
            limit: 10,
            responseShape: .rankedList,
            requestedDetail: .card,
            routeIntent: MarinaRouteIntent(
                kind: .recentTransactionRows,
                subject: .variableExpenses,
                operation: .listRows,
                measure: .transactionAmount,
                grouping: .transaction,
                targetTypes: [.card],
                requestedDetail: .card,
                responseShape: .rankedList,
                preferredExecutorRoute: .composableWorkspace
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "cardActivity")
    }

    private func topCategorySpendInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsWord("category", in: normalizedPrompt) || containsWord("categories", in: normalizedPrompt) else { return nil }
        guard containsAnyWholePhrase(["top", "highest", "largest", "biggest", "most"], in: normalizedPrompt) else { return nil }
        guard containsAnyWholePhrase(["preset", "presets", "assigned"], in: normalizedPrompt) == false else { return nil }

        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .rank,
            amountField: .budgetImpactAmount,
            dateRange: dateRequest(prompt: prompt, context: context, defaultPolicy: .currentPeriod),
            grouping: MarinaGrouping(dimension: .category, rawText: "category"),
            ranking: MarinaRanking(direction: .top, limit: 1, rawText: "top"),
            limit: 1,
            responseShape: .rankedList,
            routeIntent: MarinaRouteIntent(
                kind: .generic,
                subject: .variableExpenses,
                operation: .rank,
                measure: .spend,
                grouping: .category,
                targetTypes: [.category],
                requestedDetail: .amount,
                responseShape: .rankedList,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "topCategorySpend")
    }

    private func nextPlannedExpenseInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsWord("preset", in: normalizedPrompt)
                || containsWord("presets", in: normalizedPrompt)
                || containsWholePhrase("planned expense", in: normalizedPrompt)
                || containsWholePhrase("planned expenses", in: normalizedPrompt) else {
            return nil
        }
        guard containsAnyWholePhrase(["due next", "next due", "due", "upcoming", "next"], in: normalizedPrompt) else {
            return nil
        }

        let query = MarinaSemanticQuery(
            subject: .plannedExpenses,
            operation: .list,
            amountField: .effectivePlannedAmount,
            dateRange: dateRequest(prompt: prompt, context: context, defaultPolicy: .none),
            grouping: MarinaGrouping(dimension: .transaction, rawText: "planned expense"),
            ranking: MarinaRanking(direction: .newest, limit: 1, rawText: "due next"),
            limit: 1,
            responseShape: .rankedList,
            requestedDetail: .date,
            routeIntent: MarinaRouteIntent(
                kind: .plannedExpenseRows,
                subject: .plannedExpenses,
                operation: .listRows,
                measure: .presetAmount,
                grouping: .transaction,
                targetTypes: [.preset, .category, .card],
                requestedDetail: .date,
                responseShape: .rankedList,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "nextPlannedExpense")
    }

    private func recordedPresetActualRowsInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsWord("preset", in: normalizedPrompt) || containsWord("presets", in: normalizedPrompt) else { return nil }
        guard containsWholePhrase("actual amount", in: normalizedPrompt)
                || (containsWord("actual", in: normalizedPrompt) && containsAnyWholePhrase(["greater than 0", "over 0", "recorded"], in: normalizedPrompt)) else {
            return nil
        }

        let query = MarinaSemanticQuery(
            subject: .plannedExpenses,
            operation: .list,
            amountField: .actualAmount,
            dateRange: dateRequest(prompt: prompt, context: context, defaultPolicy: .currentPeriod),
            grouping: MarinaGrouping(dimension: .preset, rawText: "preset"),
            ranking: MarinaRanking(direction: .newest, limit: explicitLimit(in: normalizedPrompt) ?? 10, rawText: "actual amount"),
            limit: explicitLimit(in: normalizedPrompt) ?? 10,
            responseShape: .rankedList,
            requestedDetail: .amount,
            routeIntent: MarinaRouteIntent(
                kind: .generic,
                subject: .plannedExpenses,
                operation: .listRows,
                measure: .presetAmount,
                grouping: .preset,
                targetTypes: [.preset],
                requestedDetail: .amount,
                responseShape: .rankedList,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "recordedPresetActualRows")
    }

    private func presetCategoryCountInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context _: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsWord("category", in: normalizedPrompt) || containsWord("categories", in: normalizedPrompt) else { return nil }
        guard containsWord("preset", in: normalizedPrompt) || containsWord("presets", in: normalizedPrompt) else { return nil }
        guard containsAnyWholePhrase(["most", "assigned", "has the most"], in: normalizedPrompt) else { return nil }

        let query = MarinaSemanticQuery(
            subject: .presets,
            operation: .rank,
            grouping: MarinaGrouping(dimension: .category, rawText: "preset category"),
            ranking: MarinaRanking(direction: .mostFrequent, limit: 1, rawText: "most presets"),
            limit: 1,
            responseShape: .rankedList,
            requestedDetail: .linkedObjects,
            routeIntent: MarinaRouteIntent(
                kind: .generic,
                subject: .presets,
                operation: .rank,
                measure: .presetAmount,
                grouping: .category,
                targetTypes: [.category],
                requestedDetail: .linkedObjects,
                responseShape: .rankedList,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "presetCategoryCounts")
    }

    private func cardSpendInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsAnyWholePhrase(["spend", "spending", "spent"], in: normalizedPrompt) else { return nil }
        guard let card = matchedCards(in: normalizedPrompt, provider: context.provider).first else { return nil }
        guard containsWholePhrase("compare", in: normalizedPrompt) == false else { return nil }

        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .sum,
            filters: [cardFilter(card)],
            amountField: .budgetImpactAmount,
            dateRange: dateRequest(prompt: prompt, context: context, defaultPolicy: .currentPeriod),
            responseShape: .scalarCurrency,
            routeIntent: MarinaRouteIntent(
                kind: .generic,
                subject: .variableExpenses,
                operation: .sum,
                measure: .spend,
                grouping: nil,
                targetTypes: [.card],
                requestedDetail: .amount,
                responseShape: .scalarCurrency,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "cardSpend")
    }

    private func cardSpendComparisonInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsWholePhrase("compare", in: normalizedPrompt) else { return nil }
        guard containsAnyWholePhrase(["spend", "spending", "spent"], in: normalizedPrompt) else { return nil }
        let cards = Array(matchedCards(in: normalizedPrompt, provider: context.provider).prefix(2))
        guard cards.count == 2 else { return nil }

        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .compare,
            filters: [
                cardFilter(cards[0], role: .primaryTarget),
                cardFilter(cards[1], role: .comparisonTarget)
            ],
            amountField: .budgetImpactAmount,
            dateRange: dateRequest(prompt: prompt, context: context, defaultPolicy: .currentPeriod),
            grouping: MarinaGrouping(dimension: .card, rawText: "card"),
            responseShape: .comparison,
            routeIntent: MarinaRouteIntent(
                kind: .generic,
                subject: .variableExpenses,
                operation: .compare,
                measure: .spend,
                grouping: .card,
                targetTypes: [.card],
                requestedDetail: .amount,
                responseShape: .comparison,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "cardSpendComparison")
    }

    private func recentCardExpenseRowsInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        let asksForRows = containsAnyWholePhrase(["expense", "expenses", "transaction", "transactions", "purchase", "purchases", "activity"], in: normalizedPrompt)
        guard asksForRows else { return nil }
        guard containsAnyWholePhrase(["recent", "newest", "latest", "list", "show", "activity"], in: normalizedPrompt) else { return nil }
        guard let card = matchedCards(in: normalizedPrompt, provider: context.provider).first else { return nil }
        let limit = explicitLimit(in: normalizedPrompt) ?? 5

        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .list,
            filters: [cardFilter(card)],
            amountField: .budgetImpactAmount,
            dateRange: dateRequest(prompt: prompt, context: context, defaultPolicy: .none),
            grouping: MarinaGrouping(dimension: .transaction, rawText: "transaction"),
            ranking: MarinaRanking(direction: .newest, limit: limit, rawText: "recent"),
            limit: limit,
            responseShape: .rankedList,
            requestedDetail: .card,
            routeIntent: MarinaRouteIntent(
                kind: .recentTransactionRows,
                subject: .variableExpenses,
                operation: .listRows,
                measure: .transactionAmount,
                grouping: .transaction,
                targetTypes: [.card],
                requestedDetail: .card,
                responseShape: .rankedList,
                preferredExecutorRoute: .composableWorkspace
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "recentCardExpenseRows")
    }

    private func categorySpendInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsAnyWholePhrase(["spend", "spending", "spent"], in: normalizedPrompt) else { return nil }
        guard containsAnyWholePhrase(["sum", "total", "how much", "what is"], in: normalizedPrompt) else { return nil }
        guard containsWholePhrase("compare", in: normalizedPrompt) == false else { return nil }
        guard let category = matchedCategories(in: normalizedPrompt, provider: context.provider).first else { return nil }
        guard matchedAllocationAccounts(in: normalizedPrompt, provider: context.provider).isEmpty else { return nil }

        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .sum,
            filters: [categoryFilter(category)],
            amountField: .budgetImpactAmount,
            dateRange: dateRequest(prompt: prompt, context: context, defaultPolicy: .currentPeriod),
            responseShape: .summaryCard,
            routeIntent: MarinaRouteIntent(
                kind: .broadSpend,
                subject: .variableExpenses,
                operation: .sum,
                measure: .spend,
                grouping: nil,
                targetTypes: [.category],
                requestedDetail: .amount,
                responseShape: .summaryCard,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "categorySpend")
    }

    private func latestMerchantRowsInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsAnyWholePhrase(["last", "latest", "recent"], in: normalizedPrompt) else { return nil }
        guard containsAnyWholePhrase(["shopping at", "shop at", "go shopping at", "at"], in: normalizedPrompt) else { return nil }
        guard let merchant = merchantSearchText(from: prompt) else { return nil }

        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .list,
            filters: [
                MarinaFilter(
                    role: .filter,
                    relationship: .merchant,
                    value: merchant,
                    matchMode: .freeText,
                    entityTypeHint: .merchant,
                    allowedEntityTypeHints: [.merchant, .expense, .transaction]
                )
            ],
            amountField: .budgetImpactAmount,
            grouping: MarinaGrouping(dimension: .transaction, rawText: "transaction"),
            ranking: MarinaRanking(direction: .newest, limit: 1, rawText: "last"),
            limit: 1,
            responseShape: .rankedList,
            requestedDetail: .date,
            routeIntent: MarinaRouteIntent(
                kind: .recentTransactionRows,
                subject: .variableExpenses,
                operation: .listRows,
                measure: .transactionAmount,
                grouping: .transaction,
                targetTypes: [.merchant, .expense, .transaction],
                requestedDetail: .date,
                responseShape: .rankedList,
                preferredExecutorRoute: .list
            )
        )
        _ = context
        return makeInterpretation(query: query, prompt: prompt, traceName: "latestMerchantRows")
    }

    private func allocatedCategorySpendInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsAnyWholePhrase(["spend", "spent"], in: normalizedPrompt) else { return nil }
        guard let account = matchedAllocationAccounts(in: normalizedPrompt, provider: context.provider).first,
              let category = matchedCategories(in: normalizedPrompt, provider: context.provider).first else {
            return nil
        }

        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .sum,
            filters: [
                allocationAccountFilter(account),
                categoryFilter(category)
            ],
            amountField: .allocatedAmount,
            dateRange: dateRequest(prompt: prompt, context: context, defaultPolicy: .currentPeriod),
            responseShape: .summaryCard,
            routeIntent: MarinaRouteIntent(
                kind: .broadSpend,
                subject: .variableExpenses,
                operation: .sum,
                measure: .spend,
                grouping: nil,
                targetTypes: [.allocationAccount, .category],
                requestedDetail: .amount,
                responseShape: .summaryCard,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "allocatedCategorySpend")
    }

    private func actualIncomeComparisonInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsWord("income", in: normalizedPrompt) else { return nil }
        guard containsWholePhrase("compare", in: normalizedPrompt) || containsAnyWholePhrase(["up or down", "higher", "lower"], in: normalizedPrompt) else {
            return nil
        }
        guard containsWord("actual", in: normalizedPrompt) else { return nil }

        let ranges = comparisonDateRequests(prompt: prompt, context: context)
        let query = MarinaSemanticQuery(
            subject: .income,
            operation: .compare,
            amountField: .incomeAmount,
            dateRange: ranges.primary,
            comparisonDateRange: ranges.comparison,
            incomeStatusScope: .actual,
            responseShape: .comparison,
            routeIntent: MarinaRouteIntent(
                kind: .generic,
                subject: .income,
                operation: .compare,
                measure: .income,
                grouping: nil,
                targetTypes: [.incomeSource],
                requestedDetail: .amount,
                responseShape: .comparison,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "actualIncomeComparison")
    }

    private func budgetPeriodComparisonInterpretation(
        prompt: String,
        normalizedPrompt: String,
        context: MarinaTurnContext
    ) -> MarinaTurnInterpretation? {
        guard containsWord("budget", in: normalizedPrompt),
              containsWord("period", in: normalizedPrompt),
              containsWholePhrase("compare", in: normalizedPrompt) else {
            return nil
        }

        let active = activeBudgets(provider: context.provider, now: context.now)
        guard active.count == 1, let budget = active.first else {
            return budgetPeriodClarification(prompt: prompt, budgets: active)
        }

        let current = HomeQueryDateRange(startDate: budget.startDate, endDate: budget.endDate)
        let previous = previousAdjacentRange(to: current)
        let query = MarinaSemanticQuery(
            subject: .variableExpenses,
            operation: .compare,
            amountField: .budgetImpactAmount,
            dateRange: MarinaDateRangeRequest(role: .primary, rawText: budget.name, resolvedRange: current, periodUnit: context.defaultPeriodUnit),
            comparisonDateRange: MarinaDateRangeRequest(role: .comparison, rawText: "last period", resolvedRange: previous, periodUnit: context.defaultPeriodUnit),
            responseShape: .comparison,
            routeIntent: MarinaRouteIntent(
                kind: .generic,
                subject: .budgets,
                operation: .compare,
                measure: .spend,
                grouping: nil,
                targetTypes: [.budget],
                requestedDetail: .status,
                responseShape: .comparison,
                preferredExecutorRoute: .workspaceAggregation
            )
        )
        return makeInterpretation(query: query, prompt: prompt, traceName: "budgetPeriodComparison")
    }

    private func makeInterpretation(
        query: MarinaSemanticQuery,
        prompt: String,
        traceName: String
    ) -> MarinaTurnInterpretation {
        MarinaTurnInterpretation(
            result: .query(query),
            compatibilityCandidate: semanticAdapter.compatibilityCandidate(
                from: query,
                prompt: prompt,
                source: .deterministic
            ),
            repairSummary: "pipelineAudit=\(traceName)",
            generatedSchemaName: Self.generatedSchemaName
        )
    }

    private func budgetPeriodClarification(
        prompt: String,
        budgets: [Budget]
    ) -> MarinaTurnInterpretation? {
        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: prompt,
            operation: .compare,
            measure: .spend,
            responseShapeHint: .clarification,
            confidence: .high
        )
        let choices = budgets.prefix(8).map { budget in
            MarinaClarificationChoice(
                title: budget.name,
                subtitle: rangeLabel(HomeQueryDateRange(startDate: budget.startDate, endDate: budget.endDate)),
                entityRole: .primaryTarget,
                entityTypeHint: .budget,
                patchSlot: .target,
                rawValue: budget.name,
                sourceID: budget.id
            )
        }
        return MarinaTurnInterpretation(
            result: .clarification(
                MarinaTypedClarification(
                    kind: budgets.isEmpty ? .missingTarget : .ambiguousTarget,
                    message: budgets.isEmpty
                        ? "I need an active budget period before I can compare it."
                        : "Which budget period should I compare?",
                    candidate: candidate,
                    patchSlot: .target,
                    choices: choices
                )
            ),
            compatibilityCandidate: candidate,
            repairSummary: "pipelineAudit=budgetPeriodComparisonClarification",
            generatedSchemaName: Self.generatedSchemaName
        )
    }

    private enum DateDefaultPolicy {
        case none
        case currentPeriod
    }

    private func dateRequest(
        prompt: String,
        context: MarinaTurnContext,
        defaultPolicy: DateDefaultPolicy
    ) -> MarinaDateRangeRequest? {
        if let explicit = MarinaDateRangeTextResolver(
            calendar: calendar,
            nowProvider: { context.now }
        ).resolve(prompt, defaultPeriodUnit: context.defaultPeriodUnit) {
            return MarinaDateRangeRequest(
                role: .primary,
                rawText: prompt,
                resolvedRange: explicit,
                periodUnit: context.defaultPeriodUnit
            )
        }

        guard defaultPolicy == .currentPeriod else { return nil }
        return MarinaDateRangeRequest(
            role: .primary,
            rawText: "current \(context.defaultPeriodUnit.rawValue)",
            resolvedRange: currentPeriodRange(containing: context.now, unit: context.defaultPeriodUnit),
            periodUnit: context.defaultPeriodUnit
        )
    }

    private func comparisonDateRequests(
        prompt: String,
        context: MarinaTurnContext
    ) -> (primary: MarinaDateRangeRequest, comparison: MarinaDateRangeRequest) {
        let normalizedPrompt = normalized(prompt)
        let primary: MarinaDateRangeRequest
        if containsAnyWholePhrase(["this month", "current month", "this period", "current period"], in: normalizedPrompt) {
            primary = MarinaDateRangeRequest(
                role: .primary,
                rawText: "current \(context.defaultPeriodUnit.rawValue)",
                resolvedRange: currentPeriodRange(containing: context.now, unit: context.defaultPeriodUnit),
                periodUnit: context.defaultPeriodUnit
            )
        } else {
            primary = dateRequest(prompt: prompt, context: context, defaultPolicy: .currentPeriod)
                ?? MarinaDateRangeRequest(
                    role: .primary,
                    rawText: "current \(context.defaultPeriodUnit.rawValue)",
                    resolvedRange: currentPeriodRange(containing: context.now, unit: context.defaultPeriodUnit),
                    periodUnit: context.defaultPeriodUnit
                )
        }
        let comparisonRange = previousEquivalentRange(to: primary.resolvedRange ?? currentPeriodRange(containing: context.now, unit: context.defaultPeriodUnit), unit: context.defaultPeriodUnit)
        let comparison = MarinaDateRangeRequest(
            role: .comparison,
            rawText: "previous \(context.defaultPeriodUnit.rawValue)",
            resolvedRange: comparisonRange,
            periodUnit: context.defaultPeriodUnit
        )
        return (primary, comparison)
    }

    private func cardFilter(
        _ card: Card,
        role: MarinaResolvedTargetRole = .filter,
        displayName: String? = nil
    ) -> MarinaFilter {
        MarinaFilter(
            role: role,
            relationship: .card,
            value: displayName ?? card.name,
            matchMode: .exact,
            entityTypeHint: .card,
            allowedEntityTypeHints: [.card],
            sourceID: card.id
        )
    }

    private func cardDisplayName(_ card: Card, in normalizedPrompt: String) -> String {
        let normalizedName = normalized(card.name)
        let cardPhrase = "\(normalizedName) card"
        if containsWholePhrase(cardPhrase, in: normalizedPrompt) {
            return "\(card.name) Card"
        }
        return card.name
    }

    private func categoryFilter(_ category: Category) -> MarinaFilter {
        MarinaFilter(
            role: .filter,
            relationship: .category,
            value: category.name,
            matchMode: .exact,
            entityTypeHint: .category,
            allowedEntityTypeHints: [.category],
            sourceID: category.id
        )
    }

    private func allocationAccountFilter(_ account: AllocationAccount) -> MarinaFilter {
        MarinaFilter(
            role: .filter,
            relationship: .allocationAccount,
            value: account.name,
            matchMode: .exact,
            entityTypeHint: .allocationAccount,
            allowedEntityTypeHints: [.allocationAccount],
            sourceID: account.id
        )
    }

    private func matchedCards(
        in normalizedPrompt: String,
        provider: MarinaDataProvider
    ) -> [Card] {
        provider.fetchAllCards()
            .filter { containsWholePhrase(normalized($0.name), in: normalizedPrompt) }
            .sorted { $0.name.count > $1.name.count }
    }

    private func matchedCategories(
        in normalizedPrompt: String,
        provider: MarinaDataProvider
    ) -> [Category] {
        provider.fetchAllCategories()
            .filter { containsWholePhrase(normalized($0.name), in: normalizedPrompt) }
            .sorted { $0.name.count > $1.name.count }
    }

    private func matchedAllocationAccounts(
        in normalizedPrompt: String,
        provider: MarinaDataProvider
    ) -> [AllocationAccount] {
        provider.fetchAllAllocationAccounts()
            .filter { containsWholePhrase(normalized($0.name), in: normalizedPrompt) }
            .sorted { $0.name.count > $1.name.count }
    }

    private func merchantSearchText(from prompt: String) -> String? {
        let cleaned = prompt
            .replacingOccurrences(of: #"(?i)^.*\b(?:shopping at|shop at|go shopping at|at)\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)\b(?:this month|last month|this week|last week|today|yesterday|current period|for the current period)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[?!.]+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.isEmpty == false,
              normalized(cleaned).split(separator: " ").count <= 5 else {
            return nil
        }
        return cleaned
    }

    private func activeBudgets(
        provider: MarinaDataProvider,
        now: Date
    ) -> [Budget] {
        let day = calendar.startOfDay(for: now)
        return provider.fetchAllBudgets()
            .filter { calendar.startOfDay(for: $0.startDate) <= day && calendar.startOfDay(for: $0.endDate) >= day }
            .sorted { lhs, rhs in
                if lhs.startDate != rhs.startDate { return lhs.startDate < rhs.startDate }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func currentPeriodRange(
        containing date: Date,
        unit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange {
        let component: Calendar.Component
        switch unit {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .quarter:
            return quarterRange(containing: date)
        case .year:
            component = .year
        }
        guard let interval = calendar.dateInterval(of: component, for: date) else {
            return HomeQueryDateRange(startDate: calendar.startOfDay(for: date), endDate: date)
        }
        return HomeQueryDateRange(startDate: interval.start, endDate: interval.end.addingTimeInterval(-1))
    }

    private func quarterRange(containing date: Date) -> HomeQueryDateRange {
        let components = calendar.dateComponents([.year, .month], from: date)
        let month = components.month ?? 1
        let quarterStartMonth = ((month - 1) / 3) * 3 + 1
        let start = calendar.date(from: DateComponents(year: components.year, month: quarterStartMonth, day: 1)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 3, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousEquivalentRange(
        to range: HomeQueryDateRange,
        unit: HomeQueryPeriodUnit
    ) -> HomeQueryDateRange {
        let component: Calendar.Component
        switch unit {
        case .day:
            component = .day
        case .week:
            component = .weekOfYear
        case .month:
            component = .month
        case .quarter:
            component = .month
        case .year:
            component = .year
        }
        let value = unit == .quarter ? -3 : -1
        let start = calendar.date(byAdding: component, value: value, to: range.startDate) ?? range.startDate
        let end = calendar.date(byAdding: component, value: value, to: range.endDate) ?? range.endDate
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousAdjacentRange(to range: HomeQueryDateRange) -> HomeQueryDateRange {
        let duration = range.endDate.timeIntervalSince(range.startDate)
        let previousEnd = range.startDate.addingTimeInterval(-1)
        let previousStart = previousEnd.addingTimeInterval(-duration)
        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }

    private func explicitLimit(in normalizedPrompt: String) -> Int? {
        normalizedPrompt
            .split(separator: " ")
            .compactMap { Int($0) }
            .filter { $0 > 0 }
            .first
    }

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        AppDateFormat.shortDate(date)
    }

    private func containsAnyWholePhrase(_ phrases: [String], in normalizedPrompt: String) -> Bool {
        phrases.contains { containsWholePhrase($0, in: normalizedPrompt) }
    }

    private func containsWord(_ word: String, in normalizedPrompt: String) -> Bool {
        containsWholePhrase(word, in: normalizedPrompt)
    }

    private func containsWholePhrase(_ phrase: String, in normalizedPrompt: String) -> Bool {
        guard phrase.isEmpty == false else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: phrase)
        return normalizedPrompt.range(of: #"(?<![a-z0-9])\#(escaped)(?![a-z0-9])"#, options: .regularExpression) != nil
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: #"([a-z0-9&])'s\b"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
