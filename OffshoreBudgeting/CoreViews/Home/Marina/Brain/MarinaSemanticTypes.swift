// Compatibility-only payloads for previously saved chat answers.
// New conversations do not execute semantic requests.
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
    case yearToDate
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
    case incomeSavingsWhatIfUnsupported
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
        fullTotalAmount: Double? = nil
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
    }

}
