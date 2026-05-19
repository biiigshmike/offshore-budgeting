import Foundation

enum MarinaAggregationPlanStatus: String, Codable, Equatable {
    case executable
    case notExecutableShell
}

enum MarinaResolvedTargetRole: String, Codable, Equatable, CaseIterable {
    case filter
    case excludeFilter
    case primaryTarget
    case comparisonTarget
    case groupingDimension
    case simulationInput
    case simulationOutput
}

struct MarinaResolvedAggregationTarget: Codable, Equatable, Identifiable {
    let id: UUID
    let role: MarinaResolvedTargetRole
    let entityType: MarinaCandidateEntityTypeHint
    let displayName: String
    let sourceID: UUID?

    init(
        id: UUID = UUID(),
        role: MarinaResolvedTargetRole,
        entityType: MarinaCandidateEntityTypeHint,
        displayName: String,
        sourceID: UUID? = nil
    ) {
        self.id = id
        self.role = role
        self.entityType = entityType
        self.displayName = displayName
        self.sourceID = sourceID
    }
}

struct MarinaAggregationPlan: Codable, Equatable, Identifiable {
    let id: UUID
    let status: MarinaAggregationPlanStatus
    let operation: MarinaCandidateOperation
    let measure: MarinaCandidateMeasure
    let targets: [MarinaResolvedAggregationTarget]
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let grouping: MarinaGroupingCandidate?
    let ranking: MarinaRankingCandidate?
    let limit: Int?
    let incomeStatusScope: MarinaIncomeStatusScope?
    let responseShape: MarinaResponseShapeHint?
    let routeIntent: MarinaRouteIntent?

    init(
        id: UUID = UUID(),
        status: MarinaAggregationPlanStatus = .notExecutableShell,
        operation: MarinaCandidateOperation,
        measure: MarinaCandidateMeasure,
        targets: [MarinaResolvedAggregationTarget] = [],
        dateRange: HomeQueryDateRange? = nil,
        comparisonDateRange: HomeQueryDateRange? = nil,
        grouping: MarinaGroupingCandidate? = nil,
        ranking: MarinaRankingCandidate? = nil,
        limit: Int? = nil,
        incomeStatusScope: MarinaIncomeStatusScope? = nil,
        responseShape: MarinaResponseShapeHint? = nil,
        routeIntent: MarinaRouteIntent? = nil
    ) {
        self.id = id
        self.status = status
        self.operation = operation
        self.measure = measure
        self.targets = targets
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.grouping = grouping
        self.ranking = ranking
        self.limit = limit
        self.incomeStatusScope = incomeStatusScope
        self.responseShape = responseShape
        let targetTypes = targets.map(\.entityType)
        let subject = Self.subject(for: measure)
        let kind = MarinaRouteIntentRegistry.intentKind(
            subject: subject,
            operation: operation,
            measure: measure,
            grouping: grouping?.dimension,
            requestedDetail: nil,
            targetTypes: targetTypes
        )
        self.routeIntent = routeIntent ?? MarinaRouteIntent(
            kind: kind,
            subject: subject,
            operation: operation,
            measure: measure,
            grouping: grouping?.dimension,
            targetTypes: targetTypes,
            requestedDetail: nil,
            responseShape: responseShape,
            preferredExecutorRoute: nil
        )
    }

    nonisolated private static func subject(for measure: MarinaCandidateMeasure) -> MarinaSubject {
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
}
