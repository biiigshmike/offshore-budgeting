import Foundation

struct MarinaExecutionTrace: Equatable {
    let originalPrompt: String
    let routingMode: MarinaExecutionRoutingMode
    let marinaNLQv1Enabled: Bool
    let runtimeSettingsSummary: String?

    let modelWasAvailable: Bool
    let modelAvailabilityReason: String?
    let modelOutputSummary: String?
    let modelPlanSummary: String?
    let modelValidationSummary: String?
    let foundationModelFailureStep: String?
    let foundationModelFailureCategory: String?
    let foundationModelFailureDebugSummary: String?
    let foundationRepairSummary: String?
    let liveEnvelopeSummary: String?
    let canonicalRouteSummary: String?
    let routeOverrideSummary: String?
    let routeGuardSummary: String?
    let routeKeySummary: String?
    let droppedTargetSummary: String?
    let datePolicySummary: String?
    let dateSourceSummary: String?
    let effectiveDateRangeSummary: String?
    let routeRescueSummary: String?
    let blockedWrongQuery: Bool?

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
    let responseSurfaceSource: MarinaResponseSurfaceSource?
    let responseSurfaceFallbackReason: MarinaResponseGenerationFallbackReason?

    let sharedPipelineEnabled: Bool?
    let sharedPipelinePath: MarinaSharedPipelineRuntimePath?
    let sharedPipelineInterpreterSource: MarinaInterpreterSource?
    let sharedPipelineHeuristicAttempted: Bool?
    let sharedPipelineHeuristicUsedAsFallback: Bool?
    let sharedPipelineCandidateSummary: String?
    let sharedPipelineResolverSummary: String?
    let sharedPipelineValidatorSummary: String?
    let sharedPipelineExecutorSummary: String?
    let sharedPipelineResponseBridgeSummary: String?
    let sharedPipelineResponseShapeSummary: String?
    let sharedPipelineSemanticInterpretationSummary: String?
    let sharedPipelineSemanticResolverSummary: String?
    let sharedPipelineSemanticValidationSummary: String?
    let sharedPipelineFallbackReason: MarinaSharedPipelineFallbackReason?
    let sharedPipelineDisagreementSummary: String?
    let sharedPipelineTurnClassification: MarinaPromptTurnClassification?
    let sharedPipelinePriorContextIncluded: Bool?
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
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
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
        marinaNLQv1Enabled: Bool,
        runtimeSettingsSummary: String? = nil
    ) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        currentDraft = MarinaExecutionTraceDraft(
            originalPrompt: prompt,
            routingMode: routingMode,
            marinaNLQv1Enabled: marinaNLQv1Enabled,
            runtimeSettingsSummary: runtimeSettingsSummary
        )
    }

    func ensure(
        prompt: String,
        routingMode: MarinaExecutionRoutingMode,
        marinaNLQv1Enabled: Bool,
        runtimeSettingsSummary: String? = nil
    ) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if currentDraft == nil {
            currentDraft = MarinaExecutionTraceDraft(
                originalPrompt: prompt,
                routingMode: routingMode,
                marinaNLQv1Enabled: marinaNLQv1Enabled,
                runtimeSettingsSummary: runtimeSettingsSummary
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

    func recordFoundationModelsFailure(_ diagnostic: MarinaFoundationModelsFailureDiagnostic) {
        guard isEnabled else { return }
        mutate { draft in
            draft.foundationModelFailureStep = diagnostic.step.rawValue
            draft.foundationModelFailureCategory = diagnostic.category.rawValue
            draft.foundationModelFailureDebugSummary = diagnostic.debugSummary
            draft.modelValidationSummary = diagnostic.traceSummary
        }
    }

    func recordFoundationRepairSummary(_ summary: String?) {
        guard isEnabled else { return }
        mutate { draft in
            draft.foundationRepairSummary = summary
        }
    }

    func recordLiveRouteOwnership(
        liveEnvelopeSummary: String?,
        canonicalRouteSummary: String?,
        routeOverrideSummary: String?,
        routeGuardSummary: String?,
        routeKeySummary: String?,
        droppedTargetSummary: String?,
        datePolicySummary: String?,
        dateSourceSummary: String?,
        effectiveDateRangeSummary: String?,
        routeRescueSummary: String?,
        blockedWrongQuery: Bool
    ) {
        guard isEnabled else { return }
        mutate { draft in
            draft.liveEnvelopeSummary = liveEnvelopeSummary
            draft.canonicalRouteSummary = canonicalRouteSummary
            draft.routeOverrideSummary = routeOverrideSummary
            draft.routeGuardSummary = routeGuardSummary
            draft.routeKeySummary = routeKeySummary
            draft.droppedTargetSummary = droppedTargetSummary
            draft.datePolicySummary = datePolicySummary
            draft.dateSourceSummary = dateSourceSummary
            draft.effectiveDateRangeSummary = effectiveDateRangeSummary
            draft.routeRescueSummary = routeRescueSummary
            draft.blockedWrongQuery = blockedWrongQuery
        }
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

    func recordResponseSurface(
        source: MarinaResponseSurfaceSource,
        fallbackReason: MarinaResponseGenerationFallbackReason?
    ) {
        guard isEnabled else { return }
        mutate { draft in
            draft.responseSurfaceSource = source
            draft.responseSurfaceFallbackReason = fallbackReason
        }
    }

    func recordDebugMarker(_ marker: String) {
        guard isEnabled else { return }
        mutate { draft in
            let existing = draft.finalAnswerSummary
            draft.finalAnswerSummary = [existing, "debug=\(marker)"]
                .compactMap { $0 }
                .joined(separator: ";")
        }
    }

    func recordSharedPipelineTurnClassification(_ turnClassification: MarinaPromptTurnClassification) {
        guard isEnabled else { return }
        mutate { draft in
            draft.sharedPipelineTurnClassification = turnClassification
        }
    }

    func recordSharedPipelineTrace(_ trace: MarinaSharedPipelineTrace) {
        guard isEnabled else { return }
        mutate { draft in
            draft.sharedPipelineEnabled = trace.sharedPipelineEnabled
            draft.sharedPipelinePath = trace.selectedPath
            draft.sharedPipelineInterpreterSource = trace.interpreterSource
            draft.sharedPipelineHeuristicAttempted = trace.heuristicAttempted
            draft.sharedPipelineHeuristicUsedAsFallback = trace.heuristicUsedAsFallback
            draft.sharedPipelineCandidateSummary = trace.candidateSummary
            draft.sharedPipelineResolverSummary = trace.resolverSummary
            draft.sharedPipelineValidatorSummary = trace.validatorOutcomeSummary
            draft.sharedPipelineExecutorSummary = trace.executorResultSummary
            draft.sharedPipelineResponseBridgeSummary = trace.responseBridgeSummary
            draft.sharedPipelineResponseShapeSummary = trace.responseShapeSummary
            draft.sharedPipelineSemanticInterpretationSummary = trace.semanticInterpretationSummary
            draft.sharedPipelineSemanticResolverSummary = trace.semanticResolverSummary
            draft.sharedPipelineSemanticValidationSummary = trace.semanticValidationSummary
            draft.sharedPipelineFallbackReason = trace.fallbackReason
            draft.sharedPipelineDisagreementSummary = trace.disagreementSummary
            draft.sharedPipelineTurnClassification = trace.turnClassification
            draft.sharedPipelinePriorContextIncluded = trace.priorContextIncluded
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
        MarinaTraceExporter.exportIfConfigured(trace)
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
    let runtimeSettingsSummary: String?

    var modelWasAvailable: Bool = false
    var modelAvailabilityReason: String?
    var modelOutputSummary: String?
    var modelPlanSummary: String?
    var modelValidationSummary: String?
    var foundationModelFailureStep: String?
    var foundationModelFailureCategory: String?
    var foundationModelFailureDebugSummary: String?
    var foundationRepairSummary: String?
    var liveEnvelopeSummary: String?
    var canonicalRouteSummary: String?
    var routeOverrideSummary: String?
    var routeGuardSummary: String?
    var routeKeySummary: String?
    var droppedTargetSummary: String?
    var datePolicySummary: String?
    var dateSourceSummary: String?
    var effectiveDateRangeSummary: String?
    var routeRescueSummary: String?
    var blockedWrongQuery: Bool?

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
    var responseSurfaceSource: MarinaResponseSurfaceSource?
    var responseSurfaceFallbackReason: MarinaResponseGenerationFallbackReason?

    var sharedPipelineEnabled: Bool?
    var sharedPipelinePath: MarinaSharedPipelineRuntimePath?
    var sharedPipelineInterpreterSource: MarinaInterpreterSource?
    var sharedPipelineHeuristicAttempted: Bool?
    var sharedPipelineHeuristicUsedAsFallback: Bool?
    var sharedPipelineCandidateSummary: String?
    var sharedPipelineResolverSummary: String?
    var sharedPipelineValidatorSummary: String?
    var sharedPipelineExecutorSummary: String?
    var sharedPipelineResponseBridgeSummary: String?
    var sharedPipelineResponseShapeSummary: String?
    var sharedPipelineSemanticInterpretationSummary: String?
    var sharedPipelineSemanticResolverSummary: String?
    var sharedPipelineSemanticValidationSummary: String?
    var sharedPipelineFallbackReason: MarinaSharedPipelineFallbackReason?
    var sharedPipelineDisagreementSummary: String?
    var sharedPipelineTurnClassification: MarinaPromptTurnClassification?
    var sharedPipelinePriorContextIncluded: Bool?

    func freeze() -> MarinaExecutionTrace {
        MarinaExecutionTrace(
            originalPrompt: originalPrompt,
            routingMode: routingMode,
            marinaNLQv1Enabled: marinaNLQv1Enabled,
            runtimeSettingsSummary: runtimeSettingsSummary,
            modelWasAvailable: modelWasAvailable,
            modelAvailabilityReason: modelAvailabilityReason,
            modelOutputSummary: modelOutputSummary,
            modelPlanSummary: modelPlanSummary,
            modelValidationSummary: modelValidationSummary,
            foundationModelFailureStep: foundationModelFailureStep,
            foundationModelFailureCategory: foundationModelFailureCategory,
            foundationModelFailureDebugSummary: foundationModelFailureDebugSummary,
            foundationRepairSummary: foundationRepairSummary,
            liveEnvelopeSummary: liveEnvelopeSummary,
            canonicalRouteSummary: canonicalRouteSummary,
            routeOverrideSummary: routeOverrideSummary,
            routeGuardSummary: routeGuardSummary,
            routeKeySummary: routeKeySummary,
            droppedTargetSummary: droppedTargetSummary,
            datePolicySummary: datePolicySummary,
            dateSourceSummary: dateSourceSummary,
            effectiveDateRangeSummary: effectiveDateRangeSummary,
            routeRescueSummary: routeRescueSummary,
            blockedWrongQuery: blockedWrongQuery,
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
            responseSurfaceSource: responseSurfaceSource,
            responseSurfaceFallbackReason: responseSurfaceFallbackReason,
            sharedPipelineEnabled: sharedPipelineEnabled,
            sharedPipelinePath: sharedPipelinePath,
            sharedPipelineInterpreterSource: sharedPipelineInterpreterSource,
            sharedPipelineHeuristicAttempted: sharedPipelineHeuristicAttempted,
            sharedPipelineHeuristicUsedAsFallback: sharedPipelineHeuristicUsedAsFallback,
            sharedPipelineCandidateSummary: sharedPipelineCandidateSummary,
            sharedPipelineResolverSummary: sharedPipelineResolverSummary,
            sharedPipelineValidatorSummary: sharedPipelineValidatorSummary,
            sharedPipelineExecutorSummary: sharedPipelineExecutorSummary,
            sharedPipelineResponseBridgeSummary: sharedPipelineResponseBridgeSummary,
            sharedPipelineResponseShapeSummary: sharedPipelineResponseShapeSummary,
            sharedPipelineSemanticInterpretationSummary: sharedPipelineSemanticInterpretationSummary,
            sharedPipelineSemanticResolverSummary: sharedPipelineSemanticResolverSummary,
            sharedPipelineSemanticValidationSummary: sharedPipelineSemanticValidationSummary,
            sharedPipelineFallbackReason: sharedPipelineFallbackReason,
            sharedPipelineDisagreementSummary: sharedPipelineDisagreementSummary,
            sharedPipelineTurnClassification: sharedPipelineTurnClassification,
            sharedPipelinePriorContextIncluded: sharedPipelinePriorContextIncluded
        )
    }
}

struct MarinaExecutionTraceSnapshot: Codable, Equatable {
    let capturedAtISO8601: String
    let originalPrompt: String
    let promptVersion: String
    let routingMode: String
    let marinaNLQv1Enabled: Bool
    let runtimeSettingsSummary: String?
    let modelWasAvailable: Bool
    let modelAvailabilityReason: String?
    let selectedRoute: String
    let selectedRouteReason: String?
    let foundationModelFailureStep: String?
    let foundationModelFailureCategory: String?
    let foundationModelFailureDebugSummary: String?
    let foundationRepairSummary: String?
    let liveEnvelopeSummary: String?
    let canonicalRouteSummary: String?
    let routeOverrideSummary: String?
    let routeGuardSummary: String?
    let routeKeySummary: String?
    let droppedTargetSummary: String?
    let datePolicySummary: String?
    let dateSourceSummary: String?
    let effectiveDateRangeSummary: String?
    let routeRescueSummary: String?
    let blockedWrongQuery: Bool?
    let aggregationPath: String?
    let responseType: String?
    let finalAnswerSummary: String?
    let responseSurfaceSource: String?
    let responseSurfaceFallbackReason: String?
    let sharedPipelineEnabled: Bool?
    let sharedPipelinePath: String?
    let sharedPipelineInterpreterSource: String?
    let sharedPipelineHeuristicAttempted: Bool?
    let sharedPipelineHeuristicUsedAsFallback: Bool?
    let sharedPipelineCandidateSummary: String?
    let sharedPipelineResolverSummary: String?
    let sharedPipelineValidatorSummary: String?
    let sharedPipelineExecutorSummary: String?
    let sharedPipelineResponseBridgeSummary: String?
    let sharedPipelineResponseShapeSummary: String?
    let sharedPipelineSemanticInterpretationSummary: String?
    let sharedPipelineSemanticResolverSummary: String?
    let sharedPipelineSemanticValidationSummary: String?
    let sharedPipelineFallbackReason: String?
    let sharedPipelineDisagreementSummary: String?
    let turnClassification: String?
    let priorContextIncluded: Bool?
    let dataWasQueried: Bool

    init(_ trace: MarinaExecutionTrace) {
        self.capturedAtISO8601 = marinaTraceISO8601String(from: Date())
        self.originalPrompt = trace.originalPrompt
        self.promptVersion = MarinaFoundationPromptVersion.interpretationV3.rawValue
        self.routingMode = trace.routingMode.rawValue
        self.marinaNLQv1Enabled = trace.marinaNLQv1Enabled
        self.runtimeSettingsSummary = trace.runtimeSettingsSummary
        self.modelWasAvailable = trace.modelWasAvailable
        self.modelAvailabilityReason = trace.modelAvailabilityReason
        self.selectedRoute = trace.selectedRoute.rawValue
        self.selectedRouteReason = trace.selectedRouteReason
        self.foundationModelFailureStep = trace.foundationModelFailureStep
        self.foundationModelFailureCategory = trace.foundationModelFailureCategory
        self.foundationModelFailureDebugSummary = trace.foundationModelFailureDebugSummary.map(marinaSanitizedDebugSummary)
        self.foundationRepairSummary = trace.foundationRepairSummary
        self.liveEnvelopeSummary = trace.liveEnvelopeSummary
        self.canonicalRouteSummary = trace.canonicalRouteSummary
        self.routeOverrideSummary = trace.routeOverrideSummary
        self.routeGuardSummary = trace.routeGuardSummary
        self.routeKeySummary = trace.routeKeySummary
        self.droppedTargetSummary = trace.droppedTargetSummary
        self.datePolicySummary = trace.datePolicySummary
        self.dateSourceSummary = trace.dateSourceSummary
        self.effectiveDateRangeSummary = trace.effectiveDateRangeSummary
        self.routeRescueSummary = trace.routeRescueSummary
        self.blockedWrongQuery = trace.blockedWrongQuery
        self.aggregationPath = trace.aggregationPath
        self.responseType = trace.responseType
        self.finalAnswerSummary = trace.finalAnswerSummary
        self.responseSurfaceSource = trace.responseSurfaceSource?.rawValue
        self.responseSurfaceFallbackReason = trace.responseSurfaceFallbackReason?.rawValue
        self.sharedPipelineEnabled = trace.sharedPipelineEnabled
        self.sharedPipelinePath = trace.sharedPipelinePath?.rawValue
        self.sharedPipelineInterpreterSource = trace.sharedPipelineInterpreterSource?.rawValue
        self.sharedPipelineHeuristicAttempted = trace.sharedPipelineHeuristicAttempted
        self.sharedPipelineHeuristicUsedAsFallback = trace.sharedPipelineHeuristicUsedAsFallback
        self.sharedPipelineCandidateSummary = trace.sharedPipelineCandidateSummary
        self.sharedPipelineResolverSummary = trace.sharedPipelineResolverSummary
        self.sharedPipelineValidatorSummary = trace.sharedPipelineValidatorSummary
        self.sharedPipelineExecutorSummary = trace.sharedPipelineExecutorSummary
        self.sharedPipelineResponseBridgeSummary = trace.sharedPipelineResponseBridgeSummary
        self.sharedPipelineResponseShapeSummary = trace.sharedPipelineResponseShapeSummary
        self.sharedPipelineSemanticInterpretationSummary = trace.sharedPipelineSemanticInterpretationSummary
        self.sharedPipelineSemanticResolverSummary = trace.sharedPipelineSemanticResolverSummary
        self.sharedPipelineSemanticValidationSummary = trace.sharedPipelineSemanticValidationSummary
        self.sharedPipelineFallbackReason = trace.sharedPipelineFallbackReason?.rawValue
        self.sharedPipelineDisagreementSummary = trace.sharedPipelineDisagreementSummary
        self.turnClassification = trace.sharedPipelineTurnClassification?.rawValue
        self.priorContextIncluded = trace.sharedPipelinePriorContextIncluded
        self.dataWasQueried = trace.sharedPipelineExecutorSummary != nil
    }

    var accessibilityValue: String {
        [
            "prompt=\(originalPrompt)",
            "routingMode=\(routingMode)",
            "selectedRoute=\(selectedRoute)",
            foundationModelFailureStep.map { "foundationStep=\($0)" },
            foundationModelFailureCategory.map { "foundationCategory=\($0)" },
            foundationRepairSummary.map { "foundationRepair=\($0)" },
            liveEnvelopeSummary.map { "liveEnvelope=\($0)" },
            canonicalRouteSummary.map { "canonicalRoute=\($0)" },
            routeOverrideSummary.map { "routeOverride=\($0)" },
            routeGuardSummary.map { "routeGuard=\($0)" },
            routeKeySummary.map { "routeKey=\($0)" },
            droppedTargetSummary.map { "droppedTarget=\($0)" },
            datePolicySummary.map { "datePolicy=\($0)" },
            dateSourceSummary.map { "dateSource=\($0)" },
            effectiveDateRangeSummary.map { "effectiveDateRange=\($0)" },
            routeRescueSummary.map { "routeRescue=\($0)" },
            blockedWrongQuery.map { "blockedWrongQuery=\($0)" },
            sharedPipelinePath.map { "sharedPath=\($0)" },
            sharedPipelineInterpreterSource.map { "interpreter=\($0)" },
            sharedPipelineHeuristicAttempted.map { "heuristicAttempted=\($0)" },
            sharedPipelineHeuristicUsedAsFallback.map { "heuristicUsedAsFallback=\($0)" },
            turnClassification.map { "turnClassification=\($0)" },
            priorContextIncluded.map { "priorContextIncluded=\($0)" },
            sharedPipelineCandidateSummary.map { "candidate=\($0)" },
            aggregationPath.map { "aggregationPath=\($0)" },
            responseType.map { "responseType=\($0)" },
            responseSurfaceSource.map { "responseSurface=\($0)" },
            responseSurfaceFallbackReason.map { "responseSurfaceFallback=\($0)" },
            sharedPipelineExecutorSummary.map { "executor=\($0)" },
            sharedPipelineResponseBridgeSummary.map { "bridge=\($0)" },
            sharedPipelineFallbackReason.map { "fallback=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " | ")
    }
}

enum MarinaTraceExporter {
    static func exportIfConfigured(_ trace: MarinaExecutionTrace) {
        #if DEBUG
        MarinaSmokeTraceStore.exportIfEnabled(trace)

        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[MarinaRuntimeSettings.traceOutputPathEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              path.isEmpty == false else {
            return
        }

        let snapshot = MarinaExecutionTraceSnapshot(trace)
        do {
            let data = try JSONEncoder().encode(snapshot)
            let url = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: Data("\n".utf8))
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            MarinaDebugLogger.log("[MarinaTraceExporter] failed path='\(path)' error='\(error)'")
        }
        #endif
    }
}

private func marinaTraceISO8601String(from date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func marinaSanitizedDebugSummary(_ rawValue: String) -> String {
    let collapsed = rawValue
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let schemaOnly = collapsed
        .replacingOccurrences(
            of: #"Text:\s*\{.*"#,
            with: "Text:{redacted-generated-content}",
            options: .regularExpression
        )
    return String(schemaOnly.prefix(700))
}

extension MarinaExecutionTrace {
    var sanitizedLogLine: String {
        [
            "prompt=\(originalPrompt)",
            "mode=\(routingMode.rawValue)",
            runtimeSettingsSummary.map { "runtime=\($0)" },
            "route=\(selectedRoute.rawValue)",
            "fallback=\(fallbackWasAttempted)",
            "fallbackReason=\(fallbackSelectionReason?.rawValue ?? "none")",
            "sharedPath=\(sharedPipelinePath?.rawValue ?? "none")",
            "sharedFallback=\(sharedPipelineFallbackReason?.rawValue ?? "none")",
            "metric=\(normalizedMetric ?? "nil")",
            "response=\(responseType ?? "nil")",
            "surface=\(responseSurfaceSource?.rawValue ?? "nil")",
            "surfaceFallback=\(responseSurfaceFallbackReason?.rawValue ?? "nil")",
            foundationModelFailureStep.map { "foundationStep=\($0)" },
            foundationModelFailureCategory.map { "foundationCategory=\($0)" },
            foundationRepairSummary.map { "foundationRepair=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " | ")
    }
}

extension HomeQueryDateRange {
    var traceSummary: String {
        MarinaDateOnlyRangeCodec.traceSummary(self) ?? "nil"
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
