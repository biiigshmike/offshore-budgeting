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
        responseShape: MarinaResponseShapeHint? = nil
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
    }
}
