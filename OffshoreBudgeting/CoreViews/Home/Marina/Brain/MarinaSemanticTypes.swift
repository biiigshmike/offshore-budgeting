import Foundation
import SwiftData

enum MarinaSemanticEntity: String, Codable, CaseIterable, Equatable, Sendable {
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

enum MarinaSemanticOperation: String, Codable, CaseIterable, Equatable, Sendable {
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

enum MarinaSemanticMeasure: String, Codable, CaseIterable, Equatable, Sendable {
    case amount
    case plannedAmount
    case actualAmount
    case effectiveAmount
    case budgetImpact
    case savingsTotal
    case incomeAmount
    case reconciliationBalance
    case remainingRoom
    case color
    case name
}

enum MarinaSemanticDimension: String, Codable, CaseIterable, Equatable, Sendable {
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

enum MarinaSemanticDateRangeToken: String, Codable, CaseIterable, Equatable, Sendable {
    case currentPeriod
    case previousPeriod
    case currentMonth
    case previousMonth
    case nextSevenDays
    case allTime
}

enum MarinaSemanticSort: String, Codable, CaseIterable, Equatable, Sendable {
    case dateAscending
    case dateDescending
    case amountAscending
    case amountDescending
    case nameAscending
}

enum MarinaSemanticAnswerShape: String, Codable, CaseIterable, Equatable, Sendable {
    case metric
    case list
    case comparison
    case clarification
    case unsupported
}

enum MarinaSemanticExpenseScope: String, Codable, CaseIterable, Equatable, Sendable {
    case planned
    case variable
    case unified
}

enum MarinaSemanticIncomeState: String, Codable, CaseIterable, Equatable, Sendable {
    case planned
    case actual
    case all
}

enum MarinaSemanticUnsupportedReason: String, Codable, Equatable, Sendable {
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

struct MarinaSemanticRequest: Codable, Equatable, Sendable {
    var entity: MarinaSemanticEntity
    var operation: MarinaSemanticOperation
    var measure: MarinaSemanticMeasure?
    var dimensions: [MarinaSemanticDimension]
    var dateRangeToken: MarinaSemanticDateRangeToken
    var targetName: String?
    var comparisonTargetName: String?
    var textQuery: String?
    var resultLimit: Int?
    var sort: MarinaSemanticSort?
    var expenseScope: MarinaSemanticExpenseScope?
    var incomeState: MarinaSemanticIncomeState?
    var whatIfAmount: Double?
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
        resultLimit: Int? = nil,
        sort: MarinaSemanticSort? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        incomeState: MarinaSemanticIncomeState? = nil,
        whatIfAmount: Double? = nil,
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
        self.resultLimit = resultLimit
        self.sort = sort
        self.expenseScope = expenseScope
        self.incomeState = incomeState
        self.whatIfAmount = whatIfAmount
        self.expectedAnswerShape = expectedAnswerShape
        self.clarificationQuestion = clarificationQuestion
        self.unsupportedReason = unsupportedReason
    }
}

enum MarinaSemanticConfidence: String, Codable, Equatable, Sendable {
    case high
    case medium
    case low
}

enum MarinaSemanticSource: String, Codable, Equatable, Sendable {
    case ruleBased
    case foundationModel
    case repairedFoundationModel
    case unavailableFallback
}

struct MarinaInterpretedSemanticRequest: Equatable, Sendable {
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

struct MarinaBrainContext {
    let workspace: Workspace
    let modelContext: ModelContext
    let ambientDateRange: HomeQueryDateRange?
    let defaultBudgetingPeriod: BudgetingPeriod
    let now: Date
}
