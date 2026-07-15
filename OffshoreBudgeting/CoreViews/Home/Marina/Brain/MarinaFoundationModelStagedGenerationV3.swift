import Foundation

#if canImport(FoundationModels)
import FoundationModels

/// Phase one separates financial queries from Workspace metadata and terminal
/// outcomes. It deliberately does not ask the model to choose a financial
/// domain while Workspace is present in the same generated schema.
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable(description: "Choose exactly one Marina V3.1 outcome route. financialQuery covers supported budgeting and financial questions. workspaceMetadata is only for the Workspace's own name, color, list, or count.")
enum MarinaFoundationModelGeneratedOutcomeRouteV3: Equatable, Sendable {
    case financialQuery
    case workspaceMetadata
    case clarificationSelection
    case followUpDecision
    case unsupported
}

@available(iOS 26.0, macCatalyst 26.0, *)
extension MarinaFoundationModelGeneratedOutcomeRouteV3 {
    var generatedIntentDigest: MarinaFoundationModelGeneratedIntentDigest {
        switch self {
        case .financialQuery:
            MarinaFoundationModelGeneratedIntentDigest(intent: .query)
        case .workspaceMetadata:
            MarinaFoundationModelGeneratedIntentDigest(
                intent: .workspaceMetadata,
                entity: .workspace
            )
        case .clarificationSelection:
            MarinaFoundationModelGeneratedIntentDigest(intent: .clarificationSelection)
        case .followUpDecision:
            MarinaFoundationModelGeneratedIntentDigest(intent: .followUpDecision)
        case .unsupported:
            MarinaFoundationModelGeneratedIntentDigest(intent: .unsupported)
        }
    }

    var diagnosticDigest: MarinaFoundationModelGeneratedOutcomeRouteDigest {
        switch self {
        case .financialQuery: .financialQuery
        case .workspaceMetadata: .workspaceMetadata
        case .clarificationSelection: .clarificationSelection
        case .followUpDecision: .followUpDecision
        case .unsupported: .unsupported
        }
    }

}

/// The only schema choices phase one may unlock. This plan contains no prompt,
/// catalog anchor, or expected semantic tuple.
@available(iOS 26.0, macCatalyst 26.0, *)
enum MarinaFoundationModelOutcomePayloadSchemaV3: Equatable, Sendable {
    case financialDomain
    case workspaceMetadata
    case clarificationSelection
    case followUpDecision
    case unsupported

    init(modelAuthoredRoute route: MarinaFoundationModelGeneratedOutcomeRouteV3) {
        self = switch route {
        case .financialQuery: .financialDomain
        case .workspaceMetadata: .workspaceMetadata
        case .clarificationSelection: .clarificationSelection
        case .followUpDecision: .followUpDecision
        case .unsupported: .unsupported
        }
    }
}

/// A type-level source boundary: staged generation planning accepts only the
/// model-authored route and retains only its one-to-one payload schema.
@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFoundationModelOutcomeGenerationPlanV3: Equatable, Sendable {
    let payloadSchema: MarinaFoundationModelOutcomePayloadSchemaV3

    init(modelAuthoredRoute: MarinaFoundationModelGeneratedOutcomeRouteV3) {
        payloadSchema = MarinaFoundationModelOutcomePayloadSchemaV3(
            modelAuthoredRoute: modelAuthoredRoute
        )
    }
}

/// Phase two for a financial query. Workspace is structurally absent.
@available(iOS 26.0, macCatalyst 26.0, *)
@Generable(description: "Choose the financial domain the requested answer is about. The active Workspace boundary is already fixed and is not a selectable subject.")
enum MarinaFoundationModelGeneratedFinancialDomainV3: Equatable, Sendable {
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

/// Internal query-domain routing. Only model-authored output can construct the
/// next action schema; prompt text is intentionally unavailable here.
@available(iOS 26.0, macCatalyst 26.0, *)
enum MarinaFoundationModelQueryDomainV3: Equatable, Sendable {
    case workspaceMetadata
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

@available(iOS 26.0, macCatalyst 26.0, *)
extension MarinaFoundationModelGeneratedFinancialDomainV3 {
    var queryDomain: MarinaFoundationModelQueryDomainV3 {
        switch self {
        case .budget: .budget
        case .card: .card
        case .plannedExpense: .plannedExpense
        case .variableExpense: .variableExpense
        case .reconciliationAccount: .reconciliationAccount
        case .savingsAccount: .savingsAccount
        case .income: .income
        case .incomeSeries: .incomeSeries
        case .category: .category
        case .preset: .preset
        }
    }

    var generatedIntentDigest: MarinaFoundationModelGeneratedIntentDigest {
        MarinaFoundationModelGeneratedIntentDigest(
            intent: .query,
            entity: queryDomain.semanticEntity
        )
    }

    var diagnosticDigest: MarinaFoundationModelGeneratedFinancialDomainDigest {
        switch self {
        case .budget: .budget
        case .card: .card
        case .plannedExpense: .plannedExpense
        case .variableExpense: .variableExpense
        case .reconciliationAccount: .reconciliationAccount
        case .savingsAccount: .savingsAccount
        case .income: .income
        case .incomeSeries: .incomeSeries
        case .category: .category
        case .preset: .preset
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
extension MarinaFoundationModelQueryDomainV3 {
    var semanticEntity: MarinaSemanticEntity {
        switch self {
        case .workspaceMetadata: .workspace
        case .budget: .budget
        case .card: .card
        case .plannedExpense: .plannedExpense
        case .variableExpense: .variableExpense
        case .reconciliationAccount: .reconciliationAccount
        case .savingsAccount: .savingsAccount
        case .income: .income
        case .incomeSeries: .incomeSeries
        case .category: .category
        case .preset: .preset
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFoundationModelFinancialDomainGenerationPlanV3: Equatable, Sendable {
    let queryDomain: MarinaFoundationModelQueryDomainV3

    init(modelAuthoredDomain: MarinaFoundationModelGeneratedFinancialDomainV3) {
        queryDomain = modelAuthoredDomain.queryDomain
    }
}

/// The model-authored action phase. Only the enum for the previously selected
/// query domain is exposed to the model.
@available(iOS 26.0, macCatalyst 26.0, *)
enum MarinaFoundationModelGeneratedActionRouteV3 {
    @Generable enum WorkspaceMetadata: Equatable, Sendable {
        case list
        case count
        case name
        case color
    }

    @Generable enum Budget: Equatable, Sendable {
        case list
        case sum
        case average
        case compare
        case forecast
        case whatIf
    }

    @Generable enum Card: Equatable, Sendable {
        case list
        case count
        case sum
        case compare
        case group
    }

    @Generable enum PlannedExpense: Equatable, Sendable {
        case list
        case count
        case sum
        case average
        case last
        case next
        case group
    }

    @Generable enum VariableExpense: Equatable, Sendable {
        case list
        case count
        case sum
        case average
        case last
        case group
    }

    @Generable enum ReconciliationAccount: Equatable, Sendable {
        case list
        case count
        case sum
        case group
    }

    @Generable enum SavingsAccount: Equatable, Sendable {
        case list
        case count
        case sum
        case last
        case group
        case forecast
    }

    @Generable enum Income: Equatable, Sendable {
        case list
        case count
        case sum
        case average
        case compare
        case group
        case progress
        case coverage
        case forecast
    }

    @Generable enum IncomeSeries: Equatable, Sendable {
        case list
        case count
        case last
        case next
    }

    @Generable enum Category: Equatable, Sendable {
        case list
        case count
        case sum
        case average
        case compare
        case groupedSpend
        case share
        case forecast
        case availabilitySummary
        case availabilityList
    }

    @Generable enum Preset: Equatable, Sendable {
        case list
        case sum
        case next
        case group
    }
}

/// Erases the domain-specific action-route type without erasing its model
/// authorship. It carries no prompt or semantic payload fields.
@available(iOS 26.0, macCatalyst 26.0, *)
enum MarinaFoundationModelAuthoredActionRouteV3: Equatable, Sendable {
    typealias Route = MarinaFoundationModelGeneratedActionRouteV3

    case workspaceMetadata(Route.WorkspaceMetadata)
    case budget(Route.Budget)
    case card(Route.Card)
    case plannedExpense(Route.PlannedExpense)
    case variableExpense(Route.VariableExpense)
    case reconciliationAccount(Route.ReconciliationAccount)
    case savingsAccount(Route.SavingsAccount)
    case income(Route.Income)
    case incomeSeries(Route.IncomeSeries)
    case category(Route.Category)
    case preset(Route.Preset)
}

/// Exactly one third-phase schema. Each case is selected only from the
/// model-authored domain route and action route.
@available(iOS 26.0, macCatalyst 26.0, *)
enum MarinaFoundationModelActionPayloadSchemaV3: String, CaseIterable, Equatable, Hashable, Sendable {
    case workspaceList, workspaceCount, workspaceName, workspaceColor
    case budgetList, budgetSum, budgetAverage, budgetCompare, budgetForecast, budgetWhatIf
    case cardList, cardCount, cardSum, cardCompare, cardGroup
    case plannedExpenseList, plannedExpenseCount, plannedExpenseSum, plannedExpenseAverage
    case plannedExpenseLast, plannedExpenseNext, plannedExpenseGroup
    case variableExpenseList, variableExpenseCount, variableExpenseSum, variableExpenseAverage
    case variableExpenseLast, variableExpenseGroup
    case reconciliationList, reconciliationCount, reconciliationSum, reconciliationGroup
    case savingsList, savingsCount, savingsSum, savingsLast, savingsGroup, savingsForecast
    case incomeList, incomeCount, incomeSum, incomeAverage, incomeCompare, incomeGroup
    case incomeProgress, incomeCoverage, incomeForecast
    case incomeSeriesList, incomeSeriesCount, incomeSeriesLast, incomeSeriesNext
    case categoryList, categoryCount, categorySum, categoryAverage, categoryCompare
    case categoryGroupedSpend, categoryShare, categoryForecast
    case categoryAvailabilitySummary, categoryAvailabilityList
    case presetList, presetSum, presetNext, presetGroup

    init(modelAuthoredActionRoute route: MarinaFoundationModelAuthoredActionRouteV3) {
        self = switch route {
        case .workspaceMetadata(let action): switch action {
        case .list: .workspaceList
        case .count: .workspaceCount
        case .name: .workspaceName
        case .color: .workspaceColor
        }
        case .budget(let action): switch action {
        case .list: .budgetList
        case .sum: .budgetSum
        case .average: .budgetAverage
        case .compare: .budgetCompare
        case .forecast: .budgetForecast
        case .whatIf: .budgetWhatIf
        }
        case .card(let action): switch action {
        case .list: .cardList
        case .count: .cardCount
        case .sum: .cardSum
        case .compare: .cardCompare
        case .group: .cardGroup
        }
        case .plannedExpense(let action): switch action {
        case .list: .plannedExpenseList
        case .count: .plannedExpenseCount
        case .sum: .plannedExpenseSum
        case .average: .plannedExpenseAverage
        case .last: .plannedExpenseLast
        case .next: .plannedExpenseNext
        case .group: .plannedExpenseGroup
        }
        case .variableExpense(let action): switch action {
        case .list: .variableExpenseList
        case .count: .variableExpenseCount
        case .sum: .variableExpenseSum
        case .average: .variableExpenseAverage
        case .last: .variableExpenseLast
        case .group: .variableExpenseGroup
        }
        case .reconciliationAccount(let action): switch action {
        case .list: .reconciliationList
        case .count: .reconciliationCount
        case .sum: .reconciliationSum
        case .group: .reconciliationGroup
        }
        case .savingsAccount(let action): switch action {
        case .list: .savingsList
        case .count: .savingsCount
        case .sum: .savingsSum
        case .last: .savingsLast
        case .group: .savingsGroup
        case .forecast: .savingsForecast
        }
        case .income(let action): switch action {
        case .list: .incomeList
        case .count: .incomeCount
        case .sum: .incomeSum
        case .average: .incomeAverage
        case .compare: .incomeCompare
        case .group: .incomeGroup
        case .progress: .incomeProgress
        case .coverage: .incomeCoverage
        case .forecast: .incomeForecast
        }
        case .incomeSeries(let action): switch action {
        case .list: .incomeSeriesList
        case .count: .incomeSeriesCount
        case .last: .incomeSeriesLast
        case .next: .incomeSeriesNext
        }
        case .category(let action): switch action {
        case .list: .categoryList
        case .count: .categoryCount
        case .sum: .categorySum
        case .average: .categoryAverage
        case .compare: .categoryCompare
        case .groupedSpend: .categoryGroupedSpend
        case .share: .categoryShare
        case .forecast: .categoryForecast
        case .availabilitySummary: .categoryAvailabilitySummary
        case .availabilityList: .categoryAvailabilityList
        }
        case .preset(let action): switch action {
        case .list: .presetList
        case .sum: .presetSum
        case .next: .presetNext
        case .group: .presetGroup
        }
        }
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
struct MarinaFoundationModelActionGenerationPlanV3: Equatable, Sendable {
    let payloadSchema: MarinaFoundationModelActionPayloadSchemaV3

    init(modelAuthoredActionRoute: MarinaFoundationModelAuthoredActionRouteV3) {
        payloadSchema = MarinaFoundationModelActionPayloadSchemaV3(
            modelAuthoredActionRoute: modelAuthoredActionRoute
        )
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
extension MarinaFoundationModelAuthoredActionRouteV3 {
    var generatedIntentDigest: MarinaFoundationModelGeneratedIntentDigest {
        let schema = MarinaFoundationModelActionPayloadSchemaV3(modelAuthoredActionRoute: self)
        return MarinaFoundationModelGeneratedIntentDigest(
            intent: schema.intentKind,
            entity: schema.entity,
            operation: schema.operation
        )
    }
}

@available(iOS 26.0, macCatalyst 26.0, *)
extension MarinaFoundationModelActionPayloadSchemaV3 {
    var diagnosticDigest: MarinaFoundationModelGeneratedActionPayloadDigest {
        guard let digest = MarinaFoundationModelGeneratedActionPayloadDigest(rawValue: rawValue) else {
            preconditionFailure("Every V3 action schema must have a redacted diagnostic digest.")
        }
        return digest
    }

    var entity: MarinaSemanticEntity {
        switch self {
        case .workspaceList, .workspaceCount, .workspaceName, .workspaceColor: .workspace
        case .budgetList, .budgetSum, .budgetAverage, .budgetCompare, .budgetForecast, .budgetWhatIf: .budget
        case .cardList, .cardCount, .cardSum, .cardCompare, .cardGroup: .card
        case .plannedExpenseList, .plannedExpenseCount, .plannedExpenseSum, .plannedExpenseAverage,
             .plannedExpenseLast, .plannedExpenseNext, .plannedExpenseGroup: .plannedExpense
        case .variableExpenseList, .variableExpenseCount, .variableExpenseSum, .variableExpenseAverage,
             .variableExpenseLast, .variableExpenseGroup: .variableExpense
        case .reconciliationList, .reconciliationCount, .reconciliationSum, .reconciliationGroup: .reconciliationAccount
        case .savingsList, .savingsCount, .savingsSum, .savingsLast, .savingsGroup, .savingsForecast: .savingsAccount
        case .incomeList, .incomeCount, .incomeSum, .incomeAverage, .incomeCompare, .incomeGroup,
             .incomeProgress, .incomeCoverage, .incomeForecast: .income
        case .incomeSeriesList, .incomeSeriesCount, .incomeSeriesLast, .incomeSeriesNext: .incomeSeries
        case .categoryList, .categoryCount, .categorySum, .categoryAverage, .categoryCompare,
             .categoryGroupedSpend, .categoryShare, .categoryForecast,
             .categoryAvailabilitySummary, .categoryAvailabilityList: .category
        case .presetList, .presetSum, .presetNext, .presetGroup: .preset
        }
    }

    var operation: MarinaSemanticOperation {
        switch self {
        case .workspaceList, .workspaceName, .workspaceColor, .budgetList, .cardList,
             .plannedExpenseList, .variableExpenseList, .reconciliationList, .savingsList,
             .incomeList, .incomeSeriesList, .categoryList, .presetList: .list
        case .workspaceCount, .cardCount, .plannedExpenseCount, .variableExpenseCount,
             .reconciliationCount, .savingsCount, .incomeCount, .incomeSeriesCount, .categoryCount: .count
        case .budgetSum, .cardSum, .plannedExpenseSum, .variableExpenseSum,
             .reconciliationSum, .savingsSum, .incomeSum, .categorySum, .presetSum: .sum
        case .budgetAverage, .plannedExpenseAverage, .variableExpenseAverage,
             .incomeAverage, .categoryAverage: .average
        case .budgetCompare, .cardCompare, .incomeCompare, .categoryCompare: .compare
        case .plannedExpenseLast, .variableExpenseLast, .savingsLast, .incomeSeriesLast: .last
        case .plannedExpenseNext, .incomeSeriesNext, .presetNext: .next
        case .cardGroup, .plannedExpenseGroup, .variableExpenseGroup, .reconciliationGroup,
             .savingsGroup, .incomeGroup, .categoryGroupedSpend, .presetGroup: .group
        case .incomeProgress, .incomeCoverage, .categoryShare: .share
        case .budgetForecast, .savingsForecast, .incomeForecast, .categoryForecast,
             .categoryAvailabilitySummary: .forecast
        case .categoryAvailabilityList: .list
        case .budgetWhatIf: .whatIf
        }
    }

    var intentKind: MarinaFoundationModelGeneratedIntentKind {
        if entity == .workspace { return .workspaceMetadata }
        return switch self {
        case .categoryAvailabilitySummary, .categoryAvailabilityList: .categoryAvailability
        case .budgetCompare, .cardCompare, .incomeCompare, .categoryCompare: .comparison
        case .cardGroup, .plannedExpenseGroup, .variableExpenseGroup, .reconciliationGroup,
             .savingsGroup, .incomeGroup, .categoryGroupedSpend, .presetGroup: .groupedList
        case .budgetList, .cardList, .plannedExpenseList, .variableExpenseList,
             .reconciliationList, .savingsList, .incomeList, .incomeSeriesList,
             .categoryList, .presetList: .recordList
        default: .query
        }
    }
}
#endif
