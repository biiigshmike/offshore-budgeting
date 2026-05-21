import Foundation
import Testing
@testable import Offshore

struct MarinaAggregationPlanHomeQueryAdapterTests {
    private let adapter = MarinaAggregationPlanHomeQueryAdapter()

    @Test func adapter_mapsBroadSpendCategoryCardAndMerchantSpend() throws {
        #expect(try homeMetric(sumSpendPlan()).metric == .spendTotal)
        #expect(try homeMetric(sumSpendPlan(target: target(.category, "Groceries"))).metric == .categorySpendTotal)
        #expect(try homeMetric(sumSpendPlan(target: target(.card, "Apple Card"))).metric == .cardSpendTotal)
        #expect(try homeMetric(sumSpendPlan(target: target(.merchant, "Target"))).metric == .merchantSpendTotal)
    }

    @Test func adapter_mapsSpendAverageAndIncomeAverageButNotBroadIncomeTotal() throws {
        #expect(try homeMetric(MarinaAggregationPlan(operation: .average, measure: .spend)).metric == .spendAveragePerPeriod)
        #expect(try homeMetric(MarinaAggregationPlan(operation: .average, measure: .income)).metric == .incomeAverageActual)

        let incomeTotal = MarinaAggregationPlan(operation: .sum, measure: .income)
        if case .success = adapter.homeQueryPlan(from: incomeTotal) {
            Issue.record("Broad income total must remain unsupported until HomeQueryEngine has a faithful income-total metric.")
        }
    }

    @Test func adapter_preservesComparisonRangesAndTargets() throws {
        let primary = range(2026, 5, 1, 2026, 5, 31)
        let comparison = range(2026, 4, 1, 2026, 4, 30)

        let broad = try homeMetric(MarinaAggregationPlan(operation: .compare, measure: .spend, dateRange: primary, comparisonDateRange: comparison))
        let category = try homeMetric(MarinaAggregationPlan(operation: .compare, measure: .spend, targets: [target(.category, "Groceries")], dateRange: primary, comparisonDateRange: comparison))
        let card = try homeMetric(MarinaAggregationPlan(operation: .compare, measure: .spend, targets: [target(.card, "Apple Card")], dateRange: primary, comparisonDateRange: comparison))
        let merchant = try homeMetric(MarinaAggregationPlan(operation: .compare, measure: .spend, targets: [target(.merchant, "Target")], dateRange: primary, comparisonDateRange: comparison))

        #expect(broad.metric == .monthComparison)
        #expect(category.metric == .categoryMonthComparison)
        #expect(category.targetName == "Groceries")
        #expect(card.metric == .cardMonthComparison)
        #expect(merchant.metric == .merchantMonthComparison)
        assertDateRange(category.comparisonDateRange, equals: comparison)
    }

    @Test func adapter_mapsRankingAndShareFamiliesWhenFaithfullySupported() throws {
        let topCategories = MarinaAggregationPlan(
            operation: .rank,
            measure: .spend,
            grouping: MarinaGroupingCandidate(dimension: .category),
            ranking: MarinaRankingCandidate(direction: .top, limit: 5),
            limit: 5,
            responseShape: .rankedList
        )
        let topMerchants = MarinaAggregationPlan(
            operation: .rank,
            measure: .spend,
            grouping: MarinaGroupingCandidate(dimension: .merchant),
            ranking: MarinaRankingCandidate(direction: .largest, limit: 5)
        )
        let largestTransactions = MarinaAggregationPlan(
            operation: .rank,
            measure: .spend,
            grouping: MarinaGroupingCandidate(dimension: .transaction),
            ranking: MarinaRankingCandidate(direction: .largest, limit: 5)
        )
        let frequentTransactions = MarinaAggregationPlan(
            operation: .rank,
            measure: .transactionFrequency,
            grouping: MarinaGroupingCandidate(dimension: .transaction),
            ranking: MarinaRankingCandidate(direction: .mostFrequent, limit: 5)
        )
        let categoryShare = MarinaAggregationPlan(operation: .sum, measure: .categoryShare, responseShape: .groupedBreakdown)

        #expect(try homeMetric(topCategories).metric == .topCategories)
        #expect(try homeMetric(topCategories).resultLimit == 5)
        #expect(try homeMetric(topMerchants).metric == .topMerchants)
        #expect(try homeMetric(largestTransactions).metric == .largestTransactions)
        #expect(try homeMetric(frequentTransactions).metric == .mostFrequentTransactions)
        #expect(try homeMetric(categoryShare).metric == .categorySpendShare)
    }

    @Test func adapter_mapsTransactionAmountRanking_toLargestTransactions_andKeepsRankingLimit() throws {
        let plan = MarinaAggregationPlan(
            operation: .rank,
            measure: .transactionAmount,
            grouping: MarinaGroupingCandidate(dimension: .transaction),
            ranking: MarinaRankingCandidate(direction: .largest, limit: 5)
        )

        let mapped = try homeMetric(plan)
        #expect(mapped.metric == .largestTransactions)
        #expect(mapped.resultLimit == 5)
    }

    @Test func adapter_rejectsUnsupportedPlansInsteadOfApproximating() throws {
        let targetedAverage = MarinaAggregationPlan(operation: .average, measure: .spend, targets: [target(.category, "Groceries")])
        let cardRanking = MarinaAggregationPlan(
            operation: .rank,
            measure: .spend,
            grouping: MarinaGroupingCandidate(dimension: .card),
            ranking: MarinaRankingCandidate(direction: .top)
        )
        let simulation = MarinaAggregationPlan(operation: .simulate, measure: .remainingBudget)
        let multipleTargets = MarinaAggregationPlan(
            operation: .sum,
            measure: .spend,
            targets: [target(.category, "Groceries"), target(.card, "Apple Card")]
        )

        assertUnsupported(targetedAverage)
        assertUnsupported(cardRanking)
        assertUnsupported(simulation)
        assertUnsupported(multipleTargets)
    }

    @Test func adapter_rejectsClarificationAndUnsupportedValidationOutcomes() {
        let candidate = MarinaQueryPlanCandidate(source: .deterministic, rawPrompt: "spend on something")
        let clarification = MarinaPlanValidationOutcome.clarification(
            MarinaTypedClarification(kind: .missingTarget, message: "Pick a target.", candidate: candidate)
        )
        let unsupported = MarinaPlanValidationOutcome.unsupported(
            MarinaTypedUnsupportedResponse(kind: .unsupportedOperation, message: "Nope.", candidate: candidate)
        )

        if case .success = adapter.executablePlan(from: clarification) {
            Issue.record("Clarifications must not become executable plans.")
        }
        if case .success = adapter.executablePlan(from: unsupported) {
            Issue.record("Unsupported outcomes must not become executable plans.")
        }
    }

    private func homeMetric(_ plan: MarinaAggregationPlan) throws -> HomeQueryPlan {
        switch adapter.homeQueryPlan(from: plan) {
        case .success(let homePlan):
            return homePlan
        case .failure(let unsupported):
            throw TestFailure(message: unsupported.message)
        }
    }

    private func assertUnsupported(_ plan: MarinaAggregationPlan) {
        if case .success(let homePlan) = adapter.homeQueryPlan(from: plan) {
            Issue.record("Plan unexpectedly mapped to \(homePlan.metric.rawValue)")
        }
    }

    private func sumSpendPlan(target: MarinaResolvedAggregationTarget? = nil) -> MarinaAggregationPlan {
        MarinaAggregationPlan(
            operation: .sum,
            measure: .spend,
            targets: target.map { [$0] } ?? []
        )
    }

    private func target(_ type: MarinaCandidateEntityTypeHint, _ name: String) -> MarinaResolvedAggregationTarget {
        MarinaResolvedAggregationTarget(role: .primaryTarget, entityType: type, displayName: name)
    }

    private func range(
        _ startYear: Int,
        _ startMonth: Int,
        _ startDay: Int,
        _ endYear: Int,
        _ endMonth: Int,
        _ endDay: Int
    ) -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(startYear, startMonth, startDay),
            endDate: date(endYear, endMonth, endDay)
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func assertDateRange(_ actual: HomeQueryDateRange?, equals expected: HomeQueryDateRange) {
        #expect(actual?.startDate == expected.startDate)
        #expect(actual?.endDate == expected.endDate)
    }

    private struct TestFailure: Error {
        let message: String
    }
}
