import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaExecutionTraceTests {
    private static let prompts: [String] = [
        "What did I spend this month?",
        "How much did I spend last week?",
        "How much did I spend on Food & Drink this period?",
        "What did I spend on my Apple Card this month?",
        "How much did I spend on Food & Drink this period compared to last period?",
        "Compare groceries this month to last month.",
        "Did I spend more on restaurants this month than last month?",
        "How did my Apple Card spending change from March to April?",
        "What is my average grocery spending?",
        "What do I usually spend on Food & Drink per month?",
        "What are my top categories this month?",
        "Where is most of my money going?",
        "What merchants did I spend the most at?",
        "What percent of my spending was Food & Drink?",
        "Break down my spending by category this month.",
        "How am I doing this month?",
        "How is my budget looking?",
        "If I spend $50 on Food & Drink, how will that affect my budget?",
        "If I buy something for $120 today, can I still stay within my safe spend?"
    ]

    @Test func routerTrace_marksWhenFallbackReplacesModelOutput() async {
        MarinaTraceRecorder.shared.reset()
        let router = MarinaLanguageRouter(
            availability: TraceStubAvailability(status: .available),
            modelService: TraceStubInterpreter(
                result: .success(
                    .query(
                        MarinaStructuredQueryIntent(
                            metricRaw: HomeQueryMetric.overview.rawValue,
                            targetName: nil,
                            targetTypeRaw: nil,
                            dateStartISO8601: "2026-04-01",
                            dateEndISO8601: "2026-04-30",
                            comparisonDateStartISO8601: nil,
                            comparisonDateEndISO8601: nil,
                            resultLimit: nil,
                            periodUnitRaw: HomeQueryPeriodUnit.month.rawValue,
                            confidenceRaw: HomeQueryConfidenceBand.high.rawValue,
                            clarification: nil
                        )
                    )
                )
            )
        )

        let prompt = "What did I spend last week"
        MarinaTraceRecorder.shared.begin(prompt: prompt, routingMode: .modelRouter, marinaNLQv1Enabled: false)
        _ = await router.interpret(
            prompt: prompt,
            context: makeRouterContext(
                priorQueryContext: MarinaPriorQueryContext(
                    lastQueryPlan: HomeQueryPlan(
                        metric: .spendTotal,
                        dateRange: weekRange(),
                        resultLimit: nil,
                        confidenceBand: .high,
                        periodUnit: .week
                    ),
                    lastMetric: .spendTotal,
                    lastTargetName: nil,
                    lastTargetType: nil,
                    lastDateRange: weekRange(),
                    lastResultLimit: nil,
                    lastPeriodUnit: .week
                )
            ),
            heuristicFallback: {
                .query(
                    HomeQueryPlan(
                        metric: .spendTotal,
                        dateRange: weekRange(),
                        resultLimit: nil,
                        confidenceBand: .medium,
                        periodUnit: .week
                    ),
                    source: .contextual
                )
            }
        )
        let trace = MarinaTraceRecorder.shared.finish()

        #expect(trace?.fallbackReplacedModelOutput == true)
        #expect(trace?.fallbackSelectionReason == .preferHeuristicQuery)
        #expect(trace?.selectedRoute == .fallback)
    }

    @Test func diagnosticMatrixHelper_emitsTraceSummariesForBothModes() async throws {
        MarinaTraceRecorder.shared.reset()
        let modelRouterResults = await runDiagnosticPromptMatrix(mode: .modelRouter)
        let nlqResults = await runDiagnosticPromptMatrix(mode: .nlqAuthoritative)

        #expect(modelRouterResults.count == Self.prompts.count)
        #expect(nlqResults.count == Self.prompts.count)

        for result in modelRouterResults + nlqResults {
            #expect(result.routingMode.isEmpty == false)
            #expect(result.selectedRoute.isEmpty == false)
            #expect(result.aggregationPath != nil)
            #expect(result.responseType != nil)
        }
    }

    @Test func nlqTrace_targetedComparison_preservesTargetAndComparisonRange() throws {
        let pipeline = try makePipeline()
        MarinaTraceRecorder.shared.begin(
            prompt: "Compare groceries this month to last month.",
            routingMode: .nlqAuthoritative,
            marinaNLQv1Enabled: true
        )
        _ = pipeline.run(prompt: "Compare groceries this month to last month.", activeBudgetPeriod: nil, now: Date())
        let trace = MarinaTraceRecorder.shared.finish()

        #expect(trace?.normalizedMetric == "monthComparison")
        #expect(trace?.targetText?.contains("groceries") == true)
        #expect(trace?.comparisonDateRangeSummary != nil)
    }

    @Test func nlqTrace_whatIfPrompt_marksUnsupportedClarificationPath() throws {
        let pipeline = try makePipeline()
        MarinaTraceRecorder.shared.begin(
            prompt: "If I spend $50 on Food & Drink, how will that affect my budget?",
            routingMode: .nlqAuthoritative,
            marinaNLQv1Enabled: true
        )
        let result = pipeline.run(
            prompt: "If I spend $50 on Food & Drink, how will that affect my budget?",
            activeBudgetPeriod: nil,
            now: Date()
        )
        let trace = MarinaTraceRecorder.shared.finish()

        guard case .clarification = result else {
            Issue.record("Expected clarification result for unsupported what-if prompt")
            return
        }
        #expect(trace?.selectedRoute == .clarification)
        #expect(trace?.selectedRouteReason?.contains("unsupported") == true || trace?.selectedRouteReason?.contains("clarification") == true)
        #expect(trace?.normalizedMetric == nil)
    }

    @Test func trace_recordsInterpreterAndResponseSurfaceSeparately() throws {
        MarinaTraceRecorder.shared.reset()
        MarinaTraceRecorder.shared.begin(
            prompt: "What did I spend this month?",
            routingMode: .sharedPipeline,
            marinaNLQv1Enabled: false
        )
        MarinaTraceRecorder.shared.recordSelectedRoute(.sharedFoundationModels, reason: "model interpreted")
        MarinaTraceRecorder.shared.recordResponseSurface(
            source: .foundationModelsSurface,
            fallbackReason: nil
        )
        let trace = MarinaTraceRecorder.shared.finish()
        let snapshot = trace.map(MarinaExecutionTraceSnapshot.init)

        #expect(trace?.selectedRoute == .sharedFoundationModels)
        #expect(trace?.responseSurfaceSource == .foundationModelsSurface)
        #expect(trace?.responseSurfaceFallbackReason == nil)
        #expect(snapshot?.responseSurfaceSource == "foundationModelsSurface")
        #expect(snapshot?.accessibilityValue.contains("responseSurface=foundationModelsSurface") == true)
    }

    private func runDiagnosticPromptMatrix(mode: MarinaExecutionRoutingMode) async -> [PromptTraceResult] {
        switch mode {
        case .modelRouter:
            return await runModelRouterMatrix()
        case .nlqAuthoritative:
            return (try? runNLQMatrix()) ?? []
        case .sharedPipeline:
            return await runModelRouterMatrix()
        }
    }

    private func runModelRouterMatrix() async -> [PromptTraceResult] {
        let router = MarinaLanguageRouter(
            availability: TraceStubAvailability(status: .unavailable(reason: "test_unavailable")),
            modelService: TraceStubInterpreter(result: .success(.unresolved))
        )
        let parser = HomeAssistantTextParser()

        var results: [PromptTraceResult] = []
        for prompt in Self.prompts {
            MarinaTraceRecorder.shared.begin(prompt: prompt, routingMode: .modelRouter, marinaNLQv1Enabled: false)
            let interpreted = await router.interpret(
                prompt: prompt,
                context: makeRouterContext(),
                heuristicFallback: {
                    if let plan = parser.parsePlan(prompt, defaultPeriodUnit: .month) {
                        return .query(plan, source: .parser)
                    }
                    return .unresolved
                }
            )

            let trace = MarinaTraceRecorder.shared.finish()
            results.append(PromptTraceResult.from(trace: trace, interpreted: interpreted))
        }

        return results
    }

    private func runNLQMatrix() throws -> [PromptTraceResult] {
        let pipeline = try makePipeline()
        var results: [PromptTraceResult] = []

        for prompt in Self.prompts {
            MarinaTraceRecorder.shared.begin(prompt: prompt, routingMode: .nlqAuthoritative, marinaNLQv1Enabled: true)
            let result = pipeline.run(prompt: prompt, activeBudgetPeriod: nil, now: Date())
            let trace = MarinaTraceRecorder.shared.finish()
            results.append(PromptTraceResult.from(trace: trace, nlqResult: result))
        }

        return results
    }

    private func makePipeline() throws -> MarinaNLQPipeline {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Workspace.self,
            Budget.self,
            Category.self,
            PlannedExpense.self,
            VariableExpense.self,
            Card.self,
            Preset.self,
            Income.self,
            AllocationAccount.self,
            SavingsAccount.self,
            configurations: config
        )
        let context = ModelContext(container)
        let workspace = Workspace(name: "Trace Matrix Workspace", hexColor: "#3B82F6")
        context.insert(workspace)

        let provider = MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
        return MarinaNLQPipeline(provider: provider, defaultPeriodUnit: .month)
    }

    private func makeRouterContext(
        priorQueryContext: MarinaPriorQueryContext = MarinaPriorQueryContext(
            lastQueryPlan: nil,
            lastMetric: nil,
            lastTargetName: nil,
            lastTargetType: nil,
            lastDateRange: nil,
            lastResultLimit: nil,
            lastPeriodUnit: nil
        )
    ) -> MarinaLanguageRouterContext {
        MarinaLanguageRouterContext(
            workspaceName: "Trace Workspace",
            defaultPeriodUnit: .month,
            sessionContext: HomeAssistantSessionContext(),
            priorQueryContext: priorQueryContext,
            cardNames: ["Apple Card"],
            categoryNames: ["Food & Drink", "Groceries", "Restaurants"],
            incomeSourceNames: ["Salary"],
            presetTitles: ["Rent"],
            budgetNames: ["Main Budget"],
            aliasSummaries: [],
            now: Date()
        )
    }

    private func weekRange() -> HomeQueryDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        let start = calendar.date(byAdding: .weekOfYear, value: -1, to: currentWeek?.start ?? now) ?? now
        let end = calendar.date(byAdding: .second, value: -1, to: calendar.date(byAdding: .weekOfYear, value: 1, to: start) ?? start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }
}

private struct PromptTraceResult: Equatable {
    let prompt: String
    let routingMode: String
    let selectedRoute: String
    let modelOutputSummary: String?
    let fallbackOutputSummary: String?
    let fallbackReplacedModelOutput: Bool
    let selectedExecutableRequest: String?
    let operationOrMetric: String?
    let target: String?
    let dateRange: String?
    let comparisonDateRange: String?
    let aggregationPath: String?
    let responseType: String?
    let finalAnswerSummary: String?

    static func from(trace: MarinaExecutionTrace?, interpreted: MarinaInterpretedRequest) -> PromptTraceResult {
        let fallbackResponseType: String = {
            switch interpreted {
            case .query:
                return "query"
            case .command:
                return "command"
            case .clarification:
                return "clarification"
            case .unresolved:
                return "unresolved"
            }
        }()
        return PromptTraceResult(
            prompt: trace?.originalPrompt ?? "",
            routingMode: trace?.routingMode.rawValue ?? "",
            selectedRoute: trace?.selectedRoute.rawValue ?? "",
            modelOutputSummary: trace?.modelOutputSummary,
            fallbackOutputSummary: trace?.fallbackOutputSummary,
            fallbackReplacedModelOutput: trace?.fallbackReplacedModelOutput ?? false,
            selectedExecutableRequest: interpreted.traceSummary,
            operationOrMetric: trace?.normalizedOperation ?? trace?.normalizedMetric,
            target: trace?.resolvedTargetSummary ?? trace?.targetText,
            dateRange: trace?.primaryDateRangeSummary,
            comparisonDateRange: trace?.comparisonDateRangeSummary,
            aggregationPath: trace?.aggregationPath ?? "home_query_engine",
            responseType: trace?.responseType ?? fallbackResponseType,
            finalAnswerSummary: trace?.finalAnswerSummary
        )
    }

    static func from(trace: MarinaExecutionTrace?, nlqResult: MarinaNLQPipelineResult) -> PromptTraceResult {
        let executable: String
        switch nlqResult {
        case .answer(let answer, _):
            executable = "answer:\(answer.kind.rawValue)"
        case .clarification:
            executable = "clarification"
        case .recovery:
            executable = "recovery"
        }

        return PromptTraceResult(
            prompt: trace?.originalPrompt ?? "",
            routingMode: trace?.routingMode.rawValue ?? "",
            selectedRoute: trace?.selectedRoute.rawValue ?? "",
            modelOutputSummary: trace?.modelOutputSummary,
            fallbackOutputSummary: trace?.fallbackOutputSummary,
            fallbackReplacedModelOutput: trace?.fallbackReplacedModelOutput ?? false,
            selectedExecutableRequest: executable,
            operationOrMetric: trace?.normalizedOperation ?? trace?.normalizedMetric,
            target: trace?.resolvedTargetSummary ?? trace?.targetText,
            dateRange: trace?.primaryDateRangeSummary,
            comparisonDateRange: trace?.comparisonDateRangeSummary,
            aggregationPath: trace?.aggregationPath ?? "none",
            responseType: trace?.responseType ?? executable,
            finalAnswerSummary: trace?.finalAnswerSummary
        )
    }
}

private struct TraceStubAvailability: MarinaModelAvailabilityProviding {
    let status: MarinaModelAvailability.Status

    func currentStatus() -> MarinaModelAvailability.Status {
        status
    }
}

private struct TraceStubInterpreter: MarinaStructuredIntentInterpreting {
    let result: Result<MarinaStructuredIntent, Error>

    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent {
        try result.get()
    }
}
