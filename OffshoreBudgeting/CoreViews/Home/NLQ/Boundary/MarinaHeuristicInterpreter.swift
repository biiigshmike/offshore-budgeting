import Foundation

struct MarinaHeuristicInterpreter {
    private let normalize: (String, HomeQueryPeriodUnit) -> NormalizedQueryIntent
    private let now: () -> Date

    init(
        normalize: @escaping (String, HomeQueryPeriodUnit) -> NormalizedQueryIntent = { prompt, defaultPeriodUnit in
            MarinaNLQNormalizer(defaultPeriodUnit: defaultPeriodUnit).normalize(prompt: prompt)
        },
        now: @escaping () -> Date = Date.init
    ) {
        self.normalize = normalize
        self.now = now
    }

    func interpret(
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaQueryPlanCandidate {
        let intent = normalize(prompt, defaultPeriodUnit)
        if shouldPreferAnalyticsOverLookup(prompt) == false,
           let lookupRequest = MarinaDatabaseLookupDetector().detect(
            prompt: prompt,
            defaultPeriodUnit: defaultPeriodUnit
        ) {
            return MarinaQueryPlanCandidate(
                requestFamily: .databaseLookup,
                source: .heuristic,
                rawPrompt: prompt,
                limit: lookupRequest.limit,
                confidence: .high,
                databaseLookupRequest: lookupRequest
            )
        }

        let protectedShape = protectedShape(from: intent)
        let unsupportedHint = protectedShape?.unsupportedHint ?? unsupportedHint(from: intent.unsupportedShapeReason)
        let operation = protectedShape?.operation ?? operation(from: intent)
        let measure = protectedShape?.measure ?? measure(from: intent)

        return MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: prompt,
            operation: operation,
            measure: measure,
            entityMentions: entityMentions(from: intent, operation: operation, protectedShape: protectedShape),
            timeScopes: timeScopes(from: intent, defaultPeriodUnit: defaultPeriodUnit, protectedShape: protectedShape),
            grouping: protectedShape != nil ? protectedShape?.grouping : grouping(from: intent),
            ranking: protectedShape != nil ? protectedShape?.ranking : ranking(from: intent, operation: operation),
            limit: intent.resultLimit,
            responseShapeHint: protectedShape?.responseShapeHint ?? responseShapeHint(from: intent, operation: operation),
            confidence: confidence(from: intent, protectedShape: protectedShape),
            unsupportedHint: unsupportedHint
        )
    }

    private func operation(from intent: NormalizedQueryIntent) -> MarinaCandidateOperation? {
        if intent.unsupportedShapeReason == .whatIfSimulation {
            return .simulate
        }

        if intent.comparisonDateRange != nil
            || intent.modifiers.contains("comparison")
            || intent.normalizedMetric == .monthComparison
            || intent.normalizedMetric == .categoryMonthComparison {
            return .compare
        }

        switch intent.normalizedMetric {
        case .spendAveragePerPeriod, .incomeAverageActual:
            return .average
        case .topCategories, .topMerchants, .largestTransactions, .mostFrequentTransactions:
            return .rank
        case .categorySpendShare:
            return .sum
        case .spendTotal, .categorySpendTotal, .merchantSpendTotal, .categoryMonthComparison, .monthComparison, .presetDueSoon:
            return .sum
        case nil:
            switch intent.queryShape.measure {
            case .spendAverage, .incomeAverage:
                return .average
            case .transactionFrequency:
                return .count
            case .spendTotal:
                return intent.queryShape.ranking == nil ? .sum : .rank
            case .presetStatus, nil:
                return nil
            }
        }
    }

    private func measure(from intent: NormalizedQueryIntent) -> MarinaCandidateMeasure? {
        if intent.unsupportedShapeReason == .whatIfSimulation {
            return .remainingBudget
        }

        switch intent.normalizedMetric {
        case .incomeAverageActual:
            return .income
        case .categorySpendShare:
            return .categoryShare
        case .largestTransactions:
            return .transactionAmount
        case .mostFrequentTransactions:
            return .transactionFrequency
        case .presetDueSoon:
            return .presetAmount
        case .spendTotal, .categorySpendTotal, .merchantSpendTotal, .topCategories, .topMerchants,
            .monthComparison, .categoryMonthComparison, .spendAveragePerPeriod:
            return .spend
        case nil:
            switch intent.queryShape.measure {
            case .incomeAverage:
                return .income
            case .transactionFrequency:
                return .transactionFrequency
            case .presetStatus:
                return .presetAmount
            case .spendTotal, .spendAverage:
                return .spend
            case nil:
                return nil
            }
        }
    }

    private func entityMentions(
        from intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?,
        protectedShape: ProtectedShape?
    ) -> [MarinaUnresolvedEntityMention] {
        if let mentions = protectedShape?.entityMentions {
            return mentions
        }

        guard let rawTargetText = intent.rawTargetText?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawTargetText.isEmpty == false else {
            return []
        }

        if shouldSuppressUnscopedRankingTarget(rawTargetText, intent: intent, operation: operation)
            || shouldSuppressSyntheticBroadTarget(rawTargetText, intent: intent, operation: operation) {
            return []
        }

        let typeHint = entityTypeHint(from: intent, operation: operation, rawTargetText: rawTargetText)
        let cleanedRawText = cleanEntitySpan(
            rawTargetText,
            operation: operation,
            typeHint: typeHint,
            intent: intent
        )

        if shouldDropEntityMentionAfterCleanup(cleanedRawText, intent: intent, operation: operation) {
            return []
        }

        return [
            MarinaUnresolvedEntityMention(
                role: entityMentionRole(from: intent),
                rawText: cleanedRawText,
                typeHint: typeHint,
                confidence: confidence(from: intent, protectedShape: protectedShape)
            )
        ]
    }

    private func shouldSuppressUnscopedRankingTarget(
        _ rawTargetText: String,
        intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?
    ) -> Bool {
        guard operation == .rank, grouping(from: intent) != nil else { return false }
        return normalized(rawTargetText) == normalized(intent.rawPrompt)
    }

    private func shouldSuppressSyntheticBroadTarget(
        _ rawTargetText: String,
        intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?
    ) -> Bool {
        guard operation == .sum || operation == .rank else { return false }
        let normalizedTarget = normalized(rawTargetText)
        let broadScaffoldingPrefixes = [
            "how much have i spent",
            "what s my total spending",
            "what is my total spending",
            "how much money went out",
            "show me what i spent",
            "where did most of my money go",
            "where is most of my money going",
            "who did i pay the most",
            "what stores did i spend the most at"
        ]
        let orphanScaffoldingTokens: Set<String> = ["what", "who", "where", "how", "how much"]
        if orphanScaffoldingTokens.contains(normalizedTarget) {
            return true
        }
        return broadScaffoldingPrefixes.contains { prefix in
            normalizedTarget == prefix || normalizedTarget.hasPrefix(prefix + " ")
        }
    }

    private func entityMentionRole(from intent: NormalizedQueryIntent) -> MarinaEntityMentionRole {
        if isCardSpendFilter(intent) {
            return .filter
        }
        return .primaryTarget
    }

    private func entityTypeHint(
        from intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?,
        rawTargetText: String
    ) -> MarinaCandidateEntityTypeHint? {
        let normalizedPrompt = normalized(intent.rawPrompt)
        if operation == .sum || operation == .compare {
            let categoryLikePrompt =
                normalizedPrompt.contains("went to ")
                || normalizedPrompt.contains("spend in ")
                || normalizedPrompt.contains("spent in ")
                || normalizedPrompt.contains("cost me")
                || normalizedPrompt.contains("higher or lower on ")
                || normalizedPrompt.contains("portion of my money")
                || normalizedPrompt.contains("how much of my money went to")
            if categoryLikePrompt {
                return .category
            }
        }

        if operation == .compare,
           intent.normalizedMetric == .monthComparison {
            let prompt = normalizedPrompt
            if prompt.hasPrefix("compare "),
               prompt.contains("category") == false,
               prompt.contains("grocer") == false,
               prompt.contains("food & drink") == false,
               prompt.contains("transportation") == false {
                if prompt.contains(" at ") || prompt.contains(" with ") || prompt.contains("merchant") || prompt.contains("store") {
                    return .merchant
                }
                if normalized(rawTargetText).contains("card") || prompt.contains(" card ") {
                    return .card
                }
                return nil
            }
        }

        if intent.comparisonDateRange != nil,
           intent.normalizedMetric == .monthComparison,
           intent.queryShape.grouping == .some(.merchant) {
            return nil
        }

        switch intent.queryShape.grouping {
        case .some(.category):
            return .category
        case .some(.merchant):
            return .merchant
        case .some(.preset):
            return .preset
        case .some(.incomeSource):
            return .incomeSource
        case .some(.transaction):
            return .transaction
        case .some(.none):
            if isCardSpendFilter(intent) {
                return .card
            }
            return nil
        case nil:
            break
        }

        switch intent.normalizedMetric {
        case .categorySpendTotal, .categorySpendShare, .categoryMonthComparison:
            return .category
        case .merchantSpendTotal:
            return .merchant
        case .incomeAverageActual:
            return .incomeSource
        case .presetDueSoon:
            return .preset
        case .largestTransactions, .mostFrequentTransactions:
            return .transaction
        case .spendTotal, .topCategories, .topMerchants, .monthComparison, .spendAveragePerPeriod, nil:
            return isCardSpendFilter(intent) ? .card : nil
        }
    }

    private func isCardSpendFilter(_ intent: NormalizedQueryIntent) -> Bool {
        let target = intent.rawTargetText?.lowercased() ?? ""
        guard target.contains("card") else { return false }
        return intent.normalizedMetric == .spendTotal || intent.queryShape.grouping == .some(.none)
    }

    private func timeScopes(
        from intent: NormalizedQueryIntent,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        protectedShape: ProtectedShape? = nil
    ) -> [MarinaUnresolvedTimeScope] {
        if let scopes = protectedShape?.timeScopes {
            return scopes
        }

        return baseTimeScopes(from: intent, defaultPeriodUnit: defaultPeriodUnit)
    }

    private func baseTimeScopes(
        from intent: NormalizedQueryIntent,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> [MarinaUnresolvedTimeScope] {
        var scopes: [MarinaUnresolvedTimeScope] = []

        if let dateRange = intent.dateRange {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: isLookbackWindow(intent) ? .lookbackWindow : .primary,
                    rawText: nil,
                    resolvedRangeHint: dateRange,
                    periodUnitHint: defaultPeriodUnit
                )
            )
        }

        if let comparisonDateRange = intent.comparisonDateRange {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: .comparison,
                    rawText: nil,
                    resolvedRangeHint: comparisonDateRange,
                    periodUnitHint: defaultPeriodUnit
                )
            )
        }

        if intent.unsupportedShapeReason == .whatIfSimulation, scopes.isEmpty {
            scopes.append(
                MarinaUnresolvedTimeScope(
                    role: .simulationHorizon,
                    rawText: nil,
                    periodUnitHint: defaultPeriodUnit
                )
            )
        }

        return scopes
    }

    private func isLookbackWindow(_ intent: NormalizedQueryIntent) -> Bool {
        intent.normalizedMetric == .spendAveragePerPeriod
            || intent.normalizedMetric == .incomeAverageActual
            || intent.queryShape.measure == .spendAverage
            || intent.queryShape.measure == .incomeAverage
    }

    private func grouping(from intent: NormalizedQueryIntent) -> MarinaGroupingCandidate? {
        switch intent.queryShape.grouping {
        case .some(.category):
            return MarinaGroupingCandidate(dimension: .category)
        case .some(.merchant):
            return MarinaGroupingCandidate(dimension: .merchant)
        case .some(.preset):
            return MarinaGroupingCandidate(dimension: .preset)
        case .some(.incomeSource):
            return MarinaGroupingCandidate(dimension: .incomeSource)
        case .some(.transaction):
            return MarinaGroupingCandidate(dimension: .transaction)
        case .some(.none), nil:
            break
        }

        switch intent.normalizedMetric {
        case .topCategories, .categorySpendShare:
            return MarinaGroupingCandidate(dimension: .category)
        case .topMerchants:
            return MarinaGroupingCandidate(dimension: .merchant)
        default:
            return nil
        }
    }

    private func ranking(
        from intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?
    ) -> MarinaRankingCandidate? {
        let direction: MarinaRankingDirectionCandidate?

        switch intent.queryShape.ranking {
        case .top:
            direction = .top
        case .bottom:
            direction = .bottom
        case .largest:
            direction = .largest
        case .smallest:
            direction = .smallest
        case .mostFrequent:
            direction = .mostFrequent
        case .leastFrequent:
            direction = .leastFrequent
        case nil:
            switch intent.normalizedMetric {
            case .topCategories, .topMerchants:
                direction = .top
            case .largestTransactions:
                direction = .largest
            case .mostFrequentTransactions:
                direction = .mostFrequent
            default:
                direction = nil
            }
        }

        guard let direction, operation == .rank else { return nil }
        return MarinaRankingCandidate(direction: direction, limit: intent.resultLimit)
    }

    private func responseShapeHint(
        from intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?
    ) -> MarinaResponseShapeHint? {
        if intent.unsupportedShapeReason != nil {
            return .unsupported
        }

        switch operation {
        case .compare:
            return .comparison
        case .rank:
            return .rankedList
        case .sum, .average, .count:
            if intent.normalizedMetric == .categorySpendShare || intent.modifiers.contains("breakdown_by_category") {
                return .groupedBreakdown
            }
            return .scalarCurrency
        case .minimum, .maximum, .trend, .forecast, .simulate, nil:
            return nil
        }
    }

    private func unsupportedHint(from reason: MarinaUnsupportedShapeReason?) -> MarinaUnsupportedHint? {
        switch reason {
        case .whatIfSimulation:
            return .unsupportedSimulation
        case .rankedAverage, .targetedAverage, .unsupportedCombination:
            return .unsupportedCombination
        case nil:
            return nil
        }
    }

    private func confidence(
        from intent: NormalizedQueryIntent,
        protectedShape: ProtectedShape? = nil
    ) -> MarinaCandidateConfidence {
        if protectedShape != nil {
            return .medium
        }

        if intent.confidenceLevel == .low,
           intent.normalizedMetric != nil,
           intent.rawTargetText == nil,
           intent.dateRange != nil,
           intent.unsupportedShapeReason == nil {
            return .medium
        }

        switch intent.confidenceLevel {
        case .high:
            return .high
        case .medium:
            return .medium
        case .low:
            return .low
        }
    }

    private func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldPreferAnalyticsOverLookup(_ prompt: String) -> Bool {
        let prompt = normalized(prompt)
        return prompt.contains(" by source")
            || prompt.contains(" by category")
            || prompt.contains(" by card")
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

    private func protectedShape(from intent: NormalizedQueryIntent) -> ProtectedShape? {
        let prompt = normalized(intent.rawPrompt)

        if isProjectionPrompt(prompt) {
            return ProtectedShape(
                operation: .forecast,
                measure: .remainingBudget,
                entityMentions: [],
                responseShapeHint: .unsupported,
                unsupportedHint: .unsupportedProjection
            )
        }

        if isSimulationPrompt(prompt) {
            return ProtectedShape(
                operation: .simulate,
                measure: .remainingBudget,
                entityMentions: simulationMentions(from: prompt),
                responseShapeHint: .unsupported,
                unsupportedHint: .unsupportedSimulation
            )
        }

        if isBroadIncomeComparisonPrompt(prompt) {
            return ProtectedShape(
                operation: .compare,
                measure: .income,
                entityMentions: [],
                timeScopes: comparisonTimeScopes(from: prompt, intent: intent),
                responseShapeHint: .comparison
            )
        }

        if isIncomeSourceRankingPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .income,
                entityMentions: [],
                timeScopes: baseTimeScopes(from: intent, defaultPeriodUnit: .month),
                grouping: MarinaGroupingCandidate(dimension: .incomeSource),
                ranking: MarinaRankingCandidate(direction: .top, limit: intent.resultLimit),
                responseShapeHint: .summaryCard
            )
        }

        if isIncomeSummaryPrompt(prompt) {
            return ProtectedShape(
                operation: .sum,
                measure: .income,
                entityMentions: [],
                timeScopes: baseTimeScopes(from: intent, defaultPeriodUnit: .month),
                responseShapeHint: .summaryCard
            )
        }

        if isPlannedExpensesByCategoryPrompt(prompt) {
            return ProtectedShape(
                operation: .sum,
                measure: .presetAmount,
                entityMentions: [],
                timeScopes: baseTimeScopes(from: intent, defaultPeriodUnit: .month),
                grouping: MarinaGroupingCandidate(dimension: .category),
                responseShapeHint: .summaryCard
            )
        }

        if isPlannedExpensesByCardPrompt(prompt) {
            return ProtectedShape(
                operation: .sum,
                measure: .presetAmount,
                entityMentions: [],
                timeScopes: baseTimeScopes(from: intent, defaultPeriodUnit: .month),
                grouping: MarinaGroupingCandidate(dimension: .card),
                responseShapeHint: .summaryCard
            )
        }

        if isHighestCostPresetPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .presetAmount,
                entityMentions: [],
                grouping: MarinaGroupingCandidate(dimension: .preset),
                ranking: MarinaRankingCandidate(direction: .largest, limit: intent.resultLimit),
                responseShapeHint: .summaryCard
            )
        }

        if isUpcomingBillRankingPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .presetAmount,
                entityMentions: [],
                timeScopes: baseTimeScopes(from: intent, defaultPeriodUnit: .month),
                grouping: MarinaGroupingCandidate(dimension: .transaction),
                ranking: MarinaRankingCandidate(direction: .largest, limit: intent.resultLimit),
                responseShapeHint: .summaryCard
            )
        }

        if isSavingsMovementPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .savingsMovement,
                entityMentions: [],
                timeScopes: baseTimeScopes(from: intent, defaultPeriodUnit: .month),
                grouping: MarinaGroupingCandidate(dimension: .savingsLedgerEntry),
                ranking: MarinaRankingCandidate(direction: .largest, limit: intent.resultLimit),
                responseShapeHint: .summaryCard
            )
        }

        if isSharedBalancePrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .reconciliationBalance,
                entityMentions: [],
                grouping: MarinaGroupingCandidate(dimension: .allocationAccount),
                ranking: MarinaRankingCandidate(direction: .largest, limit: intent.resultLimit),
                responseShapeHint: .summaryCard
            )
        }

        if isExclusionPrompt(prompt) {
            return ProtectedShape(
                operation: .sum,
                measure: .spend,
                entityMentions: exclusionMentions(from: prompt),
                responseShapeHint: .unsupported,
                unsupportedHint: .unsupportedExclusionFilter
            )
        }

        if isBudgetLimitPrompt(prompt) {
            return ProtectedShape(
                operation: .compare,
                measure: .remainingBudget,
                entityMentions: categoryMention(from: budgetLimitTarget(in: prompt)),
                timeScopes: comparisonTimeScopes(from: prompt, intent: intent),
                responseShapeHint: .unsupported,
                unsupportedHint: .unsupportedBudgetLimit
            )
        }

        if isTransactionDeltaDriversPrompt(prompt) {
            return ProtectedShape(
                operation: .compare,
                measure: .spend,
                entityMentions: [],
                timeScopes: comparisonTimeScopes(from: prompt, intent: intent),
                grouping: MarinaGroupingCandidate(dimension: .transaction),
                ranking: MarinaRankingCandidate(direction: .largest),
                responseShapeHint: .rankedList,
                unsupportedHint: .unsupportedRankedComparison
            )
        }

        if isCategoryDeltaRankingPrompt(prompt) {
            return ProtectedShape(
                operation: .compare,
                measure: .spend,
                entityMentions: [],
                timeScopes: comparisonTimeScopes(from: prompt, intent: intent),
                grouping: MarinaGroupingCandidate(dimension: .category),
                ranking: MarinaRankingCandidate(direction: .largest),
                responseShapeHint: .rankedList,
                unsupportedHint: .unsupportedRankedComparison
            )
        }

        if isCardRankingPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .spend,
                entityMentions: [],
                grouping: MarinaGroupingCandidate(dimension: .card),
                ranking: MarinaRankingCandidate(direction: .top),
                responseShapeHint: .rankedList,
                unsupportedHint: .unsupportedCardRanking
            )
        }

        if isBreakdownPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .spend,
                entityMentions: [],
                grouping: MarinaGroupingCandidate(dimension: .category),
                ranking: MarinaRankingCandidate(direction: .top),
                responseShapeHint: .groupedBreakdown
            )
        }

        if isBroadMerchantRankingPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .spend,
                entityMentions: [],
                grouping: MarinaGroupingCandidate(dimension: .merchant),
                ranking: MarinaRankingCandidate(direction: .top, limit: intent.resultLimit),
                responseShapeHint: .rankedList
            )
        }

        if isLargestTransactionsPhrasePrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .transactionAmount,
                entityMentions: [],
                grouping: MarinaGroupingCandidate(dimension: .transaction),
                ranking: MarinaRankingCandidate(direction: .largest, limit: intent.resultLimit),
                responseShapeHint: .rankedList
            )
        }

        if isSharePrompt(prompt),
           let target = shareTarget(in: prompt) {
            return ProtectedShape(
                operation: .sum,
                measure: .categoryShare,
                entityMentions: categoryMention(from: target),
                grouping: MarinaGroupingCandidate(dimension: .category),
                responseShapeHint: .groupedBreakdown
            )
        }

        if isFrequencyRankingPrompt(prompt) {
            return ProtectedShape(
                operation: .rank,
                measure: .transactionFrequency,
                entityMentions: [],
                grouping: MarinaGroupingCandidate(dimension: .transaction),
                ranking: MarinaRankingCandidate(direction: .mostFrequent),
                responseShapeHint: .rankedList
            )
        }

        if isCardComparisonPrompt(prompt),
           let target = cardComparisonTarget(in: prompt) {
            return ProtectedShape(
                operation: .compare,
                measure: .spend,
                entityMentions: [
                    MarinaUnresolvedEntityMention(
                        role: .primaryTarget,
                        rawText: target,
                        typeHint: .card,
                        confidence: .medium
                    )
                ],
                timeScopes: comparisonTimeScopes(from: prompt, intent: intent),
                grouping: MarinaGroupingCandidate(dimension: .card),
                responseShapeHint: .comparison
            )
        }

        if isMessyCategoryComparisonPrompt(prompt),
           let target = comparisonTarget(in: prompt) {
            return ProtectedShape(
                operation: .compare,
                measure: .spend,
                entityMentions: categoryMention(from: target),
                timeScopes: comparisonTimeScopes(from: prompt, intent: intent),
                grouping: MarinaGroupingCandidate(dimension: .category),
                responseShapeHint: .comparison
            )
        }

        return nil
    }

    private func isProjectionPrompt(_ prompt: String) -> Bool {
        prompt.contains("keep spending like this")
            && prompt.contains("left")
            && prompt.contains("end of the period")
    }

    private func isSimulationPrompt(_ prompt: String) -> Bool {
        (prompt.hasPrefix("if i add") || prompt.hasPrefix("if i increase"))
            && prompt.contains("does")
            && prompt.contains("still have room")
    }

    private func isExclusionPrompt(_ prompt: String) -> Bool {
        prompt.contains(" outside of ")
    }

    private func isIncomeSummaryPrompt(_ prompt: String) -> Bool {
        prompt.contains("income came in")
            || prompt.contains("what income")
            || prompt.contains("income did i get")
            || prompt.contains("got paid")
            || prompt.contains("deposited")
    }

    private func isIncomeSourceRankingPrompt(_ prompt: String) -> Bool {
        (prompt.contains("paid me") && (prompt.contains("most") || prompt.contains("top")))
            || prompt.contains("income by source")
            || prompt.contains("income coming from")
            || prompt.contains("top income")
    }

    private func isBroadIncomeComparisonPrompt(_ prompt: String) -> Bool {
        (prompt.contains("compare income") || prompt.contains("income change") || prompt.contains("income this month"))
            && (prompt.contains("last month") || prompt.contains("compare"))
    }

    private func isUpcomingBillRankingPrompt(_ prompt: String) -> Bool {
        (prompt.contains("upcoming") || prompt.contains("due soon") || prompt.contains("coming up"))
            && (prompt.contains("bill") || prompt.contains("bills") || prompt.contains("planned expense") || prompt.contains("planned expenses"))
            || ((prompt.contains("biggest") || prompt.contains("largest")) && (prompt.contains("bill") || prompt.contains("planned expense")))
    }

    private func isHighestCostPresetPrompt(_ prompt: String) -> Bool {
        (prompt.contains("preset") || prompt.contains("recurring payment"))
            && (prompt.contains("cost the most") || prompt.contains("most expensive") || prompt.contains("highest"))
    }

    private func isPlannedExpensesByCategoryPrompt(_ prompt: String) -> Bool {
        prompt.contains("planned expenses by category")
            || prompt.contains("planned expense by category")
            || ((prompt.contains("bills by category") || prompt.contains("bill by category")) && prompt.contains("category"))
    }

    private func isPlannedExpensesByCardPrompt(_ prompt: String) -> Bool {
        prompt.contains("planned expenses by card")
            || prompt.contains("planned expense by card")
            || prompt.contains("bills by card")
    }

    private func isSavingsMovementPrompt(_ prompt: String) -> Bool {
        prompt.contains("largest savings movement")
            || prompt.contains("biggest savings movement")
            || prompt.contains("savings movements")
            || (prompt.contains("what changed") && prompt.contains("savings"))
            || (prompt.contains("savings") && prompt.contains("activity"))
    }

    private func isSharedBalancePrompt(_ prompt: String) -> Bool {
        prompt.contains("shared balances")
            || prompt.contains("reconciliation balances")
            || (prompt.contains("reconciliation account") && prompt.contains("largest balance"))
            || (prompt.contains("shared balance") && (prompt.contains("largest") || prompt.contains("show")))
    }

    private func isBudgetLimitPrompt(_ prompt: String) -> Bool {
        prompt.contains("where it should be for this budget")
            || (prompt.contains(" over ") && prompt.contains("this budget"))
    }

    private func isCategoryDeltaRankingPrompt(_ prompt: String) -> Bool {
        prompt.contains("category changed the most")
            && prompt.contains("compared to")
    }

    private func isTransactionDeltaDriversPrompt(_ prompt: String) -> Bool {
        (prompt.contains("what expenses") || prompt.contains("which expenses"))
            && (prompt.contains("making this month higher than last month")
                || prompt.contains("made this month higher than last month"))
    }

    private func isCardRankingPrompt(_ prompt: String) -> Bool {
        (prompt.hasPrefix("what card ") || prompt.hasPrefix("which card "))
            && (prompt.contains("most") || prompt.contains("eating"))
    }

    private func isBreakdownPrompt(_ prompt: String) -> Bool {
        prompt.contains("by category")
            || prompt.contains("down by category")
            || prompt.contains("category breakdown")
            || (prompt.contains("break down") && prompt.contains("by category"))
            || (prompt.contains("break down") && prompt.contains("where my money went"))
    }

    private func isSharePrompt(_ prompt: String) -> Bool {
        prompt.contains("how much of my spending")
            || prompt.contains("how much of my money went to")
            || (prompt.contains("how much of") && prompt.contains("spending was"))
            || prompt.contains("share of my spending")
            || prompt.contains("percent of my spending")
            || prompt.contains("percentage of my spending")
            || prompt.contains("portion of my money")
            || prompt.contains("what part of")
    }

    private func isFrequencyRankingPrompt(_ prompt: String) -> Bool {
        prompt.contains("too often")
            || prompt.contains("not necessarily the most money")
    }

    private func isBroadMerchantRankingPrompt(_ prompt: String) -> Bool {
        prompt.contains("what stores did i spend the most at")
            || prompt.contains("which stores did i spend the most at")
            || prompt.contains("stores got the most money from me")
            || prompt.contains("who did i pay the most")
    }

    private func isLargestTransactionsPhrasePrompt(_ prompt: String) -> Bool {
        let hasThingPhrase = prompt.contains("things i paid for")
            || prompt.contains("things i bought")
            || prompt.contains("purchases")
        let hasRankingPhrase = prompt.contains("top ")
            || prompt.contains("biggest")
            || prompt.contains("largest")
            || prompt.contains("most")
        return hasThingPhrase && hasRankingPhrase
    }

    private func isMessyCategoryComparisonPrompt(_ prompt: String) -> Bool {
        prompt.contains("spending more on")
            || prompt.contains("compared to last month")
            || prompt.contains("go up or down from")
            || prompt.contains("this month than last month")
            || prompt.contains("this month vs last month")
            || prompt.contains("higher or lower on")
    }

    private func isCardComparisonPrompt(_ prompt: String) -> Bool {
        prompt.contains("card spending change from")
            || (prompt.contains(" card ") && prompt.contains("change from") && prompt.contains(" to "))
    }

    private func cardComparisonTarget(in prompt: String) -> String? {
        firstCapture(
            in: prompt,
            patterns: [
                #"\bhow\s+did\s+my\s+(.+?)\s+spending\s+change\s+from\b"#,
                #"\bhow\s+did\s+(.+?)\s+spending\s+change\s+from\b"#
            ]
        )
        .map { cleanEntitySpan($0, operation: .compare, typeHint: .card) }
    }

    private func comparisonTarget(in prompt: String) -> String? {
        let patterns = [
            #"\bhow\s+did\s+(.+?)\s+change\s+compared\s+to\b"#,
            #"\bhow\s+did\s+my\s+(.+?)\s+spending\s+change\s+from\b"#,
            #"\bmore\s+on\s+(.+?)(?=\s+lately\b|\s+or\b|$)"#,
            #"\bwas\s+(.+?)(?=\s+compared\s+to\b|$)"#,
            #"\bdid\s+(.+?)\s+go\s+up\s+or\s+down\b"#,
            #"^compare\s+(.+?)(?=\s+in\s+[a-z]+\b|\s+this\s+month\b|\s+to\s+last\s+month\b|\s+to\s+[a-z]+\b|$)"#
        ]
        return firstCapture(in: prompt, patterns: patterns).map {
            cleanEntitySpan($0, operation: .compare, typeHint: comparisonTypeHint(for: $0, prompt: prompt), intent: nil)
        }
    }

    private func shareTarget(in prompt: String) -> String? {
        firstCapture(
            in: prompt,
            patterns: [
                #"\bwas\s+(.+?)$"#,
                #"\bspending\s+was\s+(.+?)$"#,
                #"\bwent\s+to\s+(.+?)(?=\s+(?:this|last|in|for|from|over|during)\b|$)"#
            ]
        )
        .map { cleanEntitySpan($0, operation: .sum, typeHint: .category) }
    }

    private func budgetLimitTarget(in prompt: String) -> String? {
        firstCapture(
            in: prompt,
            patterns: [
                #"^is\s+(.+?)\s+over\b"#,
                #"^is\s+(.+?)\s+where\b"#
            ]
        )
        .map { cleanEntitySpan($0, operation: .compare, typeHint: .category) }
    }

    private func simulationMentions(from prompt: String) -> [MarinaUnresolvedEntityMention] {
        guard let input = firstCapture(in: prompt, patterns: [#"\bto\s+(.+?)\s+does\b"#]),
              let output = firstCapture(in: prompt, patterns: [#"\bdoes\s+(.+?)\s+still\s+have\s+room\b"#]) else {
            return []
        }
        return [
            MarinaUnresolvedEntityMention(
                role: .simulationInput,
                rawText: cleanEntitySpan(input, operation: .simulate, typeHint: .category),
                typeHint: .category,
                confidence: .medium
            ),
            MarinaUnresolvedEntityMention(
                role: .simulationOutput,
                rawText: cleanEntitySpan(output, operation: .simulate, typeHint: .category),
                typeHint: .category,
                confidence: .medium
            )
        ]
    }

    private func exclusionMentions(from prompt: String) -> [MarinaUnresolvedEntityMention] {
        guard let card = firstCapture(in: prompt, patterns: [#"\bon\s+(.+?)\s+outside\s+of\b"#]),
              let excludedCategory = firstCapture(in: prompt, patterns: [#"\boutside\s+of\s+(.+?)$"#]) else {
            return []
        }
        return [
            MarinaUnresolvedEntityMention(
                role: .filter,
                rawText: cleanEntitySpan(card, operation: .sum, typeHint: .card),
                typeHint: .card,
                confidence: .medium
            ),
            MarinaUnresolvedEntityMention(
                role: .filter,
                rawText: cleanEntitySpan(excludedCategory, operation: .sum, typeHint: .category),
                typeHint: .category,
                confidence: .medium
            )
        ]
    }

    private func categoryMention(from rawText: String?) -> [MarinaUnresolvedEntityMention] {
        guard let rawText,
              rawText.isEmpty == false else {
            return []
        }
        return [
            MarinaUnresolvedEntityMention(
                role: .primaryTarget,
                rawText: rawText,
                typeHint: .category,
                confidence: .medium
            )
        ]
    }

    private func comparisonTimeScopes(
        from prompt: String,
        intent: NormalizedQueryIntent
    ) -> [MarinaUnresolvedTimeScope]? {
        if let primary = intent.dateRange,
           let comparison = intent.comparisonDateRange {
            if prompt.contains(" from ") && prompt.contains(" to ") {
                return comparisonScopes(primary: comparison, comparison: primary)
            }
            return comparisonScopes(primary: primary, comparison: comparison)
        }

        if isCurrentVersusLastMonthComparison(prompt) || isLatelyBaselineComparison(prompt) {
            let primary = monthRange(containing: now())
            return comparisonScopes(
                primary: primary,
                comparison: previousMonthRange(before: primary.startDate)
            )
        }

        return nil
    }

    private func isCurrentVersusLastMonthComparison(_ prompt: String) -> Bool {
        prompt.contains("compared to last month")
            || prompt.contains("this month than last month")
            || prompt.contains("this month vs last month")
            || prompt.contains("this month versus last month")
            || prompt.contains("higher than last month")
            || prompt.contains("higher or lower on") && prompt.contains("this month")
    }

    private func isLatelyBaselineComparison(_ prompt: String) -> Bool {
        prompt.contains("lately")
            && (prompt.contains("about normal") || prompt.contains("more on"))
    }

    private func comparisonScopes(
        primary: HomeQueryDateRange,
        comparison: HomeQueryDateRange
    ) -> [MarinaUnresolvedTimeScope] {
        [
            MarinaUnresolvedTimeScope(
                role: .primary,
                rawText: nil,
                resolvedRangeHint: primary,
                periodUnitHint: .month
            ),
            MarinaUnresolvedTimeScope(
                role: .comparison,
                rawText: nil,
                resolvedRangeHint: comparison,
                periodUnitHint: .month
            )
        ]
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousMonthRange(before date: Date) -> HomeQueryDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let currentMonth = monthRange(containing: date)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: currentMonth.startDate) ?? currentMonth.startDate
        return HomeQueryDateRange(startDate: previousStart, endDate: currentMonth.startDate)
    }

    private func cleanEntitySpan(
        _ text: String,
        operation: MarinaCandidateOperation?,
        typeHint: MarinaCandidateEntityTypeHint?,
        intent: NormalizedQueryIntent? = nil
    ) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = stripKnownTargetWrappers(cleaned)
        let stopPatterns = [
            #"\s+or\s+is\s+it\s+about\s+normal\b.*$"#,
            #"\s+lately\b.*$"#,
            #"\s+does\b.*$"#,
            #"\s+still\s+have\s+room\b.*$"#,
            #"\s+outside\s+of\b.*$"#,
            #"\s+by\s+category\b.*$"#,
            #"\s+cost\s+me\b.*$"#,
            #"\s+over\s+the\s+last\b.*$"#,
            #"\s+over\s+the\b.*$"#,
            #"\s+right\s+now\b.*$"#,
            #"\s+this\s+month\b.*$"#,
            #"\s+last\s+month\b.*$"#,
            #"\s+this\s+period\b.*$"#,
            #"\s+in\s+(january|february|march|april|may|june|july|august|september|october|november|december)\b.*$"#,
            #"\s+compared\s+to\b.*$"#,
            #"\s+than\b.*$"#,
            #"\s+from\b.*$"#,
            #"\s+to\b.*$"#
        ]

        for pattern in stopPatterns {
            let candidate = cleaned.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.isEmpty == false, candidate != cleaned {
                cleaned = candidate
                break
            }
        }

        if let intent, intent.comparisonDateRange != nil {
            cleaned = stripConsumedComparisonDateTokens(cleaned)
        }

        return cleaned
            .replacingOccurrences(of: #"^(?:my|the)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripKnownTargetWrappers(_ text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let wrappers = [
            #"^how\s+much\s+did\s+"#,
            #"^what\s+did\s+i\s+spend\s+(?:on|in)\s+"#,
            #"^what\s+have\s+i\s+spent\s+(?:on|in)\s+"#,
            #"^spend\s+in\s+"#,
            #"^how\s+much\s+went\s+to\s+"#,
            #"^how\s+much\s+of\s+my\s+money\s+went\s+to\s+"#,
            #"^how\s+much\s+of\s+my\s+spending\s+was\s+"#,
            #"^was\s+i\s+higher\s+or\s+lower\s+on\s+"#,
            #"^i\s+higher\s+or\s+lower\s+on\s+"#,
            #"^compare\s+"#
        ]
        for wrapper in wrappers {
            cleaned = cleaned.replacingOccurrences(of: wrapper, with: "", options: [.regularExpression, .caseInsensitive])
        }
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripConsumedComparisonDateTokens(_ text: String) -> String {
        var cleaned = text
        cleaned = cleaned.replacingOccurrences(
            of: #"\bfrom\s+(january|february|march|april|may|june|july|august|september|october|november|december)\s+to\s+(january|february|march|april|may|june|july|august|september|october|november|december)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\b(january|february|march|april|may|june|july|august|september|october|november|december|this month|last month|this period)\b"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        return cleaned
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func shouldDropEntityMentionAfterCleanup(
        _ cleaned: String,
        intent: NormalizedQueryIntent,
        operation: MarinaCandidateOperation?
    ) -> Bool {
        let normalizedCleaned = normalized(cleaned)
        if normalizedCleaned.isEmpty {
            return true
        }

        let scaffoldingTokens: Set<String> = [
            "what", "who", "where", "how", "how much", "spend", "spending",
            "where my money went", "my money went", "by category", "category breakdown"
        ]
        if scaffoldingTokens.contains(normalizedCleaned) {
            return true
        }

        if operation == .rank, grouping(from: intent)?.dimension == .category, normalizedCleaned.contains("by category") {
            return true
        }

        return false
    }

    private func comparisonTypeHint(for span: String, prompt: String) -> MarinaCandidateEntityTypeHint? {
        let normalizedSpan = normalized(span)
        let normalizedPrompt = normalized(prompt)
        if normalizedSpan.contains("card") || normalizedPrompt.contains(" card ") || normalizedPrompt.contains(" my apple card") {
            return .card
        }
        if normalizedPrompt.contains(" at ") || normalizedPrompt.contains(" with ") || normalizedPrompt.contains("merchant") || normalizedPrompt.contains("store") {
            return .merchant
        }
        if normalizedPrompt.contains(" category ") || normalizedPrompt.contains("grocer") || normalizedPrompt.contains("transportation") || normalizedPrompt.contains("food & drink") {
            return .category
        }
        return nil
    }

    private func firstCapture(in text: String, patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, options: [], range: range),
                  match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let capture = String(text[captureRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if capture.isEmpty == false {
                return capture
            }
        }
        return nil
    }
}

private struct ProtectedShape {
    let operation: MarinaCandidateOperation
    let measure: MarinaCandidateMeasure
    let entityMentions: [MarinaUnresolvedEntityMention]?
    let timeScopes: [MarinaUnresolvedTimeScope]?
    let grouping: MarinaGroupingCandidate?
    let ranking: MarinaRankingCandidate?
    let responseShapeHint: MarinaResponseShapeHint
    let unsupportedHint: MarinaUnsupportedHint?

    init(
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        entityMentions: [MarinaUnresolvedEntityMention]? = nil,
        timeScopes: [MarinaUnresolvedTimeScope]? = nil,
        grouping: MarinaGroupingCandidate? = nil,
        ranking: MarinaRankingCandidate? = nil,
        responseShapeHint: MarinaResponseShapeHint,
        unsupportedHint: MarinaUnsupportedHint? = nil
    ) {
        self.operation = operation
        self.measure = measure
        self.entityMentions = entityMentions
        self.timeScopes = timeScopes
        self.grouping = grouping
        self.ranking = ranking
        self.responseShapeHint = responseShapeHint
        self.unsupportedHint = unsupportedHint
    }
}
