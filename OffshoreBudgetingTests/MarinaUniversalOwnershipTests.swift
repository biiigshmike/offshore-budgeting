import Foundation
import Testing
@testable import Offshore

struct MarinaUniversalOwnershipTests {
    private let registry = MarinaUniversalOwnershipRegistry.current
    private let policy = MarinaUniversalRoutingPolicy.internalParityProven

    @Test func phase14AllowlistedScenariosAreUniversalOwned() {
        for scenario in policy.allowedScenarios {
            let record = registry.record(for: scenario)

            #expect(record?.scenario == scenario)
            #expect(record?.status == .universalOwned)
            #expect(record?.legacyFallbackRequired == true)
            #expect(record?.reason.isEmpty == false)
        }
    }

    @Test func ownershipRegistryAndRoutingPolicyDoNotDrift() {
        #expect(registry.universalOwnedScenarios == policy.allowedScenarios)
        #expect(policy.allowedScenarios == Set(MarinaUniversalRoutingScenario.allCases))
        #expect(registry.records.count == policy.allowedScenarios.count)
    }

    @Test func unsupportedRemainingFormulaVariantsAreNotMarkedUniversalOwned() {
        let requests = [
            semanticRequest(entity: .preset, operation: .forecast, measure: .recurringBurden),
            semanticRequest(entity: .preset, operation: .sum, measure: .recurringBurden, dateRangeToken: .allTime),
            semanticRequest(entity: .preset, operation: .sum, measure: .recurringBurden, targetName: "Phone"),
            semanticRequest(entity: .savingsAccount, operation: .whatIf, measure: .savingsTotal),
            semanticRequest(entity: .savingsAccount, operation: .forecast, measure: .savingsTotal, dateRangeToken: .allTime),
            semanticRequest(entity: .savingsAccount, operation: .forecast, measure: .savingsTotal, targetName: "Savings Account")
        ]

        for request in requests {
            expectNotUniversalOwned(request)
        }
    }

    @Test func unsupportedCategoryFormulaVariantsAreNotMarkedUniversalOwned() {
        let requests = [
            semanticRequest(entity: .category, operation: .list, measure: .categoryAvailability, expectedAnswerShape: .list),
            semanticRequest(entity: .category, operation: .forecast, measure: .categoryAvailability, categoryAvailabilityFilter: .over),
            semanticRequest(entity: .category, operation: .share, measure: .concentration, targetName: "Groceries"),
            semanticRequest(entity: .category, operation: .share, measure: .concentration, dateRangeToken: .allTime)
        ]

        for request in requests {
            expectNotUniversalOwned(request)
        }
    }

    @Test func unsupportedBudgetPaceFormulaVariantsAreNotMarkedUniversalOwned() {
        let requests = [
            semanticRequest(entity: .budget, operation: .forecast, measure: .burnRate),
            semanticRequest(entity: .budget, operation: .average, measure: .projectedSpend),
            semanticRequest(entity: .budget, operation: .compare, measure: .paceDifference),
            semanticRequest(entity: .budget, operation: .share, measure: .coverageRatio),
            semanticRequest(entity: .income, operation: .forecast, measure: .coverageRatio)
        ]

        for request in requests {
            expectNotUniversalOwned(request)
        }
    }

    @Test func compareShareAndWhatIfAreNotMarkedUniversalOwned() {
        let requests = [
            semanticRequest(entity: .budget, operation: .compare, measure: .remainingRoom, expectedAnswerShape: .comparison),
            semanticRequest(entity: .income, operation: .share, measure: .incomeAmount),
            semanticRequest(
                entity: .budget,
                operation: .whatIf,
                measure: .remainingRoom,
                whatIfAmount: 50,
                expectedAnswerShape: .comparison
            )
        ]

        for request in requests {
            expectNotUniversalOwned(request)
        }
    }

    @Test func phase2RowBackedGroupedShapesAreMarkedUniversalOwned() {
        let requests = [
            semanticRequest(
                entity: .income,
                operation: .group,
                measure: .incomeAmount,
                dimensions: [.incomeSource],
                incomeState: .planned,
                expectedAnswerShape: .list
            ),
            semanticRequest(
                entity: .income,
                operation: .group,
                measure: .incomeAmount,
                dimensions: [.incomeSource],
                incomeState: .actual,
                expectedAnswerShape: .list
            ),
            semanticRequest(
                entity: .income,
                operation: .group,
                measure: .incomeAmount,
                dimensions: [.incomeSource],
                dateRangeToken: .allTime,
                expectedAnswerShape: .list
            ),
            semanticRequest(
                entity: .variableExpense,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.card],
                dateRangeToken: .allTime,
                expenseScope: .unified,
                expectedAnswerShape: .list
            )
        ]

        for request in requests {
            expectUniversalOwned(request, as: .rowBackedQuery)
        }
    }

    @Test func unsupportedGuardrailRequestsAreNotMarkedUniversalOwned() {
        let requests = [
            semanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                expectedAnswerShape: .unsupported,
                unsupportedReason: .readOnly
            ),
            semanticRequest(
                entity: .savingsAccount,
                operation: .sum,
                measure: .savingsTotal,
                targetName: "Savings",
                expectedAnswerShape: .unsupported,
                unsupportedReason: .modelGuardrail
            ),
            semanticRequest(
                entity: .budget,
                operation: .forecast,
                measure: .remainingRoom,
                expectedAnswerShape: .clarification
            )
        ]

        for request in requests {
            expectNotUniversalOwned(request)
        }
    }

    private func expectNotUniversalOwned(_ request: MarinaSemanticRequest) {
        let scenario = policy.scenario(for: request)

        #expect(scenario == nil)
        if let scenario {
            #expect(registry.status(for: scenario) != .universalOwned)
        }
    }

    private func expectUniversalOwned(
        _ request: MarinaSemanticRequest,
        as expectedScenario: MarinaUniversalRoutingScenario
    ) {
        let scenario = policy.scenario(for: request)

        #expect(scenario == expectedScenario)
        #expect(scenario.map { registry.status(for: $0) } == .universalOwned)
    }

    private func semanticRequest(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        dimensions: [MarinaSemanticDimension] = [],
        dateRangeToken: MarinaSemanticDateRangeToken = .currentMonth,
        targetName: String? = nil,
        textQuery: String? = nil,
        sort: MarinaSemanticSort? = nil,
        expenseScope: MarinaSemanticExpenseScope? = nil,
        incomeState: MarinaSemanticIncomeState? = nil,
        whatIfAmount: Double? = nil,
        categoryAvailabilityFilter: MarinaCategoryAvailabilityFilter? = nil,
        expectedAnswerShape: MarinaSemanticAnswerShape = .metric,
        unsupportedReason: MarinaSemanticUnsupportedReason? = nil
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dimensions: dimensions,
            dateRangeToken: dateRangeToken,
            targetName: targetName,
            textQuery: textQuery,
            sort: sort,
            expenseScope: expenseScope,
            incomeState: incomeState,
            whatIfAmount: whatIfAmount,
            categoryAvailabilityFilter: categoryAvailabilityFilter,
            expectedAnswerShape: expectedAnswerShape,
            unsupportedReason: unsupportedReason
        )
    }
}
