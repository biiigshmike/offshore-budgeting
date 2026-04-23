import Foundation

enum MarinaNLQMatchType: String, Equatable {
    case exact
    case prefix
}

enum MarinaNLQTargetType: String, Equatable, CaseIterable {
    case category
    case merchant
    case expense
    case card
    case budget
    case preset
    case incomeSource
    case allocationAccount
    case savingsAccount
}

enum MarinaNLQDateFallbackPolicy: Equatable {
    case userThenActiveBudgetThenCurrentMonth
}

enum MarinaNLQWithinTypeAggregationPolicy: Equatable {
    case clarifyDistinct
    case aggregateDistinct
}

enum MarinaIntentFamily: Equatable {
    case aggregate
    case ranking
    case comparison
    case breakdown
    case trend
    case frequency
    case upcoming
    case status
}

enum MarinaIntentSubject: Equatable {
    case spend
    case transaction
    case merchant
    case category
    case budget
    case card
    case income
    case incomeSource
    case preset
    case savings
    case savingsAccount
    case allocation
    case allocationAccount
}

enum MarinaRankingMode: Equatable {
    case top
    case bottom
    case largest
    case smallest
    case mostFrequent
    case leastFrequent
}

enum MarinaAggregationMode: Equatable {
    case total
    case average
    case count
    case share
}

enum MarinaQueryMeasure: Equatable {
    case spendTotal
    case spendAverage
    case transactionFrequency
    case incomeAverage
    case presetStatus
}

enum MarinaQueryGrouping: Equatable {
    case none
    case transaction
    case category
    case merchant
    case preset
    case incomeSource
}

enum MarinaQueryRanking: Equatable {
    case top
    case bottom
    case largest
    case smallest
    case mostFrequent
    case leastFrequent
}

enum MarinaUnsupportedShapeReason: Equatable {
    case rankedAverage(grouping: MarinaQueryGrouping)
    case unsupportedCombination

    var clarificationMessage: String {
        switch self {
        case .rankedAverage(let grouping):
            switch grouping {
            case .merchant:
                return "I can rank merchants by total spend, or I can show spending averages overall. Try your top merchant or your average spend over time."
            case .category:
                return "I can rank categories by total spend, or I can show spending averages overall. Try your top category or your average spend over time."
            default:
                return "I can answer total-spend rankings and overall averages today, but not that average-based ranking yet."
            }
        case .unsupportedCombination:
            return "I recognized that kind of question, but I can't answer that shape safely yet. Try a total-spend ranking, a spend total for one target, or an average over time."
        }
    }
}

enum MarinaQueryShapeResolution: Equatable {
    case metric(MarinaNormalizedMetric)
    case unsupported(reason: MarinaUnsupportedShapeReason)
    case unresolved
}

struct MarinaQueryShape: Equatable {
    let measure: MarinaQueryMeasure?
    let grouping: MarinaQueryGrouping?
    let ranking: MarinaQueryRanking?
    let targetHint: String?
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let modifiers: [String]

    init(
        measure: MarinaQueryMeasure? = nil,
        grouping: MarinaQueryGrouping? = nil,
        ranking: MarinaQueryRanking? = nil,
        targetHint: String? = nil,
        dateRange: HomeQueryDateRange? = nil,
        comparisonDateRange: HomeQueryDateRange? = nil,
        modifiers: [String] = []
    ) {
        self.measure = measure
        self.grouping = grouping
        self.ranking = ranking
        self.targetHint = targetHint
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.modifiers = modifiers
    }
}

struct MarinaIntentSignals: Equatable {
    let family: MarinaIntentFamily?
    let subject: MarinaIntentSubject?
    let rankingMode: MarinaRankingMode?
    let aggregationMode: MarinaAggregationMode?
    let targetHint: String?
    let modifiers: [String]
}

enum MarinaNormalizedMetric: String, Equatable, CaseIterable {
    case spendTotal
    case categorySpendTotal
    case categorySpendShare
    case merchantSpendTotal
    case topCategories
    case topMerchants
    case monthComparison
    case categoryMonthComparison
    case largestTransactions
    case mostFrequentTransactions
    case spendAveragePerPeriod
    case incomeAverageActual
    case presetDueSoon
}

struct MarinaNormalizedMetricDefinition: Equatable {
    let requiresTarget: Bool
    let allowedTargetTypes: Set<MarinaNLQTargetType>
    let withinTypeAggregationPolicy: MarinaNLQWithinTypeAggregationPolicy
    let dateFallbackPolicy: MarinaNLQDateFallbackPolicy
    let isFamilyMetric: Bool
}

extension MarinaNormalizedMetric {
    var definition: MarinaNormalizedMetricDefinition {
        switch self {
        case .spendTotal:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: false,
                allowedTargetTypes: [],
                withinTypeAggregationPolicy: .aggregateDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: true
            )
        case .categorySpendTotal:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: true,
                allowedTargetTypes: [.category],
                withinTypeAggregationPolicy: .aggregateDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        case .categorySpendShare:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: false,
                allowedTargetTypes: [.category],
                withinTypeAggregationPolicy: .aggregateDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        case .merchantSpendTotal:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: true,
                allowedTargetTypes: [.merchant],
                withinTypeAggregationPolicy: .aggregateDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        case .topCategories:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: false,
                allowedTargetTypes: [],
                withinTypeAggregationPolicy: .clarifyDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        case .topMerchants:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: false,
                allowedTargetTypes: [],
                withinTypeAggregationPolicy: .clarifyDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        case .monthComparison:
            // v1 family metric placeholder: specialized in aggregation mapping by resolved target type.
            return MarinaNormalizedMetricDefinition(
                requiresTarget: false,
                allowedTargetTypes: [],
                withinTypeAggregationPolicy: .aggregateDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: true
            )
        case .categoryMonthComparison:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: true,
                allowedTargetTypes: [.category],
                withinTypeAggregationPolicy: .aggregateDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        case .largestTransactions:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: false,
                allowedTargetTypes: [],
                withinTypeAggregationPolicy: .clarifyDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        case .mostFrequentTransactions:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: false,
                allowedTargetTypes: [],
                withinTypeAggregationPolicy: .clarifyDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        case .spendAveragePerPeriod:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: false,
                allowedTargetTypes: [],
                withinTypeAggregationPolicy: .clarifyDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        case .incomeAverageActual:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: false,
                allowedTargetTypes: [.incomeSource],
                withinTypeAggregationPolicy: .aggregateDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        case .presetDueSoon:
            return MarinaNormalizedMetricDefinition(
                requiresTarget: false,
                allowedTargetTypes: [.preset],
                withinTypeAggregationPolicy: .aggregateDistinct,
                dateFallbackPolicy: .userThenActiveBudgetThenCurrentMonth,
                isFamilyMetric: false
            )
        }
    }
}

enum MarinaNLQConfidenceLevel: String, Equatable {
    case high
    case medium
    case low
}

struct NormalizedQueryIntent: Equatable {
    let rawPrompt: String
    let normalizedMetric: MarinaNormalizedMetric?
    let queryShape: MarinaQueryShape
    let intentSignals: MarinaIntentSignals
    let unsupportedShapeReason: MarinaUnsupportedShapeReason?
    let rawTargetText: String?
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let resultLimit: Int?
    let modifiers: [String]
    let confidenceLevel: MarinaNLQConfidenceLevel

    init(
        rawPrompt: String,
        normalizedMetric: MarinaNormalizedMetric?,
        queryShape: MarinaQueryShape = MarinaQueryShape(),
        intentSignals: MarinaIntentSignals,
        unsupportedShapeReason: MarinaUnsupportedShapeReason? = nil,
        rawTargetText: String?,
        dateRange: HomeQueryDateRange?,
        comparisonDateRange: HomeQueryDateRange?,
        resultLimit: Int?,
        modifiers: [String],
        confidenceLevel: MarinaNLQConfidenceLevel
    ) {
        self.rawPrompt = rawPrompt
        self.normalizedMetric = normalizedMetric
        self.queryShape = queryShape
        self.intentSignals = intentSignals
        self.unsupportedShapeReason = unsupportedShapeReason
        self.rawTargetText = rawTargetText
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.resultLimit = resultLimit
        self.modifiers = modifiers
        self.confidenceLevel = confidenceLevel
    }
}

struct MarinaNLQCandidateMatch: Equatable {
    let entityType: MarinaNLQTargetType
    let displayValue: String
    let normalizedValue: String
    let matchType: MarinaNLQMatchType
    let sourceID: UUID
}

struct MarinaNLQTargetExtractionResult: Equatable {
    let rawTargetText: String?
    let matchesByType: [MarinaNLQTargetType: [MarinaNLQCandidateMatch]]

    var hasAnyMatches: Bool {
        matchesByType.values.contains(where: { $0.isEmpty == false })
    }
}

struct MarinaNLQResolvedTargets: Equatable {
    let targetType: MarinaNLQTargetType?
    let matches: [MarinaNLQCandidateMatch]

    var resolvedTargetNames: [String] {
        matches.map(\.displayValue)
    }

    var prefixWarningTargets: [String] {
        var seen: Set<String> = []
        var warnings: [String] = []

        for match in matches where match.matchType == .prefix {
            if seen.insert(match.normalizedValue).inserted {
                warnings.append(match.displayValue)
            }
        }

        return warnings
    }
}

struct MarinaNLQClarificationOption: Equatable {
    let targetType: MarinaNLQTargetType
    let displayLabel: String
    let targetName: String
    let typedAliases: [String]
}

struct MarinaNLQClarificationPayload: Equatable {
    let rawTargetText: String?
    let message: String
    let options: [MarinaNLQClarificationOption]
}

enum MarinaNLQResolutionOutcome: Equatable {
    case execute(MarinaNLQResolvedTargets)
    case clarifyAmbiguous(MarinaNLQClarificationPayload)
    case clarifyNoMatch(MarinaNLQClarificationPayload)
}

struct MarinaNLQBreakdownItem: Equatable {
    let label: String
    let value: Double?
    let renderedValue: String?
}

struct MarinaNLQComparisonResult: Equatable {
    let currentValue: Double
    let previousValue: Double
    let currentLabel: String
    let previousLabel: String
}

struct MarinaNLQAggregationResult: Equatable {
    let value: Double?
    let breakdown: [MarinaNLQBreakdownItem]?
    let comparison: MarinaNLQComparisonResult?
    let warnings: [String]?
    let isUnresolved: Bool
    let unresolvedMessage: String?

    static func unresolved(_ message: String, warnings: [String] = []) -> MarinaNLQAggregationResult {
        MarinaNLQAggregationResult(
            value: nil,
            breakdown: nil,
            comparison: nil,
            warnings: warnings.isEmpty ? nil : warnings,
            isUnresolved: true,
            unresolvedMessage: message
        )
    }
}

struct MarinaNLQExecutionContext: Equatable {
    let metric: MarinaNormalizedMetric
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let resultLimit: Int?
    let resolvedTargetType: MarinaNLQTargetType?
    let resolvedTargetNames: [String]
    let modifiers: [String]
}

enum MarinaNLQPipelineResult: Equatable {
    case answer(HomeAnswer, MarinaNLQExecutionContext)
    case clarification(MarinaNLQClarificationPayload)
    case recovery(String)
}
