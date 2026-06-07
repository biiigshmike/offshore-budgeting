import Foundation
import Testing
@testable import Offshore

struct MarinaUniversalRoutingPolicyTests {
    private let policy = MarinaUniversalRoutingPolicy.internalParityProven

    @Test func defaultPolicyIsDisabled() {
        #expect(MarinaUniversalRoutingPolicy.disabled.isEnabled == false)
        #expect(MarinaUniversalRoutingPolicy.disabled.allowedScenarios.isEmpty)
    }

    @Test func disabledPolicyRejectsAllRequestsEvenWithAllowlist() {
        let disabled = MarinaUniversalRoutingPolicy(
            isEnabled: false,
            allowedScenarios: Set(MarinaUniversalRoutingScenario.allCases)
        )

        #expect(disabled.allows(merchantSpendRequest()) == false)
    }

    @Test func internalParityPolicyIncludesOnlyScenarioLevelAllowlist() {
        #expect(policy.isEnabled)
        #expect(policy.allowedScenarios == Set(MarinaUniversalRoutingScenario.allCases))
    }

    @Test func merchantVariableSpendMapsToMerchantScenario() {
        let request = merchantSpendRequest()

        #expect(policy.scenario(for: request) == .merchantVariableSpend)
        #expect(policy.allows(request))
    }

    @Test func categoryVariableSpendMapsToCategoryScenario() {
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category],
            targetName: "Groceries",
            expenseScope: .variable
        )

        #expect(policy.scenario(for: request) == .categoryVariableSpend)
        #expect(policy.allows(request))
    }

    @Test func cardVariableSpendMapsToCardScenario() {
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.card],
            targetName: "Apple Card",
            expenseScope: .variable
        )

        #expect(policy.scenario(for: request) == .cardVariableSpend)
        #expect(policy.allows(request))
    }

    @Test func plannedExpenseSumMapsToPlannedScenario() {
        let request = semanticRequest(
            entity: .plannedExpense,
            operation: .sum,
            measure: .budgetImpact,
            expenseScope: .planned
        )

        #expect(policy.scenario(for: request) == .plannedExpenseSum)
        #expect(policy.allows(request))
    }

    @Test func latestVariableExpenseMapsToLatestScenario() {
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .last,
            measure: .budgetImpact,
            expenseScope: .variable
        )

        #expect(policy.scenario(for: request) == .latestVariableExpense)
        #expect(policy.allows(request))
    }

    @Test func biggestVariableExpenseRowsMapToBiggestRowsScenario() {
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            resultLimit: 3,
            sort: .amountDescending,
            expenseScope: .variable,
            shape: .list
        )

        #expect(policy.scenario(for: request) == .biggestVariableExpenseRows)
        #expect(policy.allows(request))
    }

    @Test func nextPlannedExpenseMapsToNextPlannedScenario() {
        let request = semanticRequest(
            entity: .plannedExpense,
            operation: .next,
            measure: .effectiveAmount,
            dateRangeToken: .nextSevenDays,
            expenseScope: .planned
        )

        #expect(policy.scenario(for: request) == .nextPlannedExpense)
        #expect(policy.allows(request))
    }

    @Test func unifiedGroupByCategoryMapsToUnifiedCategoryScenario() {
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.category],
            expenseScope: .unified,
            shape: .list
        )

        #expect(policy.scenario(for: request) == .unifiedExpenseCategoryGroups)
        #expect(policy.allows(request))
    }

    @Test func incomeTotalMapsToIncomeScenario() {
        let request = semanticRequest(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            incomeState: .all
        )

        #expect(policy.scenario(for: request) == .incomeTotal)
        #expect(policy.allows(request))
    }

    @Test func savingsTotalRequiresExplicitAccountTarget() {
        let explicit = semanticRequest(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            dateRangeToken: .allTime,
            targetName: "Savings Account"
        )
        let missingTarget = semanticRequest(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            dateRangeToken: .allTime
        )

        #expect(policy.scenario(for: explicit) == .savingsTotalExplicitAccount)
        #expect(policy.allows(explicit))
        #expect(policy.scenario(for: missingTarget) == nil)
        #expect(policy.allows(missingTarget) == false)
    }

    @Test func reconciliationBalanceRequiresExplicitAccountTarget() {
        let explicit = semanticRequest(
            entity: .reconciliationAccount,
            operation: .sum,
            measure: .reconciliationBalance,
            dateRangeToken: .allTime,
            targetName: "Alejandro"
        )
        let missingTarget = semanticRequest(
            entity: .reconciliationAccount,
            operation: .sum,
            measure: .reconciliationBalance,
            dateRangeToken: .allTime
        )

        #expect(policy.scenario(for: explicit) == .reconciliationBalanceExplicitAccount)
        #expect(policy.allows(explicit))
        #expect(policy.scenario(for: missingTarget) == nil)
        #expect(policy.allows(missingTarget) == false)
    }

    @Test func budgetFormulasMapOnlyForecastScenarios() {
        let remainingRoom = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .remainingRoom
        )
        let safeDailySpend = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .safeDailySpend
        )

        #expect(policy.scenario(for: remainingRoom) == .budgetRemainingRoom)
        #expect(policy.scenario(for: safeDailySpend) == .safeDailySpend)
        #expect(policy.allows(remainingRoom))
        #expect(policy.allows(safeDailySpend))
    }

    @Test func deferredMeasuresAreNotAllowlisted() {
        let request = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .burnRate
        )

        #expect(policy.scenario(for: request) == nil)
        #expect(policy.allows(request) == false)
    }

    @Test func compareShareAndWhatIfAreNotAllowlisted() {
        for operation in [MarinaSemanticOperation.compare, .share, .whatIf] {
            let request = semanticRequest(
                entity: .budget,
                operation: operation,
                measure: .remainingRoom
            )

            #expect(policy.scenario(for: request) == nil)
            #expect(policy.allows(request) == false)
        }
    }

    @Test func ambiguousTargetShapeIsNotAllowlisted() {
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.category, .card],
            targetName: "Groceries",
            expenseScope: .variable
        )

        #expect(policy.scenario(for: request) == nil)
        #expect(policy.allows(request) == false)
    }

    @Test func narrowedIncomeStatesAreNotAllowlisted() {
        let plannedOnly = semanticRequest(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            incomeState: .planned
        )
        let actualOnly = semanticRequest(
            entity: .income,
            operation: .sum,
            measure: .incomeAmount,
            incomeState: .actual
        )

        #expect(policy.scenario(for: plannedOnly) == nil)
        #expect(policy.scenario(for: actualOnly) == nil)
    }

    @Test func plannedEffectiveAmountSumAndBudgetSumRemainingRoomAreNotAllowlisted() {
        let plannedEffectiveSum = semanticRequest(
            entity: .plannedExpense,
            operation: .sum,
            measure: .effectiveAmount,
            expenseScope: .planned
        )
        let budgetSumRemainingRoom = semanticRequest(
            entity: .budget,
            operation: .sum,
            measure: .remainingRoom
        )

        #expect(policy.scenario(for: plannedEffectiveSum) == nil)
        #expect(policy.scenario(for: budgetSumRemainingRoom) == nil)
    }

    private func merchantSpendRequest() -> MarinaSemanticRequest {
        semanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dimensions: [.merchantText],
            textQuery: "Apple",
            expenseScope: .variable
        )
    }

    private func semanticRequest(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dimensions: [MarinaSemanticDimension] = [],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentMonth,
        targetName: String? = nil,
        textQuery: String? = nil,
        resultLimit: Int? = nil,
        sort: MarinaSemanticSort? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        incomeState: MarinaSemanticIncomeState? = nil,
        shape: MarinaSemanticAnswerShape = .metric
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dimensions: dimensions,
            dateRangeToken: dateRangeToken,
            targetName: targetName,
            textQuery: textQuery,
            resultLimit: resultLimit,
            sort: sort,
            expenseScope: expenseScope,
            incomeState: incomeState,
            expectedAnswerShape: shape
        )
    }
}
