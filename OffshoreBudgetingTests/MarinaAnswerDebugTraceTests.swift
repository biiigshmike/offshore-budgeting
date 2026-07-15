import Foundation
import Testing
@testable import Offshore

struct MarinaAnswerDebugTraceTests {
    @Test func qaTraceExposesPreciseCompilerAttemptRejectionBeforeTerminalResult() throws {
        let request = MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: .modelGenerationFailed
        )
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: request,
            dateRange: nil,
            comparisonDateRange: nil,
            now: .now
        )
        let diagnostic = MarinaFoundationModelAttemptDiagnostic(
            attempt: 1,
            compilerVersion: "marina.semantic-compiler.v3",
            stage: .alignment,
            status: .rejected,
            rejection: .alignment(.measureMismatch),
            alignmentVerdict: .rejected,
            generatedIntent: MarinaFoundationModelGeneratedIntentDigest(
                intent: .query,
                entity: .workspace,
                projection: .records,
                operation: .list
            ),
            compiledRequest: MarinaFoundationModelCompiledRequestDigest(request: request),
            alignment: nil
        )
        let trace = MarinaAnswerDebugTrace(
            originalPrompt: "Show category availability.",
            promptTreatment: .standalone,
            priorContextChangedRequest: false,
            interpretedRequest: request,
            interpretedSource: .unavailableFallback,
            interpretedConfidence: .low,
            interpretedNotes: [],
            compilerAttempts: [diagnostic],
            candidateSearches: [],
            resolverOutput: request,
            validatorOutput: request,
            validatorAccepted: false,
            validatorNotes: [],
            queryPlan: MarinaQueryPlanTrace(plan: plan),
            executionRoute: .universal,
            executionSucceeded: false,
            rowCount: 0,
            evidenceRowSummaries: [],
            answerKind: .message,
            answerTitle: "I can't answer that yet",
            answerPrimaryValue: nil,
            narrationRequested: false
        )

        #expect(trace.debugDescription.contains("compilerAttempts=FoundationModels attempt=1"))
        #expect(trace.debugDescription.contains("compilerVersion=marina.semantic-compiler.v3"))
        #expect(trace.debugDescription.contains("rejectionCode=alignment.measureMismatch"))
        #expect(trace.debugDescription.contains("generatedIntent={intent=query;entity=workspace"))
        #expect(trace.debugDescription.contains("compiledRequest={entity=workspace"))
        let rejectionIndex = try #require(trace.debugDescription.range(of: "rejectionCode=alignment.measureMismatch")?.lowerBound)
        let terminalIndex = try #require(trace.debugDescription.range(of: "unsupported=modelGenerationFailed")?.lowerBound)
        #expect(rejectionIndex < terminalIndex)
    }
}
