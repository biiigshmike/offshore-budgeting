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
}
