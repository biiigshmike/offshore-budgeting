import Foundation

enum MarinaInterpretationSource: String, Codable, Equatable, Sendable {
    case deterministic
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
    case relationshipList
    case membershipStatus
    case comparison
    case rankedList
    case groupedBreakdown
    case chartRows
    case clarification
    case unsupported

    var isAdvisory: Bool { true }
}

enum MarinaInsightIntent: String, Codable, Equatable, CaseIterable, Sendable {
    case changeSummary
    case contributorAnalysis
    case normalityCheck
    case watchOuts
    case explainBudgeting
    case multiPartContributors
}

enum MarinaInsightSoftTimeHint: String, Codable, Equatable, CaseIterable, Sendable {
    case lately
    case sincePayday
    case budgetCycle
    case aroundTrip
}

enum MarinaRequestFamily: String, Codable, Sendable, Equatable {
    case analytics
    case databaseLookup
    case command
    case help
    case planning
    case unsupported
}

enum MarinaRequestShape: String, Codable, Sendable, Equatable {
    case objectInventoryList
    case ledgerRowList
    case objectDetails
    case relationshipList
    case aggregateMetric
}

enum MarinaRouteIntentKind: String, Codable, Sendable, Equatable {
    case generic
    case databaseLookup
    case budgetInventory
    case activeBudget
    case budgetMembership
    case budgetLinkedCards
    case budgetLinkedPresets
    case budgetCategoryLimits
    case budgetCategoryLimit
    case overBudgetCategories
    case plannedExpenseRows
    case presetTemplateRows
    case plannedExpenseByCategory
    case plannedExpenseByCard
    case plannedExpenseByPreset
    case savingsStatus
    case savingsActivity
    case savingsMovementRanking
    case incomePlannedVsActual
    case reconciliationBalance
    case allocationRows
    case settlementRows
    case recentTransactionRows
    case broadSpend
}

enum MarinaPreferredExecutorRoute: String, Codable, Sendable, Equatable {
    case lookupDetail
    case list
    case aggregate
    case comparison
    case groupedRanked
    case scenario
    case databaseLookup
    case homeAdapter
    case composableWorkspace
    case workspaceAggregation
}

struct MarinaRouteIntent: Codable, Sendable, Equatable {
    let kind: MarinaRouteIntentKind
    let subject: MarinaSubject
    let operation: MarinaCandidateOperation
    let measure: MarinaCandidateMeasure
    let grouping: MarinaGroupingDimensionCandidate?
    let targetTypes: [MarinaCandidateEntityTypeHint]
    let requestedDetail: MarinaSemanticRequestedDetail?
    let responseShape: MarinaResponseShapeHint?
    let preferredExecutorRoute: MarinaPreferredExecutorRoute?
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
    case workspaces
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
    case linkedCards
    case linkedPresets
    case categoryLimits
    case membership
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
    let incomeStatusScope: MarinaIncomeStatusScope?
    let requestedDetail: MarinaSemanticRequestedDetail?
    let insightIntent: MarinaInsightIntent?
    let softTimeHint: MarinaInsightSoftTimeHint?

    init(
        family: MarinaRequestFamily,
        action: MarinaSemanticCommandAction,
        datasets: [MarinaSemanticCommandDataset],
        measure: MarinaCandidateMeasure? = nil,
        includeFilters: [MarinaSemanticCommandFilter] = [],
        excludeFilters: [MarinaSemanticCommandFilter] = [],
        grouping: MarinaGroupingDimensionCandidate? = nil,
        sort: MarinaSemanticCommandSort? = nil,
        dateRange: HomeQueryDateRange? = nil,
        comparisonDateRange: HomeQueryDateRange? = nil,
        periodUnit: HomeQueryPeriodUnit? = nil,
        limit: Int? = nil,
        incomeStatusScope: MarinaIncomeStatusScope? = nil,
        requestedDetail: MarinaSemanticRequestedDetail? = nil,
        insightIntent: MarinaInsightIntent? = nil,
        softTimeHint: MarinaInsightSoftTimeHint? = nil
    ) {
        self.family = family
        self.action = action
        self.datasets = datasets
        self.measure = measure
        self.includeFilters = includeFilters
        self.excludeFilters = excludeFilters
        self.grouping = grouping
        self.sort = sort
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.periodUnit = periodUnit
        self.limit = limit
        self.incomeStatusScope = incomeStatusScope
        self.requestedDetail = requestedDetail
        self.insightIntent = insightIntent
        self.softTimeHint = softTimeHint
    }
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
    let source: MarinaInterpretationSource
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
    let requestShape: MarinaRequestShape?
    let insightIntent: MarinaInsightIntent?
    let softTimeHint: MarinaInsightSoftTimeHint?
    let routeIntent: MarinaRouteIntent?

    init(
        requestFamily: MarinaRequestFamily = .analytics,
        source: MarinaInterpretationSource,
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
        semanticCommand: MarinaSemanticCommand? = nil,
        requestShape: MarinaRequestShape? = nil,
        insightIntent: MarinaInsightIntent? = nil,
        softTimeHint: MarinaInsightSoftTimeHint? = nil,
        routeIntent: MarinaRouteIntent? = nil
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
        self.requestShape = requestShape
        self.insightIntent = insightIntent
        self.softTimeHint = softTimeHint
        self.routeIntent = routeIntent ?? MarinaRouteIntent.inferred(
            requestFamily: requestFamily,
            rawPrompt: rawPrompt,
            operation: operation,
            measure: measure,
            entityMentions: entityMentions,
            grouping: grouping,
            responseShapeHint: responseShapeHint,
            databaseLookupRequest: databaseLookupRequest,
            semanticCommand: semanticCommand,
            requestShape: requestShape
        )
    }
}

extension MarinaRouteIntent {
    nonisolated static func inferred(
        requestFamily: MarinaRequestFamily,
        rawPrompt: String,
        operation: MarinaCandidateOperation?,
        measure: MarinaCandidateMeasure?,
        entityMentions: [MarinaUnresolvedEntityMention],
        grouping: MarinaGroupingCandidate?,
        responseShapeHint: MarinaResponseShapeHint?,
        databaseLookupRequest: MarinaDatabaseLookupRequest?,
        semanticCommand: MarinaSemanticCommand?,
        requestShape: MarinaRequestShape?
    ) -> MarinaRouteIntent? {
        guard let inferredOperation = operation ?? operationFromCommand(semanticCommand),
              let inferredMeasure = measure ?? semanticCommand?.measure ?? measureFromCommandOrLookup(semanticCommand, databaseLookupRequest: databaseLookupRequest) else {
            return nil
        }
        let requestedDetail = semanticCommand?.requestedDetail ?? databaseLookupRequest.map(detail)
        let targetTypes = explicitTargetTypes(
            entityMentions: entityMentions,
            databaseLookupRequest: databaseLookupRequest,
            semanticCommand: semanticCommand
        )
        let subject = subject(
            measure: inferredMeasure,
            databaseLookupRequest: databaseLookupRequest,
            semanticCommand: semanticCommand
        )
        let group = grouping?.dimension ?? semanticCommand?.grouping
        let kind = MarinaRoutePatternRegistry.intentKind(
            rawPrompt: rawPrompt,
            requestFamily: requestFamily,
            operation: inferredOperation,
            measure: inferredMeasure,
            grouping: group,
            requestedDetail: requestedDetail,
            requestShape: requestShape,
            databaseLookupRequest: databaseLookupRequest
        )
        return MarinaRouteIntent(
            kind: kind,
            subject: subject,
            operation: inferredOperation,
            measure: inferredMeasure,
            grouping: group,
            targetTypes: targetTypes,
            requestedDetail: requestedDetail,
            responseShape: responseShapeHint,
            preferredExecutorRoute: preferredExecutorRoute(
                kind: kind,
                operation: inferredOperation,
                requestFamily: requestFamily
            )
        )
    }

    nonisolated static func from(
        semanticQuery: MarinaSemanticQuery,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        targetTypes: [MarinaCandidateEntityTypeHint],
        grouping: MarinaGroupingDimensionCandidate?,
        responseShape: MarinaResponseShapeHint?
    ) -> MarinaRouteIntent {
        let kind = MarinaRoutePatternRegistry.intentKind(
            subject: semanticQuery.subject,
            operation: operation,
            measure: measure,
            grouping: grouping,
            requestedDetail: semanticQuery.requestedDetail,
            targetTypes: targetTypes
        )
        return MarinaRouteIntent(
            kind: kind,
            subject: semanticQuery.subject,
            operation: operation,
            measure: measure,
            grouping: grouping,
            targetTypes: targetTypes,
            requestedDetail: semanticQuery.requestedDetail,
            responseShape: responseShape,
            preferredExecutorRoute: preferredExecutorRoute(
                kind: kind,
                operation: operation,
                requestFamily: .analytics
            )
        )
    }

    nonisolated static func from(
        plan: MarinaAggregationPlan,
        fallbackSubject: MarinaSubject? = nil
    ) -> MarinaRouteIntent {
        let targetTypes = plan.targets.map(\.entityType)
        let subject = fallbackSubject ?? subject(measure: plan.measure, databaseLookupRequest: nil, semanticCommand: nil)
        let kind = MarinaRoutePatternRegistry.intentKind(
            subject: subject,
            operation: plan.operation,
            measure: plan.measure,
            grouping: plan.grouping?.dimension,
            requestedDetail: nil,
            targetTypes: targetTypes
        )
        return MarinaRouteIntent(
            kind: kind,
            subject: subject,
            operation: plan.operation,
            measure: plan.measure,
            grouping: plan.grouping?.dimension,
            targetTypes: targetTypes,
            requestedDetail: nil,
            responseShape: plan.responseShape,
            preferredExecutorRoute: preferredExecutorRoute(
                kind: kind,
                operation: plan.operation,
                requestFamily: .analytics
            )
        )
    }

    nonisolated private static func operationFromCommand(_ command: MarinaSemanticCommand?) -> MarinaCandidateOperation? {
        switch command?.action {
        case .total, .group:
            return .sum
        case .listRows:
            return .listRows
        case .rank:
            return .rank
        case .compare:
            return .compare
        case .average:
            return .average
        case .simulate:
            return .simulate
        case .lookupDetails:
            return .lookupDetails
        case nil:
            return nil
        }
    }

    nonisolated private static func measureFromCommandOrLookup(
        _ command: MarinaSemanticCommand?,
        databaseLookupRequest: MarinaDatabaseLookupRequest?
    ) -> MarinaCandidateMeasure? {
        if let measure = command?.measure { return measure }
        if let lookupType = databaseLookupRequest?.objectTypes.first {
            switch lookupType {
            case .budget:
                return .remainingBudget
            case .income, .incomeSeries:
                return .income
            case .savingsAccount, .savingsLedgerEntry:
                return .savings
            case .reconciliationAccount, .reconciliationItem, .expenseAllocation:
                return .reconciliationBalance
            case .preset, .plannedExpense:
                return .presetAmount
            case .workspace, .card, .category, .variableExpense, .importMerchantRule, .assistantAliasRule, .unknown:
                return .transactionAmount
            }
        }
        return nil
    }

    nonisolated private static func subject(
        measure: MarinaCandidateMeasure,
        databaseLookupRequest: MarinaDatabaseLookupRequest?,
        semanticCommand: MarinaSemanticCommand?
    ) -> MarinaSubject {
        if let dataset = semanticCommand?.datasets.first {
            switch dataset {
            case .workspaces:
                return .workspaces
            case .variableExpenses:
                return .variableExpenses
            case .plannedExpenses:
                return .plannedExpenses
            case .income:
                return .income
            case .incomeSeries:
                return .incomeSource
            case .cards:
                return .cards
            case .categories:
                return .categories
            case .presets:
                return .presets
            case .budgets:
                return .budgets
            case .savingsLedger:
                return .savingsLedgerEntries
            case .reconciliation, .expenseAllocations:
                return .reconciliationAccounts
            case .importMerchantRules:
                return .merchant
            case .assistantAliasRules:
                return .workspaces
            }
        }
        if let lookupType = databaseLookupRequest?.objectTypes.first {
            switch lookupType {
            case .budget:
                return .budgets
            case .income, .incomeSeries:
                return .income
            case .variableExpense:
                return .variableExpenses
            case .plannedExpense:
                return .plannedExpenses
            case .category:
                return .categories
            case .preset:
                return .presets
            case .card:
                return .cards
            case .savingsAccount:
                return .savingsAccounts
            case .savingsLedgerEntry:
                return .savingsLedgerEntries
            case .reconciliationAccount:
                return .reconciliationAccounts
            case .reconciliationItem, .expenseAllocation:
                return .reconciliationItems
            case .importMerchantRule:
                return .merchant
            case .assistantAliasRule, .workspace, .unknown:
                return .workspaces
            }
        }
        switch measure {
        case .spend, .categoryShare, .transactionAmount, .transactionFrequency:
            return .variableExpenses
        case .income:
            return .income
        case .savings:
            return .savingsAccounts
        case .savingsMovement:
            return .savingsLedgerEntries
        case .remainingBudget:
            return .budgets
        case .reconciliationBalance:
            return .reconciliationAccounts
        case .presetAmount:
            return .plannedExpenses
        }
    }

    nonisolated private static func explicitTargetTypes(
        entityMentions: [MarinaUnresolvedEntityMention],
        databaseLookupRequest: MarinaDatabaseLookupRequest?,
        semanticCommand: MarinaSemanticCommand?
    ) -> [MarinaCandidateEntityTypeHint] {
        let mentionTypes = entityMentions.compactMap(\.typeHint)
        if mentionTypes.isEmpty == false { return mentionTypes }
        let commandTypes = semanticCommand?.includeFilters.flatMap(\.allowedTypes) ?? []
        if commandTypes.isEmpty == false { return commandTypes }
        return databaseLookupRequest?.objectTypes.compactMap(entityTypeHint) ?? []
    }

    nonisolated private static func entityTypeHint(from objectType: MarinaLookupObjectType) -> MarinaCandidateEntityTypeHint? {
        switch objectType {
        case .budget:
            return .budget
        case .income, .incomeSeries:
            return .incomeSource
        case .variableExpense, .plannedExpense, .expenseAllocation, .reconciliationItem:
            return .expense
        case .category:
            return .category
        case .preset:
            return .preset
        case .card:
            return .card
        case .savingsAccount, .savingsLedgerEntry:
            return .savingsAccount
        case .reconciliationAccount:
            return .allocationAccount
        case .importMerchantRule:
            return .merchant
        case .assistantAliasRule, .workspace:
            return .workspace
        case .unknown:
            return nil
        }
    }

    nonisolated private static func detail(from request: MarinaDatabaseLookupRequest) -> MarinaSemanticRequestedDetail {
        switch request.requestedDetail {
        case .general:
            return .general
        case .date:
            return .date
        case .amount:
            return .amount
        case .card:
            return .card
        case .category:
            return .category
        case .status:
            return .status
        case .schedule:
            return .schedule
        case .recurrence:
            return .recurrence
        case .account:
            return .account
        case .balance:
            return .balance
        case .linkedObjects:
            return .linkedObjects
        }
    }

    nonisolated private static func preferredExecutorRoute(
        kind: MarinaRouteIntentKind,
        operation: MarinaCandidateOperation,
        requestFamily: MarinaRequestFamily
    ) -> MarinaPreferredExecutorRoute? {
        if let catalogRoute = MarinaRoutePatternRegistry.preferredExecutorRoute(for: kind) {
            if kind == .recentTransactionRows {
                return nil
            }
            return catalogRoute
        }
        switch kind {
        case .databaseLookup:
            return .databaseLookup
        case .budgetInventory, .budgetMembership, .budgetLinkedCards, .budgetLinkedPresets, .budgetCategoryLimits, .budgetCategoryLimit, .overBudgetCategories, .allocationRows, .settlementRows:
            return .composableWorkspace
        case .plannedExpenseRows, .presetTemplateRows, .plannedExpenseByCategory, .plannedExpenseByCard, .plannedExpenseByPreset:
            return .workspaceAggregation
        case .savingsActivity, .savingsMovementRanking, .incomePlannedVsActual, .reconciliationBalance:
            return .workspaceAggregation
        case .savingsStatus:
            return .homeAdapter
        case .activeBudget:
            return .composableWorkspace
        case .recentTransactionRows, .broadSpend, .generic:
            break
        }
        switch operation {
        case .lookupDetails:
            return requestFamily == .databaseLookup ? .databaseLookup : .lookupDetail
        case .listRows:
            return .list
        case .rank:
            return .groupedRanked
        case .sum, .average, .count, .minimum, .maximum:
            return .aggregate
        case .compare:
            return .comparison
        case .forecast, .simulate:
            return .scenario
        case .trend:
            return .groupedRanked
        }
    }
}

struct MarinaRoutePatternRegistry {
    struct RoutePattern: Sendable, Equatable {
        let kind: MarinaRouteIntentKind
        let preferredExecutorRoute: MarinaPreferredExecutorRoute?
        let operations: Set<MarinaCandidateOperation>
        let measures: Set<MarinaCandidateMeasure>
        let groupings: Set<MarinaGroupingDimensionCandidate?>
        let requestedDetails: Set<MarinaSemanticRequestedDetail?>

        nonisolated func matches(
            operation: MarinaCandidateOperation,
            measure: MarinaCandidateMeasure,
            grouping: MarinaGroupingDimensionCandidate?,
            requestedDetail: MarinaSemanticRequestedDetail?
        ) -> Bool {
            operations.contains(operation)
                && measures.contains(measure)
                && groupings.contains(grouping)
                && requestedDetails.contains(requestedDetail)
        }
    }

    nonisolated static let routeCatalog: [RoutePattern] = [
        RoutePattern(
            kind: .budgetCategoryLimits,
            preferredExecutorRoute: .composableWorkspace,
            operations: [.lookupDetails],
            measures: [.remainingBudget, .spend],
            groupings: [nil],
            requestedDetails: [.categoryLimits]
        ),
        RoutePattern(
            kind: .budgetLinkedCards,
            preferredExecutorRoute: .composableWorkspace,
            operations: [.lookupDetails],
            measures: [.remainingBudget, .spend],
            groupings: [nil],
            requestedDetails: [.linkedCards]
        ),
        RoutePattern(
            kind: .budgetLinkedPresets,
            preferredExecutorRoute: .composableWorkspace,
            operations: [.lookupDetails],
            measures: [.remainingBudget, .spend],
            groupings: [nil],
            requestedDetails: [.linkedPresets]
        ),
        RoutePattern(
            kind: .budgetMembership,
            preferredExecutorRoute: .composableWorkspace,
            operations: [.lookupDetails],
            measures: [.remainingBudget, .spend],
            groupings: [nil],
            requestedDetails: [.membership]
        ),
        RoutePattern(
            kind: .activeBudget,
            preferredExecutorRoute: .composableWorkspace,
            operations: [.lookupDetails],
            measures: [.remainingBudget],
            groupings: [nil],
            requestedDetails: [.status]
        ),
        RoutePattern(
            kind: .budgetCategoryLimit,
            preferredExecutorRoute: .composableWorkspace,
            operations: [.lookupDetails],
            measures: [.remainingBudget],
            groupings: [nil],
            requestedDetails: [nil, .general, .amount, .balance]
        ),
        RoutePattern(
            kind: .overBudgetCategories,
            preferredExecutorRoute: .composableWorkspace,
            operations: [.rank],
            measures: [.remainingBudget],
            groupings: [.category],
            requestedDetails: [nil, .general]
        ),
        RoutePattern(
            kind: .plannedExpenseRows,
            preferredExecutorRoute: .workspaceAggregation,
            operations: [.listRows, .rank],
            measures: [.presetAmount],
            groupings: [.transaction],
            requestedDetails: [nil, .general, .date, .amount]
        ),
        RoutePattern(
            kind: .presetTemplateRows,
            preferredExecutorRoute: .workspaceAggregation,
            operations: [.listRows, .rank],
            measures: [.presetAmount],
            groupings: [.preset],
            requestedDetails: [nil, .general, .schedule, .recurrence, .amount]
        ),
        RoutePattern(
            kind: .plannedExpenseByCategory,
            preferredExecutorRoute: .workspaceAggregation,
            operations: [.sum, .rank],
            measures: [.presetAmount],
            groupings: [.category],
            requestedDetails: [nil, .general, .amount]
        ),
        RoutePattern(
            kind: .plannedExpenseByCard,
            preferredExecutorRoute: .workspaceAggregation,
            operations: [.sum, .rank],
            measures: [.presetAmount],
            groupings: [.card],
            requestedDetails: [nil, .general, .amount]
        ),
        RoutePattern(
            kind: .plannedExpenseByPreset,
            preferredExecutorRoute: .workspaceAggregation,
            operations: [.sum],
            measures: [.presetAmount],
            groupings: [.preset],
            requestedDetails: [nil, .general, .amount]
        ),
        RoutePattern(
            kind: .savingsMovementRanking,
            preferredExecutorRoute: .workspaceAggregation,
            operations: [.rank],
            measures: [.savingsMovement],
            groupings: [nil, .savingsLedgerEntry],
            requestedDetails: [nil, .general]
        ),
        RoutePattern(
            kind: .savingsActivity,
            preferredExecutorRoute: .workspaceAggregation,
            operations: [.listRows, .rank],
            measures: [.savingsMovement],
            groupings: [nil, .savingsLedgerEntry],
            requestedDetails: [nil, .general, .date, .amount]
        ),
        RoutePattern(
            kind: .savingsStatus,
            preferredExecutorRoute: .homeAdapter,
            operations: [.lookupDetails],
            measures: [.savings],
            groupings: [nil],
            requestedDetails: [nil, .general, .status, .balance, .account]
        ),
        RoutePattern(
            kind: .incomePlannedVsActual,
            preferredExecutorRoute: .workspaceAggregation,
            operations: [.sum],
            measures: [.income],
            groupings: [nil],
            requestedDetails: [.status]
        ),
        RoutePattern(
            kind: .settlementRows,
            preferredExecutorRoute: .composableWorkspace,
            operations: [.listRows, .rank],
            measures: [.reconciliationBalance],
            groupings: [.allocationAccount],
            requestedDetails: [nil, .general, .date, .amount]
        ),
        RoutePattern(
            kind: .allocationRows,
            preferredExecutorRoute: .composableWorkspace,
            operations: [.listRows, .rank],
            measures: [.reconciliationBalance],
            groupings: [.allocationAccount],
            requestedDetails: [nil, .general, .amount]
        ),
        RoutePattern(
            kind: .reconciliationBalance,
            preferredExecutorRoute: .workspaceAggregation,
            operations: [.sum, .rank, .listRows, .lookupDetails],
            measures: [.reconciliationBalance],
            groupings: [nil, .allocationAccount],
            requestedDetails: [nil, .general, .balance, .account]
        ),
        RoutePattern(
            kind: .budgetInventory,
            preferredExecutorRoute: .composableWorkspace,
            operations: [.listRows, .lookupDetails],
            measures: [.remainingBudget],
            groupings: [nil],
            requestedDetails: [nil, .general]
        ),
        RoutePattern(
            kind: .recentTransactionRows,
            preferredExecutorRoute: .list,
            operations: [.listRows, .rank],
            measures: [.transactionAmount, .spend],
            groupings: [nil, .transaction],
            requestedDetails: [nil, .general, .date, .amount, .card, .category]
        ),
        RoutePattern(
            kind: .broadSpend,
            preferredExecutorRoute: .aggregate,
            operations: [.sum],
            measures: [.spend],
            groupings: [nil],
            requestedDetails: [nil, .general]
        )
    ]

    nonisolated static func intentKind(
        rawPrompt: String,
        requestFamily: MarinaRequestFamily,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        grouping: MarinaGroupingDimensionCandidate?,
        requestedDetail: MarinaSemanticRequestedDetail?,
        requestShape: MarinaRequestShape?,
        databaseLookupRequest: MarinaDatabaseLookupRequest?
    ) -> MarinaRouteIntentKind {
        if requestFamily == .databaseLookup || databaseLookupRequest != nil {
            return .databaseLookup
        }
        let normalized = normalized(rawPrompt)

        if isSettlementRowsPrompt(normalized), matchesCatalog(.settlementRows, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) { return .settlementRows }
        if isAllocationRowsPrompt(normalized), matchesCatalog(.allocationRows, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) { return .allocationRows }
        if normalized.contains("activity") || normalized.contains("transactions") || normalized.contains("transfers"),
           matchesCatalog(.savingsActivity, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) { return .savingsActivity }
        if normalized.contains("limit"),
           matchesCatalog(.budgetCategoryLimit, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) { return .budgetCategoryLimit }
        if let detailMatch = routeCatalog.first(where: {
            [.budgetCategoryLimits, .budgetLinkedCards, .budgetLinkedPresets, .budgetMembership, .activeBudget].contains($0.kind)
                && $0.matches(operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail)
        }) {
            return detailMatch.kind
        }
        if requestShape == .objectInventoryList,
           matchesCatalog(.budgetInventory, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .budgetInventory
        }
        if matchesCatalog(.plannedExpenseRows, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .plannedExpenseRows
        }
        if matchesCatalog(.plannedExpenseByCategory, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .plannedExpenseByCategory
        }
        if matchesCatalog(.plannedExpenseByCard, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .plannedExpenseByCard
        }
        if matchesCatalog(.plannedExpenseByPreset, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .plannedExpenseByPreset
        }
        if matchesCatalog(.presetTemplateRows, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .presetTemplateRows
        }
        if operation == .lookupDetails, measure == .remainingBudget, grouping == nil {
            return .generic
        }
        if matchesCatalog(.overBudgetCategories, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .overBudgetCategories
        }
        if measure == .savingsMovement {
            return matchesCatalog(.savingsMovementRanking, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) ? .savingsMovementRanking : .savingsActivity
        }
        if matchesCatalog(.savingsStatus, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .savingsStatus
        }
        if matchesCatalog(.reconciliationBalance, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .reconciliationBalance
        }
        if isRecentTransactionRows(operation: operation, measure: measure, grouping: grouping),
           matchesCatalog(.recentTransactionRows, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .recentTransactionRows
        }
        if matchesCatalog(.broadSpend, operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail) {
            return .broadSpend
        }
        return .generic
    }

    nonisolated static func intentKind(
        subject: MarinaSubject,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        grouping: MarinaGroupingDimensionCandidate?,
        requestedDetail: MarinaSemanticRequestedDetail?,
        targetTypes: [MarinaCandidateEntityTypeHint]
    ) -> MarinaRouteIntentKind {
        if subject == .budgets {
            switch requestedDetail {
            case .categoryLimits:
                return .budgetCategoryLimits
            case .linkedCards:
                return .budgetLinkedCards
            case .linkedPresets:
                return .budgetLinkedPresets
            case .membership:
                return .budgetMembership
            case .status:
                return .activeBudget
            default:
                if operation == .lookupDetails, targetTypes.contains(.category) {
                    return .budgetCategoryLimit
                }
                if operation == .rank, measure == .remainingBudget, grouping == .category {
                    return .overBudgetCategories
                }
            }
        }
        if subject == .savingsAccounts, operation == .lookupDetails {
            return .savingsStatus
        }
        if subject == .income, operation == .sum, measure == .income, requestedDetail == .status {
            return .incomePlannedVsActual
        }
        if subject == .plannedExpenses, measure == .presetAmount {
            switch grouping {
            case .transaction:
                return .plannedExpenseRows
            case .category:
                return .plannedExpenseByCategory
            case .card:
                return .plannedExpenseByCard
            case .preset:
                return .plannedExpenseByPreset
            default:
                break
            }
        }
        if subject == .presets, measure == .presetAmount, grouping == .preset {
            return .presetTemplateRows
        }
        if subject == .savingsLedgerEntries || measure == .savingsMovement {
            return operation == .rank ? .savingsMovementRanking : .savingsActivity
        }
        if measure == .reconciliationBalance, grouping == .allocationAccount {
            return .reconciliationBalance
        }
        if isRecentTransactionRows(operation: operation, measure: measure, grouping: grouping) {
            return .recentTransactionRows
        }
        if subject == .variableExpenses, operation == .sum, measure == .spend {
            return .broadSpend
        }
        return .generic
    }

    nonisolated static func preferredExecutorRoute(for kind: MarinaRouteIntentKind) -> MarinaPreferredExecutorRoute? {
        routeCatalog.first { $0.kind == kind }?.preferredExecutorRoute
    }

    nonisolated static func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private nonisolated static func matchesCatalog(
        _ kind: MarinaRouteIntentKind,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        grouping: MarinaGroupingDimensionCandidate?,
        requestedDetail: MarinaSemanticRequestedDetail?
    ) -> Bool {
        routeCatalog.contains {
            $0.kind == kind
                && $0.matches(operation: operation, measure: measure, grouping: grouping, requestedDetail: requestedDetail)
        }
    }

    nonisolated static func fallbackComposableKind(
        rawPrompt: String,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        grouping: MarinaGroupingDimensionCandidate?
    ) -> MarinaRouteIntentKind? {
        let normalized = normalized(rawPrompt)
        if isBudgetInventoryPrompt(normalized) { return .budgetInventory }
        if isOverBudgetCategoriesPrompt(normalized) { return .overBudgetCategories }
        if isAllocationRowsPrompt(normalized) { return .allocationRows }
        if isSettlementRowsPrompt(normalized) { return .settlementRows }
        if isRecentTransactionRows(operation: operation, measure: measure, grouping: grouping) {
            return .recentTransactionRows
        }
        return nil
    }

    nonisolated static func isReadOnlyStep5Mutation(_ prompt: String) -> MarinaReadOnlyMutationViolation? {
        let normalized = normalized(prompt)
        guard containsMutationVerb(normalized) else { return nil }

        let matchedDomain = mutationDomain(in: normalized)
        guard let domain = matchedDomain else { return nil }

        return MarinaReadOnlyMutationViolation(
            domain: domain,
            message: "That looks like a \(domain.displayName) change. Marina's Foundation read pipeline is read-only for this area, so I won't approximate it as a lookup."
        )
    }

    private nonisolated static func isBudgetInventoryPrompt(_ prompt: String) -> Bool {
        let asksRelationship = prompt.contains("linked")
            || prompt.contains("link")
            || prompt.contains("attached")
            || prompt.contains("objects")
            || prompt.contains("membership")
            || prompt.contains("limit")
        return asksRelationship == false
            && (prompt.contains("budget") || prompt.contains("budgets"))
            && (prompt.contains("do i have")
                || prompt.contains("have this")
                || prompt.contains("have in")
                || prompt.contains("upcoming")
                || prompt.contains("future")
                || prompt.hasPrefix("list ")
                || prompt.hasPrefix("show ")
                || prompt.hasPrefix("what are"))
    }

    private nonisolated static func isOverBudgetCategoriesPrompt(_ prompt: String) -> Bool {
        prompt.contains("over budget")
            && (prompt.contains("category") || prompt.contains("categories"))
    }

    private nonisolated static func isAllocationRowsPrompt(_ prompt: String) -> Bool {
        prompt.contains("allocation")
            || prompt.contains("allocations")
            || prompt.contains("allocated")
            || (prompt.contains("expenses") && prompt.contains("split with"))
            || (prompt.contains("split expenses") && prompt.contains(" with "))
            || (prompt.contains("split charges") && prompt.contains(" with "))
    }

    private nonisolated static func isSettlementRowsPrompt(_ prompt: String) -> Bool {
        prompt.contains("settlement")
            || prompt.contains("settlements")
            || prompt.contains("paid me back")
            || prompt.contains("pay me back")
            || prompt.contains("repaid")
            || prompt.contains("reimburse")
    }

    private nonisolated static func isRecentTransactionRows(
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        grouping: MarinaGroupingDimensionCandidate?
    ) -> Bool {
        guard operation == .listRows || operation == .rank else { return false }
        if measure == .transactionAmount {
            return grouping == nil || grouping == .transaction
        }
        return measure == .spend && grouping == .transaction
    }

    private nonisolated static func containsMutationVerb(_ prompt: String) -> Bool {
        if prompt.contains("mark paid") || prompt.contains("mark as paid") {
            return true
        }
        if containsWord("mark", in: prompt), containsWord("paid", in: prompt) {
            return true
        }
        let verbs = ["add", "create", "delete", "remove", "update", "edit", "move", "transfer", "settle", "allocate"]
        return verbs.contains { containsWord($0, in: prompt) }
    }

    private nonisolated static func containsWord(_ word: String, in prompt: String) -> Bool {
        prompt.split(separator: " ").contains { $0 == word }
    }

    private nonisolated static func mutationDomain(in prompt: String) -> MarinaReadOnlyMutationDomain? {
        if prompt.contains("settlement") || prompt.contains("settle") || prompt.contains("paid") || prompt.contains("pay back") {
            return .settlement
        }
        if prompt.contains("allocation") || prompt.contains("allocate") || prompt.contains("split") {
            return .allocation
        }
        if prompt.contains("savings") || prompt.contains("saving") {
            return .savings
        }
        if prompt.contains("preset") {
            return .preset
        }
        if prompt.contains("reconciliation") || prompt.contains("roommate") {
            return .reconciliation
        }
        return nil
    }
}

struct MarinaRouteIntentRegistry {
    nonisolated static func intentKind(
        rawPrompt: String,
        requestFamily: MarinaRequestFamily,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        grouping: MarinaGroupingDimensionCandidate?,
        requestedDetail: MarinaSemanticRequestedDetail?,
        requestShape: MarinaRequestShape?,
        databaseLookupRequest: MarinaDatabaseLookupRequest?
    ) -> MarinaRouteIntentKind {
        MarinaRoutePatternRegistry.intentKind(
            rawPrompt: rawPrompt,
            requestFamily: requestFamily,
            operation: operation,
            measure: measure,
            grouping: grouping,
            requestedDetail: requestedDetail,
            requestShape: requestShape,
            databaseLookupRequest: databaseLookupRequest
        )
    }

    nonisolated static func intentKind(
        subject: MarinaSubject,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        grouping: MarinaGroupingDimensionCandidate?,
        requestedDetail: MarinaSemanticRequestedDetail?,
        targetTypes: [MarinaCandidateEntityTypeHint]
    ) -> MarinaRouteIntentKind {
        MarinaRoutePatternRegistry.intentKind(
            subject: subject,
            operation: operation,
            measure: measure,
            grouping: grouping,
            requestedDetail: requestedDetail,
            targetTypes: targetTypes
        )
    }
}

enum MarinaReadOnlyMutationDomain: String, Codable, Sendable, Equatable {
    case allocation
    case settlement
    case savings
    case preset
    case reconciliation

    nonisolated var displayName: String {
        switch self {
        case .allocation:
            return "allocation"
        case .settlement:
            return "settlement"
        case .savings:
            return "savings"
        case .preset:
            return "preset"
        case .reconciliation:
            return "reconciliation"
        }
    }
}

struct MarinaReadOnlyMutationViolation: Codable, Sendable, Equatable {
    let domain: MarinaReadOnlyMutationDomain
    let message: String
}
