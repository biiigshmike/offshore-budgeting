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
    case category
    case preset
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
    case savingsTotal
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
    case preset
    case savingsAccount
    case reconciliationAccount
    case workspace
}

nonisolated enum MarinaSemanticDateRangeToken: String, Codable, CaseIterable, Equatable, Sendable {
    case currentPeriod
    case previousPeriod
    case currentMonth
    case previousMonth
    case nextSevenDays
    case allTime
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
}

nonisolated struct MarinaSemanticRequest: Codable, Equatable, Sendable {
    var entity: MarinaSemanticEntity
    var operation: MarinaSemanticOperation
    var measure: MarinaSemanticMeasure?
    var dimensions: [MarinaSemanticDimension]
    var dateRangeToken: MarinaSemanticDateRangeToken
    var targetName: String?
    var comparisonTargetName: String?
    var textQuery: String?
    var targetDisplayName: String?
    var resultLimit: Int?
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
        dimensions: [MarinaSemanticDimension] = [],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentPeriod,
        targetName: String? = nil,
        comparisonTargetName: String? = nil,
        textQuery: String? = nil,
        targetDisplayName: String? = nil,
        resultLimit: Int? = nil,
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
        self.dimensions = dimensions
        self.dateRangeToken = dateRangeToken
        self.targetName = targetName
        self.comparisonTargetName = comparisonTargetName
        self.textQuery = textQuery
        self.targetDisplayName = targetDisplayName
        self.resultLimit = resultLimit
        self.sort = sort
        self.expenseScope = expenseScope
        self.incomeState = incomeState
        self.whatIfAmount = whatIfAmount
        self.categoryAvailabilityFilter = categoryAvailabilityFilter
        self.expectedAnswerShape = expectedAnswerShape
        self.clarificationQuestion = clarificationQuestion
        self.unsupportedReason = unsupportedReason
    }
}

nonisolated enum MarinaSemanticConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

nonisolated enum MarinaSemanticSource: String, Codable, Equatable, Sendable {
    case ruleBased
    case foundationModel
    case repairedFoundationModel
    case unavailableFallback
}

nonisolated struct MarinaInterpretedSemanticRequest: Equatable, Sendable {
    var request: MarinaSemanticRequest
    var confidence: MarinaSemanticConfidence
    var source: MarinaSemanticSource
    var diagnosticNotes: [String]
    var clarificationChoices: MarinaClarificationChoices?

    init(
        request: MarinaSemanticRequest,
        confidence: MarinaSemanticConfidence,
        source: MarinaSemanticSource,
        diagnosticNotes: [String] = [],
        clarificationChoices: MarinaClarificationChoices? = nil
    ) {
        self.request = request
        self.confidence = confidence
        self.source = source
        self.diagnosticNotes = diagnosticNotes
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
    var dimensions: [MarinaSemanticDimension] { semanticRequest.dimensions }
    var targetName: String? { semanticRequest.targetName }
    var comparisonTargetName: String? { semanticRequest.comparisonTargetName }
    var categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? { semanticRequest.categoryAvailabilityFilter }
    var resultLimit: Int { min(max(semanticRequest.resultLimit ?? 5, 1), HomeQuery.maxResultLimit) }
}

struct MarinaExecutionResult: Equatable {
    let kind: HomeAnswerKind
    let title: String
    let subtitle: String?
    let primaryValue: String?
    let rows: [HomeAnswerRow]
    let attachment: MarinaAttachment?
    let explanation: String?

    init(
        kind: HomeAnswerKind,
        title: String,
        subtitle: String? = nil,
        primaryValue: String? = nil,
        rows: [HomeAnswerRow] = [],
        attachment: MarinaAttachment? = nil,
        explanation: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.rows = rows
        self.attachment = attachment
        self.explanation = explanation
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

    init(
        request: MarinaSemanticRequest,
        dateRange: HomeQueryDateRange?,
        comparisonDateRange: HomeQueryDateRange?,
        answerKind: HomeAnswerKind,
        answerTitle: String,
        answerSubtitle: String?,
        primaryValue: String?,
        rowReferences: [MarinaAnswerSemanticRowReference]
    ) {
        self.request = request
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.answerKind = answerKind
        self.answerTitle = answerTitle
        self.answerSubtitle = answerSubtitle
        self.primaryValue = primaryValue
        self.rowReferences = Array(rowReferences.prefix(Self.maxRowReferences))
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
            rowReferences: result.rows.map(MarinaAnswerSemanticRowReference.init(row:))
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

    init(
        userPrompt: String? = nil,
        title: String,
        kind: HomeAnswerKind,
        subtitle: String?,
        primaryValue: String?,
        rowTitles: [String],
        semanticContext: MarinaAnswerSemanticContext?,
        recommendedFollowUp: MarinaFollowUpSuggestion?
    ) {
        self.userPrompt = userPrompt
        self.title = title
        self.kind = kind
        self.subtitle = subtitle
        self.primaryValue = primaryValue
        self.rowTitles = rowTitles
        self.semanticContext = semanticContext
        self.recommendedFollowUp = recommendedFollowUp
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
                    recommendedFollowUp: MarinaRecommendedFollowUp.suggestion(from: answer.insightBundle?.followUps ?? [])
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
                  let prompt = recentTurns[index].userPrompt else {
                continue
            }

            let entry = MarinaFollowUpMemoryEntry(followUp: previousFollowUp)
            if MarinaRecommendedFollowUp.isNegative(prompt) {
                declines.append(entry)
            } else if MarinaRecommendedFollowUp.isAffirmative(prompt) {
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
            || repeatedShowMore(entry)
    }

    func scorePenalty(for suggestion: MarinaFollowUpSuggestion) -> Int {
        let entry = MarinaFollowUpMemoryEntry(followUp: suggestion)
        if recentDeclines.contains(where: { $0.similarityKey == entry.similarityKey }) {
            return 200
        }
        if recentSuggestions.contains(where: { $0.similarityKey == entry.similarityKey }) {
            return 40
        }
        return 0
    }

    private func repeatedShowMore(_ entry: MarinaFollowUpMemoryEntry) -> Bool {
        entry.reason == .showMore
            && recentSuggestions.contains {
                $0.reason == .showMore && $0.similarityKey == entry.similarityKey
            }
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
                "sort:\(request.sort?.rawValue ?? "none")"
            ])
            if includeListLimit {
                components.append("limit:\(request.resultLimit.map(String.init) ?? "none")")
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

    init(
        workspace: Workspace,
        modelContext: ModelContext,
        ambientDateRange: HomeQueryDateRange?,
        defaultBudgetingPeriod: BudgetingPeriod,
        now: Date,
        homeContext: MarinaPanelHomeContext? = nil
    ) {
        self.workspace = workspace
        self.modelContext = modelContext
        self.homeContext = homeContext ?? ambientDateRange.map { MarinaPanelHomeContext(dateRange: $0) }
        self.defaultBudgetingPeriod = defaultBudgetingPeriod
        self.now = now
    }

    var ambientDateRange: HomeQueryDateRange? {
        homeContext?.dateRange
    }
}
