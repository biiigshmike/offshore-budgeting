import Testing
@testable import Offshore

struct MarinaSemanticUniversalPlanBridgeTests {
    private let bridge = MarinaSemanticUniversalPlanBridge()

    @Test func variableExpenseListRequestMapsToUniversalListPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(entity: .variableExpense, operation: .list, shape: .list)))

        #expect(plan.entity == .variableExpense)
        #expect(plan.operation == .list)
        #expect(plan.measure == nil)
        #expect(plan.filters.isEmpty)
        #expect(plan.sorts.isEmpty)
    }

    @Test func variableExpenseCountRequestMapsToUniversalCountPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(entity: .variableExpense, operation: .count)))

        #expect(plan.entity == .variableExpense)
        #expect(plan.operation == .count)
    }

    @Test func variableExpenseSumBudgetImpactRequestMapsToUniversalSumPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact
        )))

        #expect(plan.entity == .variableExpense)
        #expect(plan.operation == .sum)
        #expect(plan.measure == .budgetImpact)
        #expect(plan.requiresAmountField)
    }

    @Test func variableExpenseTextQueryMapsToMerchantSearchFields() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            textQuery: " Apple "
        )))

        #expect(plan.search == MarinaRowSearchClause(fields: [.merchantText, .descriptionText], query: "Apple"))
    }

    @Test func variableExpenseCategoryDimensionAndTargetNameMapToCategoryRelationshipFilter() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            targetName: "Groceries"
        )))

        #expect(plan.filters == [
            MarinaRowFilter(target: .relationship(.category), operation: .equals, value: .text("Groceries"))
        ])
    }

    @Test func variableExpenseCardDimensionAndTargetNameMapToCardRelationshipFilter() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            targetName: "Apple Card"
        )))

        #expect(plan.filters == [
            MarinaRowFilter(target: .relationship(.card), operation: .equals, value: .text("Apple Card"))
        ])
    }

    @Test func variableExpenseGroupByCategoryMapsToGroupRelationshipCategory() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.category],
            shape: .list
        )))

        #expect(plan.groupBy == .relationship(.category))
    }

    @Test func variableExpenseGroupByCardMapsToGroupRelationshipCard() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            shape: .list
        )))

        #expect(plan.groupBy == .relationship(.card))
    }

    @Test func amountDescendingMapsToMoneyLikeRowSort() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            sort: .amountDescending,
            shape: .list
        )))

        #expect(plan.sorts == [
            MarinaRowSort(target: .field(.budgetImpact), direction: .descending)
        ])
    }

    @Test func dateDescendingMapsToDefaultDateSort() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .list,
            sort: .dateDescending,
            shape: .list
        )))

        #expect(plan.sorts == [
            MarinaRowSort(target: .field(.transactionDate), direction: .descending)
        ])
    }

    @Test func plannedExpenseListMapsToUniversalListPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(entity: .plannedExpense, operation: .list, shape: .list)))

        #expect(plan.entity == .plannedExpense)
        #expect(plan.operation == .list)
    }

    @Test func plannedExpenseNextMapsToUniversalNextPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(entity: .plannedExpense, operation: .next)))

        #expect(plan.entity == .plannedExpense)
        #expect(plan.operation == .next)
        #expect(plan.sorts == [
            MarinaRowSort(target: .field(.expenseDate), direction: .ascending)
        ])
    }

    @Test func incomeSumIncomeAmountMapsToUniversalSumPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount
        )))

        #expect(plan.entity == .income)
        #expect(plan.operation == .sum)
        #expect(plan.measure == .incomeAmount)
    }

    @Test func incomeSourceTargetMapsToIncomeSourceFilter() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            targetName: "Paycheck"
        )))

        #expect(plan.filters == [
            MarinaRowFilter(target: .relationship(.incomeSource), operation: .equals, value: .text("Paycheck"))
        ])
    }

    @Test func incomeGroupByIncomeSourceMapsToGroupPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(
            entity: .income,
            operation: .group,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            shape: .list
        )))

        #expect(plan.groupBy == .relationship(.incomeSource))
    }

    @Test func categoryListMapsToUniversalListPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(entity: .category, operation: .list, shape: .list)))

        #expect(plan.entity == .category)
        #expect(plan.operation == .list)
    }

    @Test func cardListMapsToUniversalListPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(entity: .card, operation: .list, shape: .list)))

        #expect(plan.entity == .card)
        #expect(plan.operation == .list)
    }

    @Test func budgetListMapsToUniversalListPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(entity: .budget, operation: .list, shape: .list)))

        #expect(plan.entity == .budget)
        #expect(plan.operation == .list)
    }

    @Test func presetListMapsToUniversalListPlan() throws {
        let plan = try requirePlan(bridge.makePlan(from: request(entity: .preset, operation: .list, shape: .list)))

        #expect(plan.entity == .preset)
        #expect(plan.operation == .list)
    }

    @Test func unsupportedForecastOperationReturnsTypedUnsupported() {
        let result = bridge.makePlan(from: request(entity: .budget, operation: .forecast, measure: .budgetImpact))

        #expect(result == .unsupported(.unsupportedCombination))
    }

    @Test func unsupportedWhatIfOperationReturnsTypedUnsupported() {
        let result = bridge.makePlan(from: request(entity: .budget, operation: .whatIf, measure: .budgetImpact))

        #expect(result == .unsupported(.unsupportedCombination))
    }

    @Test func advancedMeasureSafeDailySpendReturnsMeasureNotAvailable() {
        let result = bridge.makePlan(from: request(entity: .budget, operation: .sum, measure: .safeDailySpend))

        #expect(result == .unsupported(.measureNotAvailable))
    }

    @Test func unresolvedAmbiguousTargetShapeReturnsUnsupportedInsteadOfGuessing() {
        let result = bridge.makePlan(from: request(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            targetName: "Apple"
        ))

        #expect(result == .unsupported(.unsupportedCombination))
    }

    private func request(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dimensions: [MarinaSemanticDimension] = [],
        targetName: String? = nil,
        textQuery: String? = nil,
        resultLimit: Int? = nil,
        sort: MarinaSemanticSort? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        shape: MarinaSemanticAnswerShape = .metric
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dimensions: dimensions,
            targetName: targetName,
            textQuery: textQuery,
            resultLimit: resultLimit,
            sort: sort,
            expenseScope: expenseScope,
            expectedAnswerShape: shape
        )
    }

    private func requirePlan(
        _ result: MarinaSemanticUniversalPlanBridgeResult
    ) throws -> MarinaUniversalQueryPlan {
        guard case let .plan(plan) = result else {
            Issue.record("Expected plan result, got \(result).")
            throw BridgeTestError.expectedPlan
        }
        return plan
    }
}

private enum BridgeTestError: Error {
    case expectedPlan
}
