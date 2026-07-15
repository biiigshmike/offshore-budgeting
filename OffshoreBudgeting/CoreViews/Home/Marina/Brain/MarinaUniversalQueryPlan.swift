import Foundation

nonisolated enum MarinaUniversalEntitySurface: Equatable, Sendable {
    case semantic(MarinaSemanticEntity)
    case unifiedExpenses
    case savingsLedgerEntries
    case reconciliationLedgerEntries

    var semanticEntity: MarinaSemanticEntity? {
        switch self {
        case let .semantic(entity):
            return entity
        case .unifiedExpenses:
            return .variableExpense
        case .savingsLedgerEntries:
            return .savingsAccount
        case .reconciliationLedgerEntries:
            return .reconciliationAccount
        }
    }
}

nonisolated struct MarinaUniversalQueryPlan: Equatable, Sendable {
    let surface: MarinaUniversalEntitySurface
    let projection: MarinaSemanticProjection
    let operation: MarinaSemanticOperation
    let measure: MarinaSemanticMeasure?
    let search: MarinaRowSearchClause?
    let filters: [MarinaRowFilter]
    let groupBy: MarinaRowGroupTarget?
    let sorts: [MarinaRowSort]
    let offset: Int
    let limit: Int?
    let dateRange: HomeQueryDateRange?
    let dateRangeSource: MarinaSemanticDateRangeSource
    let comparisonDateRange: HomeQueryDateRange?
    let resolvedTarget: MarinaResolvedEntityReference?
    let resolvedComparisonTarget: MarinaResolvedEntityReference?
    let resolvedScope: MarinaResolvedScope?
    let whatIfAmount: Double?
    let categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter?
    let requiresDateField: Bool
    let requiresAmountField: Bool

    var entity: MarinaSemanticEntity {
        surface.semanticEntity ?? .variableExpense
    }

    init(
        entity: MarinaSemanticEntity,
        projection: MarinaSemanticProjection = .records,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        search: MarinaRowSearchClause? = nil,
        filters: [MarinaRowFilter] = [],
        groupBy: MarinaRowGroupTarget? = nil,
        sorts: [MarinaRowSort] = [],
        offset: Int = 0,
        limit: Int? = nil,
        dateRange: HomeQueryDateRange? = nil,
        dateRangeSource: MarinaSemanticDateRangeSource = .defaulted,
        comparisonDateRange: HomeQueryDateRange? = nil,
        resolvedTarget: MarinaResolvedEntityReference? = nil,
        resolvedComparisonTarget: MarinaResolvedEntityReference? = nil,
        resolvedScope: MarinaResolvedScope? = nil,
        whatIfAmount: Double? = nil,
        categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
        requiresDateField: Bool = false,
        requiresAmountField: Bool = false
    ) {
        self.init(
            surface: .semantic(entity),
            projection: projection,
            operation: operation,
            measure: measure,
            search: search,
            filters: filters,
            groupBy: groupBy,
            sorts: sorts,
            offset: offset,
            limit: limit,
            dateRange: dateRange,
            dateRangeSource: dateRangeSource,
            comparisonDateRange: comparisonDateRange,
            resolvedTarget: resolvedTarget,
            resolvedComparisonTarget: resolvedComparisonTarget,
            resolvedScope: resolvedScope,
            whatIfAmount: whatIfAmount,
            categoryAvailabilityFilter: categoryAvailabilityFilter,
            requiresDateField: requiresDateField,
            requiresAmountField: requiresAmountField
        )
    }

    init(
        surface: MarinaUniversalEntitySurface,
        projection: MarinaSemanticProjection = .records,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        search: MarinaRowSearchClause? = nil,
        filters: [MarinaRowFilter] = [],
        groupBy: MarinaRowGroupTarget? = nil,
        sorts: [MarinaRowSort] = [],
        offset: Int = 0,
        limit: Int? = nil,
        dateRange: HomeQueryDateRange? = nil,
        dateRangeSource: MarinaSemanticDateRangeSource = .defaulted,
        comparisonDateRange: HomeQueryDateRange? = nil,
        resolvedTarget: MarinaResolvedEntityReference? = nil,
        resolvedComparisonTarget: MarinaResolvedEntityReference? = nil,
        resolvedScope: MarinaResolvedScope? = nil,
        whatIfAmount: Double? = nil,
        categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
        requiresDateField: Bool = false,
        requiresAmountField: Bool = false
    ) {
        self.surface = surface
        self.projection = projection
        self.operation = operation
        self.measure = measure
        self.search = search
        self.filters = filters
        self.groupBy = groupBy
        self.sorts = sorts
        self.offset = max(0, offset)
        self.limit = limit
        self.dateRange = dateRange
        self.dateRangeSource = dateRangeSource
        self.comparisonDateRange = comparisonDateRange
        self.resolvedTarget = resolvedTarget
        self.resolvedComparisonTarget = resolvedComparisonTarget
        self.resolvedScope = resolvedScope
        self.whatIfAmount = whatIfAmount
        self.categoryAvailabilityFilter = categoryAvailabilityFilter
        self.requiresDateField = requiresDateField
        self.requiresAmountField = requiresAmountField
    }
}

nonisolated enum MarinaUniversalQueryResult: Equatable, Sendable {
    case rows([MarinaQueryableRow])
    case rowsPage(MarinaUniversalRowsPage)
    case metric(MarinaUniversalMetricResult)
    case groups([MarinaUniversalGroupResult])
    case unsupported(MarinaCapabilityFailureReason)
}

nonisolated struct MarinaUniversalRowsPage: Equatable, Sendable {
    let rows: [MarinaQueryableRow]
    let totalRowCount: Int
    let fullTotalAmount: Double?
    let offset: Int
    let displayLimit: Int?
    let hasMore: Bool
    let nextOffset: Int?

    init(
        rows: [MarinaQueryableRow],
        totalRowCount: Int,
        fullTotalAmount: Double? = nil,
        offset: Int = 0,
        displayLimit: Int? = nil,
        hasMore: Bool? = nil,
        nextOffset: Int? = nil
    ) {
        let normalizedOffset = max(0, offset)
        let inferredHasMore = normalizedOffset + rows.count < totalRowCount
        self.rows = rows
        self.totalRowCount = totalRowCount
        self.fullTotalAmount = fullTotalAmount
        self.offset = normalizedOffset
        self.displayLimit = displayLimit
        self.hasMore = hasMore ?? inferredHasMore
        self.nextOffset = nextOffset ?? ((hasMore ?? inferredHasMore) ? normalizedOffset + rows.count : nil)
    }
}

nonisolated struct MarinaUniversalMetricResult: Equatable, Sendable {
    let value: MarinaValue
    let evidenceRows: [MarinaQueryableRow]
    let details: [MarinaFormulaMetricDetail]
    let presentationRows: [MarinaFormulaPresentationRow]

    init(
        value: MarinaValue,
        evidenceRows: [MarinaQueryableRow],
        details: [MarinaFormulaMetricDetail] = [],
        presentationRows: [MarinaFormulaPresentationRow] = []
    ) {
        self.value = value
        self.evidenceRows = evidenceRows
        self.details = details
        self.presentationRows = presentationRows
    }
}

nonisolated struct MarinaUniversalGroupResult: Equatable, Sendable {
    let group: MarinaGroupedRows
    let aggregate: MarinaValue?
}
