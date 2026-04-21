import Foundation

struct MarinaMetricMapper {
    func resolve(shape: MarinaQueryShape) -> MarinaQueryShapeResolution {
        if shape.comparisonDateRange != nil || shape.modifiers.contains("comparison") {
            return .metric(.monthComparison)
        }

        switch (shape.measure, shape.grouping, shape.ranking, shape.targetHint?.isEmpty == false) {
        case (.transactionFrequency, .transaction, .mostFrequent, false):
            return .metric(.mostFrequentTransactions)

        case (.spendTotal, .merchant, .top, false):
            return .metric(.topMerchants)

        case (.spendTotal, .category, .top, false):
            return .metric(.topCategories)

        case (.spendTotal, .transaction, .largest, false),
             (.spendTotal, .transaction, .top, false):
            return .metric(.largestTransactions)

        case (.spendTotal, .merchant, nil, true):
            return .metric(.merchantSpendTotal)

        case (.spendTotal, .category, nil, true):
            return .metric(.categorySpendTotal)

        case (.spendAverage, .none, nil, _):
            return .metric(.spendAveragePerPeriod)

        case (.incomeAverage, .none, nil, _),
             (.incomeAverage, .incomeSource, nil, _):
            return .metric(.incomeAverageActual)

        case (.presetStatus, .preset, _, _),
             (.presetStatus, nil, _, _):
            return .metric(.presetDueSoon)

        case (.spendAverage, .merchant, .top, _),
             (.spendAverage, .merchant, .largest, _):
            return .unsupported(reason: .rankedAverage(grouping: .merchant))

        case (.spendAverage, .category, .top, _),
             (.spendAverage, .category, .largest, _):
            return .unsupported(reason: .rankedAverage(grouping: .category))

        case let (measure?, grouping?, ranking?, _):
            if measure == .spendAverage || measure == .incomeAverage {
                return .unsupported(reason: .unsupportedCombination)
            }
            if ranking != nil, grouping != nil {
                return .unsupported(reason: .unsupportedCombination)
            }
            return .unresolved

        case let (measure?, grouping?, nil, hasTarget):
            if hasTarget && measure == .spendTotal && grouping == .transaction {
                return .unsupported(reason: .unsupportedCombination)
            }
            return .unresolved

        default:
            return .unresolved
        }
    }

    func map(signals: MarinaIntentSignals) -> MarinaNormalizedMetric? {
        let shape = MarinaQueryShape(
            measure: measure(from: signals),
            grouping: grouping(from: signals),
            ranking: ranking(from: signals),
            targetHint: signals.targetHint,
            modifiers: signals.modifiers
        )

        if case let .metric(metric) = resolve(shape: shape) {
            return metric
        }

        return nil
    }

    private func measure(from signals: MarinaIntentSignals) -> MarinaQueryMeasure? {
        switch (signals.family, signals.aggregationMode) {
        case (.frequency, _):
            return .transactionFrequency
        case (_, .average):
            return signals.subject == .income ? .incomeAverage : .spendAverage
        case (.upcoming, _):
            return .presetStatus
        case (.aggregate, _), (.ranking, _), (.comparison, _):
            return .spendTotal
        default:
            return nil
        }
    }

    private func grouping(from signals: MarinaIntentSignals) -> MarinaQueryGrouping? {
        switch signals.subject {
        case .transaction:
            return .transaction
        case .category:
            return .category
        case .merchant:
            return .merchant
        case .preset:
            return .preset
        case .income, .incomeSource:
            return .incomeSource
        case .spend:
            return .none
        default:
            return nil
        }
    }

    private func ranking(from signals: MarinaIntentSignals) -> MarinaQueryRanking? {
        switch signals.rankingMode {
        case .top:
            return .top
        case .bottom:
            return .bottom
        case .largest:
            return .largest
        case .smallest:
            return .smallest
        case .mostFrequent:
            return .mostFrequent
        case .leastFrequent:
            return .leastFrequent
        case nil:
            return nil
        }
    }
}
