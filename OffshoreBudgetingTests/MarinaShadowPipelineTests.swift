import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaShadowPipelineTests {
    @Test func shadowPipeline_heuristicPromptExecutesThroughSharedBridge() throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let candidate = MarinaHeuristicInterpreter().interpret(
            prompt: "total spend on my Apple Card",
            defaultPeriodUnit: .month
        )

        let result = try run(candidate: candidate, provider: fixture.provider, now: date(2026, 5, 15))

        guard case .scalar(let scalar) = result else {
            Issue.record("Expected heuristic card spend to execute as scalar.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("500"))
    }

    @Test func shadowPipeline_foundationModelsFixtureExecutesThroughSharedBridge() throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let candidate = MarinaFoundationModelsInterpreter().candidate(
            from: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "cardSpendTotal",
                    targetName: "Apple Card",
                    targetTypeRaw: "card",
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            ),
            prompt: "total spend on my Apple Card",
            defaultPeriodUnit: .month
        )

        let result = try run(candidate: candidate, provider: fixture.provider, now: date(2026, 5, 15))

        guard case .scalar(let scalar) = result else {
            Issue.record("Expected model card spend fixture to execute as scalar.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("500"))
    }

    @Test func shadowPipeline_heuristicAndModelPromptFamiliesProduceCompatibleResultShape() throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let heuristic = MarinaHeuristicInterpreter().interpret(
            prompt: "where is my money going?",
            defaultPeriodUnit: .month
        )
        let model = MarinaFoundationModelsInterpreter().candidate(
            from: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "topCategories",
                    targetName: nil,
                    targetTypeRaw: nil,
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: 3,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            ),
            prompt: "where is my money going?",
            defaultPeriodUnit: .month
        )

        let heuristicResult = try run(candidate: heuristic, provider: fixture.provider, now: date(2026, 5, 15))
        let modelResult = try run(candidate: model, provider: fixture.provider, now: date(2026, 5, 15))

        guard case .rankedList(let heuristicList) = heuristicResult,
              case .rankedList(let modelList) = modelResult else {
            Issue.record("Expected both interpreters to produce ranked-list results.")
            return
        }
        #expect(heuristicList.rows.isEmpty == false)
        #expect(modelList.rows.isEmpty == false)
    }

    @Test func shadowPipeline_unsupportedPromptDoesNotExecute() throws {
        let fixture = try makeFixture()
        let candidate = MarinaQueryPlanCandidate(
            source: .heuristic,
            rawPrompt: "if I increase Shopping by $100",
            operation: .simulate,
            measure: .remainingBudget,
            confidence: .medium
        )
        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)
        let outcome = MarinaQueryValidator().validate(resolved)
        let result = MarinaAggregationExecutor().execute(outcome: outcome, provider: fixture.provider)

        guard case .unsupported = result else {
            Issue.record("Unsupported simulation should not execute.")
            return
        }
    }

    @Test func shadowPipeline_ambiguousTargetClarifiesAndDoesNotExecute() throws {
        let fixture = try makeFixture()
        fixture.context.insert(Offshore.Category(name: "Apple", hexColor: "#00AA00", workspace: fixture.workspace))
        fixture.context.insert(Card(name: "Apple", workspace: fixture.workspace))
        try fixture.context.save()
        let candidate = MarinaQueryPlanCandidate(
            source: .foundationModels,
            rawPrompt: "spend on Apple",
            operation: .sum,
            measure: .spend,
            entityMentions: [
                MarinaUnresolvedEntityMention(role: .primaryTarget, rawText: "Apple", typeHint: nil)
            ],
            confidence: .high
        )

        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: fixture.provider)
        let outcome = MarinaQueryValidator().validate(resolved)
        let executionResult = MarinaAggregationExecutor().execute(outcome: outcome, provider: fixture.provider)

        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected ambiguous target clarification.")
            return
        }
        #expect(clarification.kind == .ambiguousTarget)
        guard case .unsupported = executionResult else {
            Issue.record("Clarification outcome should not execute.")
            return
        }
    }

    private func run(
        candidate: MarinaQueryPlanCandidate,
        provider: MarinaDataProvider,
        now: Date
    ) throws -> MarinaAggregationResult {
        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: provider)
        let outcome = MarinaQueryValidator().validate(resolved)
        switch MarinaAggregationPlanHomeQueryAdapter().executablePlan(from: outcome) {
        case .success(let executable):
            return MarinaAggregationExecutor().execute(executable, provider: provider, now: now)
        case .failure(let unsupported):
            throw TestFailure(message: unsupported.message)
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }

    private struct TestFailure: Error {
        let message: String
    }
}
