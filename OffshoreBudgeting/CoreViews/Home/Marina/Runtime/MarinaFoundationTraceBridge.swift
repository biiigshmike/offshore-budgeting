import Foundation

@MainActor
enum MarinaFoundationTraceBridge {
    static func record(
        context: MarinaTurnContext,
        interpretation: MarinaCanonicalReadInterpretation,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        validationOutcome: MarinaPlanValidationOutcome,
        execution: MarinaQueryExecution?
    ) {
        let candidate = interpretation.compatibilityCandidate
        MarinaTraceRecorder.shared.recordFoundationRepairSummary(interpretation.repairSummary)
        MarinaTraceRecorder.shared.recordFoundationPipelineTrace(
            MarinaFoundationPipelineTrace(
                foundationPipelineEnabled: true,
                aiOptInEnabled: context.aiEnabled,
                aiAvailable: true,
                aiOptIn: context.aiEnabled,
                aiRouteEligible: context.aiEnabled,
                selectedInterpreter: .foundationModels,
                interpreterSelectionReason: .modelEligible,
                modelAttempted: true,
                modelAvailabilitySummary: "available",
                selectedPath: .foundationModels,
                interpreterSource: candidate.source,
                candidateSummary: MarinaCandidateTrace(
                    candidate: candidate,
                    validatorOutcomeSummary: validatorSummary(validationOutcome),
                    executablePlanSummary: executablePlanSummary(validationOutcome),
                    selectionRank: nil,
                    rejectedReason: nil,
                    operationPreserved: true
                ).compactSummary,
                resolverSummary: resolverSummary(resolved),
                semanticInterpretationSummary: semanticInterpretationSummary(interpretation.result),
                semanticResolverSummary: semanticResolved.map(semanticResolverSummary),
                validatorOutcomeSummary: validatorSummary(validationOutcome),
                semanticValidationSummary: validatorSummary(validationOutcome),
                executorResultSummary: executorSummary(execution),
                responseBridgeSummary: responseBridgeSummary(
                    validationOutcome: validationOutcome,
                    execution: execution
                ),
                responseShapeSummary: responseShapeSummary(validationOutcome),
                recoveryReason: nil,
                disagreementSummary: interpretation.repairSummary.map { "foundationRepair=\($0)" },
                selectionRank: nil,
                rejectedReason: nil,
                operationPreserved: true,
                turnClassification: context.turnClassification,
                priorContextIncluded: context.routerContext.priorQueryContext.hasContext
            )
        )
    }

    static func recordUnavailable(context: MarinaTurnContext, reason: String) {
        MarinaTraceRecorder.shared.recordFoundationPipelineTrace(
            MarinaFoundationPipelineTrace(
                foundationPipelineEnabled: true,
                aiOptInEnabled: context.aiEnabled,
                aiAvailable: false,
                aiOptIn: context.aiEnabled,
                aiRouteEligible: false,
                selectedInterpreter: nil,
                interpreterSelectionReason: context.aiEnabled ? .modelUnavailable : .aiOptOut,
                modelAttempted: false,
                modelAvailabilitySummary: reason,
                selectedPath: .foundationModels,
                interpreterSource: nil,
                validatorOutcomeSummary: "unavailable:\(reason)",
                responseBridgeSummary: "kind=message,responseShape=unsupported,suggestions=0",
                responseShapeSummary: MarinaResponseShapeHint.unsupported.rawValue,
                recoveryReason: context.aiEnabled ? .modelUnavailable : .aiOptOut,
                turnClassification: context.turnClassification,
                priorContextIncluded: context.routerContext.priorQueryContext.hasContext
            )
        )
    }

    static func recordFoundationFailure(
        context: MarinaTurnContext,
        diagnostic: MarinaFoundationModelsFailureDiagnostic
    ) {
        MarinaTraceRecorder.shared.recordFoundationPipelineTrace(
            MarinaFoundationPipelineTrace(
                foundationPipelineEnabled: true,
                aiOptInEnabled: context.aiEnabled,
                aiAvailable: true,
                aiOptIn: context.aiEnabled,
                aiRouteEligible: true,
                selectedInterpreter: .foundationModels,
                interpreterSelectionReason: interpreterReason(for: diagnostic.category),
                modelAttempted: true,
                modelAvailabilitySummary: diagnostic.availabilityReason ?? "available",
                selectedPath: .foundationModels,
                interpreterSource: .foundationModels,
                validatorOutcomeSummary: diagnostic.traceSummary,
                semanticValidationSummary: diagnostic.traceSummary,
                responseBridgeSummary: "kind=message,responseShape=unsupported,suggestions=0",
                responseShapeSummary: MarinaResponseShapeHint.unsupported.rawValue,
                recoveryReason: recoveryReason(for: diagnostic.category),
                turnClassification: context.turnClassification,
                priorContextIncluded: context.routerContext.priorQueryContext.hasContext
            )
        )
    }

    private static func resolverSummary(_ resolved: MarinaResolvedQueryCandidate) -> String {
        [
            "resolved=\(resolved.resolvedTargets.count)",
            "resolvedTypes=\(resolved.resolvedTargets.map(\.entityType.rawValue).joined(separator: "+"))",
            "unresolved=\(resolved.unresolvedMentions.count)",
            "ambiguous=\(resolved.ambiguousMentions.count)",
            "ambiguousTypes=\(resolved.ambiguousMentions.flatMap { $0.choices.compactMap(\.entityTypeHint?.rawValue) }.joined(separator: "+"))",
            "primary=\(resolved.primaryDateRange?.traceSummary ?? "nil")",
            "comparison=\(resolved.comparisonDateRange?.traceSummary ?? "nil")"
        ].joined(separator: ",")
    }

    private static func semanticResolverSummary(_ resolved: MarinaResolvedSemanticQuery) -> String {
        [
            "resolved=\(resolved.resolvedFilters.count)",
            "resolvedTypes=\(resolved.resolvedFilters.map(\.entityType.rawValue).joined(separator: "+"))",
            "unresolved=\(resolved.unresolvedFilters.count)",
            "ambiguous=\(resolved.ambiguousFilters.count)",
            "ambiguousTypes=\(resolved.ambiguousFilters.flatMap { $0.choices.compactMap(\.entityTypeHint?.rawValue) }.joined(separator: "+"))",
            "primary=\(resolved.primaryDateRange?.traceSummary ?? "nil")",
            "comparison=\(resolved.comparisonDateRange?.traceSummary ?? "nil")"
        ].joined(separator: ",")
    }

    private static func semanticInterpretationSummary(_ result: MarinaInterpretationResult) -> String {
        switch result {
        case .query(let query):
            return [
                "query",
                "subject=\(query.subject.rawValue)",
                "operation=\(query.operation.rawValue)",
                "filters=\(query.filters.count)",
                "incomeStatus=\(query.incomeStatusScope?.rawValue ?? "nil")",
                "detail=\(query.requestedDetail?.rawValue ?? "nil")",
                "shape=\(query.responseShape?.rawValue ?? "nil")"
            ].joined(separator: ",")
        case .clarification(let clarification):
            return "clarification:\(clarification.kind.rawValue)"
        case .unsupported(let unsupported):
            return "unsupported:\(unsupported.kind.rawValue)"
        }
    }

    private static func validatorSummary(_ outcome: MarinaPlanValidationOutcome) -> String {
        switch outcome {
        case .executable(let plan):
            return "executable:\(plan.operation.rawValue):\(plan.measure.rawValue):incomeStatus=\(plan.incomeStatusScope?.rawValue ?? "nil"):shape=\(plan.responseShape?.rawValue ?? "nil")"
        case .clarification(let clarification):
            return "clarification:\(clarification.kind.rawValue)"
        case .unsupported(let unsupported):
            return "unsupported:\(unsupported.kind.rawValue)"
        }
    }

    private static func executablePlanSummary(_ outcome: MarinaPlanValidationOutcome) -> String? {
        guard case .executable(let plan) = outcome else { return nil }
        return [
            "operation=\(plan.operation.rawValue)",
            "measure=\(plan.measure.rawValue)",
            "targets=\(plan.targets.count)",
            "date=\(plan.dateRange?.traceSummary ?? "nil")",
            "comparison=\(plan.comparisonDateRange?.traceSummary ?? "nil")",
            "shape=\(plan.responseShape?.rawValue ?? "nil")"
        ].joined(separator: ",")
    }

    private static func executorSummary(_ execution: MarinaQueryExecution?) -> String? {
        guard let execution else { return nil }
        return [
            "route=\(execution.executionRoute.traceName)",
            "amountBasis=\(execution.amountBasis.rawValue)",
            execution.databaseLookupResponse.map { "databaseLookup=\($0.traceSummary)" },
            execution.workspaceAggregationCard.map { "workspaceCard=\($0.traceSummary)" },
            aggregationSummary(execution.aggregationResult)
        ].compactMap { $0 }.joined(separator: ",")
    }

    private static func responseBridgeSummary(
        validationOutcome: MarinaPlanValidationOutcome,
        execution: MarinaQueryExecution?
    ) -> String {
        [
            execution?.aggregationResult.sourceAnswer?.traceSummary,
            "responseShape=\(responseShapeSummary(validationOutcome))",
            "suggestions=0"
        ].compactMap { $0 }.joined(separator: ",")
    }

    private static func responseShapeSummary(_ outcome: MarinaPlanValidationOutcome) -> String {
        switch outcome {
        case .executable(let plan):
            return plan.responseShape?.rawValue ?? "nil"
        case .clarification:
            return MarinaResponseShapeHint.clarification.rawValue
        case .unsupported:
            return MarinaResponseShapeHint.unsupported.rawValue
        }
    }

    private static func aggregationSummary(_ result: MarinaAggregationResult) -> String {
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
            return "workspaceCard:\(card.traceSummary)"
        case .message(let message):
            return "message:\(message.sourceAnswer.traceSummary)"
        case .noData(let noData):
            return "noData:\(noData.sourceAnswer.traceSummary)"
        case .unsupported(let unsupported):
            return "unsupported:\(unsupported.kind.rawValue)"
        }
    }

    private static func interpreterReason(
        for category: MarinaFoundationModelsErrorCategory
    ) -> MarinaInterpretationSelectionReason {
        switch category {
        case .decodingFailure, .malformedResponse:
            return .modelInvalidStructuredOutput
        case .exceededContextWindowSize:
            return .modelTimedOut
        case .guardrailViolation:
            return .modelSafetyBlocked
        case .rateLimited:
            return .modelRateLimited
        case .unsupportedLanguageOrLocale:
            return .modelUnsupportedLocale
        case .toolCallFailed:
            return .modelToolCallFailed
        case .concurrentRequests:
            return .modelConcurrentRequest
        case .refusal:
            return .modelSafetyBlocked
        case .assetsUnavailable, .unavailable, .unsupportedGuide, .cancelled, .unknown:
            return .modelServiceFailed
        }
    }

    private static func recoveryReason(
        for category: MarinaFoundationModelsErrorCategory
    ) -> MarinaFoundationPipelineRecoveryReason {
        switch category {
        case .assetsUnavailable:
            return .modelAssetsUnavailable
        case .decodingFailure, .malformedResponse:
            return .modelDecodingFailure
        case .exceededContextWindowSize:
            return .modelContextWindowExceeded
        case .guardrailViolation:
            return .modelGuardrailViolation
        case .rateLimited:
            return .modelRateLimited
        case .refusal:
            return .modelRefusal
        case .concurrentRequests:
            return .modelConcurrentRequests
        case .unsupportedGuide:
            return .modelUnsupportedGuide
        case .unsupportedLanguageOrLocale:
            return .modelUnsupportedLanguageOrLocale
        case .toolCallFailed:
            return .modelToolCallFailed
        case .cancelled:
            return .modelCancelled
        case .unavailable:
            return .modelUnavailable
        case .unknown:
            return .modelUnknownFailure
        }
    }
}
