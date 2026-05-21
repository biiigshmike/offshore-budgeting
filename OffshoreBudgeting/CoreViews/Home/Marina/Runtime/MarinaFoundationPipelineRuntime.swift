import Foundation

enum MarinaFoundationPipelineRecoveryReason: String, Codable, Equatable {
    case aiOptOut
    case modelUnavailable
    case modelServiceFailed
    case modelInvalidStructuredOutput
    case modelTimedOut
    case modelAssetsUnavailable
    case modelDecodingFailure
    case modelContextWindowExceeded
    case modelGuardrailViolation
    case modelRateLimited
    case modelRefusal
    case modelConcurrentRequests
    case modelUnsupportedGuide
    case modelUnsupportedLanguageOrLocale
    case modelToolCallFailed
    case modelCancelled
    case modelUnknownFailure
    case droppedExplicitConstraint
    case validationDidNotProduceExecutablePlan
    case clarificationBridgeUnavailable
    case unsupportedBridgeUnavailable
    case adapterUnsupported
    case executorUnsupported
    case responseBridgeUnavailable
}

enum MarinaFoundationPipelineRuntimePath: String, Codable, Equatable {
    case foundationModels
}

enum MarinaInterpretationSelectionReason: String, Codable, Equatable {
    case modelEligible
    case aiOptOut
    case modelUnavailable
    case modelInvalidStructuredOutput
    case modelServiceFailed
    case modelTimedOut
    case modelSafetyBlocked
    case modelRateLimited
    case modelUnsupportedLocale
    case modelToolCallFailed
    case modelConcurrentRequest
    case clarificationResume
}

struct MarinaFoundationPipelineTrace: Codable, Equatable {
    let foundationPipelineEnabled: Bool
    let aiOptInEnabled: Bool
    let aiAvailable: Bool?
    let aiOptIn: Bool
    let aiRouteEligible: Bool
    let selectedInterpreter: MarinaInterpretationSource?
    let interpreterSelectionReason: MarinaInterpretationSelectionReason?
    let modelAttempted: Bool
    let modelAvailabilitySummary: String?
    let selectedPath: MarinaFoundationPipelineRuntimePath
    let interpreterSource: MarinaInterpretationSource?
    let candidateSummary: String?
    let resolverSummary: String?
    let semanticInterpretationSummary: String?
    let semanticResolverSummary: String?
    let validatorOutcomeSummary: String?
    let semanticValidationSummary: String?
    let executorResultSummary: String?
    let responseBridgeSummary: String?
    let responseShapeSummary: String?
    let recoveryReason: MarinaFoundationPipelineRecoveryReason?
    let disagreementSummary: String?
    let selectionRank: Int?
    let rejectedReason: String?
    let operationPreserved: Bool?
    let turnClassification: MarinaPromptTurnClassification
    let priorContextIncluded: Bool

    init(
        foundationPipelineEnabled: Bool,
        aiOptInEnabled: Bool,
        aiAvailable: Bool? = nil,
        aiOptIn: Bool? = nil,
        aiRouteEligible: Bool = false,
        selectedInterpreter: MarinaInterpretationSource? = nil,
        interpreterSelectionReason: MarinaInterpretationSelectionReason? = nil,
        modelAttempted: Bool = false,
        modelAvailabilitySummary: String? = nil,
        selectedPath: MarinaFoundationPipelineRuntimePath,
        interpreterSource: MarinaInterpretationSource? = nil,
        candidateSummary: String? = nil,
        resolverSummary: String? = nil,
        semanticInterpretationSummary: String? = nil,
        semanticResolverSummary: String? = nil,
        validatorOutcomeSummary: String? = nil,
        semanticValidationSummary: String? = nil,
        executorResultSummary: String? = nil,
        responseBridgeSummary: String? = nil,
        responseShapeSummary: String? = nil,
        recoveryReason: MarinaFoundationPipelineRecoveryReason? = nil,
        disagreementSummary: String? = nil,
        selectionRank: Int? = nil,
        rejectedReason: String? = nil,
        operationPreserved: Bool? = nil,
        turnClassification: MarinaPromptTurnClassification = .freshQuestion,
        priorContextIncluded: Bool = false
    ) {
        self.foundationPipelineEnabled = foundationPipelineEnabled
        self.aiOptInEnabled = aiOptInEnabled
        self.aiAvailable = aiAvailable
        self.aiOptIn = aiOptIn ?? aiOptInEnabled
        self.aiRouteEligible = aiRouteEligible
        self.selectedInterpreter = selectedInterpreter
        self.interpreterSelectionReason = interpreterSelectionReason
        self.modelAttempted = modelAttempted
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
        self.recoveryReason = recoveryReason
        self.disagreementSummary = disagreementSummary
        self.selectionRank = selectionRank
        self.rejectedReason = rejectedReason
        self.operationPreserved = operationPreserved
        self.turnClassification = turnClassification
        self.priorContextIncluded = priorContextIncluded
    }

    var compactSummary: String {
        [
            "gate=\(foundationPipelineEnabled)",
            "aiOptIn=\(aiOptInEnabled)",
            aiAvailable.map { "aiAvailable=\($0)" },
            "aiRouteEligible=\(aiRouteEligible)",
            selectedInterpreter.map { "selectedInterpreter=\($0.rawValue)" },
            interpreterSelectionReason.map { "interpreterSelectionReason=\($0.rawValue)" },
            "modelAttempted=\(modelAttempted)",
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
            recoveryReason.map { "recovery=\($0.rawValue)" },
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
