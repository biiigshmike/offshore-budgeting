import Foundation

enum MarinaInterpreterSource: String, Codable, Equatable {
    case heuristic
    case foundationModels
}

enum MarinaCandidateConfidence: String, Codable, Equatable {
    case high
    case medium
    case low
}

enum MarinaCandidateOperation: String, Codable, Equatable {
    case sum
    case average
    case count
    case minimum
    case maximum
    case rank
    case compare
    case trend
    case forecast
    case simulate
}

enum MarinaCandidateMeasure: String, Codable, Equatable {
    case spend
    case income
    case savings
    case remainingBudget
    case categoryShare
    case transactionAmount
    case transactionFrequency
    case presetAmount
}

enum MarinaCandidateEntityTypeHint: String, Codable, Equatable, CaseIterable {
    case category
    case merchant
    case expense
    case card
    case budget
    case preset
    case incomeSource
    case allocationAccount
    case savingsAccount
    case transaction
    case workspace
}

enum MarinaEntityMentionRole: String, Codable, Equatable, CaseIterable {
    case filter
    case primaryTarget
    case comparisonTarget
    case groupingDimension
    case simulationInput
    case simulationOutput
}

struct MarinaUnresolvedEntityMention: Codable, Equatable, Identifiable {
    let id: UUID
    let role: MarinaEntityMentionRole
    let rawText: String?
    let typeHint: MarinaCandidateEntityTypeHint?
    let confidence: MarinaCandidateConfidence

    init(
        id: UUID = UUID(),
        role: MarinaEntityMentionRole,
        rawText: String?,
        typeHint: MarinaCandidateEntityTypeHint?,
        confidence: MarinaCandidateConfidence = .medium
    ) {
        self.id = id
        self.role = role
        self.rawText = rawText
        self.typeHint = typeHint
        self.confidence = confidence
    }
}

enum MarinaTimeScopeRole: String, Codable, Equatable, CaseIterable {
    case primary
    case comparison
    case lookbackWindow
    case simulationHorizon
}

struct MarinaUnresolvedTimeScope: Codable, Equatable, Identifiable {
    let id: UUID
    let role: MarinaTimeScopeRole
    let rawText: String?
    let resolvedRangeHint: HomeQueryDateRange?
    let periodUnitHint: HomeQueryPeriodUnit?

    init(
        id: UUID = UUID(),
        role: MarinaTimeScopeRole,
        rawText: String?,
        resolvedRangeHint: HomeQueryDateRange? = nil,
        periodUnitHint: HomeQueryPeriodUnit? = nil
    ) {
        self.id = id
        self.role = role
        self.rawText = rawText
        self.resolvedRangeHint = resolvedRangeHint
        self.periodUnitHint = periodUnitHint
    }
}

enum MarinaGroupingDimensionCandidate: String, Codable, Equatable {
    case category
    case merchant
    case card
    case transaction
    case incomeSource
    case preset
    case day
    case week
    case month
}

struct MarinaGroupingCandidate: Codable, Equatable {
    let dimension: MarinaGroupingDimensionCandidate
    let rawText: String?

    init(dimension: MarinaGroupingDimensionCandidate, rawText: String? = nil) {
        self.dimension = dimension
        self.rawText = rawText
    }
}

enum MarinaRankingDirectionCandidate: String, Codable, Equatable {
    case top
    case bottom
    case largest
    case smallest
    case mostFrequent
    case leastFrequent
}

struct MarinaRankingCandidate: Codable, Equatable {
    let direction: MarinaRankingDirectionCandidate
    let limit: Int?
    let rawText: String?

    init(
        direction: MarinaRankingDirectionCandidate,
        limit: Int? = nil,
        rawText: String? = nil
    ) {
        self.direction = direction
        self.limit = limit
        self.rawText = rawText
    }
}

enum MarinaResponseShapeHint: String, Codable, Equatable {
    case scalarCurrency
    case comparison
    case rankedList
    case groupedBreakdown
    case chartRows
    case clarification
    case unsupported

    var isAdvisory: Bool { true }
}

enum MarinaUnsupportedHint: String, Codable, Equatable {
    case unsupportedOperation
    case unsupportedCombination
    case missingRequiredTarget
    case unsupportedSimulation
    case lowConfidence
}

struct MarinaQueryPlanCandidate: Codable, Equatable {
    let source: MarinaInterpreterSource
    let rawPrompt: String
    let operation: MarinaCandidateOperation?
    let measure: MarinaCandidateMeasure?
    let entityMentions: [MarinaUnresolvedEntityMention]
    let timeScopes: [MarinaUnresolvedTimeScope]
    let grouping: MarinaGroupingCandidate?
    let ranking: MarinaRankingCandidate?
    let limit: Int?
    let responseShapeHint: MarinaResponseShapeHint?
    let confidence: MarinaCandidateConfidence
    let unsupportedHint: MarinaUnsupportedHint?

    init(
        source: MarinaInterpreterSource,
        rawPrompt: String,
        operation: MarinaCandidateOperation? = nil,
        measure: MarinaCandidateMeasure? = nil,
        entityMentions: [MarinaUnresolvedEntityMention] = [],
        timeScopes: [MarinaUnresolvedTimeScope] = [],
        grouping: MarinaGroupingCandidate? = nil,
        ranking: MarinaRankingCandidate? = nil,
        limit: Int? = nil,
        responseShapeHint: MarinaResponseShapeHint? = nil,
        confidence: MarinaCandidateConfidence = .medium,
        unsupportedHint: MarinaUnsupportedHint? = nil
    ) {
        self.source = source
        self.rawPrompt = rawPrompt
        self.operation = operation
        self.measure = measure
        self.entityMentions = entityMentions
        self.timeScopes = timeScopes
        self.grouping = grouping
        self.ranking = ranking
        self.limit = limit
        self.responseShapeHint = responseShapeHint
        self.confidence = confidence
        self.unsupportedHint = unsupportedHint
    }
}
