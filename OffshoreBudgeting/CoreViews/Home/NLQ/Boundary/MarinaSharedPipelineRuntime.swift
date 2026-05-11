import Foundation

enum MarinaSharedPipelineFallbackReason: String, Codable, Equatable {
    case gateDisabled
    case modelUnavailable
    case modelServiceFailed
    case validationDidNotProduceExecutablePlan
    case clarificationBridgeUnavailable
    case unsupportedBridgeUnavailable
    case adapterUnsupported
    case executorUnsupported
    case responseBridgeUnavailable
}

enum MarinaSharedPipelineRuntimePath: String, Codable, Equatable {
    case legacy
    case sharedHeuristic
    case sharedFoundationModels
    case sharedAttemptedThenLegacyFallback
}

struct MarinaSharedPipelineTrace: Codable, Equatable {
    let sharedPipelineEnabled: Bool
    let aiOptInEnabled: Bool
    let modelAvailabilitySummary: String?
    let selectedPath: MarinaSharedPipelineRuntimePath
    let interpreterSource: MarinaInterpreterSource?
    let candidateSummary: String?
    let resolverSummary: String?
    let validatorOutcomeSummary: String?
    let executorResultSummary: String?
    let responseBridgeSummary: String?
    let fallbackReason: MarinaSharedPipelineFallbackReason?
    let disagreementSummary: String?
    let selectionRank: Int?
    let rejectedReason: String?
    let operationPreserved: Bool?

    init(
        sharedPipelineEnabled: Bool,
        aiOptInEnabled: Bool,
        modelAvailabilitySummary: String? = nil,
        selectedPath: MarinaSharedPipelineRuntimePath,
        interpreterSource: MarinaInterpreterSource? = nil,
        candidateSummary: String? = nil,
        resolverSummary: String? = nil,
        validatorOutcomeSummary: String? = nil,
        executorResultSummary: String? = nil,
        responseBridgeSummary: String? = nil,
        fallbackReason: MarinaSharedPipelineFallbackReason? = nil,
        disagreementSummary: String? = nil,
        selectionRank: Int? = nil,
        rejectedReason: String? = nil,
        operationPreserved: Bool? = nil
    ) {
        self.sharedPipelineEnabled = sharedPipelineEnabled
        self.aiOptInEnabled = aiOptInEnabled
        self.modelAvailabilitySummary = modelAvailabilitySummary
        self.selectedPath = selectedPath
        self.interpreterSource = interpreterSource
        self.candidateSummary = candidateSummary
        self.resolverSummary = resolverSummary
        self.validatorOutcomeSummary = validatorOutcomeSummary
        self.executorResultSummary = executorResultSummary
        self.responseBridgeSummary = responseBridgeSummary
        self.fallbackReason = fallbackReason
        self.disagreementSummary = disagreementSummary
        self.selectionRank = selectionRank
        self.rejectedReason = rejectedReason
        self.operationPreserved = operationPreserved
    }

    var compactSummary: String {
        [
            "gate=\(sharedPipelineEnabled)",
            "aiOptIn=\(aiOptInEnabled)",
            modelAvailabilitySummary.map { "model=\($0)" },
            "path=\(selectedPath.rawValue)",
            interpreterSource.map { "source=\($0.rawValue)" },
            candidateSummary.map { "candidate=\($0)" },
            resolverSummary.map { "resolver=\($0)" },
            validatorOutcomeSummary.map { "validator=\($0)" },
            executorResultSummary.map { "executor=\($0)" },
            responseBridgeSummary.map { "bridge=\($0)" },
            fallbackReason.map { "fallback=\($0.rawValue)" },
            disagreementSummary.map { "disagreement=\($0)" },
            selectionRank.map { "selectionRank=\($0)" },
            rejectedReason.map { "rejected=\($0)" },
            operationPreserved.map { "operationPreserved=\($0)" }
        ]
        .compactMap { $0 }
        .joined(separator: " | ")
    }
}

struct MarinaSharedPipelineContext {
    let provider: MarinaDataProvider
    let routerContext: MarinaLanguageRouterContext
    let defaultPeriodUnit: HomeQueryPeriodUnit
    let sharedPipelineEnabled: Bool
    let aiOptInEnabled: Bool
    let now: Date

    init(
        provider: MarinaDataProvider,
        routerContext: MarinaLanguageRouterContext,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        sharedPipelineEnabled: Bool,
        aiOptInEnabled: Bool,
        now: Date = Date()
    ) {
        self.provider = provider
        self.routerContext = routerContext
        self.defaultPeriodUnit = defaultPeriodUnit
        self.sharedPipelineEnabled = sharedPipelineEnabled
        self.aiOptInEnabled = aiOptInEnabled
        self.now = now
    }
}

enum MarinaSharedPipelineRuntimeResult: Equatable {
    case handled(
        answer: HomeAnswer,
        aggregationResult: MarinaAggregationResult,
        homeQueryPlan: HomeQueryPlan?,
        trace: MarinaSharedPipelineTrace
    )
    case validationBlocked(
        answer: HomeAnswer,
        validationOutcome: MarinaPlanValidationOutcome,
        trace: MarinaSharedPipelineTrace
    )
    case fallbackToLegacy(trace: MarinaSharedPipelineTrace)

    var trace: MarinaSharedPipelineTrace {
        switch self {
        case .handled(_, _, _, let trace),
             .validationBlocked(_, _, let trace),
             .fallbackToLegacy(let trace):
            return trace
        }
    }
}
