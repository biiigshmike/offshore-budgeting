import Foundation

struct MarinaSemanticUniversalPlanBridge {
    let catalog: MarinaEntityCatalog
    let formulaRegistry: MarinaFormulaRegistry?

    init(
        catalog: MarinaEntityCatalog = MarinaEntityCatalog(),
        formulaRegistry: MarinaFormulaRegistry? = nil
    ) {
        self.catalog = catalog
        self.formulaRegistry = formulaRegistry
    }

    func makePlan(
        from request: MarinaSemanticRequest
    ) -> MarinaSemanticUniversalPlanBridgeResult {
        makePlan(from: request, planningContext: nil)
    }

    func makePlan(
        from request: MarinaSemanticRequest,
        planningContext: MarinaUniversalPlanningContext
    ) -> MarinaSemanticUniversalPlanBridgeResult {
        makePlan(from: request, planningContext: Optional(planningContext))
    }

    private func makePlan(
        from request: MarinaSemanticRequest,
        planningContext: MarinaUniversalPlanningContext?
    ) -> MarinaSemanticUniversalPlanBridgeResult {
        if request.unsupportedReason != nil || request.expectedAnswerShape == .unsupported {
            return .unsupported(.unsupportedCombination)
        }

        switch resolvedSurface(for: request) {
        case let .success(surface):
            return makePlan(for: request, surface: surface, planningContext: planningContext)
        case let .failure(reason):
            return .unsupported(reason)
        }
    }

    private func makePlan(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        planningContext: MarinaUniversalPlanningContext?
    ) -> MarinaSemanticUniversalPlanBridgeResult {
        guard supportedSurface(surface) else {
            return .unsupported(.unsupportedCombination)
        }

        guard supportedOperations.contains(request.operation)
            || formulaSupports(request: request, surface: surface) else {
            return .unsupported(.unsupportedCombination)
        }

        guard let descriptor = catalog.descriptor(for: surface) else {
            return .unsupported(.missingEntityDescriptor)
        }

        if let measure = request.measure {
            guard supports(
                surface: surface,
                operation: request.operation,
                measure: measure,
                descriptor: descriptor
            ) else {
                return .unsupported(.measureNotAvailable)
            }
        }

        guard descriptor.supportedOperations.contains(request.operation)
            || formulaSupports(request: request, surface: surface) else {
            return .unsupported(.operationNotSupported)
        }

        guard let search = searchClause(for: request, surface: surface, descriptor: descriptor) else {
            if trimmed(request.textQuery).isEmpty == false {
                return .unsupported(.fieldNotSearchable)
            }
            return planWithoutSearch(
                for: request,
                surface: surface,
                descriptor: descriptor,
                planningContext: planningContext
            )
        }

        return planWithoutSearch(
            for: request,
            surface: surface,
            descriptor: descriptor,
            planningContext: planningContext,
            search: search
        )
    }

    private func planWithoutSearch(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        descriptor: MarinaUniversalSurfaceDescriptor,
        planningContext: MarinaUniversalPlanningContext?,
        search: MarinaRowSearchClause? = nil
    ) -> MarinaSemanticUniversalPlanBridgeResult {
        let filtersResult = filters(for: request, surface: surface, descriptor: descriptor)
        guard case let .success(filters) = filtersResult else {
            if case let .failure(reason) = filtersResult {
                return .unsupported(reason)
            }
            return .unsupported(.unsupportedCombination)
        }

        let dateFiltersResult = dateFilters(
            for: request,
            surface: surface,
            descriptor: descriptor,
            planningContext: planningContext
        )
        guard case let .success(dateFilters) = dateFiltersResult else {
            if case let .failure(reason) = dateFiltersResult {
                return .unsupported(reason)
            }
            return .unsupported(.unsupportedCombination)
        }

        let groupResult = groupTarget(for: request, descriptor: descriptor)
        guard case let .success(groupBy) = groupResult else {
            if case let .failure(reason) = groupResult {
                return .unsupported(reason)
            }
            return .unsupported(.unsupportedCombination)
        }

        let sortResult = sorts(for: request, surface: surface, descriptor: descriptor)
        guard case let .success(sorts) = sortResult else {
            if case let .failure(reason) = sortResult {
                return .unsupported(reason)
            }
            return .unsupported(.unsupportedCombination)
        }

        let resolvedDateContext = dateContext(for: request, planningContext: planningContext)

        return .plan(
            MarinaUniversalQueryPlan(
                surface: surface,
                operation: request.operation,
                measure: request.measure,
                search: search,
                filters: filters + dateFilters,
                groupBy: groupBy,
                sorts: sorts,
                limit: clampedLimit(request.resultLimit),
                dateRange: resolvedDateContext?.dateRange,
                comparisonDateRange: resolvedDateContext?.comparisonDateRange,
                whatIfAmount: request.whatIfAmount,
                requiresDateField: requiresDateField(
                    for: request,
                    surface: surface,
                    descriptor: descriptor,
                    planningContext: planningContext
                ),
                requiresAmountField: requiresAmountField(request)
            )
        )
    }

    private var supportedEntities: Set<MarinaSemanticEntity> {
        [
            .variableExpense,
            .plannedExpense,
            .income,
            .category,
            .card,
            .budget,
            .preset,
            .savingsAccount,
            .reconciliationAccount
        ]
    }

    private var supportedOperations: Set<MarinaSemanticOperation> {
        [.list, .count, .sum, .average, .group, .last, .next]
    }

    private var simpleMeasures: Set<MarinaSemanticMeasure> {
        [.budgetImpact, .amount, .plannedAmount, .actualAmount, .effectiveAmount, .incomeAmount, .name, .color]
    }

    private var dateFilteredEntities: Set<MarinaSemanticEntity> {
        [.variableExpense, .plannedExpense, .income]
    }

    private func supportedSurface(_ surface: MarinaUniversalEntitySurface) -> Bool {
        switch surface {
        case let .semantic(entity):
            return supportedEntities.contains(entity)
        case .unifiedExpenses:
            return true
        case .savingsLedgerEntries, .reconciliationLedgerEntries:
            return false
        }
    }

    private func supports(
        surface: MarinaUniversalEntitySurface,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> Bool {
        if formulaRegistry?.supports(measure: measure, surface: surface, operation: operation) == true {
            return true
        }

        guard simpleMeasures.contains(measure) else {
            return false
        }

        switch surface {
        case let .semantic(entity):
            return catalog.supports(entity: entity, measure: measure) == .supported
        case .unifiedExpenses, .savingsLedgerEntries, .reconciliationLedgerEntries:
            return descriptor.supportedMeasures.contains(measure)
        }
    }

    private func formulaSupports(
        request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface
    ) -> Bool {
        guard let measure = request.measure else {
            return false
        }
        return formulaRegistry?.supports(
            measure: measure,
            surface: surface,
            operation: request.operation
        ) == true
    }

    private func resolvedSurface(
        for request: MarinaSemanticRequest
    ) -> BridgeValueResult<MarinaUniversalEntitySurface> {
        guard let scope = request.expenseScope else {
            return .success(.semantic(request.entity))
        }

        switch scope {
        case .variable:
            return .success(.semantic(.variableExpense))
        case .planned:
            return .success(.semantic(.plannedExpense))
        case .unified:
            switch request.entity {
            case .variableExpense, .plannedExpense:
                return .success(.unifiedExpenses)
            case .workspace, .budget, .card, .reconciliationAccount, .savingsAccount, .income, .category, .preset:
                return .failure(.unsupportedCombination)
            }
        }
    }

    private func searchClause(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> MarinaRowSearchClause? {
        let query = trimmed(request.textQuery)
        guard query.isEmpty == false else {
            return nil
        }

        let preferredFields: [MarinaFieldKey]
        switch surface {
        case let .semantic(entity):
            switch entity {
            case .variableExpense:
                preferredFields = [.merchantText, .descriptionText]
            case .plannedExpense:
                preferredFields = [.merchantText, .title]
            case .income:
                preferredFields = [.source]
            case .workspace, .budget, .card, .reconciliationAccount, .savingsAccount, .category, .preset:
                preferredFields = descriptor.defaultSearchFields
            }
        case .unifiedExpenses:
            preferredFields = descriptor.defaultSearchFields
        case .savingsLedgerEntries, .reconciliationLedgerEntries:
            preferredFields = descriptor.defaultSearchFields
        }

        let searchableTextFields = Set(
            descriptor.fields
                .filter { $0.isSearchable && $0.valueType == .text }
                .map(\.key)
        )
        let fields = Set(preferredFields).intersection(searchableTextFields)

        guard fields.isEmpty == false else {
            return nil
        }

        return MarinaRowSearchClause(fields: fields, query: query)
    }

    private func filters(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> BridgeValueResult<[MarinaRowFilter]> {
        let target = trimmed(request.targetName)
        guard target.isEmpty == false else {
            return .success([])
        }

        let dimensions = relationshipDimensions(in: request.dimensions)
        if dimensions.isEmpty,
           supportsNameTarget(surface),
           descriptor.fields.contains(where: { $0.key == .name && $0.isFilterable }) {
            return .success([
                MarinaRowFilter(
                    target: .field(.name),
                    operation: .equals,
                    value: .text(target)
                )
            ])
        }

        guard dimensions.count == 1,
              let dimension = dimensions.first,
              let relationship = relationshipKey(for: dimension) else {
            return .failure(.unsupportedCombination)
        }

        guard descriptor.relationships.contains(where: { $0.key == relationship && $0.isFilterable }) else {
            return .failure(.fieldNotFilterable)
        }

        return .success([
            MarinaRowFilter(
                target: .relationship(relationship),
                operation: .equals,
                value: .text(target)
            )
        ])
    }

    private func dateFilters(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        descriptor: MarinaUniversalSurfaceDescriptor,
        planningContext: MarinaUniversalPlanningContext?
    ) -> BridgeValueResult<[MarinaRowFilter]> {
        guard let planningContext,
              request.dateRangeToken != .allTime,
              dateFilteredSurface(surface) else {
            return .success([])
        }

        guard let dateField = descriptor.defaultDateField else {
            return .failure(.missingDateField)
        }

        guard descriptor.fields.contains(where: { $0.key == dateField && $0.isFilterable }) else {
            return .failure(.fieldNotFilterable)
        }

        let planner = MarinaQueryPlanner(calendar: planningContext.calendar)
        let queryPlan = planner.plan(
            request: request,
            ambientDateRange: planningContext.ambientDateRange,
            defaultBudgetingPeriod: planningContext.defaultBudgetingPeriod,
            now: planningContext.now
        )

        guard let range = queryPlan.dateRange else {
            return .success([])
        }

        return .success([
            MarinaRowFilter(
                target: .field(dateField),
                operation: .greaterThanOrEqual,
                value: .date(range.startDate)
            ),
            MarinaRowFilter(
                target: .field(dateField),
                operation: .lessThanOrEqual,
                value: .date(range.endDate)
            )
        ])
    }

    private func dateContext(
        for request: MarinaSemanticRequest,
        planningContext: MarinaUniversalPlanningContext?
    ) -> (dateRange: HomeQueryDateRange?, comparisonDateRange: HomeQueryDateRange?)? {
        guard let planningContext else {
            return nil
        }

        let planner = MarinaQueryPlanner(calendar: planningContext.calendar)
        let queryPlan = planner.plan(
            request: request,
            ambientDateRange: planningContext.ambientDateRange,
            defaultBudgetingPeriod: planningContext.defaultBudgetingPeriod,
            now: planningContext.now
        )

        return (queryPlan.dateRange, queryPlan.comparisonDateRange)
    }

    private func groupTarget(
        for request: MarinaSemanticRequest,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> BridgeValueResult<MarinaRowGroupTarget?> {
        guard request.operation == .group else {
            return .success(nil)
        }

        let unsupportedDimensions = request.dimensions.filter { dimension in
            switch dimension {
            case .category, .card, .incomeSource, .preset, .budget:
                return false
            case .date, .merchantText, .savingsAccount, .reconciliationAccount, .workspace:
                return true
            }
        }
        guard unsupportedDimensions.isEmpty else {
            return .failure(.unsupportedCombination)
        }

        let dimensions = relationshipDimensions(in: request.dimensions)
        guard dimensions.count == 1,
              let dimension = dimensions.first,
              let relationship = relationshipKey(for: dimension) else {
            return .failure(.unsupportedCombination)
        }

        guard descriptor.relationships.contains(where: { $0.key == relationship && $0.isGroupable }) else {
            return .failure(.fieldNotGroupable)
        }

        return .success(.relationship(relationship))
    }

    private func sorts(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> BridgeValueResult<[MarinaRowSort]> {
        let sort: MarinaRowSort?

        switch request.sort {
        case nil:
            switch request.operation {
            case .last:
                guard let dateField = descriptor.defaultDateField else {
                    return .failure(.missingDateField)
                }
                sort = MarinaRowSort(target: .field(dateField), direction: .descending)
            case .next:
                guard let dateField = descriptor.defaultDateField else {
                    return .failure(.missingDateField)
                }
                sort = MarinaRowSort(target: .field(dateField), direction: .ascending)
            case .list, .count, .sum, .average, .compare, .group, .share, .forecast, .whatIf:
                sort = nil
            }
        case .some(.dateAscending):
            guard let dateField = descriptor.defaultDateField else {
                return .failure(.missingDateField)
            }
            sort = MarinaRowSort(target: .field(dateField), direction: .ascending)
        case .some(.dateDescending):
            guard let dateField = descriptor.defaultDateField else {
                return .failure(.missingDateField)
            }
            sort = MarinaRowSort(target: .field(dateField), direction: .descending)
        case .some(.amountAscending):
            guard let amountField = amountSortField(for: request, surface: surface, descriptor: descriptor) else {
                return .failure(.missingAmountField)
            }
            sort = MarinaRowSort(target: .field(amountField), direction: .ascending)
        case .some(.amountDescending):
            guard let amountField = amountSortField(for: request, surface: surface, descriptor: descriptor) else {
                return .failure(.missingAmountField)
            }
            sort = MarinaRowSort(target: .field(amountField), direction: .descending)
        case .some(.nameAscending):
            sort = MarinaRowSort(target: .field(nameSortField(for: surface)), direction: .ascending)
        }

        guard let sort else {
            return .success([])
        }

        guard sortFieldIsSortable(sort, descriptor: descriptor) else {
            return .failure(.fieldNotSortable)
        }

        return .success([sort])
    }

    private func amountSortField(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> MarinaFieldKey? {
        if let measure = request.measure {
            return field(for: measure, surface: surface)
        }
        return descriptor.defaultAmountField
    }

    private func nameSortField(for surface: MarinaUniversalEntitySurface) -> MarinaFieldKey {
        switch surface {
        case let .semantic(entity):
            switch entity {
            case .plannedExpense, .preset:
                return .title
            case .variableExpense:
                return .descriptionText
            case .income:
                return .source
            case .workspace, .budget, .card, .reconciliationAccount, .savingsAccount, .category:
                return .name
            }
        case .unifiedExpenses:
            return .merchantText
        case .savingsLedgerEntries, .reconciliationLedgerEntries:
            return .note
        }
    }

    private func sortFieldIsSortable(
        _ sort: MarinaRowSort,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> Bool {
        guard case let .field(field) = sort.target else {
            return false
        }
        return descriptor.fields.contains { $0.key == field && $0.isSortable }
    }

    private func field(
        for measure: MarinaSemanticMeasure,
        surface: MarinaUniversalEntitySurface
    ) -> MarinaFieldKey? {
        switch surface {
        case let .semantic(entity):
            return field(for: measure, entity: entity)
        case .unifiedExpenses:
            switch measure {
            case .budgetImpact:
                return .budgetImpact
            case .amount,
                 .plannedAmount,
                 .actualAmount,
                 .effectiveAmount,
                 .incomeAmount,
                 .name,
                 .color,
                 .savingsTotal,
                 .reconciliationBalance,
                 .categoryAvailability,
                 .remainingRoom,
                 .burnRate,
                 .projectedSpend,
                 .safeDailySpend,
                 .paceDifference,
                 .coverageRatio,
                 .recurringBurden,
                 .concentration:
                return nil
            }
        case .savingsLedgerEntries, .reconciliationLedgerEntries:
            switch measure {
            case .amount:
                return .amount
            case .budgetImpact,
                 .plannedAmount,
                 .actualAmount,
                 .effectiveAmount,
                 .incomeAmount,
                 .name,
                 .color,
                 .savingsTotal,
                 .reconciliationBalance,
                 .categoryAvailability,
                 .remainingRoom,
                 .burnRate,
                 .projectedSpend,
                 .safeDailySpend,
                 .paceDifference,
                 .coverageRatio,
                 .recurringBurden,
                 .concentration:
                return nil
            }
        }
    }

    private func field(
        for measure: MarinaSemanticMeasure,
        entity: MarinaSemanticEntity
    ) -> MarinaFieldKey? {
        switch measure {
        case .budgetImpact:
            return .budgetImpact
        case .amount:
            return .amount
        case .plannedAmount:
            return .plannedAmount
        case .actualAmount:
            return .actualAmount
        case .effectiveAmount:
            return .effectiveAmount
        case .incomeAmount:
            return .incomeAmount
        case .name:
            return entity == .preset ? .title : .name
        case .color:
            return .color
        case .savingsTotal,
             .reconciliationBalance,
             .categoryAvailability,
             .remainingRoom,
             .burnRate,
             .projectedSpend,
             .safeDailySpend,
             .paceDifference,
             .coverageRatio,
             .recurringBurden,
             .concentration:
            return nil
        }
    }

    private func relationshipDimensions(
        in dimensions: [MarinaSemanticDimension]
    ) -> [MarinaSemanticDimension] {
        dimensions.reduce(into: []) { result, dimension in
            guard relationshipKey(for: dimension) != nil,
                  result.contains(dimension) == false else {
                return
            }
            result.append(dimension)
        }
    }

    private func relationshipKey(
        for dimension: MarinaSemanticDimension
    ) -> MarinaRelationshipKey? {
        switch dimension {
        case .category:
            return .category
        case .card:
            return .card
        case .incomeSource:
            return .incomeSource
        case .preset:
            return .preset
        case .budget:
            return .budget
        case .date, .merchantText, .savingsAccount, .reconciliationAccount, .workspace:
            return nil
        }
    }

    private func clampedLimit(_ limit: Int?) -> Int? {
        guard let limit else {
            return nil
        }
        return min(max(limit, 1), 20)
    }

    private func requiresDateField(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        descriptor: MarinaUniversalSurfaceDescriptor,
        planningContext: MarinaUniversalPlanningContext?
    ) -> Bool {
        if planningContext != nil {
            return request.dateRangeToken != .allTime && dateFilteredSurface(surface)
        }
        return request.dateRangeToken != .allTime && descriptor.defaultDateField != nil
    }

    private func dateFilteredSurface(_ surface: MarinaUniversalEntitySurface) -> Bool {
        switch surface {
        case let .semantic(entity):
            return dateFilteredEntities.contains(entity)
        case .unifiedExpenses:
            return true
        case .savingsLedgerEntries, .reconciliationLedgerEntries:
            return false
        }
    }

    private func supportsNameTarget(_ surface: MarinaUniversalEntitySurface) -> Bool {
        guard case let .semantic(entity) = surface else {
            return false
        }
        return entity == .savingsAccount || entity == .reconciliationAccount
    }

    private func requiresAmountField(_ request: MarinaSemanticRequest) -> Bool {
        switch request.operation {
        case .sum, .average:
            return true
        case .group:
            return request.measure != nil
        case .list, .count, .compare, .last, .next, .share, .forecast, .whatIf:
            return false
        }
    }

    private func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum MarinaSemanticUniversalPlanBridgeResult: Equatable, Sendable {
    case plan(MarinaUniversalQueryPlan)
    case unsupported(MarinaCapabilityFailureReason)
}

private enum BridgeValueResult<Value> {
    case success(Value)
    case failure(MarinaCapabilityFailureReason)
}
