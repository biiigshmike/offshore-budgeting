import Foundation

enum MarinaSharedPipelineFallbackReason: String, Codable, Equatable {
    case gateDisabled
    case aiOptOut
    case modelUnavailable
    case modelServiceFailed
    case modelInvalidStructuredOutput
    case modelTimedOut
    case modelUnsupportedHeuristicExactMatch
    case modelClarificationHeuristicExactMatch
    case droppedExplicitConstraint
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

enum MarinaInterpreterSelectionReason: String, Codable, Equatable {
    case gateDisabled
    case modelEligible
    case aiOptOut
    case modelUnavailable
    case modelInvalidStructuredOutput
    case modelServiceFailed
    case modelTimedOut
    case modelUnsupportedHeuristicExactMatch
    case modelClarificationHeuristicExactMatch
    case clarificationResume
}

struct MarinaSharedPipelineTrace: Codable, Equatable {
    let sharedPipelineEnabled: Bool
    let aiOptInEnabled: Bool
    let aiAvailable: Bool?
    let aiOptIn: Bool
    let aiRouteEligible: Bool
    let selectedInterpreter: MarinaInterpreterSource?
    let interpreterSelectionReason: MarinaInterpreterSelectionReason?
    let modelAttempted: Bool
    let heuristicAttempted: Bool
    let heuristicUsedAsFallback: Bool
    let modelAvailabilitySummary: String?
    let selectedPath: MarinaSharedPipelineRuntimePath
    let interpreterSource: MarinaInterpreterSource?
    let candidateSummary: String?
    let resolverSummary: String?
    let semanticInterpretationSummary: String?
    let semanticResolverSummary: String?
    let validatorOutcomeSummary: String?
    let semanticValidationSummary: String?
    let executorResultSummary: String?
    let responseBridgeSummary: String?
    let responseShapeSummary: String?
    let fallbackReason: MarinaSharedPipelineFallbackReason?
    let disagreementSummary: String?
    let selectionRank: Int?
    let rejectedReason: String?
    let operationPreserved: Bool?
    let turnClassification: MarinaPromptTurnClassification
    let priorContextIncluded: Bool

    init(
        sharedPipelineEnabled: Bool,
        aiOptInEnabled: Bool,
        aiAvailable: Bool? = nil,
        aiOptIn: Bool? = nil,
        aiRouteEligible: Bool = false,
        selectedInterpreter: MarinaInterpreterSource? = nil,
        interpreterSelectionReason: MarinaInterpreterSelectionReason? = nil,
        modelAttempted: Bool = false,
        heuristicAttempted: Bool = false,
        heuristicUsedAsFallback: Bool = false,
        modelAvailabilitySummary: String? = nil,
        selectedPath: MarinaSharedPipelineRuntimePath,
        interpreterSource: MarinaInterpreterSource? = nil,
        candidateSummary: String? = nil,
        resolverSummary: String? = nil,
        semanticInterpretationSummary: String? = nil,
        semanticResolverSummary: String? = nil,
        validatorOutcomeSummary: String? = nil,
        semanticValidationSummary: String? = nil,
        executorResultSummary: String? = nil,
        responseBridgeSummary: String? = nil,
        responseShapeSummary: String? = nil,
        fallbackReason: MarinaSharedPipelineFallbackReason? = nil,
        disagreementSummary: String? = nil,
        selectionRank: Int? = nil,
        rejectedReason: String? = nil,
        operationPreserved: Bool? = nil,
        turnClassification: MarinaPromptTurnClassification = .freshQuestion,
        priorContextIncluded: Bool = false
    ) {
        self.sharedPipelineEnabled = sharedPipelineEnabled
        self.aiOptInEnabled = aiOptInEnabled
        self.aiAvailable = aiAvailable
        self.aiOptIn = aiOptIn ?? aiOptInEnabled
        self.aiRouteEligible = aiRouteEligible
        self.selectedInterpreter = selectedInterpreter
        self.interpreterSelectionReason = interpreterSelectionReason
        self.modelAttempted = modelAttempted
        self.heuristicAttempted = heuristicAttempted
        self.heuristicUsedAsFallback = heuristicUsedAsFallback
        self.modelAvailabilitySummary = modelAvailabilitySummary
        self.selectedPath = selectedPath
        self.interpreterSource = interpreterSource
        self.candidateSummary = candidateSummary
        self.resolverSummary = resolverSummary
        self.semanticInterpretationSummary = semanticInterpretationSummary
        self.semanticResolverSummary = semanticResolverSummary
        self.validatorOutcomeSummary = validatorOutcomeSummary
        self.semanticValidationSummary = semanticValidationSummary
        self.executorResultSummary = executorResultSummary
        self.responseBridgeSummary = responseBridgeSummary
        self.responseShapeSummary = responseShapeSummary
        self.fallbackReason = fallbackReason
        self.disagreementSummary = disagreementSummary
        self.selectionRank = selectionRank
        self.rejectedReason = rejectedReason
        self.operationPreserved = operationPreserved
        self.turnClassification = turnClassification
        self.priorContextIncluded = priorContextIncluded
    }

    var compactSummary: String {
        [
            "gate=\(sharedPipelineEnabled)",
            "aiOptIn=\(aiOptInEnabled)",
            aiAvailable.map { "aiAvailable=\($0)" },
            "aiRouteEligible=\(aiRouteEligible)",
            selectedInterpreter.map { "selectedInterpreter=\($0.rawValue)" },
            interpreterSelectionReason.map { "interpreterSelectionReason=\($0.rawValue)" },
            "modelAttempted=\(modelAttempted)",
            "heuristicAttempted=\(heuristicAttempted)",
            "heuristicUsedAsFallback=\(heuristicUsedAsFallback)",
            modelAvailabilitySummary.map { "model=\($0)" },
            "path=\(selectedPath.rawValue)",
            interpreterSource.map { "source=\($0.rawValue)" },
            candidateSummary.map { "candidate=\($0)" },
            resolverSummary.map { "resolver=\($0)" },
            semanticInterpretationSummary.map { "semanticInterpretation=\($0)" },
            semanticResolverSummary.map { "semanticResolver=\($0)" },
            validatorOutcomeSummary.map { "validator=\($0)" },
            semanticValidationSummary.map { "semanticValidation=\($0)" },
            executorResultSummary.map { "executor=\($0)" },
            responseBridgeSummary.map { "bridge=\($0)" },
            responseShapeSummary.map { "responseShape=\($0)" },
            fallbackReason.map { "fallback=\($0.rawValue)" },
            disagreementSummary.map { "disagreement=\($0)" },
            selectionRank.map { "selectionRank=\($0)" },
            rejectedReason.map { "rejected=\($0)" },
            operationPreserved.map { "operationPreserved=\($0)" },
            "turn=\(turnClassification.rawValue)",
            "priorContext=\(priorContextIncluded)"
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
    let turnClassification: MarinaPromptTurnClassification
    let now: Date

    init(
        provider: MarinaDataProvider,
        routerContext: MarinaLanguageRouterContext,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        sharedPipelineEnabled: Bool,
        aiOptInEnabled: Bool,
        turnClassification: MarinaPromptTurnClassification = .freshQuestion,
        now: Date = Date()
    ) {
        self.provider = provider
        self.routerContext = routerContext.sanitized(for: turnClassification)
        self.defaultPeriodUnit = defaultPeriodUnit
        self.sharedPipelineEnabled = sharedPipelineEnabled
        self.aiOptInEnabled = aiOptInEnabled
        self.turnClassification = turnClassification
        self.now = now
    }
}

extension MarinaLanguageRouterContext {
    func sanitized(for turnClassification: MarinaPromptTurnClassification) -> MarinaLanguageRouterContext {
        guard turnClassification != .followUp else { return self }
        return MarinaLanguageRouterContext(
            workspaceName: workspaceName,
            defaultPeriodUnit: defaultPeriodUnit,
            sessionContext: sessionContext,
            priorQueryContext: .empty,
            cardNames: cardNames,
            categoryNames: categoryNames,
            incomeSourceNames: incomeSourceNames,
            presetTitles: presetTitles,
            budgetNames: budgetNames,
            aliasSummaries: aliasSummaries,
            now: now
        )
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
