import Foundation

struct MarinaUniversalValidationRequest: Equatable, Sendable {
    let entity: MarinaSemanticEntity
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
        self.entity = entity
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

    init(catalog: MarinaEntityCatalog = MarinaEntityCatalog()) {
        self.catalog = catalog
    }

    func validate(_ request: MarinaUniversalValidationRequest) -> MarinaCapabilityResult {
        guard let descriptor = catalog.descriptor(for: request.entity) else {
            return .unsupported(.missingEntityDescriptor)
        }

        guard descriptor.isInternalOnly == false else {
            return .unsupported(.internalOnly)
        }

        guard descriptor.supportedOperations.contains(request.operation) else {
            return .unsupported(.operationNotSupported)
        }

        if let measure = request.measure,
           supports(entity: request.entity, measure: measure) == false {
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

    private func supports(entity: MarinaSemanticEntity, measure: MarinaSemanticMeasure) -> Bool {
        catalog.supports(entity: entity, measure: measure) == .supported
    }

    private func field(_ key: MarinaFieldKey, in descriptor: MarinaEntityDescriptor) -> MarinaFieldDescriptor? {
        descriptor.fields.first { $0.key == key }
    }

    private func relationship(_ key: MarinaRelationshipKey, in descriptor: MarinaEntityDescriptor) -> MarinaRelationshipDescriptor? {
        descriptor.relationships.first { $0.key == key }
    }

    private func amountRequirementIsSatisfied(
        for request: MarinaUniversalValidationRequest,
        descriptor: MarinaEntityDescriptor
    ) -> Bool {
        if descriptor.defaultAmountField != nil {
            return true
        }

        guard let measure = request.measure,
              let measureDescriptor = catalog.measureDescriptor(for: measure),
              supports(entity: request.entity, measure: measure) else {
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
