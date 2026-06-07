import Foundation

struct MarinaUniversalQueryPlan: Equatable, Sendable {
    let entity: MarinaSemanticEntity
    let operation: MarinaSemanticOperation
    let measure: MarinaSemanticMeasure?
    let search: MarinaRowSearchClause?
    let filters: [MarinaRowFilter]
    let groupBy: MarinaRowGroupTarget?
    let sorts: [MarinaRowSort]
    let limit: Int?
    let requiresDateField: Bool
    let requiresAmountField: Bool

    init(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        search: MarinaRowSearchClause? = nil,
        filters: [MarinaRowFilter] = [],
        groupBy: MarinaRowGroupTarget? = nil,
        sorts: [MarinaRowSort] = [],
        limit: Int? = nil,
        requiresDateField: Bool = false,
        requiresAmountField: Bool = false
    ) {
        self.entity = entity
        self.operation = operation
        self.measure = measure
        self.search = search
        self.filters = filters
        self.groupBy = groupBy
        self.sorts = sorts
        self.limit = limit
        self.requiresDateField = requiresDateField
        self.requiresAmountField = requiresAmountField
    }
}

enum MarinaUniversalQueryResult: Equatable, Sendable {
    case rows([MarinaQueryableRow])
    case metric(MarinaUniversalMetricResult)
    case groups([MarinaUniversalGroupResult])
    case unsupported(MarinaCapabilityFailureReason)
}

struct MarinaUniversalMetricResult: Equatable, Sendable {
    let value: MarinaValue
    let evidenceRows: [MarinaQueryableRow]
}

struct MarinaUniversalGroupResult: Equatable, Sendable {
    let group: MarinaGroupedRows
    let aggregate: MarinaValue?
}
