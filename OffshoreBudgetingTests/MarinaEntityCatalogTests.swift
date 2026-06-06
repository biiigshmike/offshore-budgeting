import Testing
@testable import Offshore

struct MarinaEntityCatalogTests {
    @Test func everySemanticEntityHasADescriptor() {
        let catalog = MarinaEntityCatalog()

        for entity in MarinaSemanticEntity.allCases {
            #expect(catalog.descriptor(for: entity) != nil, "Missing descriptor for \(entity.rawValue)")
        }
    }

    @Test func descriptorsHaveNamesOperationsAndValidDefaultFields() throws {
        let catalog = MarinaEntityCatalog()

        for entity in MarinaSemanticEntity.allCases {
            let descriptor = try #require(catalog.descriptor(for: entity))
            let fieldKeys = Set(descriptor.fields.map(\.key))

            #expect(descriptor.displayName.isEmpty == false, "Missing display name for \(entity.rawValue)")
            #expect(descriptor.supportedOperations.isEmpty == false, "Missing operations for \(entity.rawValue)")

            if let defaultDateField = descriptor.defaultDateField {
                #expect(fieldKeys.contains(defaultDateField), "Missing default date field for \(entity.rawValue)")
            }

            if let defaultAmountField = descriptor.defaultAmountField {
                #expect(fieldKeys.contains(defaultAmountField), "Missing default amount field for \(entity.rawValue)")
            }

            for searchField in descriptor.defaultSearchFields {
                let field = descriptor.fields.first { $0.key == searchField }
                #expect(field != nil, "Missing search field \(searchField.rawValue) for \(entity.rawValue)")
                #expect(field?.isSearchable == true, "Default search field \(searchField.rawValue) is not searchable for \(entity.rawValue)")
            }
        }
    }

    @Test func everyClaimedMeasureHasADefaultMeasureDescriptor() {
        let defaultMeasures = MarinaEntityCatalog.defaultMeasures

        for descriptor in MarinaEntityCatalog.defaultEntities.values {
            for measure in descriptor.supportedMeasures {
                #expect(defaultMeasures[measure] != nil, "Missing measure descriptor for \(measure.rawValue) claimed by \(descriptor.entity.rawValue)")
            }
        }
    }

    @Test func variableExpenseDeclaresExpectedPhaseOneCapabilities() throws {
        let catalog = MarinaEntityCatalog()
        let descriptor = try #require(catalog.descriptor(for: .variableExpense))

        #expect(descriptor.supportedOperations.isSuperset(of: [.list, .count, .sum, .average, .group]))
        #expect(catalog.supports(entity: .variableExpense, measure: .budgetImpact) == .supported)
    }

    @Test func plannedExpenseDeclaresExpectedPhaseOneCapabilities() throws {
        let catalog = MarinaEntityCatalog()
        let descriptor = try #require(catalog.descriptor(for: .plannedExpense))

        #expect(descriptor.supportedOperations.isSuperset(of: [.list, .count, .sum, .average, .group]))
        #expect(catalog.supports(entity: .plannedExpense, measure: .budgetImpact) == .supported)
    }

    @Test func incomeDeclaresExpectedPhaseOneCapabilities() throws {
        let catalog = MarinaEntityCatalog()
        let descriptor = try #require(catalog.descriptor(for: .income))

        #expect(descriptor.supportedOperations.isSuperset(of: [.list, .count, .sum, .average]))
        #expect(catalog.supports(entity: .income, measure: .incomeAmount) == .supported)
    }

    @Test func workspaceDoesNotSupportSum() {
        let catalog = MarinaEntityCatalog()

        #expect(catalog.supports(entity: .workspace, operation: .sum) == .unsupported(.operationNotSupported))
    }

    @Test func presetSupportsPlannedAmountButNotSavingsOrReconciliationMeasures() {
        let catalog = MarinaEntityCatalog()

        #expect(catalog.supports(entity: .preset, measure: .plannedAmount) == .supported)
        #expect(catalog.supports(entity: .preset, measure: .savingsTotal) == .unsupported(.measureNotAvailable))
        #expect(catalog.supports(entity: .preset, measure: .reconciliationBalance) == .unsupported(.measureNotAvailable))
    }

    @Test func catalogDoesNotBroadenCurrentOperationRegistry() {
        let catalog = MarinaEntityCatalog()
        let registry = MarinaQueryCapabilityRegistry()

        for entity in MarinaSemanticEntity.allCases {
            for operation in MarinaSemanticOperation.allCases {
                guard catalog.supports(entity: entity, operation: operation) == .supported else {
                    continue
                }
                #expect(registry.supports(entity: entity, operation: operation), "Catalog broadened \(entity.rawValue).\(operation.rawValue)")
            }
        }
    }
}
