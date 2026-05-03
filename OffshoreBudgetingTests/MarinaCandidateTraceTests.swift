import Foundation
import Testing
@testable import Offshore

struct MarinaCandidateTraceTests {
    @Test func trace_emptyCandidateKeepsPlaceholdersEmpty() {
        let trace = MarinaCandidateTrace()

        #expect(trace.interpreterSource == nil)
        #expect(trace.operation == nil)
        #expect(trace.measure == nil)
        #expect(trace.entityMentionSummaries.isEmpty)
        #expect(trace.timeScopeSummaries.isEmpty)
        #expect(trace.validatorOutcomeSummary == nil)
        #expect(trace.executablePlanSummary == nil)
        #expect(trace.compactSummary.isEmpty)
    }

    @Test func trace_candidateRecordsSourceOperationMeasureAndResponseHint() {
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "total spend on my Apple Card",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .filter, rawText: "Apple Card", typeHint: .card, confidence: .high)
            ],
            responseShapeHint: .scalarCurrency,
            confidence: .high
        )

        let trace = MarinaCandidateTrace(candidate: candidate)

        #expect(trace.interpreterSource == .foundationModels)
        #expect(trace.operation == .sum)
        #expect(trace.measure == .spend)
        #expect(trace.responseShapeHint == .scalarCurrency)
        #expect(trace.entityMentionSummaries == ["filter:card:Apple Card:high"])
        #expect(trace.compactSummary.contains("source=foundationModels"))
        #expect(trace.compactSummary.contains("operation=sum"))
        #expect(trace.compactSummary.contains("responseHint=scalarCurrency"))
    }

    @Test func trace_multiMentionSimulationPreservesEntityRoles() {
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "if I increase Shopping, what will I have left for Transportation?",
            operation: .simulate,
            measure: .remainingBudget,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .simulationInput, rawText: "Shopping", typeHint: .category, confidence: .high),
                MarinaUnresolvedEntityMention(role: .simulationOutput, rawText: "Transportation", typeHint: .category, confidence: .medium)
            ],
            timeScopes: [
                MarinaUnresolvedTimeScope(role: .simulationHorizon, rawText: "current period", periodUnitHint: .month)
            ],
            responseShapeHint: .scalarCurrency,
            confidence: .medium
        )

        let trace = MarinaCandidateTrace(candidate: candidate)

        #expect(trace.entityMentionSummaries.count == 2)
        #expect(trace.entityMentionSummaries[0].hasPrefix("simulationInput:category:Shopping"))
        #expect(trace.entityMentionSummaries[1].hasPrefix("simulationOutput:category:Transportation"))
        #expect(trace.timeScopeSummaries == ["simulationHorizon:current period:month:unresolved"])
    }

    @Test func trace_recordsValidatorAndExecutablePlanPlaceholdersWithoutRuntimeIntegration() {
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "where is my money going?",
            operation: .rank,
            measure: .spend,
            grouping: MarinaGroupingCandidate(dimension: .category, rawText: "money going"),
            ranking: MarinaRankingCandidate(direction: .top, limit: 5, rawText: "where"),
            responseShapeHint: .rankedList,
            confidence: .medium
        )

        let trace = MarinaCandidateTrace(
            candidate: candidate,
            validatorOutcomeSummary: "pending",
            executablePlanSummary: "not_executable_phase_1"
        )

        #expect(trace.groupingSummary == "category:money going")
        #expect(trace.rankingSummary == "top:5:where")
        #expect(trace.validatorOutcomeSummary == "pending")
        #expect(trace.executablePlanSummary == "not_executable_phase_1")
        #expect(trace.compactSummary.contains("validator=pending"))
        #expect(trace.compactSummary.contains("plan=not_executable_phase_1"))
    }

    @Test func responseShapeHint_isAdvisoryOnly() {
        #expect(MarinaResponseShapeHint.scalarCurrency.isAdvisory)
        #expect(MarinaResponseShapeHint.comparison.isAdvisory)
        #expect(MarinaResponseShapeHint.rankedList.isAdvisory)
        #expect(MarinaResponseShapeHint.groupedBreakdown.isAdvisory)
        #expect(MarinaResponseShapeHint.chartRows.isAdvisory)
    }
}
