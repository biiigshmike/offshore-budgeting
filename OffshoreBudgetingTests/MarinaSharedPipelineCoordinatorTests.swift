import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaSharedPipelineCoordinatorTests {
    @Test func coordinator_gateOffFallsBackWithoutRunningSharedPipeline() async throws {
        let fixture = try makeFixture()
        let result = await coordinator().run(
            prompt: "What did I spend this month?",
            context: sharedContext(fixture: fixture, sharedPipelineEnabled: false)
        )

        guard case .fallbackToLegacy(let trace) = result else {
            Issue.record("Gate-off shared pipeline should fall back to legacy.")
            return
        }
        #expect(trace.fallbackReason == .gateDisabled)
        #expect(trace.selectedPath == .legacy)
        #expect(trace.candidateSummary == nil)
    }

    @Test func coordinator_gateOnAIOptOutUsesHeuristicInterpreter() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator().run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: false)
        )

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected heuristic shared pipeline to handle card spend.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.interpreterSource == .heuristic)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
        #expect(answer.kind == .metric)
        guard case .scalar(let scalar) = aggregationResult else {
            Issue.record("Expected scalar result.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("500"))
    }

    @Test func coordinator_aiUnavailableFallsBackToHeuristic() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator(availability: SharedPipelineStubAvailability(status: .unavailable(reason: "test_unavailable"))).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("AI unavailable should still allow heuristic execution.")
            return
        }
        #expect(trace.modelAvailabilitySummary == "unavailable:test_unavailable")
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_modelServiceFailureFallsBackToHeuristicWithTrace() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await coordinator(structuredInterpreter: SharedPipelineThrowingStructuredInterpreter()).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Model service failure should not crash and should use heuristic.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.disagreementSummary == MarinaSharedPipelineFallbackReason.modelServiceFailed.rawValue)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_modelSelectedWhenOptedInAvailableAndExecutable() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "cardSpendTotal",
                    targetName: "Apple Card",
                    targetTypeRaw: "card",
                    dateStartISO8601: nil,
                    dateEndISO8601: nil,
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected executable model candidate to handle.")
            return
        }
        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(trace.interpreterSource == .foundationModels)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_litterRobotBadModelMetricRoutesToDatabaseLookupInsteadOfLegacyUnresolved() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(VariableExpense(
            descriptionText: "Litter Robot",
            amount: 699,
            transactionDate: sharedPipelineDate(2025, 1, 14),
            workspace: fixture.workspace,
            card: fixture.appleCard,
            category: fixture.groceries
        ))
        try fixture.context.save()

        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "card_purchase_date",
                    targetName: "Litter Robot",
                    targetTypeRaw: "entity",
                    dateStartISO8601: "2025-01-01",
                    dateEndISO8601: "2025-12-31",
                    comparisonDateStartISO8601: "2025-01-01",
                    comparisonDateEndISO8601: "2025-12-31",
                    resultLimit: 1,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(
            availability: SharedPipelineStubAvailability(status: .available),
            structuredInterpreter: model
        ).run(
            prompt: "When did I purchase Litter Robot?",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(let answer, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected Litter Robot lookup to be handled by shared pipeline.")
            return
        }

        #expect(homeQueryPlan == nil)
        #expect(trace.selectedPath == .sharedFoundationModels || trace.selectedPath == .sharedHeuristic)
        #expect(trace.compactSummary.contains("family=databaseLookup"))
        #expect(trace.compactSummary.contains("searchText=\"Litter Robot\""))
        #expect(answer.title.contains("Litter Robot"))
    }

    @Test func coordinator_workspaceAggregationPromptsUseSharedHeuristicWithoutLegacyFallback() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(Income(source: "Salary", amount: 2_500, date: sharedPipelineDate(2026, 5, 5), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(Income(source: "Side Gig", amount: 700, date: sharedPipelineDate(2026, 5, 12), isPlanned: false, workspace: fixture.workspace))
        fixture.context.insert(PlannedExpense(title: "Rent", plannedAmount: 1_500, expenseDate: sharedPipelineDate(2026, 5, 20), workspace: fixture.workspace, card: fixture.appleCard, category: fixture.groceries))
        fixture.context.insert(SavingsLedgerEntry(date: sharedPipelineDate(2026, 5, 3), amount: 400, note: "Period close", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue, workspace: fixture.workspace))
        let shared = AllocationAccount(name: "Roommate", workspace: fixture.workspace)
        fixture.context.insert(shared)
        fixture.context.insert(ExpenseAllocation(allocatedAmount: 225, workspace: fixture.workspace, account: shared))
        try fixture.context.save()

        let prompts = [
            "What paid me the most this month?",
            "What are my biggest upcoming bills?",
            "Largest savings movements this month.",
            "Show shared balances."
        ]

        for prompt in prompts {
            let result = await coordinator().run(
                prompt: prompt,
                context: sharedContext(fixture: fixture, aiOptInEnabled: false)
            )

            guard case .handled(let answer, let aggregationResult, let homeQueryPlan, let trace) = result else {
                Issue.record("Expected workspace aggregation prompt to be handled: \(prompt), actual=\(workspaceAggregationDebugSummary(result))")
                continue
            }
            #expect(homeQueryPlan == nil)
            #expect(trace.selectedPath == .sharedHeuristic)
            #expect(trace.executorResultSummary?.contains("workspaceAggregation=") == true)
            #expect(answer.kind == .list)
            guard case .workspaceCard = aggregationResult else {
                Issue.record("Expected workspace card result for \(prompt)")
                continue
            }
        }
    }

    @Test func coordinator_lowConfidenceModelTriggersHeuristicFallback() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
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
                    confidenceRaw: "low",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Low-confidence model candidate should allow heuristic handling.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.disagreementSummary != nil)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_modelHeuristicDisagreementIsTracedAndNotMerged() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "spendTotal",
                    targetName: nil,
                    targetTypeRaw: nil,
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-05-31",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await coordinator(structuredInterpreter: model).run(
            prompt: "total spend on my Apple Card",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .handled(_, _, let homeQueryPlan, let trace) = result else {
            Issue.record("Expected disagreement to still produce the conservative heuristic answer.")
            return
        }
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.disagreementSummary?.contains("model[") == true)
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
    }

    @Test func coordinator_invalidSharedResultFallsBackToLegacyWithReason() async throws {
        let fixture = try makeFixture()
        let result = await coordinator().run(
            prompt: "total spend on my Missing Card",
            context: sharedContext(fixture: fixture)
        )

        guard case .validationBlocked(let answer, let outcome, let trace) = result else {
            Issue.record("Unknown target should be blocked by typed shared clarification.")
            return
        }
        #expect(answer.kind == .message)
        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected typed clarification.")
            return
        }
        #expect(clarification.kind == .missingTarget)
        #expect(trace.selectedPath == .sharedHeuristic)
        #expect(trace.fallbackReason == nil)
        #expect(trace.validatorOutcomeSummary?.contains("clarification") == true)
    }

    private func coordinator(
        availability: MarinaModelAvailabilityProviding = SharedPipelineStubAvailability(status: .available),
        structuredInterpreter: MarinaStructuredIntentInterpreting = SharedPipelineStubStructuredInterpreter(structuredIntent: .unresolved)
    ) -> MarinaSharedPipelineCoordinator {
        MarinaSharedPipelineCoordinator(
            availability: availability,
            structuredInterpreter: structuredInterpreter
        )
    }

    private func workspaceAggregationDebugSummary(_ result: MarinaSharedPipelineRuntimeResult) -> String {
        switch result {
        case .handled(let answer, _, let plan, let trace):
            return "handled title=\(answer.title) plan=\(plan?.metric.rawValue ?? "nil") trace=\(trace.compactSummary)"
        case .validationBlocked(let answer, let outcome, let trace):
            return "validationBlocked title=\(answer.title) outcome=\(outcome) trace=\(trace.compactSummary)"
        case .fallbackToLegacy(let trace):
            return "fallback trace=\(trace.compactSummary)"
        }
    }
}
