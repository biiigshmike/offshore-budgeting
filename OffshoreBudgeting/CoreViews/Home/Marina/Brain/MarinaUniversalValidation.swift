import Foundation

struct MarinaUniversalValidationRequest: Equatable, Sendable {
    let surface: MarinaUniversalEntitySurface
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
        guard let descriptor = catalog.descriptor(for: request.surface) else {
            return .unsupported(.missingEntityDescriptor)
        }

        guard descriptor.isInternalOnly == false else {
            return .unsupported(.internalOnly)
        }

        guard descriptor.supportedOperations.contains(request.operation)
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
        switch surface {
        case let .semantic(entity):
            return catalog.supports(entity: entity, measure: measure) == .supported
                || formulaRegistry?.supports(measure: measure, surface: surface, operation: operation) == true
        case .unifiedExpenses, .savingsLedgerEntries, .reconciliationLedgerEntries:
            return descriptor.supportedMeasures.contains(measure)
                || formulaRegistry?.supports(measure: measure, surface: surface, operation: operation) == true
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
        .savingsTotal,
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
