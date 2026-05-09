import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaSharedPipelineParityTests {
    @Test func parity_broadSpendMatchesLegacyMetricFamily() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await run("What did I spend this month?", fixture: fixture)

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, _) = result else {
            Issue.record("Expected broad spend to be handled: \(result.trace.compactSummary)")
            return
        }
        #expect(homeQueryPlan?.metric == .spendTotal)
        #expect(answer.kind == .metric)
        guard case .scalar(let scalar) = aggregationResult else {
            Issue.record("Expected scalar broad spend.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("600"))
    }

    @Test func parity_categorySpendPreservesResolvedTarget() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await run("What did I spend on Groceries this month?", fixture: fixture)

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, _) = result else {
            Issue.record("Expected category spend to be handled.")
            return
        }
        #expect(homeQueryPlan?.metric == .categorySpendTotal)
        #expect(homeQueryPlan?.targetName == "Groceries")
        #expect(answer.kind == .metric)
        guard case .scalar(let scalar) = aggregationResult else {
            Issue.record("Expected scalar category spend.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("300"))
    }

    @Test func parity_cardSpendPreservesResolvedTarget() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()
        let result = await run("What is the total spend on my Apple Card?", fixture: fixture)

        guard case .handled(_, let aggregationResult, let homeQueryPlan, _) = result else {
            Issue.record("Expected card spend to be handled.")
            return
        }
        #expect(homeQueryPlan?.metric == .cardSpendTotal)
        #expect(homeQueryPlan?.targetName == "Apple Card")
        guard case .scalar(let scalar) = aggregationResult else {
            Issue.record("Expected scalar card spend.")
            return
        }
        #expect((scalar.renderedValue ?? "").filter(\.isNumber).contains("500"))
    }

    @Test func parity_comparisonPreservesShapeAndRanges() async throws {
        let fixture = try makeFixture()
        try fixture.seedComparisonData()
        let result = await run("Compare Groceries this month to last month", fixture: fixture)

        guard case .handled(let answer, let aggregationResult, let homeQueryPlan, _) = result else {
            Issue.record("Expected comparison to be handled: \(result.trace.compactSummary)")
            return
        }
        #expect(homeQueryPlan?.metric == .categoryMonthComparison)
        #expect(homeQueryPlan?.targetName == "Groceries")
        #expect(homeQueryPlan?.comparisonDateRange != nil)
        #expect(answer.kind == .comparison)
        guard case .comparison = aggregationResult else {
            Issue.record("Expected comparison result shape.")
            return
        }
    }

    @Test func parity_whereMoneyGoingAndTopCategoriesStayRankedLists() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        for prompt in ["Where is my money going?", "Show my top categories this month"] {
            let result = await run(prompt, fixture: fixture)
            guard case .handled(let answer, let aggregationResult, let homeQueryPlan, _) = result else {
                Issue.record("Expected ranked prompt to be handled: \(prompt)")
                continue
            }
            #expect(homeQueryPlan?.metric == .topCategories)
            #expect(answer.kind == .list)
            guard case .rankedList(let list) = aggregationResult else {
                Issue.record("Expected ranked-list result: \(prompt)")
                continue
            }
            #expect(list.rows.isEmpty == false)
        }
    }

    @Test func parity_largestTransactionsStaySharedPathWithoutLegacyFallback() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        let cases: [(String, Int?)] = [
            ("What were my biggest purchases this month?", nil)
        ]

        for (prompt, expectedLimit) in cases {
            let result = await run(prompt, fixture: fixture)
            guard case .handled(_, _, let plan, let trace) = result else {
                Issue.record("Expected largest-transactions prompt to be handled: \(prompt)")
                continue
            }
            #expect(trace.selectedPath != .sharedAttemptedThenLegacyFallback)
            #expect(plan?.metric == .largestTransactions)
            if let expectedLimit {
                #expect(plan?.resultLimit == expectedLimit)
            }
        }
    }

    @Test func parity_explicitUnsupportedPromptsBlockInsteadOfApproximating() async throws {
        let fixture = try makeFixture()
        try fixture.seedSpendData()

        for prompt in [
            "average Groceries for the last 3 months",
            "If I increase Shopping by $100, what will I have left for Transportation?",
            "What did I spend on Unknown this month?"
        ] {
            let result = await run(prompt, fixture: fixture)
            guard case .validationBlocked(let answer, let outcome, let trace) = result else {
                Issue.record("Expected unsupported prompt to be blocked: \(prompt)")
                continue
            }
            #expect(answer.kind == .message)
            switch outcome {
            case .clarification, .unsupported:
                break
            case .executable:
                Issue.record("Blocked prompt should not carry an executable validation outcome: \(prompt)")
            }
            #expect(trace.selectedPath == .sharedHeuristic)
            #expect(trace.fallbackReason == nil)
            #expect(trace.executorResultSummary == nil)
        }
    }

    @Test func parity_ambiguousTargetFallsBackForClarification() async throws {
        let fixture = try makeFixture()
        fixture.context.insert(Offshore.Category(name: "Apple", hexColor: "#00AA00", workspace: fixture.workspace))
        fixture.context.insert(Card(name: "Apple", workspace: fixture.workspace))
        try fixture.context.save()

        let model = SharedPipelineStubStructuredInterpreter(
            structuredIntent: .query(
                MarinaStructuredQueryIntent(
                    metricRaw: "spendTotal",
                    targetName: "Apple",
                    targetTypeRaw: nil,
                    dateStartISO8601: "2026-05-01",
                    dateEndISO8601: "2026-06-01",
                    comparisonDateStartISO8601: nil,
                    comparisonDateEndISO8601: nil,
                    resultLimit: nil,
                    periodUnitRaw: "month",
                    confidenceRaw: "high",
                    clarification: nil
                )
            )
        )

        let result = await MarinaSharedPipelineCoordinator(
            availability: SharedPipelineStubAvailability(status: .available),
            structuredInterpreter: model
        ).run(
            prompt: "Apple",
            context: sharedContext(fixture: fixture, aiOptInEnabled: true)
        )

        guard case .validationBlocked(_, let outcome, let trace) = result else {
            Issue.record("Ambiguous target should not execute: \(result.trace.compactSummary)")
            return
        }
        guard case .clarification(let clarification) = outcome else {
            Issue.record("Expected typed clarification.")
            return
        }
        #expect(clarification.kind == .ambiguousTarget)
        #expect(trace.selectedPath == .sharedFoundationModels)
        #expect(trace.fallbackReason == nil)
        #expect(trace.validatorOutcomeSummary?.contains("clarification") == true)
    }

    private func run(
        _ prompt: String,
        fixture: MarinaPhase5Fixture
    ) async -> MarinaSharedPipelineRuntimeResult {
        await MarinaSharedPipelineCoordinator().run(
            prompt: prompt,
            context: sharedContext(fixture: fixture)
        )
    }
}
