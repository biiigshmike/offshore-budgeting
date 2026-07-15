import Foundation

struct MarinaSemanticUniversalPlanBridge {
    let catalog: MarinaEntityCatalog
    let formulaRegistry: MarinaFormulaRegistry?
    let canonicalizer: MarinaSemanticExecutionCanonicalizer

    init(
        catalog: MarinaEntityCatalog = MarinaEntityCatalog(),
        formulaRegistry: MarinaFormulaRegistry? = nil,
        canonicalizer: MarinaSemanticExecutionCanonicalizer = MarinaSemanticExecutionCanonicalizer()
    ) {
        self.catalog = catalog
        self.formulaRegistry = formulaRegistry
        self.canonicalizer = canonicalizer
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

        switch canonicalizer.canonicalize(request) {
        case let .shape(shape):
            return makePlan(for: request, shape: shape, planningContext: planningContext)
        case let .unsupported(reason):
            return .unsupported(reason)
        }
    }

    private func makePlan(
        for request: MarinaSemanticRequest,
        shape: MarinaCanonicalExecutionShape,
        planningContext: MarinaUniversalPlanningContext?
    ) -> MarinaSemanticUniversalPlanBridgeResult {
        let surface = shape.surface
        guard supportedSurface(surface) else {
            return .unsupported(.unsupportedCombination)
        }

        guard supportedFormulaVariant(request) else {
            return .unsupported(.unsupportedCombination)
        }

        guard supportedOperations.contains(request.operation)
            || formulaSupports(request: request, surface: surface) else {
            return .unsupported(.unsupportedCombination)
        }

        guard let descriptor = catalog.executionDescriptor(
            for: surface,
            projection: shape.projection
        ) else {
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
            || genericComparisonIsSupported(request: request, descriptor: descriptor)
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
                projection: shape.projection,
                descriptor: descriptor,
                planningContext: planningContext
            )
        }

        return planWithoutSearch(
            for: request,
            surface: surface,
            projection: shape.projection,
            descriptor: descriptor,
            planningContext: planningContext,
            search: search
        )
    }

    private func planWithoutSearch(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        projection: MarinaSemanticProjection,
        descriptor: MarinaUniversalSurfaceDescriptor,
        planningContext: MarinaUniversalPlanningContext?,
        search: MarinaRowSearchClause? = nil
    ) -> MarinaSemanticUniversalPlanBridgeResult {
        let filtersResult = filters(
            for: request,
            surface: surface,
            projection: projection,
            descriptor: descriptor
        )
        guard case let .success(filters) = filtersResult else {
            if case let .failure(reason) = filtersResult {
                return .unsupported(reason)
            }
            return .unsupported(.unsupportedCombination)
        }

        let incomeStateFiltersResult = incomeStateFilters(
            for: request,
            surface: surface,
            descriptor: descriptor
        )
        guard case let .success(incomeStateFilters) = incomeStateFiltersResult else {
            if case let .failure(reason) = incomeStateFiltersResult {
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

        let plan = MarinaUniversalQueryPlan(
                surface: surface,
                projection: projection,
                operation: request.operation,
                measure: request.measure,
                search: search,
                filters: filters + incomeStateFilters + dateFilters,
                groupBy: groupBy,
                sorts: sorts,
                offset: max(0, request.resultOffset ?? 0),
                limit: clampedLimit(request.resultLimit, operation: request.operation),
                dateRange: resolvedDateContext?.dateRange,
                dateRangeSource: request.dateRangeSource,
                comparisonDateRange: resolvedDateContext?.comparisonDateRange,
                resolvedTarget: request.resolvedTarget,
                resolvedComparisonTarget: request.resolvedComparisonTarget,
                resolvedScope: request.resolvedScope,
                whatIfAmount: request.whatIfAmount,
                categoryAvailabilityFilter: request.categoryAvailabilityFilter,
                requiresDateField: requiresDateField(
                    for: request,
                    surface: surface,
                    descriptor: descriptor,
                    planningContext: planningContext
                ),
                requiresAmountField: requiresAmountField(request)
            )
        return validatedResult(for: plan)
    }

    private var supportedEntities: Set<MarinaSemanticEntity> {
        [
            .variableExpense,
            .plannedExpense,
            .income,
            .incomeSeries,
            .category,
            .card,
            .budget,
            .preset,
            .savingsAccount,
            .reconciliationAccount,
            .workspace
        ]
    }

    private var supportedOperations: Set<MarinaSemanticOperation> {
        [.list, .count, .sum, .average, .compare, .group, .last, .next]
    }

    private var simpleMeasures: Set<MarinaSemanticMeasure> {
        [
            .budgetImpact,
            .projectedBudgetImpact,
            .ledgerSignedAmount,
            .plannedIncomeTotal,
            .actualIncomeTotal,
            .plannedExpenseProjectedTotal,
            .plannedExpenseActualTotal,
            .plannedExpenseEffectiveTotal,
            .variableExpenseTotal,
            .unifiedExpenseTotal,
            .maximumSavings,
            .projectedSavings,
            .actualSavings,
            .amount,
            .plannedAmount,
            .actualAmount,
            .effectiveAmount,
            .incomeAmount,
            .name,
            .color
        ]
    }

    private var dateFilteredEntities: Set<MarinaSemanticEntity> {
        [.variableExpense, .plannedExpense, .income, .incomeSeries]
    }

    private func supportedFormulaVariant(_ request: MarinaSemanticRequest) -> Bool {
        guard request.entity == .category,
              request.operation == .list,
              request.measure == .categoryAvailability else {
            return true
        }

        switch request.categoryAvailabilityFilter {
        case .over, .near, .underLimit:
            return true
        case .all, nil:
            return false
        }
    }

    private func supportedSurface(_ surface: MarinaUniversalEntitySurface) -> Bool {
        switch surface {
        case let .semantic(entity):
            return supportedEntities.contains(entity)
        case .unifiedExpenses:
            return true
        case .savingsLedgerEntries, .reconciliationLedgerEntries:
            return true
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

    private func genericComparisonIsSupported(
        request: MarinaSemanticRequest,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> Bool {
        guard request.operation == .compare,
              let measure = request.measure,
              descriptor.supportedMeasures.contains(measure),
              let field = field(for: measure, surface: descriptor.surface) else {
            return false
        }
        return descriptor.fields.contains { $0.key == field && $0.isAggregatable }
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
            case .incomeSeries:
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
        projection: MarinaSemanticProjection,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> BridgeValueResult<[MarinaRowFilter]> {
        let target = trimmed(request.targetName)
        var constraints = request.constraints

        if constraints.isEmpty,
           projection == .records || projection == .summary,
           trimmed(request.textQuery).isEmpty,
           let resolvedTarget = request.resolvedTarget,
           resolvedTarget.entity == surface.semanticEntity,
           let resolvedID = resolvedTarget.id,
           descriptor.fields.contains(where: { $0.key == .id && $0.isFilterable }) {
            return .success([
                MarinaRowFilter(
                    target: .field(.id),
                    operation: .equals,
                    value: .text(resolvedID.uuidString)
                )
            ])
        }

        if constraints.isEmpty,
           target.isEmpty == false,
           projectionOwnerIsResolvedByProvider(
               surface: surface,
               projection: projection,
               target: request.resolvedTarget
           ) {
            // These projections resolve their owner before returning related
            // rows. Filtering those child rows by the owner's relationship
            // would reject valid plans (and would be redundant at execution).
            return .success([])
        }

        if constraints.isEmpty, target.isEmpty == false {
            var inferredDimensions = relationshipDimensions(in: request.dimensions)
            if inferredDimensions.isEmpty, surface == .unifiedExpenses {
                if request.entity == .card {
                    inferredDimensions = [.card]
                } else if request.entity == .category {
                    inferredDimensions = [.category]
                }
            }
            if inferredDimensions.count == 1, let dimension = inferredDimensions.first {
                constraints = [
                    MarinaSemanticConstraint(
                        dimension: dimension,
                        value: target,
                        resolvedReference: request.resolvedTarget
                    )
                ]
            }
        }

        if constraints.isEmpty,
           target.isEmpty == false,
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

        if constraints.isEmpty, target.isEmpty == false {
            return .failure(.unresolvedEntity)
        }

        if constraints.isEmpty {
            return .success([])
        }

        var filters: [MarinaRowFilter] = []
        for constraint in constraints {
            guard let reference = constraint.resolvedReference else {
                return .failure(.unresolvedEntity)
            }

            if constraint.dimension == .budget,
               case let .budget(scopeID)? = request.resolvedScope {
                guard reference.entity == .budget, reference.id == scopeID else {
                    return .failure(.unresolvedEntity)
                }
                // Budget scope is applied by the scoped row provider. Adding a
                // relationship filter would incorrectly remove linked-card
                // variable expenses, which do not carry a budget relationship.
                continue
            }

            if constraint.dimension == .merchantText {
                guard descriptor.fields.contains(where: { $0.key == .merchantText && $0.isFilterable }) else {
                    return .failure(.fieldNotFilterable)
                }
                filters.append(
                    MarinaRowFilter(
                        target: .field(.merchantText),
                        operation: .contains,
                        value: .text(constraint.value)
                    )
                )
                continue
            }

            guard let relationship = relationshipKey(for: constraint.dimension) else {
                return .failure(.unsupportedCombination)
            }
            guard descriptor.relationships.contains(where: { $0.key == relationship && $0.isFilterable }) else {
                return .failure(.fieldNotFilterable)
            }
            if constraint.dimension != .incomeSource, reference.id == nil {
                return .failure(.unresolvedEntity)
            }
            let resolvedValue = reference.id?.uuidString
                ?? primaryResolvedReference(for: constraint.dimension, request: request)?.id?.uuidString
                ?? constraint.value
            filters.append(
                MarinaRowFilter(
                    target: .relationship(relationship),
                    operation: .equals,
                    value: .text(resolvedValue)
                )
            )
        }

        return .success(filters)
    }

    private func projectionOwnerIsResolvedByProvider(
        surface: MarinaUniversalEntitySurface,
        projection: MarinaSemanticProjection,
        target: MarinaResolvedEntityReference?
    ) -> Bool {
        switch (surface, projection, target?.entity) {
        case (.semantic(.preset), .linkedBudgets, .preset),
             (.semantic(.incomeSeries), .occurrences, .incomeSeries),
             (.savingsLedgerEntries, .activity, .savingsAccount),
             (.reconciliationLedgerEntries, .activity, .reconciliationAccount):
            return true
        default:
            return false
        }
    }

    private func primaryResolvedReference(
        for dimension: MarinaSemanticDimension,
        request: MarinaSemanticRequest
    ) -> MarinaResolvedEntityReference? {
        let expectedEntity: MarinaSemanticEntity?
        switch dimension {
        case .category:
            expectedEntity = .category
        case .card:
            expectedEntity = .card
        case .budget:
            expectedEntity = .budget
        case .preset:
            expectedEntity = .preset
        case .incomeSeries:
            expectedEntity = .incomeSeries
        case .savingsAccount:
            expectedEntity = .savingsAccount
        case .reconciliationAccount:
            expectedEntity = .reconciliationAccount
        case .workspace:
            expectedEntity = .workspace
        case .incomeSource, .merchantText, .date:
            expectedEntity = nil
        }
        guard let expectedEntity else { return nil }
        guard request.resolvedTarget?.entity == expectedEntity else { return nil }
        return request.resolvedTarget
    }

    private func incomeStateFilters(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> BridgeValueResult<[MarinaRowFilter]> {
        let isIncomeSurface = surface == .semantic(.income) || surface == .semantic(.incomeSeries)
        guard isIncomeSurface,
              let incomeState = request.incomeState,
              incomeState != .all else {
            return .success([])
        }

        guard descriptor.fields.contains(where: { $0.key == .isPlanned && $0.isFilterable }) else {
            return .failure(.fieldNotFilterable)
        }

        switch incomeState {
        case .planned:
            return .success([
                MarinaRowFilter(target: .field(.isPlanned), operation: .equals, value: .boolean(true))
            ])
        case .actual:
            return .success([
                MarinaRowFilter(target: .field(.isPlanned), operation: .equals, value: .boolean(false))
            ])
        case .all:
            return .success([])
        }
    }

    private func dateFilters(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        descriptor: MarinaUniversalSurfaceDescriptor,
        planningContext: MarinaUniversalPlanningContext?
    ) -> BridgeValueResult<[MarinaRowFilter]> {
        guard let planningContext,
              projectionUsesDateRange(request.projection),
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
            case .category, .card, .incomeSource, .incomeSeries, .preset, .budget:
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
            case .list:
                if let dateField = descriptor.defaultDateField {
                    sort = MarinaRowSort(target: .field(dateField), direction: .descending)
                } else {
                    sort = MarinaRowSort(target: .field(.id), direction: .ascending)
                }
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
            case .count, .sum, .average, .compare, .group, .share, .forecast, .whatIf:
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

        var resolvedSorts = [sort]
        if case .field(.id) = sort.target {
            return .success(resolvedSorts)
        }
        if descriptor.fields.contains(where: { $0.key == .id && $0.isSortable }) {
            resolvedSorts.append(MarinaRowSort(target: .field(.id), direction: .ascending))
        }
        return .success(resolvedSorts)
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
            case .incomeSeries:
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
            case .budgetImpact, .unifiedExpenseTotal:
                return .budgetImpact
            case .projectedBudgetImpact:
                return .projectedBudgetImpact
            case .amount,
                 .plannedAmount,
                 .actualAmount,
                 .effectiveAmount,
                 .ledgerSignedAmount,
                 .plannedIncomeTotal,
                 .actualIncomeTotal,
                 .plannedExpenseProjectedTotal,
                 .plannedExpenseActualTotal,
                 .plannedExpenseEffectiveTotal,
                 .variableExpenseTotal,
                 .incomeAmount,
                 .name,
                 .color,
                 .savingsTotal,
                 .maximumSavings,
                 .projectedSavings,
                 .actualSavings,
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
                 .projectedBudgetImpact,
                 .ledgerSignedAmount,
                 .plannedAmount,
                 .actualAmount,
                 .effectiveAmount,
                 .plannedIncomeTotal,
                 .actualIncomeTotal,
                 .plannedExpenseProjectedTotal,
                 .plannedExpenseActualTotal,
                 .plannedExpenseEffectiveTotal,
                 .variableExpenseTotal,
                 .unifiedExpenseTotal,
                 .incomeAmount,
                 .name,
                 .color,
                 .savingsTotal,
                 .maximumSavings,
                 .projectedSavings,
                 .actualSavings,
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
        case .projectedBudgetImpact:
            return .projectedBudgetImpact
        case .ledgerSignedAmount:
            return .ledgerSignedAmount
        case .plannedIncomeTotal:
            return .plannedIncomeTotal
        case .actualIncomeTotal:
            return .actualIncomeTotal
        case .plannedExpenseProjectedTotal:
            return .plannedExpenseProjectedTotal
        case .plannedExpenseActualTotal:
            return .plannedExpenseActualTotal
        case .plannedExpenseEffectiveTotal:
            return .plannedExpenseEffectiveTotal
        case .variableExpenseTotal:
            return .variableExpenseTotal
        case .unifiedExpenseTotal:
            return .unifiedExpenseTotal
        case .maximumSavings:
            return .maximumSavings
        case .projectedSavings:
            return .projectedSavings
        case .actualSavings:
            return .actualSavings
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
        case .incomeSeries:
            return .incomeSeries
        case .preset:
            return .preset
        case .budget:
            return .budget
        case .savingsAccount:
            return .savingsAccount
        case .reconciliationAccount:
            return .reconciliationAccount
        case .workspace:
            return .workspace
        case .date, .merchantText:
            return nil
        }
    }

    private func clampedLimit(_ limit: Int?, operation: MarinaSemanticOperation) -> Int? {
        guard operation == .list else { return limit.map { min(max($0, 1), 20) } }
        let limit = limit ?? 20
        return min(max(limit, 1), 20)
    }

    private func requiresDateField(
        for request: MarinaSemanticRequest,
        surface: MarinaUniversalEntitySurface,
        descriptor: MarinaUniversalSurfaceDescriptor,
        planningContext: MarinaUniversalPlanningContext?
    ) -> Bool {
        if projectionUsesDateRange(request.projection) == false {
            return false
        }
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
            return true
        }
    }

    private func projectionUsesDateRange(_ projection: MarinaSemanticProjection) -> Bool {
        switch projection {
        case .linkedCards, .linkedPresets, .linkedBudgets:
            return false
        case .records, .summary, .income, .expenses, .activity, .occurrences:
            return true
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

    private func validatedResult(
        for plan: MarinaUniversalQueryPlan
    ) -> MarinaSemanticUniversalPlanBridgeResult {
        let validator = MarinaUniversalCatalogValidator(
            catalog: catalog,
            formulaRegistry: formulaRegistry
        )
        switch validator.validate(validationRequest(for: plan)) {
        case .supported:
            return .plan(plan)
        case let .unsupported(reason):
            return .unsupported(reason)
        }
    }

    private func validationRequest(
        for plan: MarinaUniversalQueryPlan
    ) -> MarinaUniversalValidationRequest {
        MarinaUniversalValidationRequest(
            surface: plan.surface,
            projection: plan.projection,
            operation: plan.operation,
            measure: plan.measure,
            searchFields: plan.search?.fields ?? [],
            filterFields: Set(plan.filters.compactMap { filter in
                guard case let .field(field) = filter.target else { return nil }
                return field
            }),
            groupFields: fieldTargets(in: plan.groupBy),
            sortFields: Set(plan.sorts.compactMap { sort in
                guard case let .field(field) = sort.target else { return nil }
                return field
            }),
            filterRelationships: Set(plan.filters.compactMap { filter in
                guard case let .relationship(relationship) = filter.target else { return nil }
                return relationship
            }),
            groupRelationships: relationshipTargets(in: plan.groupBy),
            sortRelationships: Set(plan.sorts.compactMap { sort in
                guard case let .relationship(relationship) = sort.target else { return nil }
                return relationship
            }),
            requiresDateField: plan.requiresDateField,
            requiresAmountField: plan.requiresAmountField
        )
    }

    private func fieldTargets(
        in groupBy: MarinaRowGroupTarget?
    ) -> Set<MarinaFieldKey> {
        guard case let .field(field) = groupBy else { return [] }
        return [field]
    }

    private func relationshipTargets(
        in groupBy: MarinaRowGroupTarget?
    ) -> Set<MarinaRelationshipKey> {
        guard case let .relationship(relationship) = groupBy else { return [] }
        return [relationship]
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
