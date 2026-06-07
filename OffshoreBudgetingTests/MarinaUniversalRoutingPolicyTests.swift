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

    @Test func unifiedGroupByCardMapsToUnifiedCardScenario() {
        let request = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            expenseScope: .unified,
            shape: .list
        )

        #expect(policy.scenario(for: request) == .unifiedExpenseCardGroups)
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

    @Test func incomeBySourceMapsToIncomeSourceScenario() {
        let request = semanticRequest(
            entity: .income,
            operation: .group,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            incomeState: .all,
            shape: .list
        )

        #expect(policy.scenario(for: request) == .incomeBySource)
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
        let burnRate = semanticRequest(
            entity: .budget,
            operation: .average,
            measure: .burnRate
        )
        let projectedSpend = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .projectedSpend
        )
        let paceDifference = semanticRequest(
            entity: .budget,
            operation: .compare,
            measure: .paceDifference,
            shape: .comparison
        )
        let budgetCoverage = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .coverageRatio
        )

        #expect(policy.scenario(for: remainingRoom) == .budgetRemainingRoom)
        #expect(policy.scenario(for: safeDailySpend) == .safeDailySpend)
        #expect(policy.scenario(for: burnRate) == .budgetBurnRate)
        #expect(policy.scenario(for: projectedSpend) == .budgetProjectedSpend)
        #expect(policy.scenario(for: paceDifference) == .budgetPaceDifference)
        #expect(policy.scenario(for: budgetCoverage) == .budgetCoverageRatio)
        #expect(policy.allows(remainingRoom))
        #expect(policy.allows(safeDailySpend))
        #expect(policy.allows(burnRate))
        #expect(policy.allows(projectedSpend))
        #expect(policy.allows(paceDifference))
        #expect(policy.allows(budgetCoverage))
    }

    @Test func incomeCoverageRatioMapsToExactScenario() {
        let request = semanticRequest(
            entity: .income,
            operation: .share,
            measure: .coverageRatio
        )

        #expect(policy.scenario(for: request) == .incomeCoverageRatio)
        #expect(policy.allows(request))
    }

    @Test func deferredMeasuresAreNotAllowlisted() {
        let requests = [
            semanticRequest(
                entity: .category,
                operation: .forecast,
                measure: .categoryAvailability
            ),
            semanticRequest(
                entity: .category,
                operation: .share,
                measure: .concentration
            ),
            semanticRequest(
                entity: .preset,
                operation: .sum,
                measure: .recurringBurden
            ),
            semanticRequest(
                entity: .savingsAccount,
                operation: .forecast,
                measure: .savingsTotal
            )
        ]

        for request in requests {
            #expect(policy.scenario(for: request) == nil)
            #expect(policy.allows(request) == false)
        }
    }

    @Test func budgetPaceFormulaVariantsAreNotAllowlisted() {
        let wrongOperation = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .burnRate
        )
        let wrongShape = semanticRequest(
            entity: .budget,
            operation: .compare,
            measure: .paceDifference
        )
        let allTime = semanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .projectedSpend,
            dateRangeToken: .allTime
        )

        for request in [wrongOperation, wrongShape, allTime] {
            #expect(policy.scenario(for: request) == nil)
            #expect(policy.allows(request) == false)
        }
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

    @Test func narrowedIncomeBySourceStatesAreNotAllowlisted() {
        for state in [MarinaSemanticIncomeState.planned, .actual] {
            let request = semanticRequest(
                entity: .income,
                operation: .group,
                measure: .incomeAmount,
                dimensions: [.incomeSource],
                incomeState: state,
                shape: .list
            )

            #expect(policy.scenario(for: request) == nil)
            #expect(policy.allows(request) == false)
        }
    }

    @Test func phase17GroupedScenariosRejectAllTimeTargetsSortsAndExtraDimensions() {
        let incomeAllTime = semanticRequest(
            entity: .income,
            operation: .group,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            dateRangeToken: .allTime,
            shape: .list
        )
        let incomeTarget = semanticRequest(
            entity: .income,
            operation: .group,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            targetName: "Paycheck",
            shape: .list
        )
        let incomeSorted = semanticRequest(
            entity: .income,
            operation: .group,
            measure: .incomeAmount,
            dimensions: [.incomeSource],
            sort: .amountDescending,
            shape: .list
        )
        let unifiedAllTime = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: .allTime,
            expenseScope: .unified,
            shape: .list
        )
        let unifiedExtraDimension = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card, .category],
            expenseScope: .unified,
            shape: .list
        )
        let unifiedTarget = semanticRequest(
            entity: .variableExpense,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.card],
            targetName: "Apple Card",
            expenseScope: .unified,
            shape: .list
        )

        for request in [incomeAllTime, incomeTarget, incomeSorted, unifiedAllTime, unifiedExtraDimension, unifiedTarget] {
            #expect(policy.scenario(for: request) == nil)
            #expect(policy.allows(request) == false)
        }
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
