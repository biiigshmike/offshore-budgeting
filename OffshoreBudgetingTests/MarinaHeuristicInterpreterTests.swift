import Foundation
import Testing
@testable import Offshore

struct MarinaHeuristicInterpreterTests {
    @Test func heuristic_totalSpendOnAppleCard_emitsUnresolvedCardFilterCandidate() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "total spend on my Apple Card",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .heuristic)
        #expect(candidate.rawPrompt == "total spend on my Apple Card")
        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.count <= 1)

        if let mention = candidate.entityMentions.first {
            #expect(mention.role == .filter || mention.role == .primaryTarget)
            #expect(mention.rawText?.lowercased().contains("apple") == true)
            #expect(mention.rawText?.lowercased().contains("card") == true)
            #expect(mention.typeHint == nil || mention.typeHint == .card)
        }
    }

    @Test func heuristic_averageFoodAndDrinkLastThreeMonths_emitsAverageCandidateWithoutResolvingEntityTruth() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "average Food & Drink for the last 3 months",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .heuristic)
        #expect(candidate.operation == .average)
        #expect(candidate.measure == .spend)
        #expect(candidate.responseShapeHint == .scalarCurrency || candidate.responseShapeHint == .unsupported)

        if let mention = candidate.entityMentions.first {
            #expect(mention.role == .primaryTarget)
            #expect(mention.confidence == .low || mention.confidence == .medium || mention.confidence == .high)
            #expect(mention.typeHint == nil || mention.typeHint == .category)
        }

        #expect(candidate.timeScopes.allSatisfy { $0.role == .primary || $0.role == .lookbackWindow })
    }

    @Test func heuristic_compareGroceriesThisMonthToLastMonth_emitsComparisonCandidate() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "compare groceries this month to last month",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .heuristic)
        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.responseShapeHint == .comparison || candidate.responseShapeHint == .unsupported)
        #expect(candidate.entityMentions.count <= 1)
        #expect(candidate.timeScopes.contains { $0.role == .primary })
        #expect(candidate.timeScopes.contains { $0.role == .comparison })

        if let mention = candidate.entityMentions.first {
            #expect(mention.rawText?.lowercased().contains("groceries") == true)
            #expect(mention.typeHint == nil || MarinaCandidateEntityTypeHint.allCases.contains(mention.typeHint!))
        }
    }

    @Test func heuristic_whereIsMyMoneyGoing_emitsGroupedRankingWithoutSpecificEntityTruth() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "where is my money going?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .heuristic)
        #expect(candidate.operation == .rank)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.isEmpty)
        #expect(candidate.grouping?.dimension == .category)
        #expect(candidate.ranking?.direction == .top)
        #expect(candidate.responseShapeHint == .rankedList)
    }

    @Test func heuristic_whatIfPromptDoesNotPretendToSolveMultiEntityExtraction() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "If I increase Shopping by $100, what will I have left for Transportation?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.source == .heuristic)
        #expect(candidate.operation == .simulate || candidate.operation == .sum || candidate.operation == nil)
        #expect(candidate.measure == .remainingBudget || candidate.measure == .spend || candidate.measure == nil)
        #expect(candidate.responseShapeHint == .unsupported || candidate.responseShapeHint == nil)
        #expect(candidate.entityMentions.count <= 1)
        #expect(candidate.entityMentions.map(\.role).contains(.simulationInput) == false)
        #expect(candidate.entityMentions.map(\.role).contains(.simulationOutput) == false)
    }

    @Test func heuristic_dirtyFoodComparisonCleansTrailingClauseOnlyAfterShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "Am I spending more on food lately, or is it about normal?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.rawText == "food")
        #expect(candidate.entityMentions.first?.typeHint == .category)
    }

    @Test func heuristic_simulationShapeSplitsShoppingAndTransportationMentions() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "If I add $75 to Shopping, does Transportation still have room?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .simulate)
        #expect(candidate.measure == .remainingBudget)
        #expect(candidate.unsupportedHint == .unsupportedSimulation)
        #expect(candidate.entityMentions.map(\.role) == [.simulationInput, .simulationOutput])
        #expect(candidate.entityMentions.map(\.rawText) == ["shopping", "transportation"])
        #expect(candidate.entityMentions.allSatisfy { $0.typeHint == .category })
    }

    @Test func heuristic_sharePromptPreservesCategoryShareShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "How much of my spending this month was Food & Drink?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .categoryShare)
        #expect(candidate.entityMentions.first?.rawText == "food & drink")
        #expect(candidate.entityMentions.first?.typeHint == .category)
        #expect(candidate.responseShapeHint == .groupedBreakdown)
    }

    @Test func heuristic_groupedBreakdownPromptPreservesCategoryGroupedShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "Break down where my money went this month, but don’t just give me the total.",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .rank)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.isEmpty)
        #expect(candidate.grouping?.dimension == .category)
        #expect(candidate.ranking?.direction == .top)
        #expect(candidate.responseShapeHint == .groupedBreakdown)
    }

    @Test func heuristic_frequencyPromptPreservesFrequencyRankingShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "Show me the stuff I’m spending on too often, not necessarily the most money.",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .rank)
        #expect(candidate.measure == .transactionFrequency)
        #expect(candidate.grouping?.dimension == .transaction)
        #expect(candidate.ranking?.direction == .mostFrequent)
        #expect(candidate.entityMentions.isEmpty)
    }

    @Test func heuristic_projectionPromptPreservesUnsupportedForecastShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "If I keep spending like this, how much will I have left by the end of the period?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .forecast)
        #expect(candidate.measure == .remainingBudget)
        #expect(candidate.unsupportedHint == .unsupportedProjection)
        #expect(candidate.entityMentions.isEmpty)
    }

    @Test func heuristic_exclusionPromptPreservesUnsupportedFilterShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "What did I spend on Apple Card outside of Food & Drink?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .spend)
        #expect(candidate.unsupportedHint == .unsupportedExclusionFilter)
        #expect(candidate.entityMentions.map(\.rawText) == ["apple card", "food & drink"])
        #expect(candidate.entityMentions.map(\.typeHint) == [.card, .category])
    }

    @Test func heuristic_categoryAvailabilityPromptPreservesUnsupportedBudgetLimitShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "Is Shopping over where it should be for this budget?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .remainingBudget)
        #expect(candidate.unsupportedHint == .unsupportedBudgetLimit)
        #expect(candidate.entityMentions.first?.rawText == "shopping")
        #expect(candidate.entityMentions.first?.typeHint == .category)
    }

    @Test func heuristic_cardRankingPromptPreservesUnsupportedCardRankingShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "What card is eating most of my budget this period?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .rank)
        #expect(candidate.measure == .spend)
        #expect(candidate.grouping?.dimension == .card)
        #expect(candidate.ranking?.direction == .top)
        #expect(candidate.unsupportedHint == .unsupportedCardRanking)
        #expect(candidate.entityMentions.isEmpty)
    }

    @Test func heuristic_categoryDeltaRankingPreservesUnsupportedRankedComparisonShape() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "What category changed the most compared to last month?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.grouping?.dimension == .category)
        #expect(candidate.ranking?.direction == .largest)
        #expect(candidate.unsupportedHint == .unsupportedRankedComparison)
        #expect(candidate.entityMentions.isEmpty)
    }

    @Test func heuristic_comparedToLastMonthBuildsPrimaryAndComparisonScopes() {
        let candidate = fixedNowInterpreter().interpret(
            prompt: "How bad was Food & Drink compared to last month?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.rawText == "food & drink")
        #expect(candidate.entityMentions.first?.typeHint == .category)
        assertMonthScopes(candidate, primaryMonth: 5, comparisonMonth: 4)
    }

    @Test func heuristic_thisMonthThanLastMonthBuildsPrimaryAndComparisonScopes() {
        let candidate = fixedNowInterpreter().interpret(
            prompt: "Did I spend more on restaurants this month than last month?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.rawText == "restaurants")
        assertMonthScopes(candidate, primaryMonth: 5, comparisonMonth: 4)
    }

    @Test func heuristic_thisMonthVsLastMonthBuildsPrimaryAndComparisonScopes() {
        let candidate = fixedNowInterpreter().interpret(
            prompt: "Compare Food & Drink this month vs last month",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        assertMonthScopes(candidate, primaryMonth: 5, comparisonMonth: 4)
    }

    @Test func heuristic_fromMarchToAprilBuildsBothScopesWithAprilPrimary() {
        let candidate = fixedNowInterpreter().interpret(
            prompt: "Did groceries go up or down from March to April?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.first?.rawText == "groceries")
        assertMonthScopes(candidate, primaryMonth: 4, comparisonMonth: 3)
    }

    @Test func heuristic_transactionDeltaDriversPreservesUnsupportedRankedComparisonShape() {
        let candidate = fixedNowInterpreter().interpret(
            prompt: "What expenses are making this month higher than last month?",
            defaultPeriodUnit: .month
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.measure == .spend)
        #expect(candidate.grouping?.dimension == .transaction)
        #expect(candidate.ranking?.direction == .largest)
        #expect(candidate.unsupportedHint == .unsupportedRankedComparison)
        #expect(candidate.entityMentions.isEmpty)
        assertMonthScopes(candidate, primaryMonth: 5, comparisonMonth: 4)
    }

    @Test func heuristicCandidateTrace_summarizesAdapterOutput() {
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "where is my money going?",
            defaultPeriodUnit: .month
        )
        let trace = MarinaCandidateTrace(candidate: candidate)

        #expect(trace.interpreterSource == .heuristic)
        #expect(trace.operation == candidate.operation)
        #expect(trace.measure == candidate.measure)
        #expect(trace.compactSummary.contains("source=heuristic"))
        #expect(trace.executablePlanSummary == nil)
        #expect(trace.validatorOutcomeSummary == nil)
    }

    private func fixedNowInterpreter() -> MarinaHeuristicInterpreter {
        MarinaHeuristicInterpreter(now: { date(2026, 5, 8) })
    }

    private func assertMonthScopes(
        _ candidate: MarinaQueryPlanCandidate,
        primaryMonth: Int,
        comparisonMonth: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let calendar = Calendar(identifier: .gregorian)
        let primary = candidate.timeScopes.first { $0.role == .primary }?.resolvedRangeHint?.startDate
        let comparison = candidate.timeScopes.first { $0.role == .comparison }?.resolvedRangeHint?.startDate

        #expect(primary != nil, sourceLocation: sourceLocation)
        #expect(comparison != nil, sourceLocation: sourceLocation)
        #expect(primary.map { calendar.component(.month, from: $0) } == primaryMonth, sourceLocation: sourceLocation)
        #expect(comparison.map { calendar.component(.month, from: $0) } == comparisonMonth, sourceLocation: sourceLocation)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}
