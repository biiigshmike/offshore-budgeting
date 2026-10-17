import Foundation

struct MarinaUniversalQueryRunner {
    let catalog: MarinaEntityCatalog
    let validator: MarinaUniversalCatalogValidator
    let adapterRegistry: MarinaEntityAdapterRegistry
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

        guard supportedRunnerOperations.contains(plan.operation) else {
            return .unsupported(.unsupportedCombination)
        }

        guard let descriptor = catalog.descriptor(for: plan.surface) else {
            return .unsupported(.missingEntityDescriptor)
        }

        guard var rows = adapterRegistry.rows(for: plan.surface, from: snapshot) else {
            return .unsupported(.unsupportedCombination)
        }

        if let search = plan.search {
            rows = rowEngine.search(rows, clause: search, descriptor: descriptor)
        }
        rows = rowEngine.filter(rows, filters: plan.filters)
        rows = rowEngine.sort(rows, sorts: effectiveSorts(for: plan, descriptor: descriptor))

        switch plan.operation {
        case .list:
            return .rowsPage(
                MarinaUniversalRowsPage(
                    rows: rowEngine.limit(rows, to: plan.limit),
                    totalRowCount: rows.count,
                    fullTotalAmount: fullTotalAmount(for: rows, plan: plan),
                    displayLimit: plan.limit
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
        case .compare, .share, .forecast, .whatIf:
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

        if case .formulaBacked = measureExecutionKind(for: plan),
           let formulaRegistry,
           let measure = plan.measure {
            return universalResult(
                from: formulaRegistry.evaluate(
                    request: MarinaFormulaRequest(
                        surface: plan.surface,
                        operation: plan.operation,
                        measure: measure,
                        dateRange: plan.dateRange,
                        comparisonDateRange: plan.comparisonDateRange,
                        filters: plan.filters,
                        search: plan.search,
                        groupBy: plan.groupBy,
                        limit: plan.limit,
                        whatIfAmount: plan.whatIfAmount,
                        categoryAvailabilityFilter: plan.categoryAvailabilityFilter
                    ),
                    snapshot: snapshot
                )
            )
        }

        return run(plan: plan, snapshot: snapshot)
    }

    private var supportedRunnerOperations: Set<MarinaSemanticOperation> {
        [.list, .count, .sum, .average, .group, .last, .next]
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

    private func universalResult(from formulaResult: MarinaFormulaResult) -> MarinaUniversalQueryResult {
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
            return .rows(rows)
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

    private func fullTotalAmount(
        for rows: [MarinaQueryableRow],
        plan: MarinaUniversalQueryPlan
    ) -> Double? {
        guard isExpenseList(plan),
              let measure = plan.measure,
              let field = field(for: measure, surface: plan.surface) else {
            return nil
        }

        return rows.reduce(0) { partial, row in
            partial + numericValue(row.fields[field])
        }
    }

    private func isExpenseList(_ plan: MarinaUniversalQueryPlan) -> Bool {
        guard plan.operation == .list else { return false }
        switch plan.surface {
        case .unifiedExpenses,
             .semantic(.variableExpense),
             .semantic(.plannedExpense):
            return true
        case .semantic,
             .savingsLedgerEntries,
             .reconciliationLedgerEntries:
            return false
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
            descriptor: catalog.descriptor(for: plan.surface)
        )

        return MarinaUniversalValidationRequest(
            surface: plan.surface,
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

    private func field(for measure: MarinaSemanticMeasure, entity: MarinaSemanticEntity) -> MarinaFieldKey? {
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

private enum MetricNumericKind {
    case money
    case number
}
