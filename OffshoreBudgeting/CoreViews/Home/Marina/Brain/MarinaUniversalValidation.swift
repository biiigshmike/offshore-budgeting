import Foundation

struct MarinaUniversalValidationRequest: Equatable, Sendable {
    let surface: MarinaUniversalEntitySurface
    let projection: MarinaSemanticProjection
    let operation: MarinaSemanticOperation
    let measure: MarinaSemanticMeasure?
    let searchFields: Set<MarinaFieldKey>
    let filterFields: Set<MarinaFieldKey>
    let groupFields: Set<MarinaFieldKey>
    let sortFields: Set<MarinaFieldKey>
    let filterRelationships: Set<MarinaRelationshipKey>
    let groupRelationships: Set<MarinaRelationshipKey>
    let sortRelationships: Set<MarinaRelationshipKey>
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
        searchFields: Set<MarinaFieldKey> = [],
        filterFields: Set<MarinaFieldKey> = [],
        groupFields: Set<MarinaFieldKey> = [],
        sortFields: Set<MarinaFieldKey> = [],
        filterRelationships: Set<MarinaRelationshipKey> = [],
        groupRelationships: Set<MarinaRelationshipKey> = [],
        sortRelationships: Set<MarinaRelationshipKey> = [],
        requiresDateField: Bool = false,
        requiresAmountField: Bool = false
    ) {
        self.init(
            surface: .semantic(entity),
            projection: projection,
            operation: operation,
            measure: measure,
            searchFields: searchFields,
            filterFields: filterFields,
            groupFields: groupFields,
            sortFields: sortFields,
            filterRelationships: filterRelationships,
            groupRelationships: groupRelationships,
            sortRelationships: sortRelationships,
            requiresDateField: requiresDateField,
            requiresAmountField: requiresAmountField
        )
    }

    init(
        surface: MarinaUniversalEntitySurface,
        projection: MarinaSemanticProjection = .records,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        searchFields: Set<MarinaFieldKey> = [],
        filterFields: Set<MarinaFieldKey> = [],
        groupFields: Set<MarinaFieldKey> = [],
        sortFields: Set<MarinaFieldKey> = [],
        filterRelationships: Set<MarinaRelationshipKey> = [],
        groupRelationships: Set<MarinaRelationshipKey> = [],
        sortRelationships: Set<MarinaRelationshipKey> = [],
        requiresDateField: Bool = false,
        requiresAmountField: Bool = false
    ) {
        self.surface = surface
        self.projection = projection
        self.operation = operation
        self.measure = measure
        self.searchFields = searchFields
        self.filterFields = filterFields
        self.groupFields = groupFields
        self.sortFields = sortFields
        self.filterRelationships = filterRelationships
        self.groupRelationships = groupRelationships
        self.sortRelationships = sortRelationships
        self.requiresDateField = requiresDateField
        self.requiresAmountField = requiresAmountField
    }
}

struct MarinaUniversalCatalogValidator: Sendable {
    let catalog: MarinaEntityCatalog
    let formulaRegistry: MarinaFormulaRegistry?

    init(
        catalog: MarinaEntityCatalog = MarinaEntityCatalog(),
        formulaRegistry: MarinaFormulaRegistry? = nil
    ) {
        self.catalog = catalog
        self.formulaRegistry = formulaRegistry
    }

    func validate(_ request: MarinaUniversalValidationRequest) -> MarinaCapabilityResult {
        guard let descriptor = catalog.executionDescriptor(
            for: request.surface,
            projection: request.projection
        ) else {
            return .unsupported(.missingEntityDescriptor)
        }

        guard let semanticEntity = request.surface.semanticEntity,
              catalog.supports(entity: semanticEntity, projection: request.projection) == .supported else {
            return .unsupported(.unsupportedCombination)
        }

        guard descriptor.isInternalOnly == false || request.projection == .activity else {
            return .unsupported(.internalOnly)
        }

        guard descriptor.supportedOperations.contains(request.operation)
            || rowBackedComparisonSupports(request, descriptor: descriptor)
            || formulaSupports(request) else {
            return .unsupported(.operationNotSupported)
        }

        if let measure = request.measure,
           supports(
            surface: request.surface,
            operation: request.operation,
            measure: measure,
            descriptor: descriptor
           ) == false {
            return .unsupported(.measureNotAvailable)
        }

        guard request.searchFields.allSatisfy({ field($0, in: descriptor)?.isSearchable == true }) else {
            return .unsupported(.fieldNotSearchable)
        }

        guard request.filterFields.allSatisfy({ field($0, in: descriptor)?.isFilterable == true }),
              request.filterRelationships.allSatisfy({ relationship($0, in: descriptor)?.isFilterable == true }) else {
            return .unsupported(.fieldNotFilterable)
        }

        guard request.groupFields.allSatisfy({ field($0, in: descriptor)?.isGroupable == true }),
              request.groupRelationships.allSatisfy({ relationship($0, in: descriptor)?.isGroupable == true }) else {
            return .unsupported(.fieldNotGroupable)
        }

        guard request.sortFields.allSatisfy({ field($0, in: descriptor)?.isSortable == true }),
              request.sortRelationships.allSatisfy({ relationship($0, in: descriptor)?.isSortable == true }) else {
            return .unsupported(.fieldNotSortable)
        }

        if request.requiresDateField, descriptor.defaultDateField == nil {
            return .unsupported(.missingDateField)
        }

        if request.requiresAmountField, amountRequirementIsSatisfied(for: request, descriptor: descriptor) == false {
            return .unsupported(.missingAmountField)
        }

        return .supported
    }

    private func supports(
        surface: MarinaUniversalEntitySurface,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> Bool {
        if formulaRegistry?.supports(
            measure: measure,
            surface: surface,
            operation: operation
        ) == true {
            return true
        }

        guard descriptor.supportedMeasures.contains(measure),
              let field = rowBackedField(for: measure, surface: surface) else {
            return false
        }
        return descriptor.fields.contains { $0.key == field }
    }

    private func rowBackedField(
        for measure: MarinaSemanticMeasure,
        surface: MarinaUniversalEntitySurface
    ) -> MarinaFieldKey? {
        switch surface {
        case let .semantic(entity):
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
        case .unifiedExpenses:
            switch measure {
            case .budgetImpact, .unifiedExpenseTotal:
                return .budgetImpact
            case .projectedBudgetImpact:
                return .projectedBudgetImpact
            default:
                return nil
            }
        case .savingsLedgerEntries, .reconciliationLedgerEntries:
            return measure == .amount ? .amount : nil
        }
    }

    private func formulaSupports(_ request: MarinaUniversalValidationRequest) -> Bool {
        guard let measure = request.measure else {
            return false
        }
        return formulaRegistry?.supports(
            measure: measure,
            surface: request.surface,
            operation: request.operation
        ) == true
    }

    private func rowBackedComparisonSupports(
        _ request: MarinaUniversalValidationRequest,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> Bool {
        guard request.operation == .compare,
              let measure = request.measure,
              descriptor.supportedMeasures.contains(measure),
              let measureDescriptor = catalog.measureDescriptor(for: measure) else {
            return false
        }

        if let defaultAmountField = descriptor.defaultAmountField,
           descriptor.fields.contains(where: {
               $0.key == defaultAmountField && $0.isAggregatable
           }) {
            return true
        }

        return measureDescriptor.requiredFields.contains { fieldKey in
            descriptor.fields.contains { $0.key == fieldKey && $0.isAggregatable }
        }
    }

    private func field(_ key: MarinaFieldKey, in descriptor: MarinaUniversalSurfaceDescriptor) -> MarinaFieldDescriptor? {
        descriptor.fields.first { $0.key == key }
    }

    private func relationship(_ key: MarinaRelationshipKey, in descriptor: MarinaUniversalSurfaceDescriptor) -> MarinaRelationshipDescriptor? {
        descriptor.relationships.first { $0.key == key }
    }

    private func amountRequirementIsSatisfied(
        for request: MarinaUniversalValidationRequest,
        descriptor: MarinaUniversalSurfaceDescriptor
    ) -> Bool {
        if formulaSupports(request) {
            return true
        }

        if descriptor.defaultAmountField != nil {
            return true
        }

        guard let measure = request.measure,
              let measureDescriptor = catalog.measureDescriptor(for: measure),
              supports(
                surface: request.surface,
                operation: request.operation,
                measure: measure,
                descriptor: descriptor
              ) else {
            return false
        }

        if Self.amountLikeMeasures.contains(measure) {
            return true
        }

        return measureDescriptor.requiredFields.contains { fieldKey in
            field(fieldKey, in: descriptor)?.valueType == .money
        }
    }

    private static let amountLikeMeasures: Set<MarinaSemanticMeasure> = [
        .amount,
        .plannedAmount,
        .actualAmount,
        .effectiveAmount,
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
        .savingsTotal,
        .maximumSavings,
        .projectedSavings,
        .actualSavings,
        .incomeAmount,
        .reconciliationBalance,
        .categoryAvailability,
        .remainingRoom,
        .burnRate,
        .projectedSpend,
        .safeDailySpend,
        .paceDifference,
        .coverageRatio,
        .recurringBurden,
        .concentration
    ]
}
