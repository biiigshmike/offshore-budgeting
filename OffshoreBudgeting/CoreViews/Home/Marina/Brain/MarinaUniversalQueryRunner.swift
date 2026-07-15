import Foundation

struct MarinaUniversalQueryRunner {
    let catalog: MarinaEntityCatalog
    let validator: MarinaUniversalCatalogValidator
    let adapterRegistry: MarinaEntityAdapterRegistry
    let scopedRowProvider: MarinaScopedRowProvider
    let rowEngine: MarinaRowOperationEngine
    let formulaRegistry: MarinaFormulaRegistry?

    init(
        catalog: MarinaEntityCatalog = MarinaEntityCatalog(),
        adapterRegistry: MarinaEntityAdapterRegistry = MarinaEntityAdapterRegistry(),
        rowEngine: MarinaRowOperationEngine = MarinaRowOperationEngine(),
        formulaRegistry: MarinaFormulaRegistry? = nil
    ) {
        self.catalog = catalog
        self.validator = MarinaUniversalCatalogValidator(catalog: catalog)
        self.adapterRegistry = adapterRegistry
        self.scopedRowProvider = MarinaScopedRowProvider(adapterRegistry: adapterRegistry)
        self.rowEngine = rowEngine
        self.formulaRegistry = formulaRegistry
    }

    func run(
        plan: MarinaUniversalQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaUniversalQueryResult {
        let validationRequest = makeValidationRequest(for: plan)
        switch validator.validate(validationRequest) {
        case .supported:
            break
        case let .unsupported(reason):
            return .unsupported(reason)
        }

        if plan.measure != nil {
            switch measureExecutionKind(for: plan) {
            case .rowBacked:
                break
            case .formulaBacked, .unsupported:
                return .unsupported(.measureNotAvailable)
            }
        }

        guard supportedRunnerOperations.contains(plan.operation) else {
            return .unsupported(.unsupportedCombination)
        }

        guard let descriptor = catalog.executionDescriptor(
            for: plan.surface,
            projection: plan.projection
        ) else {
            return .unsupported(.missingEntityDescriptor)
        }

        if let reason = invalidResolvedReferenceReason(for: plan, snapshot: snapshot) {
            return .unsupported(reason)
        }

        guard var rows = scopedRowProvider.rows(for: plan, from: snapshot) else {
            return .unsupported(.unsupportedCombination)
        }

        if let search = plan.search {
            rows = rowEngine.search(rows, clause: search, descriptor: descriptor)
        }

        if plan.operation == .compare {
            return comparisonResult(
                plan: plan,
                descriptor: descriptor,
                unfilteredRows: rows,
                snapshot: snapshot
            )
        }

        rows = rowEngine.filter(rows, filters: plan.filters)
        rows = rowEngine.sort(rows, sorts: effectiveSorts(for: plan, descriptor: descriptor))

        switch plan.operation {
        case .list:
            let pageRows = rowEngine.page(rows, offset: plan.offset, limit: plan.limit)
            let nextOffset = plan.offset + pageRows.count
            return .rowsPage(
                MarinaUniversalRowsPage(
                    rows: pageRows,
                    totalRowCount: rows.count,
                    fullTotalAmount: fullTotalAmount(for: rows, plan: plan),
                    offset: plan.offset,
                    displayLimit: plan.limit,
                    hasMore: nextOffset < rows.count,
                    nextOffset: nextOffset < rows.count ? nextOffset : nil
                )
            )
        case .count:
            return .metric(
                MarinaUniversalMetricResult(
                    value: .integer(rowEngine.count(rows)),
                    evidenceRows: rows
                )
            )
        case .sum:
            return sumResult(plan: plan, descriptor: descriptor, rows: rows)
        case .average:
            return averageResult(plan: plan, descriptor: descriptor, rows: rows)
        case .group:
            return groupResult(plan: plan, descriptor: descriptor, rows: rows)
        case .last, .next:
            return .rows(rowEngine.limit(rows, to: 1))
        case .compare:
            return .unsupported(.unsupportedCombination)
        case .share, .forecast, .whatIf:
            return .unsupported(.unsupportedCombination)
        }
    }

    @MainActor
    func runFormulaAware(
        plan: MarinaUniversalQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaUniversalQueryResult {
        let validationRequest = makeValidationRequest(for: plan)
        let formulaValidator = MarinaUniversalCatalogValidator(
            catalog: catalog,
            formulaRegistry: formulaRegistry
        )
        switch formulaValidator.validate(validationRequest) {
        case .supported:
            break
        case let .unsupported(reason):
            return .unsupported(reason)
        }

        if let reason = invalidResolvedReferenceReason(for: plan, snapshot: snapshot) {
            return .unsupported(reason)
        }

        if case .formulaBacked = measureExecutionKind(for: plan),
           let formulaRegistry,
           let measure = plan.measure {
            return universalResult(
                from: formulaRegistry.evaluate(
                    request: MarinaFormulaRequest(
                        surface: plan.surface,
                        projection: plan.projection,
                        operation: plan.operation,
                        measure: measure,
                        dateRange: plan.dateRange,
                        comparisonDateRange: plan.comparisonDateRange,
                        filters: plan.filters,
                        search: plan.search,
                        groupBy: plan.groupBy,
                        offset: plan.offset,
                        limit: plan.limit,
                        whatIfAmount: plan.whatIfAmount,
                        categoryAvailabilityFilter: plan.categoryAvailabilityFilter,
                        dateRangeSource: plan.dateRangeSource,
                        resolvedTarget: plan.resolvedTarget,
                        resolvedComparisonTarget: plan.resolvedComparisonTarget,
                        resolvedScope: plan.resolvedScope
                    ),
                    snapshot: snapshot
                ),
                plan: plan
            )
        }

        return run(plan: plan, snapshot: snapshot)
    }

    private var supportedRunnerOperations: Set<MarinaSemanticOperation> {
        [.list, .count, .sum, .average, .compare, .group, .last, .next]
    }

    private func measureExecutionKind(for plan: MarinaUniversalQueryPlan) -> MarinaMeasureExecutionKind {
        guard let measure = plan.measure else {
            return .unsupported(.measureNotAvailable)
        }

        if formulaRegistry?.supports(
            measure: measure,
            surface: plan.surface,
            operation: plan.operation
        ) == true {
            return .formulaBacked
        }

        guard let field = field(for: measure, surface: plan.surface) else {
            return .unsupported(.measureNotAvailable)
        }

        return .rowBacked(field: field)
    }

    private func universalResult(
        from formulaResult: MarinaFormulaResult,
        plan: MarinaUniversalQueryPlan
    ) -> MarinaUniversalQueryResult {
        switch formulaResult {
        case let .metric(metric):
            return .metric(
                MarinaUniversalMetricResult(
                    value: metric.value,
                    evidenceRows: metric.evidenceRows,
                    details: metric.details,
                    presentationRows: metric.presentationRows
                )
            )
        case let .rows(rows):
            let descriptor = catalog.executionDescriptor(
                for: plan.surface,
                projection: plan.projection
            )
            let sortedRows = rowEngine.sort(
                rows,
                sorts: effectiveSorts(for: plan, descriptor: descriptor)
            )
            let pageRows = rowEngine.page(sortedRows, offset: plan.offset, limit: plan.limit)
            let nextOffset = plan.offset + pageRows.count
            return .rowsPage(
                MarinaUniversalRowsPage(
                    rows: pageRows,
                    totalRowCount: sortedRows.count,
                    fullTotalAmount: fullTotalAmount(for: sortedRows, plan: plan),
                    offset: plan.offset,
                    displayLimit: plan.limit,
                    hasMore: nextOffset < sortedRows.count,
                    nextOffset: nextOffset < sortedRows.count ? nextOffset : nil
                )
            )
        case let .groups(groups):
            return .groups(
                groups.map { group in
                    MarinaUniversalGroupResult(
                        group: MarinaGroupedRows(
                            key: group.displayName,
                            displayName: group.displayName,
                            rows: group.evidenceRows
                        ),
                        aggregate: group.value
                    )
                }
            )
        case let .unsupported(reason):
            return .unsupported(reason)
        }
    }

    private func sumResult(
        plan: MarinaUniversalQueryPlan,
        descriptor: MarinaUniversalSurfaceDescriptor,
        rows: [MarinaQueryableRow]
    ) -> MarinaUniversalQueryResult {
        switch resolveNumericField(plan: plan, descriptor: descriptor, rows: rows) {
        case let .success(resolvedField):
            return .metric(
                MarinaUniversalMetricResult(
                    value: metricValue(rowEngine.sum(rows, field: resolvedField.field), kind: resolvedField.kind),
                    evidenceRows: rows
                )
            )
        case let .failure(reason):
            return .unsupported(reason)
        }
    }

    private func averageResult(
        plan: MarinaUniversalQueryPlan,
        descriptor: MarinaUniversalSurfaceDescriptor,
        rows: [MarinaQueryableRow]
    ) -> MarinaUniversalQueryResult {
        switch resolveNumericField(plan: plan, descriptor: descriptor, rows: rows) {
        case let .success(resolvedField):
            let average = rowEngine.average(rows, field: resolvedField.field)
            return .metric(
                MarinaUniversalMetricResult(
                    value: average.map { metricValue($0, kind: resolvedField.kind) } ?? .empty,
                    evidenceRows: rows
                )
            )
        case let .failure(reason):
            return .unsupported(reason)
        }
    }

    private func comparisonResult(
        plan: MarinaUniversalQueryPlan,
        descriptor: MarinaUniversalSurfaceDescriptor,
        unfilteredRows: [MarinaQueryableRow],
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaUniversalQueryResult {
        switch resolveNumericField(plan: plan, descriptor: descriptor, rows: unfilteredRows) {
        case let .failure(reason):
            return .unsupported(reason)
        case let .success(resolvedField):
            if let comparisonTarget = plan.resolvedComparisonTarget {
                return targetComparisonResult(
                    plan: plan,
                    descriptor: descriptor,
                    resolvedField: resolvedField,
                    primaryTarget: plan.resolvedTarget,
                    comparisonTarget: comparisonTarget,
                    unfilteredRows: unfilteredRows,
                    snapshot: snapshot
                )
            }
            return periodComparisonResult(
                plan: plan,
                descriptor: descriptor,
                resolvedField: resolvedField,
                primaryRows: unfilteredRows,
                snapshot: snapshot
            )
        }
    }

    private func targetComparisonResult(
        plan: MarinaUniversalQueryPlan,
        descriptor: MarinaUniversalSurfaceDescriptor,
        resolvedField: ResolvedNumericField,
        primaryTarget: MarinaResolvedEntityReference?,
        comparisonTarget: MarinaResolvedEntityReference,
        unfilteredRows: [MarinaQueryableRow],
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaUniversalQueryResult {
        guard let primaryTarget else {
            return .unsupported(.unresolvedEntity)
        }
        guard primaryTarget.entity == comparisonTarget.entity,
              let primaryID = primaryTarget.id,
              let comparisonID = comparisonTarget.id else {
            return .unsupported(.ambiguousEntity)
        }
        guard primaryID != comparisonID else {
            return .unsupported(.unsupportedCombination)
        }
        guard referenceIsValid(primaryTarget, snapshot: snapshot),
              referenceIsValid(comparisonTarget, snapshot: snapshot) else {
            return .unsupported(.unresolvedEntity)
        }

        let primaryRows: [MarinaQueryableRow]
        let comparisonRows: [MarinaQueryableRow]
        if let relationship = relationshipKey(for: primaryTarget.entity),
           descriptor.relationships.contains(where: { $0.key == relationship && $0.isFilterable }) {
            let commonFilters = plan.filters.filter { filter in
                guard case let .relationship(key) = filter.target else { return true }
                return key != relationship
            }
            let commonRows = rowEngine.filter(unfilteredRows, filters: commonFilters)
            primaryRows = rowEngine.filter(
                commonRows,
                filters: [identityFilter(relationship: relationship, id: primaryID)]
            )
            comparisonRows = rowEngine.filter(
                commonRows,
                filters: [identityFilter(relationship: relationship, id: comparisonID)]
            )
        } else if plan.surface.semanticEntity == primaryTarget.entity {
            let commonFilters = plan.filters.filter { filter in
                guard case .field(.id) = filter.target else { return true }
                return false
            }
            guard let primarySourceRows = scopedRows(
                for: planWithTarget(plan, target: primaryTarget),
                snapshot: snapshot,
                descriptor: descriptor
            ),
            let comparisonSourceRows = scopedRows(
                for: planWithTarget(plan, target: comparisonTarget),
                snapshot: snapshot,
                descriptor: descriptor
            ) else {
                return .unsupported(.unsupportedCombination)
            }
            primaryRows = rowEngine.filter(primarySourceRows, filters: commonFilters)
            comparisonRows = rowEngine.filter(comparisonSourceRows, filters: commonFilters)
        } else {
            return .unsupported(.unsupportedCombination)
        }

        return comparisonMetric(
            primaryTitle: primaryTarget.displayName,
            primaryRows: primaryRows,
            comparisonTitle: comparisonTarget.displayName,
            comparisonRows: comparisonRows,
            resolvedField: resolvedField
        )
    }

    private func periodComparisonResult(
        plan: MarinaUniversalQueryPlan,
        descriptor: MarinaUniversalSurfaceDescriptor,
        resolvedField: ResolvedNumericField,
        primaryRows: [MarinaQueryableRow],
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaUniversalQueryResult {
        guard let primaryRange = plan.dateRange,
              let comparisonRange = plan.comparisonDateRange,
              primaryRange != comparisonRange,
              let dateField = descriptor.defaultDateField else {
            return .unsupported(.unresolvedEntity)
        }

        let commonFilters = plan.filters.filter { filter in
            guard case let .field(field) = filter.target else { return true }
            return field != dateField
        }
        let filteredPrimaryRows = rowEngine.filter(
            primaryRows,
            filters: commonFilters + dateFilters(field: dateField, range: primaryRange)
        )
        let comparisonPlan = planForComparisonRange(plan, range: comparisonRange)
        guard let comparisonSourceRows = scopedRows(
            for: comparisonPlan,
            snapshot: snapshot,
            descriptor: descriptor
        ) else {
            return .unsupported(.unsupportedCombination)
        }
        let filteredComparisonRows = rowEngine.filter(
            comparisonSourceRows,
            filters: commonFilters + dateFilters(field: dateField, range: comparisonRange)
        )

        return comparisonMetric(
            primaryTitle: "Current period",
            primaryRows: filteredPrimaryRows,
            comparisonTitle: "Comparison period",
            comparisonRows: filteredComparisonRows,
            resolvedField: resolvedField
        )
    }

    private func comparisonMetric(
        primaryTitle: String,
        primaryRows: [MarinaQueryableRow],
        comparisonTitle: String,
        comparisonRows: [MarinaQueryableRow],
        resolvedField: ResolvedNumericField
    ) -> MarinaUniversalQueryResult {
        let primaryValue = rowEngine.sum(primaryRows, field: resolvedField.field)
        let comparisonValue = rowEngine.sum(comparisonRows, field: resolvedField.field)
        let difference = primaryValue - comparisonValue
        let style: MarinaFormulaValueStyle = resolvedField.kind == .money ? .deltaMoney : .automatic
        let valueStyle: MarinaFormulaValueStyle = resolvedField.kind == .money ? .money : .automatic

        return .metric(
            MarinaUniversalMetricResult(
                value: metricValue(difference, kind: resolvedField.kind),
                evidenceRows: primaryRows + comparisonRows,
                details: [
                    MarinaFormulaMetricDetail(
                        .difference,
                        value: metricValue(difference, kind: resolvedField.kind),
                        style: style
                    )
                ],
                presentationRows: [
                    MarinaFormulaPresentationRow(
                        title: primaryTitle,
                        primaryValue: metricValue(primaryValue, kind: resolvedField.kind),
                        primaryStyle: valueStyle,
                        amount: primaryValue
                    ),
                    MarinaFormulaPresentationRow(
                        title: comparisonTitle,
                        primaryValue: metricValue(comparisonValue, kind: resolvedField.kind),
                        primaryStyle: valueStyle,
                        amount: comparisonValue
                    )
                ]
            )
        )
    }

    private func scopedRows(
        for plan: MarinaUniversalQueryPlan,
        snapshot: MarinaWorkspaceSnapshot,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> [MarinaQueryableRow]? {
        guard var rows = scopedRowProvider.rows(for: plan, from: snapshot) else { return nil }
        if let search = plan.search {
            rows = rowEngine.search(rows, clause: search, descriptor: descriptor)
        }
        return rows
    }

    private func referenceIsValid(
        _ reference: MarinaResolvedEntityReference,
        snapshot: MarinaWorkspaceSnapshot
    ) -> Bool {
        guard let id = reference.id else { return false }
        let validationPlan = MarinaUniversalQueryPlan(
            entity: reference.entity,
            operation: .list,
            resolvedScope: .workspace(snapshot.workspace.id)
        )
        guard let rows = scopedRowProvider.rows(for: validationPlan, from: snapshot) else {
            return false
        }
        return rows.contains { $0.id == id }
    }

    private func invalidResolvedReferenceReason(
        for plan: MarinaUniversalQueryPlan,
        snapshot: MarinaWorkspaceSnapshot
    ) -> MarinaCapabilityFailureReason? {
        if let scope = plan.resolvedScope {
            switch scope {
            case let .workspace(workspaceID):
                guard workspaceID == snapshot.workspace.id else {
                    return .unresolvedEntity
                }
            case let .budget(budgetID):
                guard snapshot.budgets.contains(where: {
                    $0.id == budgetID && $0.workspace?.id == snapshot.workspace.id
                }) else {
                    return .unresolvedEntity
                }
            }
        }

        for reference in [plan.resolvedTarget, plan.resolvedComparisonTarget].compactMap({ $0 }) {
            guard reference.id != nil else {
                // Text-only merchant references are intentionally not stable-ID references.
                continue
            }
            guard referenceIsValid(reference, snapshot: snapshot) else {
                return .unresolvedEntity
            }
        }

        for filter in plan.filters {
            guard filter.operation == .equals,
                  case let .relationship(relationship) = filter.target,
                  let entity = entity(for: relationship),
                  case let .text(rawID) = filter.value,
                  let id = UUID(uuidString: rawID) else {
                continue
            }
            let reference = MarinaResolvedEntityReference(
                entity: entity,
                id: id,
                displayName: "",
                provenance: .explicitIdentifier
            )
            guard referenceIsValid(reference, snapshot: snapshot) else {
                return .unresolvedEntity
            }
        }
        return nil
    }

    private func entity(
        for relationship: MarinaRelationshipKey
    ) -> MarinaSemanticEntity? {
        switch relationship {
        case .workspace:
            return .workspace
        case .budget:
            return .budget
        case .card:
            return .card
        case .category:
            return .category
        case .preset:
            return .preset
        case .incomeSeries:
            return .incomeSeries
        case .savingsAccount:
            return .savingsAccount
        case .reconciliationAccount, .allocationAccount:
            return .reconciliationAccount
        case .plannedExpense:
            return .plannedExpense
        case .variableExpense:
            return .variableExpense
        case .incomeSource:
            return nil
        }
    }

    private func relationshipKey(
        for entity: MarinaSemanticEntity
    ) -> MarinaRelationshipKey? {
        switch entity {
        case .workspace:
            return .workspace
        case .budget:
            return .budget
        case .card:
            return .card
        case .plannedExpense:
            return .plannedExpense
        case .variableExpense:
            return .variableExpense
        case .reconciliationAccount:
            return .reconciliationAccount
        case .savingsAccount:
            return .savingsAccount
        case .incomeSeries:
            return .incomeSeries
        case .category:
            return .category
        case .preset:
            return .preset
        case .income:
            return nil
        }
    }

    private func identityFilter(
        relationship: MarinaRelationshipKey,
        id: UUID
    ) -> MarinaRowFilter {
        MarinaRowFilter(
            target: .relationship(relationship),
            operation: .equals,
            value: .text(id.uuidString)
        )
    }

    private func dateFilters(
        field: MarinaFieldKey,
        range: HomeQueryDateRange
    ) -> [MarinaRowFilter] {
        [
            MarinaRowFilter(
                target: .field(field),
                operation: .greaterThanOrEqual,
                value: .date(range.startDate)
            ),
            MarinaRowFilter(
                target: .field(field),
                operation: .lessThanOrEqual,
                value: .date(range.endDate)
            )
        ]
    }

    private func planWithTarget(
        _ plan: MarinaUniversalQueryPlan,
        target: MarinaResolvedEntityReference
    ) -> MarinaUniversalQueryPlan {
        copiedPlan(plan, dateRange: plan.dateRange, dateRangeSource: plan.dateRangeSource, target: target)
    }

    private func planForComparisonRange(
        _ plan: MarinaUniversalQueryPlan,
        range: HomeQueryDateRange
    ) -> MarinaUniversalQueryPlan {
        copiedPlan(plan, dateRange: range, dateRangeSource: .explicit, target: plan.resolvedTarget)
    }

    private func copiedPlan(
        _ plan: MarinaUniversalQueryPlan,
        dateRange: HomeQueryDateRange?,
        dateRangeSource: MarinaSemanticDateRangeSource,
        target: MarinaResolvedEntityReference?
    ) -> MarinaUniversalQueryPlan {
        MarinaUniversalQueryPlan(
            surface: plan.surface,
            projection: plan.projection,
            operation: plan.operation,
            measure: plan.measure,
            search: plan.search,
            filters: plan.filters,
            groupBy: plan.groupBy,
            sorts: plan.sorts,
            offset: plan.offset,
            limit: plan.limit,
            dateRange: dateRange,
            dateRangeSource: dateRangeSource,
            comparisonDateRange: plan.comparisonDateRange,
            resolvedTarget: target,
            resolvedComparisonTarget: plan.resolvedComparisonTarget,
            resolvedScope: plan.resolvedScope,
            whatIfAmount: plan.whatIfAmount,
            categoryAvailabilityFilter: plan.categoryAvailabilityFilter,
            requiresDateField: plan.requiresDateField,
            requiresAmountField: plan.requiresAmountField
        )
    }

    private func fullTotalAmount(
        for rows: [MarinaQueryableRow],
        plan: MarinaUniversalQueryPlan
    ) -> Double? {
        guard plan.operation == .list,
              let descriptor = catalog.executionDescriptor(
                for: plan.surface,
                projection: plan.projection
              ) else {
            return nil
        }

        let totalField = plan.measure.flatMap { field(for: $0, surface: plan.surface) }
            ?? descriptor.defaultAmountField
        guard let totalField,
              rows.contains(where: { numericValueIfPresent($0.fields[totalField]) != nil }) else {
            return nil
        }

        return rows.reduce(0) { partial, row in
            partial + numericValue(row.fields[totalField])
        }
    }

    private func numericValueIfPresent(_ value: MarinaValue?) -> Double? {
        switch value {
        case let .money(number)?, let .number(number)?: number
        case let .integer(number)?: Double(number)
        case .text?, .date?, .boolean?, .colorHex?, .empty?, nil: nil
        }
    }

    private func groupResult(
        plan: MarinaUniversalQueryPlan,
        descriptor: MarinaUniversalSurfaceDescriptor,
        rows: [MarinaQueryableRow]
    ) -> MarinaUniversalQueryResult {
        guard let groupBy = plan.groupBy else {
            return .unsupported(.unsupportedCombination)
        }

        let groups = rowEngine.group(rows, by: groupBy)
        guard plan.measure != nil else {
            return .groups(groups.map { MarinaUniversalGroupResult(group: $0, aggregate: nil) })
        }

        switch resolveNumericField(plan: plan, descriptor: descriptor, rows: rows) {
        case let .success(resolvedField):
            return .groups(
                groups.map { group in
                    MarinaUniversalGroupResult(
                        group: group,
                        aggregate: metricValue(rowEngine.sum(group.rows, field: resolvedField.field), kind: resolvedField.kind)
                    )
                }
            )
        case let .failure(reason):
            return .unsupported(reason)
        }
    }

    private func makeValidationRequest(for plan: MarinaUniversalQueryPlan) -> MarinaUniversalValidationRequest {
        let effectiveSorts = effectiveSorts(
            for: plan,
            descriptor: catalog.executionDescriptor(
                for: plan.surface,
                projection: plan.projection
            )
        )

        return MarinaUniversalValidationRequest(
            surface: plan.surface,
            projection: plan.projection,
            operation: plan.operation,
            measure: plan.measure,
            searchFields: plan.search?.fields ?? [],
            filterFields: fieldTargets(in: plan.filters),
            groupFields: fieldTargets(in: plan.groupBy),
            sortFields: fieldTargets(in: effectiveSorts),
            filterRelationships: relationshipTargets(in: plan.filters),
            groupRelationships: relationshipTargets(in: plan.groupBy),
            sortRelationships: relationshipTargets(in: effectiveSorts),
            requiresDateField: plan.requiresDateField || requiresDefaultDateField(plan),
            requiresAmountField: plan.requiresAmountField || requiresAmountField(plan)
        )
    }

    private func requiresDefaultDateField(_ plan: MarinaUniversalQueryPlan) -> Bool {
        (plan.operation == .last || plan.operation == .next) && plan.sorts.isEmpty
    }

    private func requiresAmountField(_ plan: MarinaUniversalQueryPlan) -> Bool {
        switch plan.operation {
        case .sum, .average:
            return true
        case .group:
            return plan.measure != nil
        case .list, .count, .compare, .last, .next, .share, .forecast, .whatIf:
            return false
        }
    }

    private func effectiveSorts(
        for plan: MarinaUniversalQueryPlan,
        descriptor: MarinaUniversalSurfaceDescriptor?
    ) -> [MarinaRowSort] {
        guard plan.sorts.isEmpty,
              let descriptor,
              let dateField = descriptor.defaultDateField else {
            return plan.sorts
        }

        switch plan.operation {
        case .last:
            return [MarinaRowSort(target: .field(dateField), direction: .descending)]
        case .next:
            return [MarinaRowSort(target: .field(dateField), direction: .ascending)]
        case .list, .count, .sum, .average, .compare, .group, .share, .forecast, .whatIf:
            return plan.sorts
        }
    }

    private func resolveNumericField(
        plan: MarinaUniversalQueryPlan,
        descriptor: MarinaUniversalSurfaceDescriptor,
        rows: [MarinaQueryableRow]
    ) -> ResolvedNumericFieldResult {
        let resolvedField: MarinaFieldKey
        if let measure = plan.measure {
            guard let mappedField = field(for: measure, surface: plan.surface) else {
                return .failure(.measureNotAvailable)
            }
            resolvedField = mappedField
        } else if let defaultAmountField = descriptor.defaultAmountField {
            resolvedField = defaultAmountField
        } else {
            return .failure(.missingAmountField)
        }

        guard fieldIsExposed(resolvedField, in: rows, descriptor: descriptor),
              let kind = numericKind(for: resolvedField, in: rows, descriptor: descriptor) else {
            return .failure(.measureNotAvailable)
        }

        return .success(ResolvedNumericField(field: resolvedField, kind: kind))
    }

    private func field(for measure: MarinaSemanticMeasure, surface: MarinaUniversalEntitySurface) -> MarinaFieldKey? {
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

    private func field(for measure: MarinaSemanticMeasure, entity: MarinaSemanticEntity) -> MarinaFieldKey? {
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
        case .categoryAvailability:
            return .amount
        case .savingsTotal,
             .reconciliationBalance,
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

    private func fieldIsExposed(
        _ field: MarinaFieldKey,
        in rows: [MarinaQueryableRow],
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> Bool {
        if rows.isEmpty {
            return descriptor.fields.contains { $0.key == field }
        }

        return rows.contains { row in
            row.fields[field] != nil
        }
    }

    private func numericKind(
        for field: MarinaFieldKey,
        in rows: [MarinaQueryableRow],
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> MetricNumericKind? {
        for row in rows {
            switch row.fields[field] {
            case .money?:
                return .money
            case .number?, .integer?:
                return .number
            case .text?, .date?, .boolean?, .colorHex?, .empty?, nil:
                continue
            }
        }

        guard let fieldDescriptor = descriptor.fields.first(where: { $0.key == field }) else {
            return nil
        }

        switch fieldDescriptor.valueType {
        case .money:
            return .money
        case .number:
            return .number
        case .text, .date, .boolean, .color, .relationship:
            return nil
        }
    }

    private func metricValue(_ value: Double, kind: MetricNumericKind) -> MarinaValue {
        switch kind {
        case .money:
            return .money(value)
        case .number:
            return .number(value)
        }
    }

    private func fieldTargets(in filters: [MarinaRowFilter]) -> Set<MarinaFieldKey> {
        Set(filters.compactMap { filter in
            if case let .field(field) = filter.target {
                return field
            }
            return nil
        })
    }

    private func relationshipTargets(in filters: [MarinaRowFilter]) -> Set<MarinaRelationshipKey> {
        Set(filters.compactMap { filter in
            if case let .relationship(relationship) = filter.target {
                return relationship
            }
            return nil
        })
    }

    private func fieldTargets(in groupBy: MarinaRowGroupTarget?) -> Set<MarinaFieldKey> {
        guard case let .field(field) = groupBy else {
            return []
        }
        return [field]
    }

    private func relationshipTargets(in groupBy: MarinaRowGroupTarget?) -> Set<MarinaRelationshipKey> {
        guard case let .relationship(relationship) = groupBy else {
            return []
        }
        return [relationship]
    }

    private func fieldTargets(in sorts: [MarinaRowSort]) -> Set<MarinaFieldKey> {
        Set(sorts.compactMap { sort in
            if case let .field(field) = sort.target {
                return field
            }
            return nil
        })
    }

    private func relationshipTargets(in sorts: [MarinaRowSort]) -> Set<MarinaRelationshipKey> {
        Set(sorts.compactMap { sort in
            if case let .relationship(relationship) = sort.target {
                return relationship
            }
            return nil
        })
    }

    private func numericValue(_ value: MarinaValue?) -> Double {
        switch value {
        case let .money(value)?:
            return value
        case let .number(value)?:
            return value
        case let .integer(value)?:
            return Double(value)
        case .text, .date, .boolean, .colorHex, .empty, nil:
            return 0
        }
    }
}

private struct ResolvedNumericField {
    let field: MarinaFieldKey
    let kind: MetricNumericKind
}

private enum ResolvedNumericFieldResult {
    case success(ResolvedNumericField)
    case failure(MarinaCapabilityFailureReason)
}

private enum MetricNumericKind: Equatable {
    case money
    case number
}
