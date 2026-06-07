import Foundation
import Testing
@testable import Offshore

struct MarinaSemanticUniversalPlanBridgeSavingsReconciliationTests {
    private let bridge = MarinaSemanticUniversalPlanBridge()
    private let formulaBridge = MarinaSemanticUniversalPlanBridge(formulaRegistry: MarinaFormulaRegistry())

    @Test func savingsAccountListAndCountMapToUniversalPlans() throws {
        let listPlan = try requirePlan(bridge.makePlan(from: request(
            entity: .savingsAccount,
            operation: .list,
            shape: .list
        )))
        let countPlan = try requirePlan(bridge.makePlan(from: request(
            entity: .savingsAccount,
            operation: .count,
            shape: .metric
        )))

        #expect(listPlan.surface == .semantic(.savingsAccount))
        #expect(listPlan.operation == .list)
        #expect(countPlan.surface == .semantic(.savingsAccount))
        #expect(countPlan.operation == .count)
    }

    @Test func savingsAccountSearchAndTargetNameMapToNameQueryFields() throws {
        let searchPlan = try requirePlan(bridge.makePlan(from: request(
            entity: .savingsAccount,
            operation: .list,
            textQuery: "Emergency",
            shape: .list
        )))
        let targetPlan = try requirePlan(bridge.makePlan(from: request(
            entity: .savingsAccount,
            operation: .list,
            targetName: "Emergency Fund",
            shape: .list
        )))

        #expect(searchPlan.search == MarinaRowSearchClause(fields: [.name], query: "Emergency"))
        #expect(targetPlan.filters == [
            MarinaRowFilter(target: .field(.name), operation: .equals, value: .text("Emergency Fund"))
        ])
    }

    @Test func savingsFormulaForecastAndWhatIfReturnTypedUnsupported() {
        #expect(bridge.makePlan(from: request(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            shape: .metric
        )) == .unsupported(.measureNotAvailable))

        #expect(bridge.makePlan(from: request(
            entity: .savingsAccount,
            operation: .forecast,
            measure: .savingsTotal,
            shape: .metric
        )) == .unsupported(.unsupportedCombination))

        #expect(bridge.makePlan(from: request(
            entity: .savingsAccount,
            operation: .whatIf,
            measure: .savingsTotal,
            shape: .metric
        )) == .unsupported(.unsupportedCombination))
    }

    @Test func formulaBridgeMapsSavingsTotalWithTargetToUniversalPlan() throws {
        let plan = try requirePlan(formulaBridge.makePlan(from: request(
            entity: .savingsAccount,
            operation: .sum,
            measure: .savingsTotal,
            targetName: "Emergency Fund",
            shape: .metric
        )))

        #expect(plan.surface == .semantic(.savingsAccount))
        #expect(plan.operation == .sum)
        #expect(plan.measure == .savingsTotal)
        #expect(plan.filters == [
            MarinaRowFilter(target: .field(.name), operation: .equals, value: .text("Emergency Fund"))
        ])
    }

    @Test func formulaBridgeMapsForecastSavingsWithDateContext() throws {
        let plan = try requirePlan(formulaBridge.makePlan(
            from: request(
                entity: .savingsAccount,
                operation: .forecast,
                measure: .savingsTotal,
                dateRangeToken: .currentMonth,
                shape: .metric
            ),
            planningContext: context(now: date(2026, 6, 15))
        ))

        #expect(plan.surface == .semantic(.savingsAccount))
        #expect(plan.operation == .forecast)
        #expect(plan.measure == .savingsTotal)
        #expect(plan.dateRange == HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30)))
    }

    @Test func reconciliationAccountListAndCountMapToUniversalPlans() throws {
        let listPlan = try requirePlan(bridge.makePlan(from: request(
            entity: .reconciliationAccount,
            operation: .list,
            shape: .list
        )))
        let countPlan = try requirePlan(bridge.makePlan(from: request(
            entity: .reconciliationAccount,
            operation: .count,
            shape: .metric
        )))

        #expect(listPlan.surface == .semantic(.reconciliationAccount))
        #expect(listPlan.operation == .list)
        #expect(countPlan.surface == .semantic(.reconciliationAccount))
        #expect(countPlan.operation == .count)
    }

    @Test func reconciliationAccountSearchAndTargetNameMapToNameQueryFields() throws {
        let searchPlan = try requirePlan(bridge.makePlan(from: request(
            entity: .reconciliationAccount,
            operation: .list,
            textQuery: "Roommate",
            shape: .list
        )))
        let targetPlan = try requirePlan(bridge.makePlan(from: request(
            entity: .reconciliationAccount,
            operation: .list,
            targetName: "Roommate",
            shape: .list
        )))

        #expect(searchPlan.search == MarinaRowSearchClause(fields: [.name], query: "Roommate"))
        #expect(targetPlan.filters == [
            MarinaRowFilter(target: .field(.name), operation: .equals, value: .text("Roommate"))
        ])
    }

    @Test func reconciliationBalanceForecastAndWhatIfReturnTypedUnsupported() {
        #expect(bridge.makePlan(from: request(
            entity: .reconciliationAccount,
            operation: .sum,
            measure: .reconciliationBalance,
            shape: .metric
        )) == .unsupported(.measureNotAvailable))

        #expect(bridge.makePlan(from: request(
            entity: .reconciliationAccount,
            operation: .forecast,
            measure: .reconciliationBalance,
            shape: .metric
        )) == .unsupported(.unsupportedCombination))

        #expect(bridge.makePlan(from: request(
            entity: .reconciliationAccount,
            operation: .whatIf,
            measure: .reconciliationBalance,
            shape: .metric
        )) == .unsupported(.unsupportedCombination))
    }

    @Test func formulaBridgeMapsReconciliationBalanceWithTargetToUniversalPlan() throws {
        let plan = try requirePlan(formulaBridge.makePlan(from: request(
            entity: .reconciliationAccount,
            operation: .sum,
            measure: .reconciliationBalance,
            targetName: "Roommate",
            shape: .metric
        )))

        #expect(plan.surface == .semantic(.reconciliationAccount))
        #expect(plan.operation == .sum)
        #expect(plan.measure == .reconciliationBalance)
        #expect(plan.filters == [
            MarinaRowFilter(target: .field(.name), operation: .equals, value: .text("Roommate"))
        ])
    }

    @Test func formulaBridgeMapsBudgetSafeDailySpendWithDateContext() throws {
        let plan = try requirePlan(formulaBridge.makePlan(
            from: request(
                entity: .budget,
                operation: .forecast,
                measure: .safeDailySpend,
                dateRangeToken: .currentMonth,
                shape: .metric
            ),
            planningContext: context(now: date(2026, 6, 15))
        ))

        #expect(plan.surface == .semantic(.budget))
        #expect(plan.operation == .forecast)
        #expect(plan.measure == .safeDailySpend)
        #expect(plan.dateRange == HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30)))
    }

    @Test func formulaBridgeMapsBudgetPaceFormulasWithDateContext() throws {
        let context = context(now: date(2026, 6, 15))
        let expectedRange = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
        let cases: [(MarinaSemanticOperation, MarinaSemanticMeasure, MarinaSemanticAnswerShape)] = [
            (.average, .burnRate, .metric),
            (.forecast, .projectedSpend, .metric),
            (.compare, .paceDifference, .comparison),
            (.forecast, .coverageRatio, .metric)
        ]

        for testCase in cases {
            let plan = try requirePlan(formulaBridge.makePlan(
                from: request(
                    entity: .budget,
                    operation: testCase.0,
                    measure: testCase.1,
                    dateRangeToken: .currentMonth,
                    shape: testCase.2
                ),
                planningContext: context
            ))

            #expect(plan.surface == .semantic(.budget))
            #expect(plan.operation == testCase.0)
            #expect(plan.measure == testCase.1)
            #expect(plan.dateRange == expectedRange)
        }
    }

    @Test func formulaBridgeMapsIncomeCoverageRatioWithDateContext() throws {
        let plan = try requirePlan(formulaBridge.makePlan(
            from: request(
                entity: .income,
                operation: .share,
                measure: .coverageRatio,
                dateRangeToken: .currentMonth,
                shape: .metric
            ),
            planningContext: context(now: date(2026, 6, 15))
        ))

        #expect(plan.surface == .semantic(.income))
        #expect(plan.operation == .share)
        #expect(plan.measure == .coverageRatio)
        #expect(plan.dateRange == HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30)))
    }

    @Test func formulaBridgeMapsCategoryFormulasWithDateContext() throws {
        let context = context(now: date(2026, 6, 15))
        let expectedRange = HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30))
        let cases: [(MarinaSemanticOperation, MarinaSemanticMeasure)] = [
            (.forecast, .categoryAvailability),
            (.share, .concentration)
        ]

        for testCase in cases {
            let plan = try requirePlan(formulaBridge.makePlan(
                from: request(
                    entity: .category,
                    operation: testCase.0,
                    measure: testCase.1,
                    dateRangeToken: .currentMonth,
                    shape: .metric
                ),
                planningContext: context
            ))

            #expect(plan.surface == .semantic(.category))
            #expect(plan.operation == testCase.0)
            #expect(plan.measure == testCase.1)
            #expect(plan.dateRange == expectedRange)
        }
    }

    @Test func formulaBridgeMapsPresetRecurringBurdenWithDateContext() throws {
        let plan = try requirePlan(formulaBridge.makePlan(
            from: request(
                entity: .preset,
                operation: .sum,
                measure: .recurringBurden,
                dateRangeToken: .currentMonth,
                shape: .metric
            ),
            planningContext: context(now: date(2026, 6, 15))
        ))

        #expect(plan.surface == .semantic(.preset))
        #expect(plan.operation == .sum)
        #expect(plan.measure == .recurringBurden)
        #expect(plan.dateRange == HomeQueryDateRange(startDate: date(2026, 6, 1), endDate: date(2026, 6, 30)))
    }

    @Test func formulaBridgeKeepsDeferredFormulaVariantsAndWhatIfUnsupported() {
        #expect(formulaBridge.makePlan(from: request(
            entity: .category,
            operation: .list,
            measure: .categoryAvailability,
            shape: .list
        )) == .unsupported(.measureNotAvailable))

        #expect(formulaBridge.makePlan(from: request(
            entity: .preset,
            operation: .forecast,
            measure: .recurringBurden,
            shape: .metric
        )) == .unsupported(.unsupportedCombination))

        #expect(formulaBridge.makePlan(from: request(
            entity: .savingsAccount,
            operation: .whatIf,
            measure: .savingsTotal,
            shape: .metric
        )) == .unsupported(.unsupportedCombination))
    }

    @Test func reconciliationAccountNextRemainsTypedUnsupported() {
        #expect(bridge.makePlan(from: request(
            entity: .reconciliationAccount,
            operation: .next,
            shape: .list
        )) == .unsupported(.operationNotSupported))
    }

    private func request(
        entity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure? = nil,
        targetName: String? = nil,
        textQuery: String? = nil,
        dateRangeToken: MarinaSemanticDateRangeToken = .allTime,
        shape: MarinaSemanticAnswerShape
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: entity,
            operation: operation,
            measure: measure,
            dateRangeToken: dateRangeToken,
            targetName: targetName,
            textQuery: textQuery,
            expectedAnswerShape: shape
        )
    }

    private func context(now: Date) -> MarinaUniversalPlanningContext {
        MarinaUniversalPlanningContext(now: now, calendar: calendar)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        DateComponents(calendar: calendar, timeZone: TimeZone(secondsFromGMT: 0), year: year, month: month, day: day).date!
    }

    private func requirePlan(_ result: MarinaSemanticUniversalPlanBridgeResult) throws -> MarinaUniversalQueryPlan {
        guard case let .plan(plan) = result else {
            Issue.record("Expected plan result, got \(result).")
            throw TestFailure()
        }
        return plan
    }
}

private struct TestFailure: Error {}
