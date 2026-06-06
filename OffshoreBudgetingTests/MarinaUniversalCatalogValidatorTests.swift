import Testing
@testable import Offshore

struct MarinaUniversalCatalogValidatorTests {
    private let validator = MarinaUniversalCatalogValidator()

    @Test func variableExpenseSupportsMerchantSearch() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            searchFields: [.merchantText],
            requiresDateField: true,
            requiresAmountField: true
        )

        #expect(validator.validate(request) == .supported)
    }

    @Test func variableExpenseSupportsCardCategoryAndDateFiltering() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .list,
            filterFields: [.transactionDate],
            filterRelationships: [.card, .category],
            requiresDateField: true
        )

        #expect(validator.validate(request) == .supported)
    }

    @Test func variableExpenseSupportsCardAndCategoryGrouping() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            groupRelationships: [.card, .category],
            requiresAmountField: true
        )

        #expect(validator.validate(request) == .supported)
    }

    @Test func variableExpenseSupportsAmountAndDateSorting() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .list,
            sortFields: [.amount, .transactionDate]
        )

        #expect(validator.validate(request) == .supported)
    }

    @Test func plannedExpenseSupportsTitleAndMerchantSearch() {
        let request = MarinaUniversalValidationRequest(
            entity: .plannedExpense,
            operation: .list,
            searchFields: [.title, .merchantText]
        )

        #expect(validator.validate(request) == .supported)
    }

    @Test func incomeSupportsSourceFilteringAndGrouping() {
        let filterRequest = MarinaUniversalValidationRequest(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            filterFields: [.source],
            filterRelationships: [.incomeSource],
            requiresAmountField: true
        )
        let groupRequest = MarinaUniversalValidationRequest(
            entity: .income,
            operation: .share,
            measure: .incomeAmount,
            groupFields: [.source],
            groupRelationships: [.incomeSource],
            requiresAmountField: true
        )

        #expect(validator.validate(filterRequest) == .supported)
        #expect(validator.validate(groupRequest) == .supported)
    }

    @Test func incomeSupportsPlannedStateFilteringGroupingAndSorting() {
        let request = MarinaUniversalValidationRequest(
            entity: .income,
            operation: .list,
            filterFields: [.isPlanned],
            groupFields: [.isPlanned],
            sortFields: [.isPlanned]
        )

        #expect(validator.validate(request) == .supported)
    }

    @Test func workspaceRejectsSumBeforeAmountRequirement() {
        let request = MarinaUniversalValidationRequest(
            entity: .workspace,
            operation: .sum,
            requiresAmountField: true
        )

        #expect(validator.validate(request) == .unsupported(.operationNotSupported))
    }

    @Test func savingsAccountRejectsMerchantTextSearch() {
        let request = MarinaUniversalValidationRequest(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            searchFields: [.merchantText]
        )

        #expect(validator.validate(request) == .unsupported(.fieldNotSearchable))
    }

    @Test func presetRejectsSavingsAndReconciliationMeasures() {
        let savingsRequest = MarinaUniversalValidationRequest(
            entity: .preset,
            operation: .sum,
            measure: .savingsTotal
        )
        let reconciliationRequest = MarinaUniversalValidationRequest(
            entity: .preset,
            operation: .sum,
            measure: .reconciliationBalance
        )

        #expect(validator.validate(savingsRequest) == .unsupported(.measureNotAvailable))
        #expect(validator.validate(reconciliationRequest) == .unsupported(.measureNotAvailable))
    }

    @Test func unsupportedMeasureReturnsMeasureNotAvailable() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .savingsTotal
        )

        #expect(validator.validate(request) == .unsupported(.measureNotAvailable))
    }

    @Test func nonSearchableFieldReturnsFieldNotSearchable() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .list,
            searchFields: [.amount]
        )

        #expect(validator.validate(request) == .unsupported(.fieldNotSearchable))
    }

    @Test func nonFilterableFieldReturnsFieldNotFilterable() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .list,
            filterFields: [.id]
        )

        #expect(validator.validate(request) == .unsupported(.fieldNotFilterable))
    }

    @Test func nonGroupableFieldReturnsFieldNotGroupable() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            groupFields: [.amount]
        )

        #expect(validator.validate(request) == .unsupported(.fieldNotGroupable))
    }

    @Test func nonSortableFieldReturnsFieldNotSortable() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .list,
            sortFields: [.id]
        )

        #expect(validator.validate(request) == .unsupported(.fieldNotSortable))
    }

    @Test func missingDateRequirementReturnsMissingDateField() {
        let request = MarinaUniversalValidationRequest(
            entity: .category,
            operation: .sum,
            measure: .budgetImpact,
            requiresDateField: true
        )

        #expect(validator.validate(request) == .unsupported(.missingDateField))
    }

    @Test func missingAmountRequirementDoesNotTreatNameAsAmountLike() {
        let request = MarinaUniversalValidationRequest(
            entity: .workspace,
            operation: .list,
            measure: .name,
            requiresAmountField: true
        )

        #expect(validator.validate(request) == .unsupported(.missingAmountField))
    }

    @Test func shadowAppleMerchantSpendShapeValidates() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            searchFields: [.merchantText],
            requiresDateField: true,
            requiresAmountField: true
        )

        #expect(validator.validate(request) == .supported)
    }

    @Test func shadowSpendingByCardShapeValidates() {
        let request = MarinaUniversalValidationRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            groupRelationships: [.card],
            requiresAmountField: true
        )

        #expect(validator.validate(request) == .supported)
    }

    @Test func shadowMonthlyIncomeShapeValidates() {
        let request = MarinaUniversalValidationRequest(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            filterFields: [.date, .source],
            requiresDateField: true,
            requiresAmountField: true
        )

        #expect(validator.validate(request) == .supported)
    }
}
