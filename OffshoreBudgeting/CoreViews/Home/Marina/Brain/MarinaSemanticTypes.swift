import Foundation
import SwiftData

nonisolated enum MarinaSemanticEntity: String, Codable, CaseIterable, Equatable, Sendable {
    case workspace
    case budget
    case card
    case plannedExpense
    case variableExpense
    case reconciliationAccount
    case savingsAccount
    case income
    case incomeSeries
    case category
    case preset
}

nonisolated enum MarinaSemanticProjection: String, Codable, CaseIterable, Equatable, Sendable {
    case records
    case summary
    case income
    case expenses
    case linkedCards
    case linkedPresets
    case linkedBudgets
    case activity
    case occurrences
}

nonisolated enum MarinaSemanticOperation: String, Codable, CaseIterable, Equatable, Sendable {
    case list
    case count
    case sum
    case average
    case compare
    case last
    case next
    case group
    case share
    case forecast
    case whatIf
}

nonisolated enum MarinaSemanticMeasure: String, Codable, CaseIterable, Equatable, Sendable {
    case amount
    case plannedAmount
    case actualAmount
    case effectiveAmount
    case budgetImpact
    case projectedBudgetImpact
    case ledgerSignedAmount
    case plannedIncomeTotal
    case actualIncomeTotal
    case plannedExpenseProjectedTotal
    case plannedExpenseActualTotal
    case plannedExpenseEffectiveTotal
    case variableExpenseTotal
    case unifiedExpenseTotal
    case savingsTotal
    case maximumSavings
    case projectedSavings
    case actualSavings
    case incomeAmount
    case reconciliationBalance
    case categoryAvailability
    case remainingRoom
    case burnRate
    case projectedSpend
    case safeDailySpend
    case paceDifference
    case coverageRatio
    case recurringBurden
    case concentration
    case color
    case name
}

nonisolated enum MarinaCategoryAvailabilityFilter: String, Codable, CaseIterable, Equatable, Sendable {
    case all
    case over
    case near
    case underLimit
}

nonisolated enum MarinaSemanticDimension: String, Codable, CaseIterable, Equatable, Sendable {
    case date
    case category
    case card
    case merchantText
    case budget
    case incomeSource
    case incomeSeries
    case preset
    case savingsAccount
    case reconciliationAccount
    case workspace
}

nonisolated struct MarinaSemanticConstraint: Codable, Equatable, Sendable {
    let dimension: MarinaSemanticDimension
    let value: String
    let resolvedReference: MarinaResolvedEntityReference?
    let kindSource: MarinaSemanticTargetKindSource

    init(
        dimension: MarinaSemanticDimension,
        value: String,
        resolvedReference: MarinaResolvedEntityReference? = nil,
        kindSource: MarinaSemanticTargetKindSource = .unspecified
    ) {
        self.dimension = dimension
        self.value = value
        self.resolvedReference = resolvedReference
        self.kindSource = kindSource
    }

    private enum CodingKeys: String, CodingKey {
        case dimension
        case value
        case resolvedReference
        case kindSource
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dimension = try container.decode(MarinaSemanticDimension.self, forKey: .dimension)
        value = try container.decode(String.self, forKey: .value)
        resolvedReference = try container.decodeIfPresent(
            MarinaResolvedEntityReference.self,
            forKey: .resolvedReference
        )
        kindSource = try container.decodeIfPresent(
            MarinaSemanticTargetKindSource.self,
            forKey: .kindSource
        ) ?? .unspecified
    }
}

nonisolated enum MarinaSemanticTargetKindSource: String, Codable, CaseIterable, Equatable, Sendable {
    case explicit
    case inferred
    case unspecified
}

nonisolated enum MarinaSemanticContinuationIntent: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case showMore
}

nonisolated enum MarinaSemanticDateRangeToken: String, Codable, CaseIterable, Equatable, Sendable {
    case currentPeriod
    case previousPeriod
    case currentMonth
    case previousMonth
    case yearToDate
    case nextSevenDays
    case allTime
}

nonisolated enum MarinaSemanticDateRangeSource: String, Codable, CaseIterable, Equatable, Sendable {
    case defaulted
    case explicit
    case conversationContext
}

nonisolated enum MarinaSemanticSort: String, Codable, CaseIterable, Equatable, Sendable {
    case dateAscending
    case dateDescending
    case amountAscending
    case amountDescending
    case nameAscending
}

nonisolated enum MarinaSemanticAnswerShape: String, Codable, CaseIterable, Equatable, Sendable {
    case metric
    case list
    case comparison
    case clarification
    case acknowledgement
    case unsupported
}

nonisolated enum MarinaSemanticExpenseScope: String, Codable, CaseIterable, Equatable, Sendable {
    case planned
    case variable
    case unified
}

nonisolated enum MarinaSemanticIncomeState: String, Codable, CaseIterable, Equatable, Sendable {
    case planned
    case actual
    case all
}

nonisolated enum MarinaResolutionProvenance: String, Codable, CaseIterable, Equatable, Sendable {
    case explicitIdentifier
    case explicitTargetType
    case assistantAlias
    case importMerchantRule
    case dominantExact
    case candidateResolver
    case clarificationChoice
    case conversationContext
}

nonisolated struct MarinaResolvedEntityReference: Codable, Equatable, Sendable {
    let entity: MarinaSemanticEntity
    let id: UUID?
    let displayName: String
    let provenance: MarinaResolutionProvenance
}

nonisolated enum MarinaResolvedScope: Codable, Equatable, Sendable {
    case workspace(UUID)
    case budget(UUID)
}

nonisolated enum MarinaSemanticUnsupportedReason: String, Codable, Equatable, Sendable {
    case readOnly
    case unavailableModel
    case unsupportedCombination
    case unresolvedEntity
    case ambiguousEntity
    case modelContextLimit
    case modelGuardrail
    case modelGenerationFailed
    case unsupportedLanguageOrLocale
    case incomeSavingsWhatIfUnsupported
}

nonisolated struct MarinaSemanticRequest: Codable, Equatable, Sendable {
    var entity: MarinaSemanticEntity
    var operation: MarinaSemanticOperation
    var measure: MarinaSemanticMeasure?
    var projection: MarinaSemanticProjection
    var dimensions: [MarinaSemanticDimension]
    var constraints: [MarinaSemanticConstraint]
    var dateRangeToken: MarinaSemanticDateRangeToken
    var dateRangeSource: MarinaSemanticDateRangeSource
    var targetName: String?
    var comparisonTargetName: String?
    var textQuery: String?
    var targetDisplayName: String?
    var resolvedTarget: MarinaResolvedEntityReference?
    var resolvedComparisonTarget: MarinaResolvedEntityReference?
    var resolvedScope: MarinaResolvedScope?
    var targetKindSource: MarinaSemanticTargetKindSource
    var comparisonTargetKindSource: MarinaSemanticTargetKindSource
    var continuationIntent: MarinaSemanticContinuationIntent
    var resultLimit: Int?
    var resultOffset: Int?
    var sort: MarinaSemanticSort?
    var expenseScope: MarinaSemanticExpenseScope?
    var incomeState: MarinaSemanticIncomeState?
    var whatIfAmount: Double?
    var categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter?
    var expectedAnswerShape: MarinaSemanticAnswerShape
    var clarificationQuestion: String?
    var unsupportedReason: MarinaSemanticUnsupportedReason?

    init(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        projection: MarinaSemanticProjection = .records,
        dimensions: [MarinaSemanticDimension] = [],
        constraints: [MarinaSemanticConstraint] = [],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod,
        dateRangeSource: MarinaSemanticDateRangeSource = .defaulted,
        targetName: String? = nil,
        comparisonTargetName: String? = nil,
        textQuery: String? = nil,
        targetDisplayName: String? = nil,
        resolvedTarget: MarinaResolvedEntityReference? = nil,
        resolvedComparisonTarget: MarinaResolvedEntityReference? = nil,
        resolvedScope: MarinaResolvedScope? = nil,
        targetKindSource: MarinaSemanticTargetKindSource = .unspecified,
        comparisonTargetKindSource: MarinaSemanticTargetKindSource = .unspecified,
        continuationIntent: MarinaSemanticContinuationIntent = .none,
        resultLimit: Int? = nil,
        resultOffset: Int? = nil,
        sort: MarinaSemanticSort? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        incomeState: MarinaSemanticIncomeState? = nil,
        whatIfAmount: Double? = nil,
        categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
        expectedAnswerShape: MarinaSemanticAnswerShape,
        clarificationQuestion: String? = nil,
        unsupportedReason: MarinaSemanticUnsupportedReason? = nil
    ) {
        self.entity = entity
        self.operation = operation
        self.measure = measure
        self.projection = projection
        self.dimensions = dimensions
        self.constraints = constraints
        self.dateRangeToken = dateRangeToken
        self.dateRangeSource = dateRangeSource
        self.targetName = targetName
        self.comparisonTargetName = comparisonTargetName
        self.textQuery = textQuery
        self.targetDisplayName = targetDisplayName
        self.resolvedTarget = resolvedTarget
        self.resolvedComparisonTarget = resolvedComparisonTarget
        self.resolvedScope = resolvedScope
        self.targetKindSource = targetKindSource
        self.comparisonTargetKindSource = comparisonTargetKindSource
        self.continuationIntent = continuationIntent
        self.resultLimit = resultLimit
        self.resultOffset = resultOffset
        self.sort = sort
        self.expenseScope = expenseScope
        self.incomeState = incomeState
        self.whatIfAmount = whatIfAmount
        self.categoryAvailabilityFilter = categoryAvailabilityFilter
        self.expectedAnswerShape = expectedAnswerShape
        self.clarificationQuestion = clarificationQuestion
        self.unsupportedReason = unsupportedReason
    }

    private enum CodingKeys: String, CodingKey {
        case entity
        case operation
        case measure
        case projection
        case dimensions
        case constraints
        case dateRangeToken
        case dateRangeSource
        case targetName
        case comparisonTargetName
        case textQuery
        case targetDisplayName
        case resolvedTarget
        case resolvedComparisonTarget
        case resolvedScope
        case targetKindSource
        case comparisonTargetKindSource
        case continuationIntent
        case resultLimit
        case resultOffset
        case sort
        case expenseScope
        case incomeState
        case whatIfAmount
        case categoryAvailabilityFilter
        case expectedAnswerShape
        case clarificationQuestion
        case unsupportedReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entity = try container.decode(MarinaSemanticEntity.self, forKey: .entity)
        operation = try container.decode(MarinaSemanticOperation.self, forKey: .operation)
        measure = try container.decodeIfPresent(MarinaSemanticMeasure.self, forKey: .measure)
        projection = try container.decodeIfPresent(MarinaSemanticProjection.self, forKey: .projection) ?? .records
        dimensions = try container.decodeIfPresent([MarinaSemanticDimension].self, forKey: .dimensions) ?? []
        constraints = try container.decodeIfPresent([MarinaSemanticConstraint].self, forKey: .constraints) ?? []
        dateRangeToken = try container.decodeIfPresent(MarinaSemanticDateRangeToken.self, forKey: .dateRangeToken) ?? .currentPeriod
        dateRangeSource = try container.decodeIfPresent(MarinaSemanticDateRangeSource.self, forKey: .dateRangeSource) ?? .defaulted
        targetName = try container.decodeIfPresent(String.self, forKey: .targetName)
        comparisonTargetName = try container.decodeIfPresent(String.self, forKey: .comparisonTargetName)
        textQuery = try container.decodeIfPresent(String.self, forKey: .textQuery)
        targetDisplayName = try container.decodeIfPresent(String.self, forKey: .targetDisplayName)
        resolvedTarget = try container.decodeIfPresent(MarinaResolvedEntityReference.self, forKey: .resolvedTarget)
        resolvedComparisonTarget = try container.decodeIfPresent(MarinaResolvedEntityReference.self, forKey: .resolvedComparisonTarget)
        resolvedScope = try container.decodeIfPresent(MarinaResolvedScope.self, forKey: .resolvedScope)
        targetKindSource = try container.decodeIfPresent(MarinaSemanticTargetKindSource.self, forKey: .targetKindSource) ?? .unspecified
        comparisonTargetKindSource = try container.decodeIfPresent(MarinaSemanticTargetKindSource.self, forKey: .comparisonTargetKindSource) ?? .unspecified
        continuationIntent = try container.decodeIfPresent(MarinaSemanticContinuationIntent.self, forKey: .continuationIntent) ?? .none
        resultLimit = try container.decodeIfPresent(Int.self, forKey: .resultLimit)
        resultOffset = try container.decodeIfPresent(Int.self, forKey: .resultOffset)
        sort = try container.decodeIfPresent(MarinaSemanticSort.self, forKey: .sort)
        expenseScope = try container.decodeIfPresent(MarinaSemanticExpenseScope.self, forKey: .expenseScope)
        incomeState = try container.decodeIfPresent(MarinaSemanticIncomeState.self, forKey: .incomeState)
        whatIfAmount = try container.decodeIfPresent(Double.self, forKey: .whatIfAmount)
        categoryAvailabilityFilter = try container.decodeIfPresent(MarinaCategoryAvailabilityFilter.self, forKey: .categoryAvailabilityFilter)
        expectedAnswerShape = try container.decodeIfPresent(MarinaSemanticAnswerShape.self, forKey: .expectedAnswerShape) ?? .metric
        clarificationQuestion = try container.decodeIfPresent(String.self, forKey: .clarificationQuestion)
        unsupportedReason = try container.decodeIfPresent(MarinaSemanticUnsupportedReason.self, forKey: .unsupportedReason)
    }
}

nonisolated enum MarinaSemanticConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

nonisolated enum MarinaSemanticSource: String, Codable, Equatable, Sendable {
    case foundationModel
    case unavailableFallback
}

nonisolated struct MarinaInterpretedSemanticRequest: Equatable, Sendable {
    var request: MarinaSemanticRequest
    var confidence: MarinaSemanticConfidence
    var source: MarinaSemanticSource
    var diagnosticNotes: [String]
    var attemptDiagnostics: [MarinaFoundationModelAttemptDiagnostic]
    var clarificationChoices: MarinaClarificationChoices?

    init(
        request: MarinaSemanticRequest,
        confidence: MarinaSemanticConfidence,
        source: MarinaSemanticSource,
        diagnosticNotes: [String] = [],
        attemptDiagnostics: [MarinaFoundationModelAttemptDiagnostic] = [],
        clarificationChoices: MarinaClarificationChoices? = nil
    ) {
        self.request = request
        self.confidence = confidence
        self.source = source
        self.diagnosticNotes = diagnosticNotes
        self.attemptDiagnostics = attemptDiagnostics
        self.clarificationChoices = clarificationChoices
    }
}

struct MarinaQueryPlan: Equatable {
    let id: UUID
    let semanticRequest: MarinaSemanticRequest
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let now: Date
    let clarificationChoices: MarinaClarificationChoices?

    init(
        id: UUID,
        semanticRequest: MarinaSemanticRequest,
        dateRange: HomeQueryDateRange?,
        comparisonDateRange: HomeQueryDateRange?,
        now: Date,
        clarificationChoices: MarinaClarificationChoices? = nil
    ) {
        self.id = id
        self.semanticRequest = semanticRequest
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.now = now
        self.clarificationChoices = clarificationChoices
    }

    var entity: MarinaSemanticEntity { semanticRequest.entity }
    var operation: MarinaSemanticOperation { semanticRequest.operation }
    var measure: MarinaSemanticMeasure? { semanticRequest.measure }
    var projection: MarinaSemanticProjection { semanticRequest.projection }
    var dimensions: [MarinaSemanticDimension] { semanticRequest.dimensions }
    var targetName: String? { semanticRequest.targetName }
    var comparisonTargetName: String? { semanticRequest.comparisonTargetName }
    var resolvedTarget: MarinaResolvedEntityReference? { semanticRequest.resolvedTarget }
    var resolvedComparisonTarget: MarinaResolvedEntityReference? { semanticRequest.resolvedComparisonTarget }
    var resolvedScope: MarinaResolvedScope? { semanticRequest.resolvedScope }
    var categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? { semanticRequest.categoryAvailabilityFilter }
    var resultLimit: Int { min(max(semanticRequest.resultLimit ?? 20, 1), HomeQuery.maxResultLimit) }
    var resultOffset: Int { max(semanticRequest.resultOffset ?? 0, 0) }
}

struct MarinaExecutionResult: Equatable {
    let kind: HomeAnswerKind
    let title: String
    let subtitle: String?
    let primaryValue: String?
    let rows: [HomeAnswerRow]
    let attachment: MarinaAttachment?
    let explanation: String?
    let displayedRowCount: Int?
    let totalRowCount: Int?
    let fullTotalAmount: Double?
    let hasMore: Bool?
    let nextOffset: Int?

    init(
        kind: HomeAnswerKind,
        title: String,
        subtitle: String? = nil,
        primaryValue: String? = nil,
        rows: [HomeAnswerRow] = [],
        attachment: MarinaAttachment? = nil,
        explanation: String? = nil,
        displayedRowCount: Int? = nil,
        totalRowCount: Int? = nil,
        fullTotalAmount: Double? = nil,
        hasMore: Bool? = nil,
        nextOffset: Int? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.rows = rows
        self.attachment = attachment
        self.explanation = explanation
        self.displayedRowCount = displayedRowCount
        self.totalRowCount = totalRowCount
        self.fullTotalAmount = fullTotalAmount
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }
}

struct MarinaAnswerSemanticRowReference: Codable, Equatable, Sendable {
    let title: String
    let value: String
    let sourceID: UUID?
    let objectType: MarinaLookupObjectType?
    let amount: Double?
    let date: Date?
    let role: HomeAnswerRowRole

    nonisolated init(row: HomeAnswerRow) {
        self.title = row.title
        self.value = row.value
        self.sourceID = row.sourceID
        self.objectType = row.objectType
        self.amount = row.amount
        self.date = row.date
        self.role = row.role
    }
}

struct MarinaAnswerSemanticContext: Codable, Equatable, Sendable {
    static let maxRowReferences = 8

    let request: MarinaSemanticRequest
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let answerKind: HomeAnswerKind
    let answerTitle: String
    let answerSubtitle: String?
    let primaryValue: String?
    let rowReferences: [MarinaAnswerSemanticRowReference]
    let displayedRowCount: Int?
    let totalRowCount: Int?
    let fullTotalAmount: Double?
    let hasMore: Bool?
    let nextOffset: Int?

    init(
        request: MarinaSemanticRequest,
        dateRange: HomeQueryDateRange?,
        comparisonDateRange: HomeQueryDateRange?,
        answerKind: HomeAnswerKind,
        answerTitle: String,
        answerSubtitle: String?,
        primaryValue: String?,
        rowReferences: [MarinaAnswerSemanticRowReference],
        displayedRowCount: Int? = nil,
        totalRowCount: Int? = nil,
        fullTotalAmount: Double? = nil,
        hasMore: Bool? = nil,
        nextOffset: Int? = nil
    ) {
        self.request = request
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.answerKind = answerKind
        self.answerTitle = answerTitle
        self.answerSubtitle = answerSubtitle
        self.primaryValue = primaryValue
        self.rowReferences = Array(rowReferences.prefix(Self.maxRowReferences))
        self.displayedRowCount = displayedRowCount
        self.totalRowCount = totalRowCount
        self.fullTotalAmount = fullTotalAmount
        self.hasMore = hasMore
        self.nextOffset = nextOffset
    }

    init(plan: MarinaQueryPlan, result: MarinaExecutionResult) {
        self.init(
            request: plan.semanticRequest,
            dateRange: plan.dateRange,
            comparisonDateRange: plan.comparisonDateRange,
            answerKind: result.kind,
            answerTitle: result.title,
            answerSubtitle: result.subtitle,
            primaryValue: result.primaryValue,
            rowReferences: result.rows.map(MarinaAnswerSemanticRowReference.init(row:)),
            displayedRowCount: result.displayedRowCount,
            totalRowCount: result.totalRowCount,
            fullTotalAmount: result.fullTotalAmount,
            hasMore: result.hasMore,
            nextOffset: result.nextOffset
        )
    }
}

struct MarinaConversationTurn: Codable, Equatable, Sendable {
    let userPrompt: String?
    let title: String
    let kind: HomeAnswerKind
    let subtitle: String?
    let primaryValue: String?
    let rowTitles: [String]
    let semanticContext: MarinaAnswerSemanticContext?
    let recommendedFollowUp: MarinaFollowUpSuggestion?
    let clarificationOptions: [MarinaClarificationChoice]

    init(
        userPrompt: String? = nil,
        title: String,
        kind: HomeAnswerKind,
        subtitle: String?,
        primaryValue: String?,
        rowTitles: [String],
        semanticContext: MarinaAnswerSemanticContext?,
        recommendedFollowUp: MarinaFollowUpSuggestion?,
        clarificationOptions: [MarinaClarificationChoice] = []
    ) {
        self.userPrompt = userPrompt
        self.title = title
        self.kind = kind
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.rowTitles = rowTitles
        self.semanticContext = semanticContext
        self.recommendedFollowUp = recommendedFollowUp
        self.clarificationOptions = Array(clarificationOptions.prefix(6))
    }

    private enum CodingKeys: String, CodingKey {
        case userPrompt
        case title
        case kind
        case subtitle
        case primaryValue
        case rowTitles
        case semanticContext
        case recommendedFollowUp
        case clarificationOptions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userPrompt = try container.decodeIfPresent(String.self, forKey: .userPrompt)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decode(HomeAnswerKind.self, forKey: .kind)
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
        primaryValue = try container.decodeIfPresent(String.self, forKey: .primaryValue)
        rowTitles = try container.decodeIfPresent([String].self, forKey: .rowTitles) ?? []
        semanticContext = try? container.decodeIfPresent(MarinaAnswerSemanticContext.self, forKey: .semanticContext)
        recommendedFollowUp = try? container.decodeIfPresent(MarinaFollowUpSuggestion.self, forKey: .recommendedFollowUp)
        clarificationOptions = (try? container.decodeIfPresent([MarinaClarificationChoice].self, forKey: .clarificationOptions)) ?? []
    }
}

struct MarinaConversationContext: Codable, Equatable, Sendable {
    nonisolated static let empty = MarinaConversationContext()
    nonisolated static let maxTurns = 5

    let recentTurns: [MarinaConversationTurn]

    nonisolated init(recentTurns: [MarinaConversationTurn] = []) {
        self.recentTurns = Array(recentTurns.suffix(Self.maxTurns))
    }

    init(recentAnswers: [HomeAnswer]) {
        self.init(
            recentTurns: recentAnswers.suffix(Self.maxTurns).map { answer in
                MarinaConversationTurn(
                    userPrompt: answer.userPrompt,
                    title: answer.title,
                    kind: answer.kind,
                    subtitle: answer.subtitle,
                    primaryValue: answer.primaryValue,
                    rowTitles: answer.rows.map(\.title),
                    semanticContext: answer.semanticContext,
                    recommendedFollowUp: MarinaRecommendedFollowUp.suggestion(from: answer.insightBundle?.followUps ?? []),
                    clarificationOptions: {
                        guard case let .clarificationChoices(choices)? = answer.attachment else { return [] }
                        return choices.choices
                    }()
                )
            }
        )
    }

    var lastTurn: MarinaConversationTurn? {
        recentTurns.last
    }

    var lastSemanticContext: MarinaAnswerSemanticContext? {
        recentTurns.reversed().compactMap(\.semanticContext).first
    }

    var lastRecommendedFollowUp: MarinaFollowUpSuggestion? {
        lastTurn?.recommendedFollowUp
    }

    var followUpMemory: MarinaFollowUpMemory {
        MarinaFollowUpMemory(recentTurns: recentTurns)
    }
}

struct MarinaFollowUpMemory: Codable, Equatable, Sendable {
    static let empty = MarinaFollowUpMemory()

    let recentSuggestions: [MarinaFollowUpMemoryEntry]
    let recentDeclines: [MarinaFollowUpMemoryEntry]
    let recentAcceptances: [MarinaFollowUpMemoryEntry]

    init(
        recentSuggestions: [MarinaFollowUpMemoryEntry] = [],
        recentDeclines: [MarinaFollowUpMemoryEntry] = [],
        recentAcceptances: [MarinaFollowUpMemoryEntry] = []
    ) {
        self.recentSuggestions = recentSuggestions
        self.recentDeclines = recentDeclines
        self.recentAcceptances = recentAcceptances
    }

    init(recentTurns: [MarinaConversationTurn]) {
        var suggestions: [MarinaFollowUpMemoryEntry] = []
        var declines: [MarinaFollowUpMemoryEntry] = []
        var acceptances: [MarinaFollowUpMemoryEntry] = []

        for turn in recentTurns {
            if let followUp = turn.recommendedFollowUp {
                suggestions.append(MarinaFollowUpMemoryEntry(followUp: followUp))
            }
        }

        for index in recentTurns.indices.dropFirst() {
            guard let previousFollowUp = recentTurns[recentTurns.index(before: index)].recommendedFollowUp,
                  let currentRequest = recentTurns[index].semanticContext?.request else {
                continue
            }

            let entry = MarinaFollowUpMemoryEntry(followUp: previousFollowUp)
            if currentRequest.expectedAnswerShape == .acknowledgement {
                declines.append(entry)
                continue
            }
            if let followUpRequest = previousFollowUp.semanticRequest,
               currentRequest == followUpRequest {
                acceptances.append(entry)
            }
        }

        self.init(
            recentSuggestions: suggestions,
            recentDeclines: declines,
            recentAcceptances: acceptances
        )
    }

    func shouldSuppress(_ suggestion: MarinaFollowUpSuggestion) -> Bool {
        let entry = MarinaFollowUpMemoryEntry(followUp: suggestion)
        return recentDeclines.contains { $0.fingerprint == entry.fingerprint }
            || recentSuggestions.contains { $0.fingerprint == entry.fingerprint }
    }

    func scorePenalty(for suggestion: MarinaFollowUpSuggestion) -> Int {
        let entry = MarinaFollowUpMemoryEntry(followUp: suggestion)
        if recentDeclines.contains(where: { $0.similarityKey == entry.similarityKey }) {
            return 200
        }
        if entry.reason == .showMore {
            return 0
        }
        if recentSuggestions.contains(where: { $0.similarityKey == entry.similarityKey }) {
            return 40
        }
        return 0
    }
}

struct MarinaFollowUpMemoryEntry: Codable, Equatable, Sendable {
    let reason: MarinaFollowUpSuggestion.Reason
    let fingerprint: String
    let similarityKey: String

    init(followUp: MarinaFollowUpSuggestion) {
        reason = followUp.reason
        fingerprint = Self.fingerprint(for: followUp, includeListLimit: true)
        similarityKey = Self.fingerprint(for: followUp, includeListLimit: false)
    }

    nonisolated private static func fingerprint(
        for followUp: MarinaFollowUpSuggestion,
        includeListLimit: Bool
    ) -> String {
        var components = [
            "reason:\(followUp.reason.rawValue)",
            "mode:\(followUp.executionMode.rawValue)"
        ]

        if let request = followUp.semanticRequest {
            components.append(contentsOf: [
                "entity:\(request.entity.rawValue)",
                "operation:\(request.operation.rawValue)",
                "measure:\(request.measure?.rawValue ?? "none")",
                "projection:\(request.projection.rawValue)",
                "shape:\(request.expectedAnswerShape.rawValue)",
                "date:\(request.dateRangeToken.rawValue)",
                "target:\(normalized(request.targetName))",
                "display:\(normalized(request.targetDisplayName))",
                "query:\(normalized(request.textQuery))",
                "comparison:\(normalized(request.comparisonTargetName))",
                "dimensions:\(request.dimensions.map(\.rawValue).sorted().joined(separator: ","))",
                "amount:\(request.whatIfAmount.map(Self.amountComponent) ?? "none")",
                "filter:\(request.categoryAvailabilityFilter?.rawValue ?? "none")",
                "scope:\(request.expenseScope?.rawValue ?? "none")",
                "incomeState:\(request.incomeState?.rawValue ?? "none")",
                "sort:\(request.sort?.rawValue ?? "none")",
                "resolvedScope:\(String(describing: request.resolvedScope))",
                "primaryID:\(request.resolvedTarget?.id?.uuidString ?? "none")",
                "comparisonID:\(request.resolvedComparisonTarget?.id?.uuidString ?? "none")"
            ])
            if includeListLimit {
                components.append("limit:\(request.resultLimit.map(String.init) ?? "none")")
                components.append("offset:\(request.resultOffset.map(String.init) ?? "none")")
            }
        } else {
            components.append("prompt:\(normalized(followUp.prompt))")
        }

        return components.joined(separator: "|")
    }

    nonisolated private static func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    nonisolated private static func amountComponent(_ amount: Double) -> String {
        String(Int((amount * 100).rounded()))
    }
}

struct MarinaBrainContext {
    let workspace: Workspace
    let modelContext: ModelContext
    let homeContext: MarinaPanelHomeContext?
    let defaultBudgetingPeriod: BudgetingPeriod
    let now: Date
    let conversationContext: MarinaConversationContext

    init(
        workspace: Workspace,
        modelContext: ModelContext,
        ambientDateRange: HomeQueryDateRange?,
        defaultBudgetingPeriod: BudgetingPeriod,
        now: Date,
        homeContext: MarinaPanelHomeContext? = nil,
        conversationContext: MarinaConversationContext = .empty
    ) {
        self.workspace = workspace
        self.modelContext = modelContext
        self.homeContext = homeContext ?? ambientDateRange.map { MarinaPanelHomeContext(dateRange: $0) }
        self.defaultBudgetingPeriod = defaultBudgetingPeriod
        self.now = now
        self.conversationContext = conversationContext
    }

    var ambientDateRange: HomeQueryDateRange? {
        homeContext?.dateRange
    }
}
