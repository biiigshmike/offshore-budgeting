import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaTraceAnalysisTests {
    @Test func matrixAnalysis_generatesDeterministicRowsForBothModes() async throws {
        let analyzer = try MarinaTraceAnalyzer()
        let report = await analyzer.buildReport()
        let artifacts = try TraceAnalysisArtifactWriter.write(report: report)

        #expect(report.rows.count == 83)
        #expect(report.rowsByGroup[TracePromptGroup.core] == 38)
        #expect(report.rowsByGroup[TracePromptGroup.stressMessyManual202605] == 45)
        let stressPromptModes = Dictionary(
            grouping: report.rows.filter { $0.group == TracePromptGroup.stressMessyManual202605 },
            by: { $0.prompt }
        ).mapValues { Set($0.map(\.mode)) }
        #expect(stressPromptModes.count == 15)
        #expect(stressPromptModes.values.allSatisfy { $0 == Set(["model_router", "nlq_authoritative", "shared_pipeline_heuristic"]) })
        let sharedRows = report.rows.filter { $0.mode == "shared_pipeline_heuristic" }
        #expect(sharedRows.count == 15)
        #expect(sharedRows.allSatisfy { $0.sharedPath?.isEmpty == false })
        #expect(sharedRows.allSatisfy { $0.sharedFailureLayer?.isEmpty == false })
        #expect(sharedRows.allSatisfy { $0.sharedFailureBucket?.isEmpty == false })
        #expect(report.rows.allSatisfy { $0.mode.isEmpty == false })
        #expect(report.rows.allSatisfy { $0.group.isEmpty == false })
        #expect(report.rows.allSatisfy { $0.selectedRoute.isEmpty == false })
        #expect(report.rows.allSatisfy { $0.verdictRaw.isEmpty == false })
        #expect(
            report.rows.allSatisfy { row in
                switch row.mode {
                case "model_router":
                    return row.fallbackSummary != nil || row.modelSummary != nil
                case "nlq_authoritative":
                    // NLQ-authoritative runs may not populate model/fallback summaries.
                    // Route/aggregation/response fields remain the required signal.
                    return true
                case "shared_pipeline_heuristic":
                    return row.sharedPath != nil && row.sharedFailureLayer != nil
                default:
                    return false
                }
            }
        )

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(
            TraceAnalysisReport.self,
            from: Data(contentsOf: artifacts.jsonURL)
        )
        #expect(decoded.rows.count == 83)
        #expect(decoded.rowsByGroup[TracePromptGroup.core] == 38)
        #expect(decoded.rowsByGroup[TracePromptGroup.stressMessyManual202605] == 45)

        let txt = try String(contentsOf: artifacts.txtURL, encoding: .utf8)
        #expect(txt.contains("group: \(TracePromptGroup.core)"))
        #expect(txt.contains("group: \(TracePromptGroup.stressMessyManual202605)"))
        #expect(txt.contains("rowsByGroup"))
        #expect(txt.contains("mode: model_router"))
        #expect(txt.contains("mode: nlq_authoritative"))
        #expect(txt.contains("mode: shared_pipeline_heuristic"))
        #expect(txt.contains("sharedPath: sharedHeuristic"))
        #expect(txt.contains("sharedFailuresByBucket"))
        #expect(txt.contains("sharedFailuresByLayer"))
        #expect(txt.contains("failuresByBucket"))
        #expect(txt.contains("failuresByRootCauseFamily"))
        #expect(txt.contains("nextPhaseRecommendation"))

        print("Marina trace JSON artifact: \(artifacts.jsonURL.path)")
        print("Marina trace TXT artifact: \(artifacts.txtURL.path)")
        if let snapshotJSONURL = artifacts.snapshotJSONURL,
           let snapshotTXTURL = artifacts.snapshotTXTURL {
            print("Marina trace JSON snapshot: \(snapshotJSONURL.path)")
            print("Marina trace TXT snapshot: \(snapshotTXTURL.path)")
        } else if let warning = artifacts.snapshotWriteWarning {
            print("Marina trace snapshot warning: \(warning)")
        }
        print("Marina trace summary: \(report.nextPhaseRecommendation)")
    }
}

private enum TracePromptGroup {
    static let core = "core"
    static let stressMessyManual202605 = "stress_messy_manual_2026_05"
}

@MainActor
private struct MarinaTraceAnalyzer {
    private static let analysisNow = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 5, day: 15, hour: 12)
    )!

    private static let prompts: [PromptExpectation] = [
        .init(prompt: "What did I spend this month?", expectedOperation: "sum", expectedMeasure: "spendTotal", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: nil, expectedPresentationIntent: "metric"),
        .init(prompt: "How much did I spend last week?", expectedOperation: "sum", expectedMeasure: "spendTotal", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "last_week", expectedComparisonDateRange: nil, expectedPresentationIntent: "metric"),
        .init(prompt: "How much did I spend on Food & Drink this period?", expectedOperation: "sum", expectedMeasure: "categorySpendTotal", expectedEntityScope: "category", expectedTarget: "Food & Drink", expectedPrimaryDateRange: "current_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "metric"),
        .init(prompt: "What did I spend on my Apple Card this month?", expectedOperation: "sum", expectedMeasure: "cardSpendTotal", expectedEntityScope: "card", expectedTarget: "Apple Card", expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: nil, expectedPresentationIntent: "metric"),
        .init(prompt: "How much did I spend on Food & Drink this period compared to last period?", expectedOperation: "difference", expectedMeasure: "categoryMonthComparison", expectedEntityScope: "category", expectedTarget: "Food & Drink", expectedPrimaryDateRange: "current_period", expectedComparisonDateRange: "previous_period", expectedPresentationIntent: "comparison"),
        .init(prompt: "Compare groceries this month to last month.", expectedOperation: "difference", expectedMeasure: "categoryMonthComparison", expectedEntityScope: "category", expectedTarget: "groceries", expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: "last_month", expectedPresentationIntent: "comparison"),
        .init(prompt: "Did I spend more on restaurants this month than last month?", expectedOperation: "difference", expectedMeasure: "categoryMonthComparison", expectedEntityScope: "category", expectedTarget: "restaurants", expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: "last_month", expectedPresentationIntent: "comparison"),
        .init(prompt: "How did my Apple Card spending change from March to April?", expectedOperation: "difference", expectedMeasure: "cardMonthComparison", expectedEntityScope: "card", expectedTarget: "Apple Card", expectedPrimaryDateRange: "april", expectedComparisonDateRange: "march", expectedPresentationIntent: "comparison"),
        .init(prompt: "What is my average grocery spending?", expectedOperation: "average", expectedMeasure: "categoryAverageSpend", expectedEntityScope: "category", expectedTarget: "grocery", expectedPrimaryDateRange: "default_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "metric"),
        .init(prompt: "What do I usually spend on Food & Drink per month?", expectedOperation: "average", expectedMeasure: "categoryAverageSpend", expectedEntityScope: "category", expectedTarget: "Food & Drink", expectedPrimaryDateRange: "monthly", expectedComparisonDateRange: nil, expectedPresentationIntent: "metric"),
        .init(prompt: "What are my top categories this month?", expectedOperation: "ranked_list", expectedMeasure: "topCategories", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: nil, expectedPresentationIntent: "list"),
        .init(prompt: "Where is most of my money going?", expectedOperation: "ranked_list", expectedMeasure: "topCategories", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "default_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "list"),
        .init(prompt: "What merchants did I spend the most at?", expectedOperation: "ranked_list", expectedMeasure: "topMerchants", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "default_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "list"),
        .init(prompt: "What percent of my spending was Food & Drink?", expectedOperation: "share_of_total", expectedMeasure: "categorySpendShare", expectedEntityScope: "category", expectedTarget: "Food & Drink", expectedPrimaryDateRange: "default_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "metric"),
        .init(prompt: "Break down my spending by category this month.", expectedOperation: "ranked_list", expectedMeasure: "topCategories", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: nil, expectedPresentationIntent: "list"),
        .init(prompt: "How am I doing this month?", expectedOperation: "overview", expectedMeasure: "overview", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: nil, expectedPresentationIntent: "overview"),
        .init(prompt: "How is my budget looking?", expectedOperation: "overview", expectedMeasure: "overview", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "default_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "overview"),
        .init(prompt: "If I spend $50 on Food & Drink, how will that affect my budget?", expectedOperation: "what_if", expectedMeasure: "simulation", expectedEntityScope: "category", expectedTarget: "Food & Drink", expectedPrimaryDateRange: "current_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "what_if"),
        .init(prompt: "If I buy something for $120 today, can I still stay within my safe spend?", expectedOperation: "what_if", expectedMeasure: "safe_spend_simulation", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "today", expectedComparisonDateRange: nil, expectedPresentationIntent: "what_if"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "Am I spending more on food lately, or is it about normal?", expectedOperation: "difference", expectedMeasure: "categoryMonthComparison", expectedEntityScope: "category", expectedTarget: "food", expectedPrimaryDateRange: "lately", expectedComparisonDateRange: "normal_baseline", expectedPresentationIntent: "comparison"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "How bad was Food & Drink compared to last month?", expectedOperation: "difference", expectedMeasure: "categoryMonthComparison", expectedEntityScope: "category", expectedTarget: "Food & Drink", expectedPrimaryDateRange: "default_period", expectedComparisonDateRange: "last_month", expectedPresentationIntent: "comparison"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "Did groceries go up or down from March to April?", expectedOperation: "difference", expectedMeasure: "categoryMonthComparison", expectedEntityScope: "category", expectedTarget: "groceries", expectedPrimaryDateRange: "april", expectedComparisonDateRange: "march", expectedPresentationIntent: "comparison"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "What card is eating most of my budget this period?", expectedOperation: "ranked_list", expectedMeasure: "topCards", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "current_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "list"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "Which category is hurting me the most right now?", expectedOperation: "ranked_list", expectedMeasure: "topCategories", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "current_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "list"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "Break down where my money went this month, but don’t just give me the total.", expectedOperation: "ranked_list", expectedMeasure: "topCategories", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: nil, expectedPresentationIntent: "list"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "What did I spend on Apple Card outside of Food & Drink?", expectedOperation: "sum", expectedMeasure: "cardSpendExcludingCategory", expectedEntityScope: "card_and_category_filter", expectedTarget: "Apple Card", expectedPrimaryDateRange: "default_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "metric"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "How much of my spending this month was Food & Drink?", expectedOperation: "share_of_total", expectedMeasure: "categorySpendShare", expectedEntityScope: "category", expectedTarget: "Food & Drink", expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: nil, expectedPresentationIntent: "metric"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "Is Shopping over where it should be for this budget?", expectedOperation: "compare_to_limit", expectedMeasure: "categoryBudgetAvailability", expectedEntityScope: "category", expectedTarget: "Shopping", expectedPrimaryDateRange: "current_budget", expectedComparisonDateRange: nil, expectedPresentationIntent: "comparison"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "What category changed the most compared to last month?", expectedOperation: "ranked_list", expectedMeasure: "categoryMonthComparisonRanked", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: "last_month", expectedPresentationIntent: "list"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "What was my average weekly spending on groceries over the last 3 months?", expectedOperation: "average", expectedMeasure: "categoryAverageSpend", expectedEntityScope: "category", expectedTarget: "groceries", expectedPrimaryDateRange: "last_3_months", expectedComparisonDateRange: nil, expectedPresentationIntent: "metric"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "If I keep spending like this, how much will I have left by the end of the period?", expectedOperation: "forecast", expectedMeasure: "projectedRemainingBudget", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "current_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "forecast"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "If I add $75 to Shopping, does Transportation still have room?", expectedOperation: "what_if", expectedMeasure: "simulation", expectedEntityScope: "category_pair", expectedTarget: "Shopping", expectedPrimaryDateRange: "current_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "what_if"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "What expenses are making this month higher than last month?", expectedOperation: "ranked_list", expectedMeasure: "transactionDeltaDrivers", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "this_month", expectedComparisonDateRange: "last_month", expectedPresentationIntent: "list"),
        .init(group: TracePromptGroup.stressMessyManual202605, prompt: "Show me the stuff I’m spending on too often, not necessarily the most money.", expectedOperation: "ranked_list", expectedMeasure: "frequentMerchants", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "default_period", expectedComparisonDateRange: nil, expectedPresentationIntent: "list")
    ]

    private let nlqPipeline: MarinaNLQPipeline
    private let modelRouter: MarinaLanguageRouter
    private let parser: HomeAssistantTextParser
    private let provider: MarinaDataProvider

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Workspace.self,
            Budget.self,
            BudgetCardLink.self,
            BudgetPresetLink.self,
            BudgetCategoryLimit.self,
            Category.self,
            PlannedExpense.self,
            VariableExpense.self,
            Card.self,
            Preset.self,
            Income.self,
            IncomeSeries.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            configurations: config
        )
        let context = ModelContext(container)
        let workspace = Workspace(name: "Trace Analysis Workspace", hexColor: "#3B82F6")
        context.insert(workspace)
        let appleCard = Card(name: "Apple Card", workspace: workspace)
        context.insert(appleCard)
        for categoryName in ["Food & Drink", "Groceries", "Restaurants", "Shopping", "Transportation"] {
            context.insert(Category(name: categoryName, hexColor: "#3B82F6", workspace: workspace))
        }
        try context.save()

        let provider = MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
        self.provider = provider
        self.nlqPipeline = MarinaNLQPipeline(provider: provider, defaultPeriodUnit: .month)
        self.modelRouter = MarinaLanguageRouter(
            availability: AnalysisStubAvailability(status: .unavailable(reason: "test_unavailable")),
            modelService: AnalysisStubInterpreter(result: .success(.unresolved))
        )
        self.parser = HomeAssistantTextParser()
    }

    func buildReport() async -> TraceAnalysisReport {
        MarinaTraceRecorder.shared.reset()
        var rows: [TraceAnalysisRow] = []

        for prompt in Self.prompts {
            rows.append(await runModelRouter(prompt))
            rows.append(runNLQ(prompt))
            if prompt.group == TracePromptGroup.stressMessyManual202605 {
                rows.append(await runSharedPipeline(prompt))
            }
        }

        let legacyAndNLQRows = rows.filter { $0.mode != "shared_pipeline_heuristic" }
        let bucketCounts = Dictionary(grouping: legacyAndNLQRows, by: { $0.verdictRaw }).mapValues(\.count)
        let rootCauseCounts = Dictionary(grouping: legacyAndNLQRows, by: { $0.rootCauseFamily }).mapValues(\.count)
        let groupCounts = Dictionary(grouping: rows, by: { $0.group }).mapValues(\.count)
        let sharedBucketCounts = Dictionary(
            grouping: rows.compactMap(\.sharedFailureBucket),
            by: { $0 }
        ).mapValues(\.count)
        let sharedLayerCounts = Dictionary(
            grouping: rows.compactMap(\.sharedFailureLayer),
            by: { $0 }
        ).mapValues(\.count)

        return TraceAnalysisReport(
            rows: rows,
            rowsByGroup: groupCounts,
            failuresByBucket: bucketCounts,
            failuresByRootCauseFamily: rootCauseCounts,
            sharedFailuresByBucket: sharedBucketCounts,
            sharedFailuresByLayer: sharedLayerCounts,
            nextPhaseRecommendation: nextPhaseRecommendation(from: bucketCounts)
        )
    }

    private func runModelRouter(_ prompt: PromptExpectation) async -> TraceAnalysisRow {
        MarinaTraceRecorder.shared.begin(prompt: prompt.prompt, routingMode: .modelRouter, marinaNLQv1Enabled: false)
        let interpreted = await modelRouter.interpret(
            prompt: prompt.prompt,
            context: routerContext(),
            heuristicFallback: {
                if let plan = parser.parsePlan(prompt.prompt, defaultPeriodUnit: .month) {
                    return .query(plan, source: .parser)
                }
                return .unresolved
            }
        )
        let trace = MarinaTraceRecorder.shared.finish()

        return classify(
            expectation: prompt,
            mode: .modelRouter,
            trace: trace,
            executable: interpreted.traceSummary,
            aggregationPath: trace?.aggregationPath ?? "home_query_engine",
            responseType: trace?.responseType ?? responseType(from: interpreted)
        )
    }

    private func runNLQ(_ prompt: PromptExpectation) -> TraceAnalysisRow {
        MarinaTraceRecorder.shared.begin(prompt: prompt.prompt, routingMode: .nlqAuthoritative, marinaNLQv1Enabled: true)
        let result = nlqPipeline.run(prompt: prompt.prompt, activeBudgetPeriod: nil, now: Self.analysisNow)
        let trace = MarinaTraceRecorder.shared.finish()

        let executable: String
        let responseType: String
        switch result {
        case .answer(let answer, _):
            executable = "answer:\(answer.kind.rawValue)"
            responseType = trace?.responseType ?? answer.kind.rawValue
        case .clarification:
            executable = "clarification"
            responseType = trace?.responseType ?? "clarification"
        case .recovery:
            executable = "recovery"
            responseType = trace?.responseType ?? "recovery"
        }

        return classify(
            expectation: prompt,
            mode: .nlqAuthoritative,
            trace: trace,
            executable: executable,
            aggregationPath: trace?.aggregationPath ?? "none",
            responseType: responseType
        )
    }

    private func runSharedPipeline(_ prompt: PromptExpectation) async -> TraceAnalysisRow {
        let coordinator = MarinaSharedPipelineCoordinator(
            availability: AnalysisStubAvailability(status: .unavailable(reason: "baseline_fixture_unavailable")),
            structuredInterpreter: AnalysisStubInterpreter(result: .success(.unresolved))
        )
        let context = MarinaSharedPipelineContext(
            provider: provider,
            routerContext: routerContext(),
            defaultPeriodUnit: .month,
            sharedPipelineEnabled: true,
            aiOptInEnabled: false,
            now: Self.analysisNow
        )
        let result = await coordinator.run(prompt: prompt.prompt, context: context)
        let trace = result.trace
        let diagnostics = sharedDiagnostics(prompt: prompt.prompt, trace: trace)
        let actualMetricOperation = [
            diagnostics.candidateOperation.map { "operation=\($0)" },
            diagnostics.candidateMeasure.map { "measure=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " | ")

        return TraceAnalysisRow(
            group: prompt.group,
            prompt: prompt.prompt,
            mode: "shared_pipeline_heuristic",
            expectedOperation: prompt.expectedOperation,
            expectedMeasure: prompt.expectedMeasure,
            expectedEntityScope: prompt.expectedEntityScope,
            expectedTarget: prompt.expectedTarget,
            expectedPrimaryDateRange: prompt.expectedPrimaryDateRange,
            expectedComparisonDateRange: prompt.expectedComparisonDateRange,
            expectedPresentationIntent: prompt.expectedPresentationIntent,
            selectedRoute: trace.selectedPath.rawValue,
            fallbackReplacedModelOutput: false,
            modelSummary: trace.modelAvailabilitySummary,
            fallbackSummary: trace.fallbackReason?.rawValue,
            actualMetricOperation: actualMetricOperation,
            actualTarget: diagnostics.resolvedEntityStates.isEmpty ? nil : diagnostics.resolvedEntityStates.joined(separator: ";"),
            actualPrimaryDateRange: diagnostics.primaryDateRangeSummary,
            actualComparisonDateRange: diagnostics.comparisonDateRangeSummary,
            aggregationPath: diagnostics.aggregationPlanSummary == nil ? "none" : "shared_pipeline",
            responseType: diagnostics.responseBridgeShape ?? diagnostics.executorResultShape ?? diagnostics.validatorOutcome,
            verdictRaw: diagnostics.failureBucket,
            likelySmallestFix: diagnostics.likelySmallestFix,
            sharedPath: trace.selectedPath.rawValue,
            sharedSelectedInterpreter: trace.interpreterSource?.rawValue,
            sharedCandidateOperation: diagnostics.candidateOperation,
            sharedCandidateMeasure: diagnostics.candidateMeasure,
            sharedCandidateSummary: trace.candidateSummary,
            sharedUnresolvedEntityMentions: diagnostics.unresolvedEntityMentions,
            sharedResolvedEntityStates: diagnostics.resolvedEntityStates,
            sharedTimeScopes: diagnostics.timeScopes,
            sharedValidatorOutcome: diagnostics.validatorOutcome,
            sharedAggregationPlanSummary: diagnostics.aggregationPlanSummary,
            sharedExecutorResultShape: diagnostics.executorResultShape,
            sharedResponseBridgeShape: diagnostics.responseBridgeShape,
            sharedFallbackReason: trace.fallbackReason?.rawValue,
            sharedFailureLayer: diagnostics.failureLayer,
            sharedFailureBucket: diagnostics.failureBucket
        )
    }

    private func classify(
        expectation: PromptExpectation,
        mode: MarinaExecutionRoutingMode,
        trace: MarinaExecutionTrace?,
        executable: String,
        aggregationPath: String,
        responseType: String
    ) -> TraceAnalysisRow {
        let actualMetric = trace?.normalizedMetric
        let actualOperation = trace?.normalizedOperation
        let actualTarget = trace?.resolvedTargetSummary ?? trace?.targetText
        let actualPrimary = trace?.primaryDateRangeSummary
        let actualComparison = trace?.comparisonDateRangeSummary

        let verdict = classifyVerdict(
            expectation: expectation,
            mode: mode,
            trace: trace,
            actualMetric: actualMetric,
            actualOperation: actualOperation,
            responseType: responseType,
            aggregationPath: aggregationPath
        )

        return TraceAnalysisRow(
            group: expectation.group,
            prompt: expectation.prompt,
            mode: mode.rawValue,
            expectedOperation: expectation.expectedOperation,
            expectedMeasure: expectation.expectedMeasure,
            expectedEntityScope: expectation.expectedEntityScope,
            expectedTarget: expectation.expectedTarget,
            expectedPrimaryDateRange: expectation.expectedPrimaryDateRange,
            expectedComparisonDateRange: expectation.expectedComparisonDateRange,
            expectedPresentationIntent: expectation.expectedPresentationIntent,
            selectedRoute: trace?.selectedRoute.rawValue ?? "unknown",
            fallbackReplacedModelOutput: trace?.fallbackReplacedModelOutput ?? false,
            modelSummary: trace?.modelOutputSummary ?? trace?.modelPlanSummary,
            fallbackSummary: trace?.fallbackOutputSummary,
            actualMetricOperation: [actualMetric, actualOperation].compactMap { $0 }.joined(separator: " | "),
            actualTarget: actualTarget,
            actualPrimaryDateRange: actualPrimary,
            actualComparisonDateRange: actualComparison,
            aggregationPath: aggregationPath,
            responseType: responseType,
            verdictRaw: verdict.rawValue,
            likelySmallestFix: smallestFix(for: verdict),
            sharedPath: trace?.sharedPipelinePath?.rawValue,
            sharedSelectedInterpreter: nil,
            sharedCandidateOperation: nil,
            sharedCandidateMeasure: nil,
            sharedCandidateSummary: trace?.sharedPipelineCandidateSummary,
            sharedUnresolvedEntityMentions: nil,
            sharedResolvedEntityStates: nil,
            sharedTimeScopes: nil,
            sharedValidatorOutcome: trace?.sharedPipelineValidatorSummary,
            sharedAggregationPlanSummary: nil,
            sharedExecutorResultShape: trace?.sharedPipelineExecutorSummary,
            sharedResponseBridgeShape: trace?.sharedPipelineResponseBridgeSummary,
            sharedFallbackReason: trace?.sharedPipelineFallbackReason?.rawValue,
            sharedFailureLayer: nil,
            sharedFailureBucket: nil
        )
    }

    private func sharedDiagnostics(
        prompt: String,
        trace: MarinaSharedPipelineTrace
    ) -> SharedPipelineDiagnostics {
        let candidate = MarinaHeuristicInterpreter().interpret(prompt: prompt, defaultPeriodUnit: .month)
        let resolved = MarinaQueryResolver().resolve(candidate: candidate, provider: provider)
        let validation = MarinaQueryValidator().validate(resolved)
        var aggregationPlanSummary: String?
        let executorResultShape = trace.executorResultSummary
        let responseBridgeShape = trace.responseBridgeSummary

        if case .executable(let plan) = validation {
            aggregationPlanSummary = sharedAggregationPlanSummary(plan)
        }

        let failureLayer = sharedFailureLayer(
            candidate: candidate,
            resolved: resolved,
            validation: validation,
            aggregationPlanSummary: aggregationPlanSummary,
            executorResultShape: executorResultShape,
            responseBridgeShape: responseBridgeShape,
            trace: trace
        )
        let failureBucket = sharedFailureBucket(
            candidate: candidate,
            resolved: resolved,
            validation: validation,
            executorResultShape: executorResultShape,
            responseBridgeShape: responseBridgeShape,
            trace: trace
        )

        return SharedPipelineDiagnostics(
            candidateOperation: candidate.operation?.rawValue,
            candidateMeasure: candidate.measure?.rawValue,
            unresolvedEntityMentions: resolved.unresolvedMentions.map(entityMentionSummary),
            resolvedEntityStates: resolved.resolvedTargets.map(resolvedEntitySummary),
            timeScopes: candidate.timeScopes.map(timeScopeSummary),
            primaryDateRangeSummary: resolved.primaryDateRange?.traceSummary,
            comparisonDateRangeSummary: resolved.comparisonDateRange?.traceSummary,
            validatorOutcome: validationSummary(validation),
            aggregationPlanSummary: aggregationPlanSummary,
            executorResultShape: executorResultShape,
            responseBridgeShape: responseBridgeShape,
            failureLayer: failureLayer,
            failureBucket: failureBucket,
            likelySmallestFix: sharedSmallestFix(for: failureLayer)
        )
    }

    private func sharedFailureLayer(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        validation: MarinaPlanValidationOutcome,
        aggregationPlanSummary: String?,
        executorResultShape: String?,
        responseBridgeShape: String?,
        trace: MarinaSharedPipelineTrace
    ) -> String {
        if candidate.operation == nil || candidate.measure == nil {
            return "candidate construction"
        }
        if resolved.unresolvedMentions.isEmpty == false || resolved.ambiguousMentions.isEmpty == false {
            return "entity resolution"
        }
        if candidate.entityMentions.isEmpty == false && resolved.resolvedTargets.isEmpty {
            return "entity extraction"
        }
        switch validation {
        case .clarification, .unsupported:
            return "validation"
        case .executable:
            break
        }
        if candidate.operation == .compare && resolved.comparisonDateRange == nil {
            return "date scope construction"
        }
        if aggregationPlanSummary == nil {
            return "adapter mapping"
        }
        if executorResultShape?.hasPrefix("unsupported") == true || executorResultShape?.hasPrefix("adapterUnsupported") == true {
            return "execution"
        }
        if responseBridgeShape == nil {
            return "response bridging"
        }
        if trace.fallbackReason != nil {
            return "legacy fallback"
        }
        return "handled"
    }

    private func sharedFailureBucket(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        validation: MarinaPlanValidationOutcome,
        executorResultShape: String?,
        responseBridgeShape: String?,
        trace: MarinaSharedPipelineTrace
    ) -> String {
        if let unsupportedHint = candidate.unsupportedHint {
            return "typed unsupported:\(unsupportedHint.rawValue)"
        }
        if candidate.operation == nil || candidate.measure == nil {
            return "missing operation or measure"
        }
        if resolved.unresolvedMentions.isEmpty == false {
            return "unresolved entity mention"
        }
        if resolved.ambiguousMentions.isEmpty == false {
            return "ambiguous entity mention"
        }
        if candidate.operation == .compare && resolved.comparisonDateRange == nil {
            return "missing comparison date range"
        }
        switch validation {
        case .clarification(let clarification):
            return "validator clarification:\(clarification.kind.rawValue)"
        case .unsupported(let unsupported):
            return "validator unsupported:\(unsupported.kind.rawValue)"
        case .executable:
            break
        }
        if executorResultShape?.hasPrefix("adapterUnsupported") == true {
            return "adapter unsupported"
        }
        if executorResultShape?.hasPrefix("unsupported") == true {
            return "executor unsupported"
        }
        if responseBridgeShape == nil {
            return "response bridge missing"
        }
        if let fallbackReason = trace.fallbackReason {
            return "legacy fallback:\(fallbackReason.rawValue)"
        }
        return "handled"
    }

    private func sharedSmallestFix(for layer: String) -> String {
        switch layer {
        case "phrase normalization":
            return "teach the normalizer to preserve unsupported projection/simulation/frequency intent"
        case "candidate construction":
            return "map messy prompt intent into explicit operation and measure candidates"
        case "entity extraction":
            return "extract only entity spans instead of broad prompt fragments"
        case "entity resolution":
            return "resolve card/category mentions before adapter execution and keep unresolved spans explicit"
        case "date scope construction":
            return "synthesize comparison ranges for compared-to/from-to prompts"
        case "validation":
            return "classify unsupported or clarification outcomes without collapsing to scalar spend"
        case "adapter mapping":
            return "preserve grouped/share/ranked query shape when adapting to HomeQueryPlan"
        case "execution":
            return "execute supported aggregation shapes without dropping targets"
        case "response bridging":
            return "bridge aggregation result shape into matching HomeAnswer presentation"
        case "legacy fallback":
            return "record fallback cause and route quality before legacy handoff"
        default:
            return "none"
        }
    }

    private func entityMentionSummary(_ mention: MarinaUnresolvedEntityMention) -> String {
        [
            mention.role.rawValue,
            mention.typeHint?.rawValue ?? "unknown",
            mention.rawText ?? "nil",
            mention.confidence.rawValue
        ].joined(separator: ":")
    }

    private func resolvedEntitySummary(_ mention: MarinaResolvedEntityMention) -> String {
        [
            mention.role.rawValue,
            mention.entityType.rawValue,
            mention.displayName,
            mention.sourceID?.uuidString ?? "nil"
        ].joined(separator: ":")
    }

    private func timeScopeSummary(_ scope: MarinaUnresolvedTimeScope) -> String {
        [
            scope.role.rawValue,
            scope.rawText ?? "nil",
            scope.periodUnitHint?.rawValue ?? "none",
            scope.resolvedRangeHint?.traceSummary ?? "unresolved"
        ].joined(separator: ":")
    }

    private func validationSummary(_ outcome: MarinaPlanValidationOutcome) -> String {
        switch outcome {
        case .executable(let plan):
            return "executable:\(plan.operation.rawValue):\(plan.measure.rawValue)"
        case .clarification(let clarification):
            return "clarification:\(clarification.kind.rawValue)"
        case .unsupported(let unsupported):
            return "unsupported:\(unsupported.kind.rawValue)"
        }
    }

    private func sharedAggregationPlanSummary(_ plan: MarinaAggregationPlan) -> String {
        [
            "operation=\(plan.operation.rawValue)",
            "measure=\(plan.measure.rawValue)",
            "targets=\(plan.targets.map { "\($0.role.rawValue):\($0.entityType.rawValue):\($0.displayName)" }.joined(separator: ";"))",
            "primary=\(plan.dateRange?.traceSummary ?? "nil")",
            "comparison=\(plan.comparisonDateRange?.traceSummary ?? "nil")",
            "grouping=\(plan.grouping?.dimension.rawValue ?? "nil")",
            "ranking=\(plan.ranking?.direction.rawValue ?? "nil")",
            "shape=\(plan.responseShape?.rawValue ?? "nil")"
        ].joined(separator: ",")
    }

    private func aggregationResultShape(_ result: MarinaAggregationResult) -> String {
        switch result {
        case .scalar(let scalar):
            return "scalar:\(scalar.renderedValue ?? "nil")"
        case .comparison(let comparison):
            return "comparison:\(comparison.primaryRenderedValue):\(comparison.comparisonRenderedValue)"
        case .rankedList(let list):
            return "rankedList:rows=\(list.rows.count)"
        case .groupedBreakdown(let list):
            return "groupedBreakdown:rows=\(list.rows.count)"
        case .workspaceCard(let card):
            return card.traceSummary
        case .message(let message):
            return "message:\(message.title)"
        case .noData(let result):
            return "noData:\(result.title)"
        case .unsupported(let unsupported):
            return "unsupported:\(unsupported.kind.rawValue)"
        }
    }

    private func classifyVerdict(
        expectation: PromptExpectation,
        mode: MarinaExecutionRoutingMode,
        trace: MarinaExecutionTrace?,
        actualMetric: String?,
        actualOperation: String?,
        responseType: String,
        aggregationPath: String
    ) -> TraceFailureBucket {
        if expectation.expectedOperation == "what_if" {
            return .unsupportedCapability
        }

        if responseType == "recovery" || responseType == "unresolved" {
            return .aggregationExecutionFailure
        }

        if trace?.fallbackReplacedModelOutput == true {
            return .fallbackReplacedBetterModelOutput
        }

        if mode == .modelRouter,
           trace?.modelWasAvailable == false,
           trace?.selectedRoute == .fallback,
           actualMetric != nil {
            return .fallbackProducedBetterOutput
        }

        if mode == .modelRouter,
           trace?.modelWasAvailable == true,
           trace?.modelOutputSummary == nil {
            return .modelInterpretationFailure
        }

        if expectation.expectedMeasure == "categoryAverageSpend",
           (actualMetric == nil || actualMetric == "spendAveragePerPeriod") {
            return .metricOperationMappingFailure
        }

        if let expectedTarget = expectation.expectedTarget,
           let actualTarget = trace?.resolvedTargetSummary,
           actualTarget.isEmpty == false,
           actualTarget.localizedCaseInsensitiveContains(expectedTarget) == false {
            return .targetResolutionFailure
        }

        if expectation.expectedComparisonDateRange != nil,
           trace?.comparisonDateRangeSummary == nil {
            return .comparisonRangeFailure
        }

        if expectation.expectedOperation == "difference",
           actualOperation != "difference" {
            return .modelToPlanMappingFailure
        }

        if aggregationPath == "none" {
            return .aggregationExecutionFailure
        }

        return .correct
    }

    private func smallestFix(for bucket: TraceFailureBucket) -> String {
        switch bucket {
        case .correct:
            return "none"
        case .modelInterpretationFailure:
            return "improve structured intent disambiguation with constrained examples"
        case .modelToPlanMappingFailure:
            return "tighten structured metric-to-plan mapping contract"
        case .fallbackReplacedBetterModelOutput:
            return "add trace-backed guardrails before fallback override"
        case .fallbackProducedBetterOutput:
            return "prefer fallback only when model unavailable and parser confidence is high"
        case .metricOperationMappingFailure:
            return "add explicit average-by-target mapping metric"
        case .targetResolutionFailure:
            return "add deterministic target canonicalization before execution"
        case .dateRangeFailure:
            return "normalize explicit temporal phrases before plan finalization"
        case .comparisonRangeFailure:
            return "require secondary range synthesis for comparison prompts"
        case .aggregationExecutionFailure:
            return "add graceful execution fallback for unresolved mapped queries"
        case .responseFormattingPresentationFailure:
            return "separate response intent from data intent in formatter"
        case .clarificationUXFailure:
            return "improve actionable clarification options and follow-up carryover"
        case .unsupportedCapability:
            return "add dedicated what-if trace path classification without execution"
        }
    }

    private func nextPhaseRecommendation(from buckets: [String: Int]) -> String {
        if (buckets[TraceFailureBucket.metricOperationMappingFailure.rawValue] ?? 0) > 0 {
            return "Phase 1: mapping hardening for average/targeted operations + explicit unsupported capability labels"
        }
        if (buckets[TraceFailureBucket.fallbackReplacedBetterModelOutput.rawValue] ?? 0) > 0 {
            return "Phase 1: fallback override guardrails with route-quality checks"
        }
        return "Phase 1: target/date normalization consistency pass"
    }

    private func responseType(from interpreted: MarinaInterpretedRequest) -> String {
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
    }

    private func routerContext() -> MarinaLanguageRouterContext {
        MarinaLanguageRouterContext(
            workspaceName: "Trace Analysis Workspace",
            defaultPeriodUnit: .month,
            sessionContext: HomeAssistantSessionContext(),
            priorQueryContext: MarinaPriorQueryContext(
                lastQueryPlan: nil,
                lastMetric: nil,
                lastTargetName: nil,
                lastTargetType: nil,
                lastDateRange: nil,
                lastResultLimit: nil,
                lastPeriodUnit: nil
            ),
            cardNames: ["Apple Card"],
            categoryNames: ["Food & Drink", "Groceries", "Restaurants", "Shopping", "Transportation"],
            incomeSourceNames: ["Salary"],
            presetTitles: ["Rent"],
            budgetNames: ["Main Budget"],
            aliasSummaries: [],
            now: Self.analysisNow
        )
    }
}

private struct PromptExpectation {
    let group: String
    let prompt: String
    let expectedOperation: String
    let expectedMeasure: String
    let expectedEntityScope: String
    let expectedTarget: String?
    let expectedPrimaryDateRange: String?
    let expectedComparisonDateRange: String?
    let expectedPresentationIntent: String

    init(
        group: String = TracePromptGroup.core,
        prompt: String,
        expectedOperation: String,
        expectedMeasure: String,
        expectedEntityScope: String,
        expectedTarget: String?,
        expectedPrimaryDateRange: String?,
        expectedComparisonDateRange: String?,
        expectedPresentationIntent: String
    ) {
        self.group = group
        self.prompt = prompt
        self.expectedOperation = expectedOperation
        self.expectedMeasure = expectedMeasure
        self.expectedEntityScope = expectedEntityScope
        self.expectedTarget = expectedTarget
        self.expectedPrimaryDateRange = expectedPrimaryDateRange
        self.expectedComparisonDateRange = expectedComparisonDateRange
        self.expectedPresentationIntent = expectedPresentationIntent
    }
}

private enum TraceFailureBucket: String {
    case correct = "correct"
    case modelInterpretationFailure = "model interpretation failure"
    case modelToPlanMappingFailure = "model-to-plan mapping failure"
    case fallbackReplacedBetterModelOutput = "fallback replaced better model output"
    case fallbackProducedBetterOutput = "fallback produced better output"
    case metricOperationMappingFailure = "metric/operation mapping failure"
    case targetResolutionFailure = "target resolution failure"
    case dateRangeFailure = "date range failure"
    case comparisonRangeFailure = "comparison range failure"
    case aggregationExecutionFailure = "aggregation execution failure"
    case responseFormattingPresentationFailure = "response formatting/presentation failure"
    case clarificationUXFailure = "clarification UX failure"
    case unsupportedCapability = "unsupported capability"
}

private struct TraceAnalysisRow: Codable, Equatable {
    let group: String
    let prompt: String
    let mode: String
    let expectedOperation: String
    let expectedMeasure: String
    let expectedEntityScope: String
    let expectedTarget: String?
    let expectedPrimaryDateRange: String?
    let expectedComparisonDateRange: String?
    let expectedPresentationIntent: String
    let selectedRoute: String
    let fallbackReplacedModelOutput: Bool
    let modelSummary: String?
    let fallbackSummary: String?
    let actualMetricOperation: String
    let actualTarget: String?
    let actualPrimaryDateRange: String?
    let actualComparisonDateRange: String?
    let aggregationPath: String
    let responseType: String
    let verdictRaw: String
    let likelySmallestFix: String
    let sharedPath: String?
    let sharedSelectedInterpreter: String?
    let sharedCandidateOperation: String?
    let sharedCandidateMeasure: String?
    let sharedCandidateSummary: String?
    let sharedUnresolvedEntityMentions: [String]?
    let sharedResolvedEntityStates: [String]?
    let sharedTimeScopes: [String]?
    let sharedValidatorOutcome: String?
    let sharedAggregationPlanSummary: String?
    let sharedExecutorResultShape: String?
    let sharedResponseBridgeShape: String?
    let sharedFallbackReason: String?
    let sharedFailureLayer: String?
    let sharedFailureBucket: String?

    var rootCauseFamily: String {
        switch verdictRaw {
        case TraceFailureBucket.modelInterpretationFailure.rawValue,
             TraceFailureBucket.modelToPlanMappingFailure.rawValue,
             TraceFailureBucket.metricOperationMappingFailure.rawValue:
            return "interpretation_and_mapping"
        case TraceFailureBucket.fallbackReplacedBetterModelOutput.rawValue,
             TraceFailureBucket.fallbackProducedBetterOutput.rawValue:
            return "routing_and_fallback"
        case TraceFailureBucket.targetResolutionFailure.rawValue,
             TraceFailureBucket.dateRangeFailure.rawValue,
             TraceFailureBucket.comparisonRangeFailure.rawValue:
            return "entity_and_time_resolution"
        case TraceFailureBucket.aggregationExecutionFailure.rawValue:
            return "execution"
        case TraceFailureBucket.responseFormattingPresentationFailure.rawValue,
             TraceFailureBucket.clarificationUXFailure.rawValue:
            return "response_and_ux"
        case TraceFailureBucket.unsupportedCapability.rawValue:
            return "capability_gap"
        default:
            return "correct"
        }
    }
}

private struct SharedPipelineDiagnostics {
    let candidateOperation: String?
    let candidateMeasure: String?
    let unresolvedEntityMentions: [String]
    let resolvedEntityStates: [String]
    let timeScopes: [String]
    let primaryDateRangeSummary: String?
    let comparisonDateRangeSummary: String?
    let validatorOutcome: String
    let aggregationPlanSummary: String?
    let executorResultShape: String?
    let responseBridgeShape: String?
    let failureLayer: String
    let failureBucket: String
    let likelySmallestFix: String
}

private struct TraceAnalysisReport: Codable, Equatable {
    let rows: [TraceAnalysisRow]
    let rowsByGroup: [String: Int]
    let failuresByBucket: [String: Int]
    let failuresByRootCauseFamily: [String: Int]
    let sharedFailuresByBucket: [String: Int]
    let sharedFailuresByLayer: [String: Int]
    let nextPhaseRecommendation: String
}

private struct TraceAnalysisArtifactWriter {
    let jsonURL: URL
    let txtURL: URL
    let snapshotJSONURL: URL?
    let snapshotTXTURL: URL?
    let snapshotWriteWarning: String?

    static func write(report: TraceAnalysisReport) throws -> TraceAnalysisArtifactWriter {
        let base = artifactOutputDirectory()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        let jsonURL = base.appendingPathComponent("MarinaTraceAnalysisReport.json")
        let txtURL = base.appendingPathComponent("MarinaTraceAnalysisReport.txt")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(report)
        try data.write(to: jsonURL, options: .atomic)

        let text = renderTextReport(report: report, jsonURL: jsonURL, txtURL: txtURL)
        try text.write(to: txtURL, atomically: true, encoding: .utf8)

        let snapshotBase = snapshotOutputDirectory()
        let snapshotJSONURL = snapshotBase.appendingPathComponent("MarinaTraceAnalysisReport.json")
        let snapshotTXTURL = snapshotBase.appendingPathComponent("MarinaTraceAnalysisReport.txt")
        var snapshotWriteWarning: String?
        var persistedSnapshotJSONURL: URL?
        var persistedSnapshotTXTURL: URL?
        do {
            try data.write(to: snapshotJSONURL, options: .atomic)
            try text.write(to: snapshotTXTURL, atomically: true, encoding: .utf8)
            persistedSnapshotJSONURL = snapshotJSONURL
            persistedSnapshotTXTURL = snapshotTXTURL
        } catch {
            snapshotWriteWarning = "Snapshot write skipped: \(error.localizedDescription)"
        }

        return TraceAnalysisArtifactWriter(
            jsonURL: jsonURL,
            txtURL: txtURL,
            snapshotJSONURL: persistedSnapshotJSONURL,
            snapshotTXTURL: persistedSnapshotTXTURL,
            snapshotWriteWarning: snapshotWriteWarning
        )
    }

    private static func artifactOutputDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("OffshoreBudgetingTestArtifacts", isDirectory: true)
            .appendingPathComponent("MarinaTraceAnalysis", isDirectory: true)
    }

    private static func snapshotOutputDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
    }

    private static func renderTextReport(
        report: TraceAnalysisReport,
        jsonURL: URL,
        txtURL: URL
    ) -> String {
        var lines: [String] = []
        lines.append("Marina Trace Analysis Report")
        lines.append("GeneratedAtUTC: \(isoTimestamp(reportGeneratedAt()))")
        lines.append("Rows: \(report.rows.count)")
        lines.append("JSON: \(jsonURL.lastPathComponent)")
        lines.append("TXT: \(txtURL.lastPathComponent)")
        lines.append("")

        for mode in ["model_router", "nlq_authoritative", "shared_pipeline_heuristic"] {
            lines.append("mode: \(mode)")
            let modeRows = report.rows.filter { $0.mode == mode }
            for row in modeRows {
                lines.append("- prompt: \(row.prompt)")
                lines.append("  group: \(row.group)")
                lines.append("  expectedOperation: \(row.expectedOperation)")
                lines.append("  expectedMeasure: \(row.expectedMeasure)")
                lines.append("  expectedEntityScope: \(row.expectedEntityScope)")
                lines.append("  expectedTarget: \(row.expectedTarget ?? "nil")")
                lines.append("  expectedPrimaryDateRange: \(row.expectedPrimaryDateRange ?? "nil")")
                lines.append("  expectedComparisonDateRange: \(row.expectedComparisonDateRange ?? "nil")")
                lines.append("  expectedPresentationIntent: \(row.expectedPresentationIntent)")
                lines.append("  selectedRoute: \(row.selectedRoute)")
                lines.append("  fallbackReplacedModelOutput: \(row.fallbackReplacedModelOutput)")
                lines.append("  modelSummary: \(row.modelSummary ?? "nil")")
                lines.append("  fallbackSummary: \(row.fallbackSummary ?? "nil")")
                lines.append("  actualMetricOperation: \(display(row.actualMetricOperation))")
                lines.append("  actualTarget: \(display(row.actualTarget))")
                lines.append("  actualPrimaryDateRange: \(display(row.actualPrimaryDateRange))")
                lines.append("  actualComparisonDateRange: \(display(row.actualComparisonDateRange))")
                lines.append("  aggregationPath: \(row.aggregationPath)")
                lines.append("  responseType: \(row.responseType)")
                lines.append("  verdictRaw: \(row.verdictRaw)")
                lines.append("  likelySmallestFix: \(row.likelySmallestFix)")
                if mode == "shared_pipeline_heuristic" {
                    lines.append("  sharedPath: \(display(row.sharedPath))")
                    lines.append("  sharedSelectedInterpreter: \(display(row.sharedSelectedInterpreter))")
                    lines.append("  sharedCandidateOperation: \(display(row.sharedCandidateOperation))")
                    lines.append("  sharedCandidateMeasure: \(display(row.sharedCandidateMeasure))")
                    lines.append("  sharedCandidateSummary: \(display(row.sharedCandidateSummary))")
                    lines.append("  sharedUnresolvedEntityMentions: \(display(row.sharedUnresolvedEntityMentions))")
                    lines.append("  sharedResolvedEntityStates: \(display(row.sharedResolvedEntityStates))")
                    lines.append("  sharedTimeScopes: \(display(row.sharedTimeScopes))")
                    lines.append("  sharedValidatorOutcome: \(display(row.sharedValidatorOutcome))")
                    lines.append("  sharedAggregationPlanSummary: \(display(row.sharedAggregationPlanSummary))")
                    lines.append("  sharedExecutorResultShape: \(display(row.sharedExecutorResultShape))")
                    lines.append("  sharedResponseBridgeShape: \(display(row.sharedResponseBridgeShape))")
                    lines.append("  sharedFallbackReason: \(display(row.sharedFallbackReason))")
                    lines.append("  sharedFailureLayer: \(display(row.sharedFailureLayer))")
                    lines.append("  sharedFailureBucket: \(display(row.sharedFailureBucket))")
                }
            }
            lines.append("")
        }

        lines.append("rowsByGroup")
        for (group, count) in report.rowsByGroup.sorted(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }) {
            lines.append("- \(group): \(count)")
        }
        lines.append("")

        lines.append("failuresByBucket")
        for (bucket, count) in report.failuresByBucket.sorted(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }) {
            lines.append("- \(bucket): \(count)")
        }
        lines.append("")

        lines.append("failuresByRootCauseFamily")
        for (family, count) in report.failuresByRootCauseFamily.sorted(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }) {
            lines.append("- \(family): \(count)")
        }
        lines.append("")

        lines.append("sharedFailuresByBucket")
        for (bucket, count) in report.sharedFailuresByBucket.sorted(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }) {
            lines.append("- \(bucket): \(count)")
        }
        lines.append("")

        lines.append("sharedFailuresByLayer")
        for (layer, count) in report.sharedFailuresByLayer.sorted(by: { lhs, rhs in
            if lhs.value == rhs.value { return lhs.key < rhs.key }
            return lhs.value > rhs.value
        }) {
            lines.append("- \(layer): \(count)")
        }
        lines.append("")
        lines.append("nextPhaseRecommendation")
        lines.append("- \(report.nextPhaseRecommendation)")
        lines.append("")
        return lines.joined(separator: "\n")
    }

    private static func reportGeneratedAt() -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: 2026, month: 5, day: 15, hour: 12)
        )!
    }

    private static func display(_ value: String?) -> String {
        guard let value, value.isEmpty == false else {
            return "nil"
        }
        return value
    }

    private static func display(_ values: [String]?) -> String {
        guard let values, values.isEmpty == false else {
            return "nil"
        }
        return values.joined(separator: ";")
    }

    private static func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

private struct AnalysisStubAvailability: MarinaModelAvailabilityProviding {
    let status: MarinaModelAvailability.Status

    func currentStatus() -> MarinaModelAvailability.Status {
        status
    }
}

private struct AnalysisStubInterpreter: MarinaStructuredIntentInterpreting {
    let result: Result<MarinaStructuredIntent, Error>

    func interpret(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaStructuredIntent {
        try result.get()
    }
}
