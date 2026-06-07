import Foundation

struct MarinaSemanticUniversalPlanBridge {
    let catalog: MarinaEntityCatalog

    init(catalog: MarinaEntityCatalog = MarinaEntityCatalog()) {
        self.catalog = catalog
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

        switch resolvedEntity(for: request) {
        case let .success(entity):
            return makePlan(for: request, entity: entity, planningContext: planningContext)
        case let .failure(reason):
            return .unsupported(reason)
        }
    }

    private func makePlan(
        for request: MarinaSemanticRequest,
        entity: MarinaSemanticEntity,
        planningContext: MarinaUniversalPlanningContext?
    ) -> MarinaSemanticUniversalPlanBridgeResult {
        guard supportedEntities.contains(entity) else {
            return .unsupported(.unsupportedCombination)
        }

        guard supportedOperations.contains(request.operation) else {
            return .unsupported(.unsupportedCombination)
        }

        guard let descriptor = catalog.descriptor(for: entity) else {
            return .unsupported(.missingEntityDescriptor)
        }

        if let measure = request.measure {
            guard simpleMeasures.contains(measure) else {
                return .unsupported(.measureNotAvailable)
            }

            guard catalog.supports(entity: entity, measure: measure) == .supported else {
                return .unsupported(.measureNotAvailable)
            }
        }

        guard catalog.supports(entity: entity, operation: request.operation) == .supported else {
            return .unsupported(.operationNotSupported)
        }

        guard let search = searchClause(for: request, entity: entity, descriptor: descriptor) else {
            if trimmed(request.textQuery).isEmpty == false {
                return .unsupported(.fieldNotSearchable)
            }
            return planWithoutSearch(
                for: request,
                entity: entity,
                descriptor: descriptor,
                planningContext: planningContext
            )
        }

        return planWithoutSearch(
            for: request,
            entity: entity,
            descriptor: descriptor,
            planningContext: planningContext,
            search: search
        )
    }

    private func planWithoutSearch(
        for request: MarinaSemanticRequest,
        entity: MarinaSemanticEntity,
        descriptor: MarinaEntityDescriptor,
        planningContext: MarinaUniversalPlanningContext?,
        search: MarinaRowSearchClause? = nil
    ) -> MarinaSemanticUniversalPlanBridgeResult {
        let filtersResult = filters(for: request, descriptor: descriptor)
        guard case let .success(filters) = filtersResult else {
            if case let .failure(reason) = filtersResult {
                return .unsupported(reason)
            }
            return .unsupported(.unsupportedCombination)
        }

        let dateFiltersResult = dateFilters(
            for: request,
            entity: entity,
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

        let sortResult = sorts(for: request, entity: entity, descriptor: descriptor)
        guard case let .success(sorts) = sortResult else {
            if case let .failure(reason) = sortResult {
                return .unsupported(reason)
            }
            return .unsupported(.unsupportedCombination)
        }

        return .plan(
            MarinaUniversalQueryPlan(
                entity: entity,
                operation: request.operation,
                measure: request.measure,
                search: search,
                filters: filters + dateFilters,
                groupBy: groupBy,
                sorts: sorts,
                limit: clampedLimit(request.resultLimit),
                requiresDateField: requiresDateField(
                    for: request,
                    entity: entity,
                    descriptor: descriptor,
                    planningContext: planningContext
                ),
                requiresAmountField: requiresAmountField(request)
            )
        )
    }

    private var supportedEntities: Set<MarinaSemanticEntity> {
        [.variableExpense, .plannedExpense, .income, .category, .card, .budget, .preset]
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

    private func resolvedEntity(
        for request: MarinaSemanticRequest
    ) -> BridgeValueResult<MarinaSemanticEntity> {
        guard let scope = request.expenseScope else {
            return .success(request.entity)
        }

        switch scope {
        case .variable:
            return .success(.variableExpense)
        case .planned:
            return .success(.plannedExpense)
        case .unified:
            return .failure(.unsupportedCombination)
        }
    }

    private func searchClause(
        for request: MarinaSemanticRequest,
        entity: MarinaSemanticEntity,
        descriptor: MarinaEntityDescriptor
    ) -> MarinaRowSearchClause? {
        let query = trimmed(request.textQuery)
        guard query.isEmpty == false else {
            return nil
        }

        let preferredFields: [MarinaFieldKey]
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
        descriptor: MarinaEntityDescriptor
    ) -> BridgeValueResult<[MarinaRowFilter]> {
        let target = trimmed(request.targetName)
        guard target.isEmpty == false else {
            return .success([])
        }

        let dimensions = relationshipDimensions(in: request.dimensions)
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
        entity: MarinaSemanticEntity,
        descriptor: MarinaEntityDescriptor,
        planningContext: MarinaUniversalPlanningContext?
    ) -> BridgeValueResult<[MarinaRowFilter]> {
        guard let planningContext,
              request.dateRangeToken != .allTime,
              dateFilteredEntities.contains(entity) else {
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

    private func groupTarget(
        for request: MarinaSemanticRequest,
        descriptor: MarinaEntityDescriptor
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
        entity: MarinaSemanticEntity,
        descriptor: MarinaEntityDescriptor
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
            guard let amountField = amountSortField(for: request, descriptor: descriptor) else {
                return .failure(.missingAmountField)
            }
            sort = MarinaRowSort(target: .field(amountField), direction: .ascending)
        case .some(.amountDescending):
            guard let amountField = amountSortField(for: request, descriptor: descriptor) else {
                return .failure(.missingAmountField)
            }
            sort = MarinaRowSort(target: .field(amountField), direction: .descending)
        case .some(.nameAscending):
            sort = MarinaRowSort(target: .field(nameSortField(for: entity)), direction: .ascending)
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
        descriptor: MarinaEntityDescriptor
    ) -> MarinaFieldKey? {
        if let measure = request.measure {
            return field(for: measure, entity: descriptor.entity)
        }
        return descriptor.defaultAmountField
    }

    private func nameSortField(for entity: MarinaSemanticEntity) -> MarinaFieldKey {
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
    }

    private func sortFieldIsSortable(
        _ sort: MarinaRowSort,
        descriptor: MarinaEntityDescriptor
    ) -> Bool {
        guard case let .field(field) = sort.target else {
            return false
        }
        return descriptor.fields.contains { $0.key == field && $0.isSortable }
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
        entity: MarinaSemanticEntity,
        descriptor: MarinaEntityDescriptor,
        planningContext: MarinaUniversalPlanningContext?
    ) -> Bool {
        if planningContext != nil {
            return request.dateRangeToken != .allTime && dateFilteredEntities.contains(entity)
        }
        return request.dateRangeToken != .allTime && descriptor.defaultDateField != nil
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

enum MarinaSemanticUniversalPlanBridgeResult: Equatable, Sendable {
    case plan(MarinaUniversalQueryPlan)
    case unsupported(MarinaCapabilityFailureReason)
}

private enum BridgeValueResult<Value> {
    case success(Value)
    case failure(MarinaCapabilityFailureReason)
}
