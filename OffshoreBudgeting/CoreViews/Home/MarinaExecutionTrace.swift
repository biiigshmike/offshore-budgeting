import Foundation

struct MarinaExecutionTrace: Equatable {
    let originalPrompt: String
    let routingMode: MarinaExecutionRoutingMode
    let marinaNLQv1Enabled: Bool

    let modelWasAvailable: Bool
    let modelAvailabilityReason: String?
    let modelOutputSummary: String?
    let modelPlanSummary: String?
    let modelValidationSummary: String?

    let fallbackWasAttempted: Bool
    let fallbackOutputSummary: String?
    let fallbackSelectionReason: MarinaExecutionFallbackReason?
    let fallbackReplacedModelOutput: Bool

    let selectedRoute: MarinaExecutionSelectedRoute
    let selectedRouteReason: String?

    let normalizedMetric: String?
    let normalizedOperation: String?
    let presentationIntent: String?

    let targetText: String?
    let targetType: String?
    let resolvedTargetSummary: String?

    let primaryDateRangeSummary: String?
    let comparisonDateRangeSummary: String?

    let aggregationPath: String?
    let responseType: String?
    let finalAnswerSummary: String?

    let sharedPipelineEnabled: Bool?
    let sharedPipelinePath: MarinaSharedPipelineRuntimePath?
    let sharedPipelineInterpreterSource: MarinaInterpreterSource?
    let sharedPipelineCandidateSummary: String?
    let sharedPipelineResolverSummary: String?
    let sharedPipelineValidatorSummary: String?
    let sharedPipelineExecutorSummary: String?
    let sharedPipelineResponseBridgeSummary: String?
    let sharedPipelineFallbackReason: MarinaSharedPipelineFallbackReason?
    let sharedPipelineDisagreementSummary: String?
}

enum MarinaExecutionRoutingMode: String, Equatable {
    case modelRouter = "model_router"
    case nlqAuthoritative = "nlq_authoritative"
    case sharedPipeline = "shared_pipeline"
}

enum MarinaExecutionSelectedRoute: String, Equatable {
    case model
    case fallback
    case nlq
    case sharedHeuristic = "shared_heuristic"
    case sharedFoundationModels = "shared_foundation_models"
    case sharedFallback = "shared_fallback"
    case clarification
    case recovery
    case unresolved
}

enum MarinaExecutionFallbackReason: String, Equatable {
    case modelUnavailable = "model_unavailable"
    case modelError = "model_error"
    case modelUnresolved = "model_unresolved"
    case modelQueryInvalid = "model_query_invalid"
    case preferHeuristicQuery = "prefer_heuristic_query"
    case preferHeuristicClarificationBypass = "prefer_heuristic_clarification_bypass"
    case manualClarificationFallback = "manual_clarification_fallback"
}

final class MarinaTraceRecorder {
    static let shared = MarinaTraceRecorder()

    private var lock = NSLock()
    private var currentDraft: MarinaExecutionTraceDraft?
    private(set) var completed: [MarinaExecutionTrace] = []

    private init() {}

    var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        currentDraft = nil
        completed = []
    }

    func begin(
        prompt: String,
        routingMode: MarinaExecutionRoutingMode,
        marinaNLQv1Enabled: Bool
    ) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        currentDraft = MarinaExecutionTraceDraft(
            originalPrompt: prompt,
            routingMode: routingMode,
            marinaNLQv1Enabled: marinaNLQv1Enabled
        )
    }

    func ensure(prompt: String, routingMode: MarinaExecutionRoutingMode, marinaNLQv1Enabled: Bool) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if currentDraft == nil {
            currentDraft = MarinaExecutionTraceDraft(
                originalPrompt: prompt,
                routingMode: routingMode,
                marinaNLQv1Enabled: marinaNLQv1Enabled
            )
        }
    }

    func recordModelAvailability(_ availability: MarinaModelAvailability.Status) {
        guard isEnabled else { return }
        mutate { draft in
            switch availability {
            case .available:
                draft.modelWasAvailable = true
                draft.modelAvailabilityReason = nil
            case .unavailable(let reason):
                draft.modelWasAvailable = false
                draft.modelAvailabilityReason = reason
            }
        }
    }

    func recordModelOutputSummary(_ summary: String?) {
        guard isEnabled else { return }
        mutate { $0.modelOutputSummary = summary }
    }

    func recordModelPlanSummary(_ summary: String?) {
        guard isEnabled else { return }
        mutate { $0.modelPlanSummary = summary }
    }

    func recordModelValidationSummary(_ summary: String?) {
        guard isEnabled else { return }
        mutate { $0.modelValidationSummary = summary }
    }

    func recordFallbackAttempt(outputSummary: String?) {
        guard isEnabled else { return }
        mutate { draft in
            draft.fallbackWasAttempted = true
            draft.fallbackOutputSummary = outputSummary
        }
    }

    func recordFallbackSelection(
        reason: MarinaExecutionFallbackReason,
        replacedModelOutput: Bool
    ) {
        guard isEnabled else { return }
        mutate { draft in
            draft.fallbackSelectionReason = reason
            draft.fallbackReplacedModelOutput = replacedModelOutput
        }
    }

    func recordSelectedRoute(_ route: MarinaExecutionSelectedRoute, reason: String?) {
        guard isEnabled else { return }
        mutate { draft in
            draft.selectedRoute = route
            draft.selectedRouteReason = reason
        }
    }

    func recordNormalized(
        metric: String?,
        operation: String?,
        presentationIntent: String?
    ) {
        guard isEnabled else { return }
        mutate { draft in
            draft.normalizedMetric = metric
            draft.normalizedOperation = operation
            draft.presentationIntent = presentationIntent
        }
    }

    func recordTarget(
        targetText: String?,
        targetType: String?,
        resolvedTargetSummary: String?
    ) {
        guard isEnabled else { return }
        mutate { draft in
            draft.targetText = targetText
            draft.targetType = targetType
            draft.resolvedTargetSummary = resolvedTargetSummary
        }
    }

    func recordDateRanges(primary: HomeQueryDateRange?, comparison: HomeQueryDateRange?) {
        guard isEnabled else { return }
        mutate { draft in
            draft.primaryDateRangeSummary = primary?.traceSummary
            draft.comparisonDateRangeSummary = comparison?.traceSummary
        }
    }

    func recordAggregation(path: String?, summary: String?) {
        guard isEnabled else { return }
        mutate { draft in
            draft.aggregationPath = path
            draft.finalAnswerSummary = summary ?? draft.finalAnswerSummary
        }
    }

    func recordResponse(type: String?, finalAnswerSummary: String?) {
        guard isEnabled else { return }
        mutate { draft in
            draft.responseType = type
            draft.finalAnswerSummary = finalAnswerSummary
        }
    }

    func recordSharedPipelineTrace(_ trace: MarinaSharedPipelineTrace) {
        guard isEnabled else { return }
        mutate { draft in
            draft.sharedPipelineEnabled = trace.sharedPipelineEnabled
            draft.sharedPipelinePath = trace.selectedPath
            draft.sharedPipelineInterpreterSource = trace.interpreterSource
            draft.sharedPipelineCandidateSummary = trace.candidateSummary
            draft.sharedPipelineResolverSummary = trace.resolverSummary
            draft.sharedPipelineValidatorSummary = trace.validatorOutcomeSummary
            draft.sharedPipelineExecutorSummary = trace.executorResultSummary
            draft.sharedPipelineResponseBridgeSummary = trace.responseBridgeSummary
            draft.sharedPipelineFallbackReason = trace.fallbackReason
            draft.sharedPipelineDisagreementSummary = trace.disagreementSummary
        }
    }

    @discardableResult
    func finish() -> MarinaExecutionTrace? {
        guard isEnabled else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let draft = currentDraft else { return nil }
        let trace = draft.freeze()
        completed.append(trace)
        currentDraft = nil
        MarinaDebugLogger.log("[MarinaTrace] \(trace.sanitizedLogLine)")
        return trace
    }

    var latestTrace: MarinaExecutionTrace? {
        lock.lock()
        defer { lock.unlock() }
        return completed.last
    }

    private func mutate(_ body: (inout MarinaExecutionTraceDraft) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard var draft = currentDraft else { return }
        body(&draft)
        currentDraft = draft
    }
}

private struct MarinaExecutionTraceDraft {
    let originalPrompt: String
    let routingMode: MarinaExecutionRoutingMode
    let marinaNLQv1Enabled: Bool

    var modelWasAvailable: Bool = false
    var modelAvailabilityReason: String?
    var modelOutputSummary: String?
    var modelPlanSummary: String?
    var modelValidationSummary: String?

    var fallbackWasAttempted: Bool = false
    var fallbackOutputSummary: String?
    var fallbackSelectionReason: MarinaExecutionFallbackReason?
    var fallbackReplacedModelOutput: Bool = false

    var selectedRoute: MarinaExecutionSelectedRoute = .unresolved
    var selectedRouteReason: String?

    var normalizedMetric: String?
    var normalizedOperation: String?
    var presentationIntent: String?

    var targetText: String?
    var targetType: String?
    var resolvedTargetSummary: String?

    var primaryDateRangeSummary: String?
    var comparisonDateRangeSummary: String?

    var aggregationPath: String?
    var responseType: String?
    var finalAnswerSummary: String?

    var sharedPipelineEnabled: Bool?
    var sharedPipelinePath: MarinaSharedPipelineRuntimePath?
    var sharedPipelineInterpreterSource: MarinaInterpreterSource?
    var sharedPipelineCandidateSummary: String?
    var sharedPipelineResolverSummary: String?
    var sharedPipelineValidatorSummary: String?
    var sharedPipelineExecutorSummary: String?
    var sharedPipelineResponseBridgeSummary: String?
    var sharedPipelineFallbackReason: MarinaSharedPipelineFallbackReason?
    var sharedPipelineDisagreementSummary: String?

    func freeze() -> MarinaExecutionTrace {
        MarinaExecutionTrace(
            originalPrompt: originalPrompt,
            routingMode: routingMode,
            marinaNLQv1Enabled: marinaNLQv1Enabled,
            modelWasAvailable: modelWasAvailable,
            modelAvailabilityReason: modelAvailabilityReason,
            modelOutputSummary: modelOutputSummary,
            modelPlanSummary: modelPlanSummary,
            modelValidationSummary: modelValidationSummary,
            fallbackWasAttempted: fallbackWasAttempted,
            fallbackOutputSummary: fallbackOutputSummary,
            fallbackSelectionReason: fallbackSelectionReason,
            fallbackReplacedModelOutput: fallbackReplacedModelOutput,
            selectedRoute: selectedRoute,
            selectedRouteReason: selectedRouteReason,
            normalizedMetric: normalizedMetric,
            normalizedOperation: normalizedOperation,
            presentationIntent: presentationIntent,
            targetText: targetText,
            targetType: targetType,
            resolvedTargetSummary: resolvedTargetSummary,
            primaryDateRangeSummary: primaryDateRangeSummary,
            comparisonDateRangeSummary: comparisonDateRangeSummary,
            aggregationPath: aggregationPath,
            responseType: responseType,
            finalAnswerSummary: finalAnswerSummary,
            sharedPipelineEnabled: sharedPipelineEnabled,
            sharedPipelinePath: sharedPipelinePath,
            sharedPipelineInterpreterSource: sharedPipelineInterpreterSource,
            sharedPipelineCandidateSummary: sharedPipelineCandidateSummary,
            sharedPipelineResolverSummary: sharedPipelineResolverSummary,
            sharedPipelineValidatorSummary: sharedPipelineValidatorSummary,
            sharedPipelineExecutorSummary: sharedPipelineExecutorSummary,
            sharedPipelineResponseBridgeSummary: sharedPipelineResponseBridgeSummary,
            sharedPipelineFallbackReason: sharedPipelineFallbackReason,
            sharedPipelineDisagreementSummary: sharedPipelineDisagreementSummary
        )
    }
}

extension MarinaExecutionTrace {
    var sanitizedLogLine: String {
        [
            "prompt=\(originalPrompt)",
            "mode=\(routingMode.rawValue)",
            "route=\(selectedRoute.rawValue)",
            "fallback=\(fallbackWasAttempted)",
            "fallbackReason=\(fallbackSelectionReason?.rawValue ?? "none")",
            "sharedPath=\(sharedPipelinePath?.rawValue ?? "none")",
            "sharedFallback=\(sharedPipelineFallbackReason?.rawValue ?? "none")",
            "metric=\(normalizedMetric ?? "nil")",
            "response=\(responseType ?? "nil")"
        ].joined(separator: " | ")
    }
}

extension HomeQueryDateRange {
    var traceSummary: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: startDate))..\(formatter.string(from: endDate))"
    }
}

extension MarinaInterpretedRequest {
    var traceSummary: String {
        switch self {
        case .query(let plan, let source):
            return "query(source=\(source.rawValue),metric=\(plan.metric.rawValue),target=\(plan.targetName ?? "nil"))"
        case .command(let command, let source):
            return "command(source=\(source.rawValue),intent=\(command.intent.rawValue))"
        case .clarification(_, let source):
            return "clarification(source=\(source?.rawValue ?? "nil"))"
        case .unresolved:
            return "unresolved"
        }
    }
}

extension HomeAnswer {
    var traceSummary: String {
        "kind=\(kind.rawValue),title=\(title),rows=\(rows.count)"
    }
}

extension HomeQueryPlan {
    var traceSummary: String {
        "metric=\(metric.rawValue),target=\(targetName ?? "nil"),date=\(dateRange?.traceSummary ?? "nil"),comparison=\(comparisonDateRange?.traceSummary ?? "nil")"
    }
}

extension HomeQueryMetric {
    var traceOperation: String {
        switch self {
        case .spendTotal, .categorySpendTotal, .cardSpendTotal, .merchantSpendTotal:
            return "sum"
        case .spendAveragePerPeriod, .incomeAverageActual, .savingsAverageRecentPeriods:
            return "average"
        case .mostFrequentTransactions:
            return "count"
        case .monthComparison, .categoryMonthComparison, .cardMonthComparison, .incomeSourceMonthComparison, .merchantMonthComparison:
            return "difference"
        case .categorySpendShare, .incomeSourceShare:
            return "share_of_total"
        case .topCategories, .topMerchants, .largestTransactions, .topCategoryChanges, .topCardChanges:
            return "ranked_list"
        case .overview, .savingsStatus, .safeSpendToday, .forecastSavings, .nextPlannedExpense, .spendTrendsSummary, .cardSnapshotSummary:
            return "overview"
        default:
            return "metric"
        }
    }
}

extension MarinaNormalizedMetric {
    var traceOperation: String {
        switch self {
        case .spendTotal, .categorySpendTotal, .merchantSpendTotal:
            return "sum"
        case .spendAveragePerPeriod, .incomeAverageActual:
            return "average"
        case .mostFrequentTransactions:
            return "count"
        case .monthComparison, .categoryMonthComparison:
            return "difference"
        case .categorySpendShare:
            return "share_of_total"
        case .topCategories, .topMerchants, .largestTransactions:
            return "ranked_list"
        case .presetDueSoon:
            return "overview"
        }
    }
}
