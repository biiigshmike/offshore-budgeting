import Foundation

enum MarinaInterpreterSource: String, Codable, Equatable, Sendable {
    case heuristic
    case foundationModels
}

enum MarinaCandidateConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

enum MarinaCandidateOperation: String, Codable, Equatable, Sendable {
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
    case listRows
    case lookupDetails
}

enum MarinaCandidateMeasure: String, Codable, Equatable, Sendable {
    case spend
    case income
    case savings
    case remainingBudget
    case reconciliationBalance
    case categoryShare
    case transactionAmount
    case transactionFrequency
    case presetAmount
    case savingsMovement
}

enum MarinaCandidateEntityTypeHint: String, Codable, Equatable, CaseIterable, Sendable {
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

enum MarinaEntityMentionRole: String, Codable, Equatable, CaseIterable, Sendable {
    case filter
    case excludeFilter
    case primaryTarget
    case comparisonTarget
    case groupingDimension
    case simulationInput
    case simulationOutput
}

struct MarinaUnresolvedEntityMention: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let role: MarinaEntityMentionRole
    let rawText: String?
    let typeHint: MarinaCandidateEntityTypeHint?
    let allowedTypeHints: [MarinaCandidateEntityTypeHint]?
    let confidence: MarinaCandidateConfidence

    init(
        id: UUID = UUID(),
        role: MarinaEntityMentionRole,
        rawText: String?,
        typeHint: MarinaCandidateEntityTypeHint?,
        allowedTypeHints: [MarinaCandidateEntityTypeHint]? = nil,
        confidence: MarinaCandidateConfidence = .medium
    ) {
        self.id = id
        self.role = role
        self.rawText = rawText
        self.typeHint = typeHint
        self.allowedTypeHints = allowedTypeHints
        self.confidence = confidence
    }
}

enum MarinaTimeScopeRole: String, Codable, Equatable, CaseIterable, Sendable {
    case primary
    case comparison
    case lookbackWindow
    case simulationHorizon
}

struct MarinaUnresolvedTimeScope: Codable, Equatable, Identifiable, Sendable {
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

enum MarinaGroupingDimensionCandidate: String, Codable, Equatable, Sendable {
    case category
    case merchant
    case card
    case transaction
    case incomeSource
    case preset
    case savingsLedgerEntry
    case allocationAccount
    case day
    case week
    case month
}

struct MarinaGroupingCandidate: Codable, Equatable, Sendable {
    let dimension: MarinaGroupingDimensionCandidate
    let rawText: String?

    init(dimension: MarinaGroupingDimensionCandidate, rawText: String? = nil) {
        self.dimension = dimension
        self.rawText = rawText
    }
}

enum MarinaRankingDirectionCandidate: String, Codable, Equatable, Sendable {
    case top
    case bottom
    case largest
    case smallest
    case mostFrequent
    case leastFrequent
    case newest
}

struct MarinaRankingCandidate: Codable, Equatable, Sendable {
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

enum MarinaResponseShapeHint: String, Codable, Equatable, Sendable {
    case scalarCurrency
    case summaryCard
    case comparison
    case rankedList
    case groupedBreakdown
    case chartRows
    case clarification
    case unsupported

    var isAdvisory: Bool { true }
}

enum MarinaRequestFamily: String, Codable, Sendable, Equatable {
    case analytics
    case databaseLookup
    case command
    case help
    case planning
    case unsupported
}

enum MarinaSemanticCommandAction: String, Codable, Equatable, Sendable {
    case total
    case listRows
    case rank
    case group
    case compare
    case average
    case simulate
    case lookupDetails
}

enum MarinaSemanticCommandDataset: String, Codable, Equatable, Sendable {
    case variableExpenses
    case plannedExpenses
    case income
    case incomeSeries
    case cards
    case categories
    case presets
    case budgets
    case savingsLedger
    case reconciliation
    case expenseAllocations
    case importMerchantRules
    case assistantAliasRules
}

enum MarinaSemanticCommandSort: String, Codable, Equatable, Sendable {
    case newest
    case largest
    case deltaDescending
    case groupedTotalDescending
}

enum MarinaSemanticRequestedDetail: String, Codable, Equatable, Sendable {
    case general
    case date
    case amount
    case card
    case category
    case status
    case schedule
    case recurrence
    case account
    case balance
    case linkedObjects
}

struct MarinaSemanticCommandFilter: Codable, Equatable, Sendable {
    let rawText: String
    let allowedTypes: [MarinaCandidateEntityTypeHint]
}

struct MarinaSemanticCommand: Codable, Equatable, Sendable {
    let family: MarinaRequestFamily
    let action: MarinaSemanticCommandAction
    let datasets: [MarinaSemanticCommandDataset]
    let measure: MarinaCandidateMeasure?
    let includeFilters: [MarinaSemanticCommandFilter]
    let excludeFilters: [MarinaSemanticCommandFilter]
    let grouping: MarinaGroupingDimensionCandidate?
    let sort: MarinaSemanticCommandSort?
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let periodUnit: HomeQueryPeriodUnit?
    let limit: Int?
    let requestedDetail: MarinaSemanticRequestedDetail?
}

enum MarinaUnsupportedHint: String, Codable, Equatable, Sendable {
    case unsupportedOperation
    case unsupportedCombination
    case missingRequiredTarget
    case unsupportedSimulation
    case unsupportedProjection
    case unsupportedExclusionFilter
    case unsupportedBudgetLimit
    case unsupportedFrequencyRanking
    case unsupportedCardRanking
    case unsupportedRankedComparison
    case lowConfidence
}

struct MarinaResolvedRequest: Codable, Sendable, Equatable {
    var family: MarinaRequestFamily
    var analyticsCandidate: MarinaQueryPlanCandidate?
    var databaseLookupRequest: MarinaDatabaseLookupRequest?
    var unsupportedReason: MarinaUnsupportedHint?
}

typealias MarinaQueryCandidate = MarinaQueryPlanCandidate

struct MarinaPromptNormalization: Codable, Equatable, Sendable {
    let originalText: String
    let normalizedText: String
    let defaultPeriodUnit: HomeQueryPeriodUnit
    let completedMonthDefaultWindow: HomeQueryDateRange
}

struct MarinaPromptNormalizer {
    private let calendar: Calendar

    init(calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
    }

    func normalize(
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        now: Date
    ) -> MarinaPromptNormalization {
        MarinaPromptNormalization(
            originalText: prompt,
            normalizedText: prompt
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            defaultPeriodUnit: defaultPeriodUnit,
            completedMonthDefaultWindow: completedMonthLookbackRange(endingBefore: now, months: 3)
        )
    }

    func completedMonthLookbackRange(endingBefore date: Date, months: Int) -> HomeQueryDateRange {
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let start = calendar.date(byAdding: .month, value: -max(months, 1), to: currentMonthStart) ?? currentMonthStart
        let end = calendar.date(byAdding: .second, value: -1, to: currentMonthStart) ?? currentMonthStart
        return HomeQueryDateRange(startDate: start, endDate: end)
    }
}

struct MarinaQueryPlanCandidate: Codable, Equatable, Sendable {
    let requestFamily: MarinaRequestFamily
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
    let databaseLookupRequest: MarinaDatabaseLookupRequest?
    let semanticCommand: MarinaSemanticCommand?

    init(
        requestFamily: MarinaRequestFamily = .analytics,
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
        unsupportedHint: MarinaUnsupportedHint? = nil,
        databaseLookupRequest: MarinaDatabaseLookupRequest? = nil,
        semanticCommand: MarinaSemanticCommand? = nil
    ) {
        self.requestFamily = requestFamily
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
        self.databaseLookupRequest = databaseLookupRequest
        self.semanticCommand = semanticCommand
    }
}
