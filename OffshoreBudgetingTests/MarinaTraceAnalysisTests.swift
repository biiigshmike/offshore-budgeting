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

        #expect(report.rows.count == 38)
        #expect(report.rows.allSatisfy { $0.mode.isEmpty == false })
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
        #expect(decoded.rows.count == 38)

        let txt = try String(contentsOf: artifacts.txtURL, encoding: .utf8)
        #expect(txt.contains("mode: model_router"))
        #expect(txt.contains("mode: nlq_authoritative"))
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

@MainActor
private struct MarinaTraceAnalyzer {
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
        .init(prompt: "If I buy something for $120 today, can I still stay within my safe spend?", expectedOperation: "what_if", expectedMeasure: "safe_spend_simulation", expectedEntityScope: "global", expectedTarget: nil, expectedPrimaryDateRange: "today", expectedComparisonDateRange: nil, expectedPresentationIntent: "what_if")
    ]

    private let nlqPipeline: MarinaNLQPipeline
    private let modelRouter: MarinaLanguageRouter
    private let parser: HomeAssistantTextParser

    init() throws {
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
        let workspace = Workspace(name: "Trace Analysis Workspace", hexColor: "#3B82F6")
        context.insert(workspace)

        let provider = MarinaDataProvider(modelContext: context, workspaceID: workspace.id)
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
        }

        let bucketCounts = Dictionary(grouping: rows, by: { $0.verdictRaw }).mapValues(\.count)
        let rootCauseCounts = Dictionary(grouping: rows, by: { $0.rootCauseFamily }).mapValues(\.count)

        return TraceAnalysisReport(
            rows: rows,
            failuresByBucket: bucketCounts,
            failuresByRootCauseFamily: rootCauseCounts,
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
        let result = nlqPipeline.run(prompt: prompt.prompt, activeBudgetPeriod: nil, now: Date())
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
            likelySmallestFix: smallestFix(for: verdict)
        )
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
            categoryNames: ["Food & Drink", "Groceries", "Restaurants"],
            incomeSourceNames: ["Salary"],
            presetTitles: ["Rent"],
            budgetNames: ["Main Budget"],
            aliasSummaries: [],
            now: Date()
        )
    }
}

private struct PromptExpectation {
    let prompt: String
    let expectedOperation: String
    let expectedMeasure: String
    let expectedEntityScope: String
    let expectedTarget: String?
    let expectedPrimaryDateRange: String?
    let expectedComparisonDateRange: String?
    let expectedPresentationIntent: String
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

private struct TraceAnalysisReport: Codable, Equatable {
    let rows: [TraceAnalysisRow]
    let failuresByBucket: [String: Int]
    let failuresByRootCauseFamily: [String: Int]
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
        lines.append("GeneratedAtUTC: \(isoTimestamp(Date()))")
        lines.append("Rows: \(report.rows.count)")
        lines.append("JSON: \(jsonURL.path)")
        lines.append("TXT: \(txtURL.path)")
        lines.append("")

        for mode in ["model_router", "nlq_authoritative"] {
            lines.append("mode: \(mode)")
            let modeRows = report.rows.filter { $0.mode == mode }
            for row in modeRows {
                lines.append("- prompt: \(row.prompt)")
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
                lines.append("  actualMetricOperation: \(row.actualMetricOperation)")
                lines.append("  actualTarget: \(row.actualTarget ?? "nil")")
                lines.append("  actualPrimaryDateRange: \(row.actualPrimaryDateRange ?? "nil")")
                lines.append("  actualComparisonDateRange: \(row.actualComparisonDateRange ?? "nil")")
                lines.append("  aggregationPath: \(row.aggregationPath)")
                lines.append("  responseType: \(row.responseType)")
                lines.append("  verdictRaw: \(row.verdictRaw)")
                lines.append("  likelySmallestFix: \(row.likelySmallestFix)")
            }
            lines.append("")
        }

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
        lines.append("nextPhaseRecommendation")
        lines.append("- \(report.nextPhaseRecommendation)")
        lines.append("")
        return lines.joined(separator: "\n")
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
