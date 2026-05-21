import Foundation
import Testing
@testable import Offshore

struct MarinaQueryPlanCandidateTests {
    @Test func candidate_totalSpendOnAppleCard_representsCardFilter() {
        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "total spend on my Apple Card",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .filter,
                    rawText: "Apple Card",
                    typeHint: .card,
                    confidence: .high
                )
            ],
            responseShapeHint: .scalarCurrency,
            confidence: .high
        )

        #expect(candidate.source == .deterministic)
        #expect(candidate.operation == .sum)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.count == 1)
        #expect(candidate.entityMentions[0].role == .filter)
        #expect(candidate.entityMentions[0].typeHint == .card)
        #expect(candidate.entityMentions[0].rawText == "Apple Card")
        #expect(candidate.responseShapeHint?.isAdvisory == true)
    }

    @Test func candidate_averageFoodAndDrinkLastThreeMonths_representsCategoryAndLookbackWindow() {
        let lookbackRange = HomeQueryDateRange(
            startDate: date(2026, 2, 1),
            endDate: date(2026, 4, 30)
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "average Food & Drink for the last 3 months",
            operation: .average,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .primaryTarget,
                    rawText: "Food & Drink",
                    typeHint: .category,
                    confidence: .high
                )
            ],
            timeScopes: [
                MarinaUnresolvedTimeScope(
                    role: .lookbackWindow,
                    rawText: "last 3 months",
                    resolvedRangeHint: lookbackRange,
                    periodUnitHint: .month
                )
            ],
            responseShapeHint: .scalarCurrency,
            confidence: .high
        )

        #expect(candidate.source == .foundationModels)
        #expect(candidate.operation == .average)
        #expect(candidate.entityMentions[0].role == .primaryTarget)
        #expect(candidate.entityMentions[0].typeHint == .category)
        #expect(candidate.timeScopes[0].role == .lookbackWindow)
        #expect(candidate.timeScopes[0].periodUnitHint == .month)
        assertDateRange(candidate.timeScopes[0].resolvedRangeHint, equals: lookbackRange)
    }

    @Test func candidate_compareGroceries_representsTargetAndComparisonRange() {
        let primaryRange = HomeQueryDateRange(
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 31)
        )
        let comparisonRange = HomeQueryDateRange(
            startDate: date(2026, 4, 1),
            endDate: date(2026, 4, 30)
        )
        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "compare groceries this month to last month",
            operation: .compare,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .primaryTarget,
                    rawText: "groceries",
                    typeHint: .category,
                    confidence: .medium
                )
            ],
            timeScopes: [
                MarinaUnresolvedTimeScope(role: .primary, rawText: "this month", resolvedRangeHint: primaryRange, periodUnitHint: .month),
                MarinaUnresolvedTimeScope(role: .comparison, rawText: "last month", resolvedRangeHint: comparisonRange, periodUnitHint: .month)
            ],
            responseShapeHint: .comparison,
            confidence: .medium
        )

        #expect(candidate.operation == .compare)
        #expect(candidate.entityMentions.map(\.role) == [.primaryTarget])
        #expect(candidate.timeScopes.map(\.role) == [.primary, .comparison])
        assertDateRange(candidate.timeScopes[1].resolvedRangeHint, equals: comparisonRange)
        #expect(candidate.responseShapeHint == .comparison)
    }

    @Test func candidate_whatIfIncreaseShopping_representsSimulationInputAndOutputRoles() {
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "if I increase Shopping, what will I have left for Transportation?",
            operation: .simulate,
            measure: .remainingBudget,
            entityMentions: [
                MarinaUnresolvedEntityMention(
                    role: .simulationInput,
                    rawText: "Shopping",
                    typeHint: .category,
                    confidence: .high
                ),
                MarinaUnresolvedEntityMention(
                    role: .simulationOutput,
                    rawText: "Transportation",
                    typeHint: .category,
                    confidence: .high
                )
            ],
            timeScopes: [
                MarinaUnresolvedTimeScope(role: .simulationHorizon, rawText: nil, periodUnitHint: .month)
            ],
            responseShapeHint: .scalarCurrency,
            confidence: .medium
        )

        #expect(candidate.operation == .simulate)
        #expect(candidate.measure == .remainingBudget)
        #expect(candidate.entityMentions.count == 2)
        #expect(candidate.entityMentions.map(\.role) == [.simulationInput, .simulationOutput])
        #expect(candidate.entityMentions.map(\.rawText) == ["Shopping", "Transportation"])
        #expect(candidate.timeScopes.first?.role == .simulationHorizon)
    }

    @Test func candidate_whereIsMyMoneyGoing_representsGroupingAndRankingWithoutSpecificTarget() {
        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "where is my money going?",
            operation: .rank,
            measure: .spend,
            grouping: MarinaGroupingCandidate(dimension: .category, rawText: "where"),
            ranking: MarinaRankingCandidate(direction: .top, rawText: "money going"),
            responseShapeHint: .rankedList,
            confidence: .medium
        )

        #expect(candidate.operation == .rank)
        #expect(candidate.measure == .spend)
        #expect(candidate.entityMentions.isEmpty)
        #expect(candidate.grouping?.dimension == .category)
        #expect(candidate.ranking?.direction == .top)
        #expect(candidate.responseShapeHint == .rankedList)
    }

    @Test func aggregationPlan_shellCanRepresentResolvedFutureExecutableBoundary() {
        let plan = MarinaAggregationPlan(
            operation: .sum,
            measure: .spend,
            targets: [
                MarinaResolvedAggregationTarget(
                    role: .filter,
                    entityType: .card,
                    displayName: "Apple Card"
                )
            ],
            dateRange: HomeQueryDateRange(startDate: date(2026, 5, 1), endDate: date(2026, 5, 31)),
            responseShape: .scalarCurrency
        )

        #expect(plan.status == .notExecutableShell)
        #expect(plan.operation == .sum)
        #expect(plan.targets.first?.role == .filter)
        #expect(plan.targets.first?.entityType == .card)
    }

    @Test func typedValidationOutcome_canRepresentExecutableClarificationAndUnsupportedShells() {
        let candidate = MarinaQueryPlanCandidate(
            source: .deterministic,
            rawPrompt: "average Food & Drink",
            operation: .average,
            measure: .spend,
            confidence: .low
        )
        let clarification = MarinaTypedClarification(
            kind: .missingDateRange,
            message: "Which period should I average?",
            candidate: candidate,
            choices: [
                MarinaClarificationChoice(title: "This month", rawValue: "this month")
            ]
        )
        let unsupported = MarinaTypedUnsupportedResponse(
            kind: .unsupportedCombination,
            message: "That query shape is not supported yet.",
            candidate: candidate
        )

        let clarificationOutcome = MarinaPlanValidationOutcome.clarification(clarification)
        let unsupportedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)

        guard case .clarification(let resolvedClarification) = clarificationOutcome else {
            Issue.record("Expected clarification validation outcome")
            return
        }
        #expect(resolvedClarification.kind == .missingDateRange)
        #expect(resolvedClarification.message == "Which period should I average?")

        guard case .unsupported(let resolvedUnsupported) = unsupportedOutcome else {
            Issue.record("Expected unsupported validation outcome")
            return
        }
        #expect(resolvedUnsupported.kind == .unsupportedCombination)
        #expect(resolvedUnsupported.message == "That query shape is not supported yet.")
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func assertDateRange(
        _ actual: HomeQueryDateRange?,
        equals expected: HomeQueryDateRange
    ) {
        guard let actual else {
            Issue.record("Expected date range")
            return
        }

        #expect(actual.startDate == expected.startDate)
        #expect(actual.endDate == expected.endDate)
    }
}
