import Foundation

struct MarinaExecutionTrace: Equatable {
    let originalPrompt: String
    let routingMode: MarinaExecutionRoutingMode
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
    let foundationTranscriptSummary: String?
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
    let responseSurfaceRecoveryReason: MarinaResponseGenerationRecoveryReason?

    let foundationPipelineEnabled: Bool?
    let foundationPipelinePath: MarinaFoundationPipelineRuntimePath?
    let foundationPipelineInterpreterSource: MarinaInterpretationSource?
    let foundationPipelineCandidateSummary: String?
    let foundationPipelineResolverSummary: String?
    let foundationPipelineValidatorSummary: String?
    let foundationPipelineExecutorSummary: String?
    let foundationPipelineResponseBridgeSummary: String?
    let foundationPipelineResponseShapeSummary: String?
    let foundationPipelineSemanticInterpretationSummary: String?
    let foundationPipelineSemanticResolverSummary: String?
    let foundationPipelineSemanticValidationSummary: String?
    let foundationPipelineRecoveryReason: MarinaFoundationPipelineRecoveryReason?
    let foundationPipelineDisagreementSummary: String?
    let foundationPipelineTurnClassification: MarinaPromptTurnClassification?
    let foundationPipelinePriorContextIncluded: Bool?
}

enum MarinaExecutionRoutingMode: String, Equatable {
    case foundationPipeline = "foundationPipeline"
}

enum MarinaExecutionSelectedRoute: String, Equatable {
    case foundationModels = "foundationModels"
    case clarification
    case recovery
    case unresolved
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
        runtimeSettingsSummary: String? = nil
    ) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        currentDraft = MarinaExecutionTraceDraft(
            originalPrompt: prompt,
            routingMode: routingMode,
            runtimeSettingsSummary: runtimeSettingsSummary
        )
    }

    func ensure(
        prompt: String,
        routingMode: MarinaExecutionRoutingMode,
        runtimeSettingsSummary: String? = nil
    ) {
        guard isEnabled else { return }
        lock.lock()
        defer { lock.unlock() }
        if currentDraft == nil {
            currentDraft = MarinaExecutionTraceDraft(
                originalPrompt: prompt,
                routingMode: routingMode,
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
                draft.modelAvailabilityReason = reason.rawValue
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

    func recordFoundationTranscriptSummary(_ summary: String?) {
        guard isEnabled else { return }
        mutate { draft in
            draft.foundationTranscriptSummary = summary
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
        recoveryReason: MarinaResponseGenerationRecoveryReason?
    ) {
        guard isEnabled else { return }
        mutate { draft in
            draft.responseSurfaceSource = source
            draft.responseSurfaceRecoveryReason = recoveryReason
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

    func recordFoundationPipelineTurnClassification(_ turnClassification: MarinaPromptTurnClassification) {
        guard isEnabled else { return }
        mutate { draft in
            draft.foundationPipelineTurnClassification = turnClassification
        }
    }

    func recordFoundationPipelineTrace(_ trace: MarinaFoundationPipelineTrace) {
        guard isEnabled else { return }
        mutate { draft in
            draft.foundationPipelineEnabled = trace.foundationPipelineEnabled
            draft.foundationPipelinePath = trace.selectedPath
            draft.foundationPipelineInterpreterSource = trace.interpreterSource
            draft.foundationPipelineCandidateSummary = trace.candidateSummary
            draft.foundationPipelineResolverSummary = trace.resolverSummary
            draft.foundationPipelineValidatorSummary = trace.validatorOutcomeSummary
            draft.foundationPipelineExecutorSummary = trace.executorResultSummary
            draft.foundationPipelineResponseBridgeSummary = trace.responseBridgeSummary
            draft.foundationPipelineResponseShapeSummary = trace.responseShapeSummary
            draft.foundationPipelineSemanticInterpretationSummary = trace.semanticInterpretationSummary
            draft.foundationPipelineSemanticResolverSummary = trace.semanticResolverSummary
            draft.foundationPipelineSemanticValidationSummary = trace.semanticValidationSummary
            draft.foundationPipelineRecoveryReason = trace.recoveryReason
            draft.foundationPipelineDisagreementSummary = trace.disagreementSummary
            draft.foundationPipelineTurnClassification = trace.turnClassification
            draft.foundationPipelinePriorContextIncluded = trace.priorContextIncluded
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
    var foundationTranscriptSummary: String?
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
    var responseSurfaceRecoveryReason: MarinaResponseGenerationRecoveryReason?

    var foundationPipelineEnabled: Bool?
    var foundationPipelinePath: MarinaFoundationPipelineRuntimePath?
    var foundationPipelineInterpreterSource: MarinaInterpretationSource?
    var foundationPipelineCandidateSummary: String?
    var foundationPipelineResolverSummary: String?
    var foundationPipelineValidatorSummary: String?
    var foundationPipelineExecutorSummary: String?
    var foundationPipelineResponseBridgeSummary: String?
    var foundationPipelineResponseShapeSummary: String?
    var foundationPipelineSemanticInterpretationSummary: String?
    var foundationPipelineSemanticResolverSummary: String?
    var foundationPipelineSemanticValidationSummary: String?
    var foundationPipelineRecoveryReason: MarinaFoundationPipelineRecoveryReason?
    var foundationPipelineDisagreementSummary: String?
    var foundationPipelineTurnClassification: MarinaPromptTurnClassification?
    var foundationPipelinePriorContextIncluded: Bool?

    func freeze() -> MarinaExecutionTrace {
        MarinaExecutionTrace(
            originalPrompt: originalPrompt,
            routingMode: routingMode,
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
            foundationTranscriptSummary: foundationTranscriptSummary,
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
            responseSurfaceRecoveryReason: responseSurfaceRecoveryReason,
            foundationPipelineEnabled: foundationPipelineEnabled,
            foundationPipelinePath: foundationPipelinePath,
            foundationPipelineInterpreterSource: foundationPipelineInterpreterSource,
            foundationPipelineCandidateSummary: foundationPipelineCandidateSummary,
            foundationPipelineResolverSummary: foundationPipelineResolverSummary,
            foundationPipelineValidatorSummary: foundationPipelineValidatorSummary,
            foundationPipelineExecutorSummary: foundationPipelineExecutorSummary,
            foundationPipelineResponseBridgeSummary: foundationPipelineResponseBridgeSummary,
            foundationPipelineResponseShapeSummary: foundationPipelineResponseShapeSummary,
            foundationPipelineSemanticInterpretationSummary: foundationPipelineSemanticInterpretationSummary,
            foundationPipelineSemanticResolverSummary: foundationPipelineSemanticResolverSummary,
            foundationPipelineSemanticValidationSummary: foundationPipelineSemanticValidationSummary,
            foundationPipelineRecoveryReason: foundationPipelineRecoveryReason,
            foundationPipelineDisagreementSummary: foundationPipelineDisagreementSummary,
            foundationPipelineTurnClassification: foundationPipelineTurnClassification,
            foundationPipelinePriorContextIncluded: foundationPipelinePriorContextIncluded
        )
    }
}

struct MarinaExecutionTraceSnapshot: Codable, Equatable {
    let capturedAtISO8601: String
    let originalPrompt: String
    let promptVersion: String
    let routingMode: String
    let runtimeSettingsSummary: String?
    let modelWasAvailable: Bool
    let modelAvailabilityReason: String?
    let selectedRoute: String
    let selectedRouteReason: String?
    let foundationModelFailureStep: String?
    let foundationModelFailureCategory: String?
    let foundationModelFailureDebugSummary: String?
    let foundationRepairSummary: String?
    let foundationTranscriptSummary: String?
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
    let responseSurfaceRecoveryReason: String?
    let foundationPipelineEnabled: Bool?
    let foundationPipelinePath: String?
    let foundationPipelineInterpreterSource: String?
    let foundationPipelineCandidateSummary: String?
    let foundationPipelineResolverSummary: String?
    let foundationPipelineValidatorSummary: String?
    let foundationPipelineExecutorSummary: String?
    let foundationPipelineResponseBridgeSummary: String?
    let foundationPipelineResponseShapeSummary: String?
    let foundationPipelineSemanticInterpretationSummary: String?
    let foundationPipelineSemanticResolverSummary: String?
    let foundationPipelineSemanticValidationSummary: String?
    let foundationPipelineRecoveryReason: String?
    let foundationPipelineDisagreementSummary: String?
    let turnClassification: String?
    let priorContextIncluded: Bool?
    let dataWasQueried: Bool

    init(_ trace: MarinaExecutionTrace) {
        self.capturedAtISO8601 = marinaTraceISO8601String(from: Date())
        self.originalPrompt = trace.originalPrompt
        self.promptVersion = MarinaFoundationPromptVersion.interpretation.rawValue
        self.routingMode = trace.routingMode.rawValue
        self.runtimeSettingsSummary = trace.runtimeSettingsSummary
        self.modelWasAvailable = trace.modelWasAvailable
        self.modelAvailabilityReason = trace.modelAvailabilityReason
        self.selectedRoute = trace.selectedRoute.rawValue
        self.selectedRouteReason = trace.selectedRouteReason
        self.foundationModelFailureStep = trace.foundationModelFailureStep
        self.foundationModelFailureCategory = trace.foundationModelFailureCategory
        self.foundationModelFailureDebugSummary = trace.foundationModelFailureDebugSummary.map(marinaSanitizedDebugSummary)
        self.foundationRepairSummary = trace.foundationRepairSummary
        self.foundationTranscriptSummary = trace.foundationTranscriptSummary
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
        self.responseSurfaceRecoveryReason = trace.responseSurfaceRecoveryReason?.rawValue
        self.foundationPipelineEnabled = trace.foundationPipelineEnabled
        self.foundationPipelinePath = trace.foundationPipelinePath?.rawValue
        self.foundationPipelineInterpreterSource = trace.foundationPipelineInterpreterSource?.rawValue
        self.foundationPipelineCandidateSummary = trace.foundationPipelineCandidateSummary
        self.foundationPipelineResolverSummary = trace.foundationPipelineResolverSummary
        self.foundationPipelineValidatorSummary = trace.foundationPipelineValidatorSummary
        self.foundationPipelineExecutorSummary = trace.foundationPipelineExecutorSummary
        self.foundationPipelineResponseBridgeSummary = trace.foundationPipelineResponseBridgeSummary
        self.foundationPipelineResponseShapeSummary = trace.foundationPipelineResponseShapeSummary
        self.foundationPipelineSemanticInterpretationSummary = trace.foundationPipelineSemanticInterpretationSummary
        self.foundationPipelineSemanticResolverSummary = trace.foundationPipelineSemanticResolverSummary
        self.foundationPipelineSemanticValidationSummary = trace.foundationPipelineSemanticValidationSummary
        self.foundationPipelineRecoveryReason = trace.foundationPipelineRecoveryReason?.rawValue
        self.foundationPipelineDisagreementSummary = trace.foundationPipelineDisagreementSummary
        self.turnClassification = trace.foundationPipelineTurnClassification?.rawValue
        self.priorContextIncluded = trace.foundationPipelinePriorContextIncluded
        self.dataWasQueried = trace.foundationPipelineExecutorSummary != nil
    }

    var accessibilityValue: String {
        [
            "prompt=\(originalPrompt)",
            "routingMode=\(routingMode)",
            "selectedRoute=\(selectedRoute)",
            foundationModelFailureStep.map { "foundationStep=\($0)" },
            foundationModelFailureCategory.map { "foundationCategory=\($0)" },
            foundationRepairSummary.map { "foundationRepair=\($0)" },
            foundationTranscriptSummary.map { "foundationTranscript=\($0)" },
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
            foundationPipelinePath.map { "foundationPath=\($0)" },
            foundationPipelineInterpreterSource.map { "interpreter=\($0)" },
            turnClassification.map { "turnClassification=\($0)" },
            priorContextIncluded.map { "priorContextIncluded=\($0)" },
            foundationPipelineCandidateSummary.map { "candidate=\($0)" },
            aggregationPath.map { "aggregationPath=\($0)" },
            responseType.map { "responseType=\($0)" },
            responseSurfaceSource.map { "responseSurface=\($0)" },
            responseSurfaceRecoveryReason.map { "responseSurfaceRecovery=\($0)" },
            foundationPipelineExecutorSummary.map { "executor=\($0)" },
            foundationPipelineResponseBridgeSummary.map { "bridge=\($0)" },
            foundationPipelineRecoveryReason.map { "foundationRecovery=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " | ")
    }
}

enum MarinaTraceExporter {
    static func exportIfConfigured(_ trace: MarinaExecutionTrace) {
        #if DEBUG
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
            "foundationPath=\(foundationPipelinePath?.rawValue ?? "none")",
            "foundationRecovery=\(foundationPipelineRecoveryReason?.rawValue ?? "none")",
            "metric=\(normalizedMetric ?? "nil")",
            "response=\(responseType ?? "nil")",
            "surface=\(responseSurfaceSource?.rawValue ?? "nil")",
            "surfaceRecovery=\(responseSurfaceRecoveryReason?.rawValue ?? "nil")",
            foundationModelFailureStep.map { "foundationStep=\($0)" },
            foundationModelFailureCategory.map { "foundationCategory=\($0)" },
            foundationRepairSummary.map { "foundationRepair=\($0)" },
            foundationTranscriptSummary.map { "foundationTranscript=\($0)" }
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
