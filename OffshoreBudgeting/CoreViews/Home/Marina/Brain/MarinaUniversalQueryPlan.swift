import Foundation

nonisolated enum MarinaUniversalEntitySurface: Equatable, Sendable {
    case semantic(MarinaSemanticEntity)
    case unifiedExpenses
    case savingsLedgerEntries
    case reconciliationLedgerEntries

    var semanticEntity: MarinaSemanticEntity? {
        guard case let .semantic(entity) = self else {
            return nil
        }
        return entity
    }
}

nonisolated struct MarinaUniversalQueryPlan: Equatable, Sendable {
    let surface: MarinaUniversalEntitySurface
    let operation: MarinaSemanticOperation
    let measure: MarinaSemanticMeasure?
    let search: MarinaRowSearchClause?
    let filters: [MarinaRowFilter]
    let groupBy: MarinaRowGroupTarget?
    let sorts: [MarinaRowSort]
    let limit: Int?
    let dateRange: HomeQueryDateRange?
    let comparisonDateRange: HomeQueryDateRange?
    let whatIfAmount: Double?
    let requiresDateField: Bool
    let requiresAmountField: Bool

    var entity: MarinaSemanticEntity {
        surface.semanticEntity ?? .variableExpense
    }

    init(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        search: MarinaRowSearchClause? = nil,
        filters: [MarinaRowFilter] = [],
        groupBy: MarinaRowGroupTarget? = nil,
        sorts: [MarinaRowSort] = [],
        limit: Int? = nil,
        dateRange: HomeQueryDateRange? = nil,
        comparisonDateRange: HomeQueryDateRange? = nil,
        whatIfAmount: Double? = nil,
        requiresDateField: Bool = false,
        requiresAmountField: Bool = false
    ) {
        self.init(
            surface: .semantic(entity),
            operation: operation,
            measure: measure,
            search: search,
            filters: filters,
            groupBy: groupBy,
            sorts: sorts,
            limit: limit,
            dateRange: dateRange,
            comparisonDateRange: comparisonDateRange,
            whatIfAmount: whatIfAmount,
            requiresDateField: requiresDateField,
            requiresAmountField: requiresAmountField
        )
    }

    init(
        surface: MarinaUniversalEntitySurface,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        search: MarinaRowSearchClause? = nil,
        filters: [MarinaRowFilter] = [],
        groupBy: MarinaRowGroupTarget? = nil,
        sorts: [MarinaRowSort] = [],
        limit: Int? = nil,
        dateRange: HomeQueryDateRange? = nil,
        comparisonDateRange: HomeQueryDateRange? = nil,
        whatIfAmount: Double? = nil,
        requiresDateField: Bool = false,
        requiresAmountField: Bool = false
    ) {
        self.surface = surface
        self.operation = operation
        self.measure = measure
        self.search = search
        self.filters = filters
        self.groupBy = groupBy
        self.sorts = sorts
        self.limit = limit
        self.dateRange = dateRange
        self.comparisonDateRange = comparisonDateRange
        self.whatIfAmount = whatIfAmount
        self.requiresDateField = requiresDateField
        self.requiresAmountField = requiresAmountField
    }
}

nonisolated enum MarinaUniversalQueryResult: Equatable, Sendable {
    case rows([MarinaQueryableRow])
    case metric(MarinaUniversalMetricResult)
    case groups([MarinaUniversalGroupResult])
    case unsupported(MarinaCapabilityFailureReason)
}

nonisolated struct MarinaUniversalMetricResult: Equatable, Sendable {
    let value: MarinaValue
    let evidenceRows: [MarinaQueryableRow]
    let details: [MarinaFormulaMetricDetail]

    init(
        value: MarinaValue,
        evidenceRows: [MarinaQueryableRow],
        details: [MarinaFormulaMetricDetail] = []
    ) {
        self.value = value
        self.evidenceRows = evidenceRows
        self.details = details
    }
}

nonisolated struct MarinaUniversalGroupResult: Equatable, Sendable {
    let group: MarinaGroupedRows
    let aggregate: MarinaValue?
}
