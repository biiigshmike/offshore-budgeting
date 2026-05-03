import Foundation

struct MarinaHeuristicInterpreter {
    private let normalize: (String, HomeQueryPeriodUnit) -> NormalizedQueryIntent

    init(
        normalize: @escaping (String, HomeQueryPeriodUnit) -> NormalizedQueryIntent = { prompt, defaultPeriodUnit in
            MarinaNLQNormalizer(defaultPeriodUnit: defaultPeriodUnit).normalize(prompt: prompt)
        }
    ) {
        self.normalize = normalize
    }

    func interpret(
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaQueryPlanCandidate {
        let intent = normalize(prompt, defaultPeriodUnit)
        let unsupportedHint = unsupportedHint(from: intent.unsupportedShapeReason)
        let operation = operation(from: intent)
        let measure = measure(from: intent)

        return MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: prompt,
            operation: operation,
            measure: measure,
            entityMentions: entityMentions(from: intent, operation: operation),
            timeScopes: timeScopes(from: intent, defaultPeriodUnit: defaultPeriodUnit),
            grouping: grouping(from: intent),
            ranking: ranking(from: intent, operation: operation),
            limit: intent.resultLimit,
            responseShapeHint: responseShapeHint(from: intent, operation: operation),
            confidence: confidence(from: intent),
            unsupportedHint: unsupportedHint
        )
    }

    private func operation(from intent: NormalizedQueryIntent) -> MarinaCandidateOperation? {
        if intent.unsupportedShapeReason == .whatIfSimulation {
            return .simulate
        }

        if intent.comparisonDateRange != nil || intent.modifiers.contains("comparison") {
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
        operation: MarinaCandidateOperation?
    ) -> [MarinaUnresolvedEntityMention] {
        guard let rawTargetText = intent.rawTargetText?.trimmingCharacters(in: .whitespacesAndNewlines),
              rawTargetText.isEmpty == false else {
            return []
        }

        if shouldSuppressUnscopedRankingTarget(rawTargetText, intent: intent, operation: operation) {
            return []
        }

        return [
            MarinaUnresolvedEntityMention(
                role: entityMentionRole(from: intent),
                rawText: rawTargetText,
                typeHint: entityTypeHint(from: intent),
                confidence: confidence(from: intent)
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

    private func entityMentionRole(from intent: NormalizedQueryIntent) -> MarinaEntityMentionRole {
        if isCardSpendFilter(intent) {
            return .filter
        }
        return .primaryTarget
    }

    private func entityTypeHint(from intent: NormalizedQueryIntent) -> MarinaCandidateEntityTypeHint? {
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

    private func confidence(from intent: NormalizedQueryIntent) -> MarinaCandidateConfidence {
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
}
