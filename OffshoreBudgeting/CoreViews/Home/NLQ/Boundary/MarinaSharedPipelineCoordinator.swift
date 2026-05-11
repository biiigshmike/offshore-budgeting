import Foundation

@MainActor
struct MarinaSharedPipelineCoordinator {
    private let availability: MarinaModelAvailabilityProviding
    private let foundationModelsInterpreter: MarinaFoundationModelsInterpreter
    private let heuristicInterpreter: MarinaHeuristicInterpreter
    private let resolver: MarinaQueryResolver
    private let validator: MarinaQueryValidator
    private let adapter: MarinaAggregationPlanHomeQueryAdapter
    private let executor: MarinaAggregationExecutor
    private let composableWorkspaceQueryExecutor: MarinaComposableWorkspaceQueryExecutor
    private let workspaceAggregationExecutor: MarinaWorkspaceAggregationExecutor
    private let responseBridge: MarinaAggregationResponseBridge
    private let workspaceAggregationResponseBridge: MarinaWorkspaceAggregationResponseBridge
    private let databaseLookupExecutor: MarinaDatabaseLookupExecutor
    private let databaseLookupResponseBuilder: MarinaDatabaseLookupResponseBuilder
    private let promptNormalizer = MarinaPromptNormalizer()
    private let recoveryPolicy = MarinaQueryRecoveryPolicy()

    init(
        availability: MarinaModelAvailabilityProviding? = nil,
        structuredInterpreter: MarinaStructuredIntentInterpreting? = nil,
        heuristicInterpreter: MarinaHeuristicInterpreter? = nil,
        resolver: MarinaQueryResolver? = nil,
        validator: MarinaQueryValidator? = nil,
        adapter: MarinaAggregationPlanHomeQueryAdapter? = nil,
        executor: MarinaAggregationExecutor? = nil,
        composableWorkspaceQueryExecutor: MarinaComposableWorkspaceQueryExecutor? = nil,
        workspaceAggregationExecutor: MarinaWorkspaceAggregationExecutor? = nil,
        responseBridge: MarinaAggregationResponseBridge? = nil,
        workspaceAggregationResponseBridge: MarinaWorkspaceAggregationResponseBridge? = nil,
        databaseLookupExecutor: MarinaDatabaseLookupExecutor? = nil,
        databaseLookupResponseBuilder: MarinaDatabaseLookupResponseBuilder? = nil
    ) {
        self.availability = availability ?? MarinaModelAvailability()
        self.foundationModelsInterpreter = MarinaFoundationModelsInterpreter(
            structuredInterpreter: structuredInterpreter ?? MarinaFoundationModelsService()
        )
        self.heuristicInterpreter = heuristicInterpreter ?? MarinaHeuristicInterpreter()
        self.resolver = resolver ?? MarinaQueryResolver()
        self.validator = validator ?? MarinaQueryValidator()
        self.adapter = adapter ?? MarinaAggregationPlanHomeQueryAdapter()
        self.executor = executor ?? MarinaAggregationExecutor()
        self.composableWorkspaceQueryExecutor = composableWorkspaceQueryExecutor ?? MarinaComposableWorkspaceQueryExecutor()
        self.workspaceAggregationExecutor = workspaceAggregationExecutor ?? MarinaWorkspaceAggregationExecutor()
        self.responseBridge = responseBridge ?? MarinaAggregationResponseBridge()
        self.workspaceAggregationResponseBridge = workspaceAggregationResponseBridge ?? MarinaWorkspaceAggregationResponseBridge()
        self.databaseLookupExecutor = databaseLookupExecutor ?? MarinaDatabaseLookupExecutor()
        self.databaseLookupResponseBuilder = databaseLookupResponseBuilder ?? MarinaDatabaseLookupResponseBuilder()
    }

    func run(
        prompt: String,
        context: MarinaSharedPipelineContext
    ) async -> MarinaSharedPipelineRuntimeResult {
        guard context.sharedPipelineEnabled else {
            return fallback(
                context: context,
                modelAvailabilitySummary: nil,
                reason: .gateDisabled
            )
        }

        let normalization = promptNormalizer.normalize(
            prompt: prompt,
            defaultPeriodUnit: context.defaultPeriodUnit,
            now: context.now
        )
        let modelAvailability = context.aiOptInEnabled ? availability.currentStatus() : nil
        let modelAvailabilitySummary = modelAvailability.map(Self.modelAvailabilitySummary)
        var modelFailureReason: MarinaSharedPipelineFallbackReason?
        let candidate: MarinaQueryPlanCandidate

        if context.aiOptInEnabled, modelAvailability == .available {
            do {
                let modelCandidate = try await foundationModelsInterpreter.interpret(
                    prompt: normalization.originalText,
                    context: context.routerContext
                )
                if shouldUseDeterministicFallback(for: modelCandidate) {
                    modelFailureReason = .validationDidNotProduceExecutablePlan
                    candidate = heuristicInterpreter.interpret(
                        prompt: normalization.originalText,
                        defaultPeriodUnit: normalization.defaultPeriodUnit
                    )
                } else {
                    candidate = modelCandidate
                }
            } catch {
                modelFailureReason = .modelServiceFailed
                candidate = heuristicInterpreter.interpret(
                    prompt: normalization.originalText,
                    defaultPeriodUnit: normalization.defaultPeriodUnit
                )
            }
        } else if context.aiOptInEnabled {
            modelFailureReason = .modelUnavailable
            candidate = heuristicInterpreter.interpret(
                prompt: normalization.originalText,
                defaultPeriodUnit: normalization.defaultPeriodUnit
            )
        } else {
            candidate = heuristicInterpreter.interpret(
                prompt: normalization.originalText,
                defaultPeriodUnit: normalization.defaultPeriodUnit
            )
        }

        let evaluation = evaluate(
            candidate,
            provider: context.provider,
            now: context.now
        )

        if evaluation.isExecutableHandled {
            let trace = trace(
                context: context,
                modelAvailabilitySummary: modelAvailabilitySummary,
                selectedPath: evaluation.candidate.source == .foundationModels ? .sharedFoundationModels : .sharedHeuristic,
                evaluation: evaluation,
                fallbackReason: nil,
                disagreementSummary: modelFailureReason?.rawValue
            )
            return .handled(
                answer: evaluation.answer!,
                aggregationResult: evaluation.aggregationResult!,
                homeQueryPlan: evaluation.executablePlan?.homeQueryPlan,
                trace: trace
            )
        }

        if evaluation.isValidationBlocked {
            let trace = trace(
                context: context,
                modelAvailabilitySummary: modelAvailabilitySummary,
                selectedPath: evaluation.candidate.source == .foundationModels ? .sharedFoundationModels : .sharedHeuristic,
                evaluation: evaluation,
                fallbackReason: nil,
                disagreementSummary: modelFailureReason?.rawValue
            )
            return .validationBlocked(
                answer: evaluation.blockedAnswer!,
                validationOutcome: evaluation.validationOutcome,
                trace: trace
            )
        }

        let blocked = unsupportedEvaluation(
            candidate: evaluation.candidate,
            resolved: evaluation.resolved,
            reason: evaluation.runtimeFallbackReason ?? modelFailureReason ?? .validationDidNotProduceExecutablePlan
        )
        let trace = trace(
            context: context,
            modelAvailabilitySummary: modelAvailabilitySummary,
            selectedPath: blocked.candidate.source == .foundationModels ? .sharedFoundationModels : .sharedHeuristic,
            evaluation: blocked,
            fallbackReason: nil,
            disagreementSummary: modelFailureReason?.rawValue
        )
        return .validationBlocked(
            answer: blocked.blockedAnswer!,
            validationOutcome: blocked.validationOutcome,
            trace: trace
        )
    }

    private func shouldUseDeterministicFallback(for candidate: MarinaQueryPlanCandidate) -> Bool {
        candidate.confidence == .low || candidate.unsupportedHint != nil
    }

    private func unsupportedEvaluation(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        reason: MarinaSharedPipelineFallbackReason
    ) -> CandidateEvaluation {
        let unsupported = MarinaTypedUnsupportedResponse(
            kind: .unsupportedCombination,
            message: "The shared Marina pipeline could not execute this validated shape: \(reason.rawValue).",
            candidate: candidate
        )
        let outcome = MarinaPlanValidationOutcome.unsupported(unsupported)
        return CandidateEvaluation(
            candidate: candidate,
            resolved: resolved,
            validationOutcome: outcome,
            blockedAnswer: MarinaResponseBuilder().responseCompatibleAnswer(from: outcome),
            runtimeFallbackReason: reason
        )
    }

    private func evaluate(
        _ candidate: MarinaQueryPlanCandidate,
        provider: MarinaDataProvider,
        now: Date
    ) -> CandidateEvaluation {
        let resolved = resolver.resolve(candidate: candidate, provider: provider)
        let outcome = validator.validate(resolved)
        let responseBuilder = MarinaResponseBuilder(
            aggregationBridge: responseBridge,
            workspaceBridge: workspaceAggregationResponseBridge
        )

        switch outcome {
        case .clarification:
            return CandidateEvaluation(
                candidate: candidate,
                resolved: resolved,
                validationOutcome: outcome,
                blockedAnswer: responseBuilder.responseCompatibleAnswer(from: outcome),
                runtimeFallbackReason: .clarificationBridgeUnavailable
            )
        case .unsupported:
            return CandidateEvaluation(
                candidate: candidate,
                resolved: resolved,
                validationOutcome: outcome,
                blockedAnswer: responseBuilder.responseCompatibleAnswer(from: outcome),
                runtimeFallbackReason: .unsupportedBridgeUnavailable
            )
        case .executable:
            let queryExecutor = MarinaQueryExecutor(
                adapter: adapter,
                executor: executor,
                composableWorkspaceQueryExecutor: composableWorkspaceQueryExecutor,
                workspaceAggregationExecutor: workspaceAggregationExecutor
            )
            switch queryExecutor.execute(
                candidate: candidate,
                resolved: resolved,
                validationOutcome: outcome,
                provider: provider,
                now: now
            ) {
            case .handled(let execution):
                let answer = responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult)
                let suggestions = MarinaSuggestionBuilder().suggestions(
                    candidate: candidate,
                    executablePlan: execution.executablePlan,
                    result: execution.aggregationResult,
                    answer: answer
                )
                return CandidateEvaluation(
                    candidate: candidate,
                    resolved: resolved,
                    validationOutcome: outcome,
                    executablePlan: execution.executablePlan,
                    aggregationResult: execution.aggregationResult,
                    answer: answer,
                    suggestionCount: suggestions.count,
                    workspaceAggregationCard: execution.workspaceAggregationCard
                )
            case .unsupported(let unsupported):
                let unsupportedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                return CandidateEvaluation(
                    candidate: candidate,
                    resolved: resolved,
                    validationOutcome: unsupportedOutcome,
                    blockedAnswer: responseBuilder.responseCompatibleAnswer(from: unsupportedOutcome),
                    runtimeFallbackReason: .executorUnsupported
                )
            }
        }
    }

    private func selectExecutable(
        modelEvaluation: CandidateEvaluation?,
        heuristicEvaluation: CandidateEvaluation?,
        preferModelWhenAvailable: Bool
    ) -> CandidateEvaluation? {
        let modelExecutable = modelEvaluation?.isExecutableHandled == true ? modelEvaluation : nil
        let heuristicExecutable = heuristicEvaluation?.isExecutableHandled == true ? heuristicEvaluation : nil

        switch (modelExecutable, heuristicExecutable) {
        case (.some(let model), .some(let heuristic)):
            if model.candidate.semanticCommand != nil, heuristic.candidate.semanticCommand == nil {
                return model
            }
            if model.operationPreserved != heuristic.operationPreserved {
                return model.operationPreserved ? model : heuristic
            }
            if materiallyDiffer(model: model, heuristic: heuristic) {
                return preferModelWhenAvailable ? model : heuristic
            }
            return model
        case (.some(let model), .none):
            return model
        case (.none, .some(let heuristic)):
            return heuristic
        case (.none, .none):
            return nil
        }
    }

    private func selectValidationBlocked(
        modelEvaluation: CandidateEvaluation?,
        heuristicEvaluation: CandidateEvaluation?
    ) -> CandidateEvaluation? {
        let modelBlocked = modelEvaluation?.isValidationBlocked == true ? modelEvaluation : nil
        let heuristicBlocked = heuristicEvaluation?.isValidationBlocked == true ? heuristicEvaluation : nil

        switch (modelBlocked, heuristicBlocked) {
        case (.some(let model), .some(let heuristic)):
            if isClarification(model), isClarification(heuristic) == false {
                return model
            }
            if isClarification(heuristic), isClarification(model) == false {
                return heuristic
            }
            if model.operationPreserved != heuristic.operationPreserved {
                return model.operationPreserved ? model : heuristic
            }
            return recoveryPolicy.selectionRank(for: model) <= recoveryPolicy.selectionRank(for: heuristic)
                ? model
                : heuristic
        case (.some(let modelBlocked), .none):
            return modelBlocked
        case (.none, .some(let heuristicBlocked)):
            return heuristicBlocked
        case (.none, .none):
            return nil
        }
    }

    private func fallback(
        context: MarinaSharedPipelineContext,
        modelAvailabilitySummary: String?,
        reason: MarinaSharedPipelineFallbackReason
    ) -> MarinaSharedPipelineRuntimeResult {
        .fallbackToLegacy(
            trace: MarinaSharedPipelineTrace(
                sharedPipelineEnabled: context.sharedPipelineEnabled,
                aiOptInEnabled: context.aiOptInEnabled,
                modelAvailabilitySummary: modelAvailabilitySummary,
                selectedPath: .legacy,
                fallbackReason: reason
            )
        )
    }

    private func fallbackReason(
        modelFailureReason: MarinaSharedPipelineFallbackReason?,
        modelEvaluation: CandidateEvaluation?,
        heuristicEvaluation: CandidateEvaluation?
    ) -> MarinaSharedPipelineFallbackReason {
        if let clarificationReason = [modelEvaluation, heuristicEvaluation]
            .compactMap({ $0 })
            .first(where: { evaluation in
                if case .clarification = evaluation.validationOutcome {
                    return true
                }
                return false
            })?
            .runtimeFallbackReason {
            return clarificationReason
        }

        if let heuristicReason = heuristicEvaluation?.runtimeFallbackReason {
            return heuristicReason
        }
        if let modelReason = modelEvaluation?.runtimeFallbackReason {
            return modelReason
        }
        return modelFailureReason ?? .validationDidNotProduceExecutablePlan
    }

    private func fallbackTraceEvaluation(
        modelEvaluation: CandidateEvaluation?,
        heuristicEvaluation: CandidateEvaluation?
    ) -> CandidateEvaluation? {
        [modelEvaluation, heuristicEvaluation]
            .compactMap { $0 }
            .first { evaluation in
                if case .clarification = evaluation.validationOutcome {
                    return true
                }
                return false
            } ?? heuristicEvaluation ?? modelEvaluation
    }

    private func trace(
        context: MarinaSharedPipelineContext,
        modelAvailabilitySummary: String?,
        selectedPath: MarinaSharedPipelineRuntimePath,
        evaluation: CandidateEvaluation?,
        competingEvaluation: CandidateEvaluation? = nil,
        fallbackReason: MarinaSharedPipelineFallbackReason?,
        disagreementSummary: String?
    ) -> MarinaSharedPipelineTrace {
        MarinaSharedPipelineTrace(
            sharedPipelineEnabled: context.sharedPipelineEnabled,
            aiOptInEnabled: context.aiOptInEnabled,
            modelAvailabilitySummary: modelAvailabilitySummary,
            selectedPath: selectedPath,
            interpreterSource: evaluation?.candidate.source,
            candidateSummary: evaluation.map {
                MarinaCandidateTrace(
                    candidate: $0.candidate,
                    validatorOutcomeSummary: validatorSummary($0.validationOutcome),
                    executablePlanSummary: executablePlanSummary($0),
                    selectionRank: recoveryPolicy.selectionRank(for: $0),
                    rejectedReason: recoveryPolicy.rejectedReason(selected: $0, other: competingEvaluation),
                    operationPreserved: $0.operationPreserved
                ).compactSummary
            },
            resolverSummary: evaluation.map { resolverSummary($0.resolved) },
            validatorOutcomeSummary: evaluation.map { validatorSummary($0.validationOutcome) },
            executorResultSummary: evaluation?.databaseLookupResponse?.traceSummary ?? evaluation?.workspaceAggregationCard?.traceSummary ?? evaluation?.aggregationResult.map(Self.aggregationResultSummary),
            responseBridgeSummary: responseBridgeSummary(evaluation),
            fallbackReason: fallbackReason,
            disagreementSummary: disagreementSummary,
            selectionRank: evaluation.map(recoveryPolicy.selectionRank),
            rejectedReason: evaluation.flatMap {
                recoveryPolicy.rejectedReason(selected: $0, other: competingEvaluation)
            },
            operationPreserved: evaluation?.operationPreserved
        )
    }

    private func otherEvaluation(
        selected: CandidateEvaluation,
        modelEvaluation: CandidateEvaluation?,
        heuristicEvaluation: CandidateEvaluation?
    ) -> CandidateEvaluation? {
        selected.candidate.source == .foundationModels ? heuristicEvaluation : modelEvaluation
    }

    private func isClarification(_ evaluation: CandidateEvaluation) -> Bool {
        if case .clarification = evaluation.validationOutcome {
            return true
        }
        return false
    }

    private func disagreementSummary(
        modelEvaluation: CandidateEvaluation?,
        heuristicEvaluation: CandidateEvaluation?
    ) -> String? {
        guard let modelEvaluation,
              let heuristicEvaluation else {
            return nil
        }

        let modelSignature = candidateSignature(modelEvaluation)
        let heuristicSignature = candidateSignature(heuristicEvaluation)
        guard modelSignature != heuristicSignature else { return nil }
        return "model[\(modelSignature)] heuristic[\(heuristicSignature)]"
    }

    private func materiallyDiffer(
        model: CandidateEvaluation,
        heuristic: CandidateEvaluation
    ) -> Bool {
        model.executablePlan?.homeQueryPlan != heuristic.executablePlan?.homeQueryPlan
    }

    private func candidateSignature(_ evaluation: CandidateEvaluation) -> String {
        [
            evaluation.candidate.operation?.rawValue ?? "nil",
            evaluation.candidate.measure?.rawValue ?? "nil",
            evaluation.executablePlan?.homeQueryPlan.metric.rawValue ?? "nil",
            evaluation.databaseLookupResponse?.request.objectTypes.map(\.rawValue).joined(separator: ",") ?? "nil",
            evaluation.databaseLookupResponse?.request.searchText ?? "nil",
            evaluation.workspaceAggregationCard?.traceSummary ?? "nil",
            evaluation.executablePlan?.homeQueryPlan.targetName ?? "nil",
            evaluation.executablePlan?.homeQueryPlan.dateRange?.traceSummary ?? "nil",
            evaluation.executablePlan?.homeQueryPlan.comparisonDateRange?.traceSummary ?? "nil",
            evaluation.candidate.grouping?.dimension.rawValue ?? "nil",
            evaluation.candidate.ranking?.direction.rawValue ?? "nil"
        ].joined(separator: ":")
    }

    private func resolverSummary(_ resolved: MarinaResolvedQueryCandidate) -> String {
        [
            "resolved=\(resolved.resolvedTargets.count)",
            "unresolved=\(resolved.unresolvedMentions.count)",
            "ambiguous=\(resolved.ambiguousMentions.count)",
            "primary=\(resolved.primaryDateRange?.traceSummary ?? "nil")",
            "comparison=\(resolved.comparisonDateRange?.traceSummary ?? "nil")"
        ].joined(separator: ",")
    }

    private func validatorSummary(_ outcome: MarinaPlanValidationOutcome) -> String {
        switch outcome {
        case .executable(let plan):
            return "executable:\(plan.operation.rawValue):\(plan.measure.rawValue):shape=\(plan.responseShape?.rawValue ?? "nil")"
        case .clarification(let clarification):
            return "clarification:\(clarification.kind.rawValue)"
        case .unsupported(let unsupported):
            return "unsupported:\(unsupported.kind.rawValue)"
        }
    }

    private func executablePlanSummary(_ evaluation: CandidateEvaluation) -> String? {
        if let homeQueryPlan = evaluation.executablePlan?.homeQueryPlan {
            return homeQueryPlan.traceSummary
        }
        guard case .executable(let plan) = evaluation.validationOutcome else {
            return nil
        }
        return [
            "operation=\(plan.operation.rawValue)",
            "measure=\(plan.measure.rawValue)",
            "targets=\(plan.targets.count)",
            "date=\(plan.dateRange?.traceSummary ?? "nil")",
            "comparison=\(plan.comparisonDateRange?.traceSummary ?? "nil")",
            "shape=\(plan.responseShape?.rawValue ?? "nil")"
        ].joined(separator: ",")
    }

    private func responseBridgeSummary(_ evaluation: CandidateEvaluation?) -> String? {
        guard let evaluation,
              let answer = evaluation.answer ?? evaluation.blockedAnswer else {
            return nil
        }
        return [
            answer.traceSummary,
            "responseShape=\(responseShapeSummary(evaluation))",
            "suggestions=\(evaluation.suggestionCount)"
        ].joined(separator: ",")
    }

    private func responseShapeSummary(_ evaluation: CandidateEvaluation) -> String {
        switch evaluation.validationOutcome {
        case .executable(let plan):
            return plan.responseShape?.rawValue ?? "nil"
        case .clarification:
            return MarinaResponseShapeHint.clarification.rawValue
        case .unsupported:
            return MarinaResponseShapeHint.unsupported.rawValue
        }
    }

    private static func aggregationResultSummary(_ result: MarinaAggregationResult) -> String {
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
        case .unsupported(let unsupported):
            return "unsupported:\(unsupported.kind.rawValue)"
        }
    }

    private static func modelAvailabilitySummary(_ status: MarinaModelAvailability.Status) -> String {
        switch status {
        case .available:
            return "available"
        case .unavailable(let reason):
            return "unavailable:\(reason)"
        }
    }
}

struct CandidateEvaluation {
    let candidate: MarinaQueryPlanCandidate
    let resolved: MarinaResolvedQueryCandidate
    let validationOutcome: MarinaPlanValidationOutcome
    let executablePlan: MarinaExecutableAggregationPlan?
    let aggregationResult: MarinaAggregationResult?
    let answer: HomeAnswer?
    let blockedAnswer: HomeAnswer?
    let suggestionCount: Int
    let runtimeFallbackReason: MarinaSharedPipelineFallbackReason?
    let databaseLookupResponse: MarinaDatabaseLookupResponse?
    let workspaceAggregationCard: MarinaWorkspaceAggregationCard?

    init(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        validationOutcome: MarinaPlanValidationOutcome,
        executablePlan: MarinaExecutableAggregationPlan? = nil,
        aggregationResult: MarinaAggregationResult? = nil,
        answer: HomeAnswer? = nil,
        blockedAnswer: HomeAnswer? = nil,
        suggestionCount: Int = 0,
        runtimeFallbackReason: MarinaSharedPipelineFallbackReason? = nil,
        databaseLookupResponse: MarinaDatabaseLookupResponse? = nil,
        workspaceAggregationCard: MarinaWorkspaceAggregationCard? = nil
    ) {
        self.candidate = candidate
        self.resolved = resolved
        self.validationOutcome = validationOutcome
        self.executablePlan = executablePlan
        self.aggregationResult = aggregationResult
        self.answer = answer
        self.blockedAnswer = blockedAnswer
        self.suggestionCount = suggestionCount
        self.runtimeFallbackReason = runtimeFallbackReason
        self.databaseLookupResponse = databaseLookupResponse
        self.workspaceAggregationCard = workspaceAggregationCard
    }

    var isExecutableHandled: Bool {
        answer != nil && aggregationResult != nil && (executablePlan != nil || databaseLookupResponse != nil || workspaceAggregationCard != nil)
    }

    var isValidationBlocked: Bool {
        blockedAnswer != nil && answer == nil && aggregationResult == nil
    }

    var operationPreserved: Bool {
        MarinaQueryRecoveryPolicy().operationPreserved(candidate: candidate)
    }
}

struct MarinaQueryExecution {
    let executablePlan: MarinaExecutableAggregationPlan?
    let aggregationResult: MarinaAggregationResult
    let workspaceAggregationCard: MarinaWorkspaceAggregationCard?
}

enum MarinaQueryExecutionResult {
    case handled(MarinaQueryExecution)
    case unsupported(MarinaTypedUnsupportedResponse)
}

@MainActor
struct MarinaQueryExecutor {
    let adapter: MarinaAggregationPlanHomeQueryAdapter
    let executor: MarinaAggregationExecutor
    let composableWorkspaceQueryExecutor: MarinaComposableWorkspaceQueryExecutor
    let workspaceAggregationExecutor: MarinaWorkspaceAggregationExecutor

    func execute(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        validationOutcome: MarinaPlanValidationOutcome,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaQueryExecutionResult {
        guard case .executable(let plan) = validationOutcome else {
            return .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: "Only executable validation outcomes can run.",
                    candidate: candidate
                )
            )
        }

        if case .success(let executablePlan) = adapter.executablePlan(from: validationOutcome) {
            let result = executor.execute(executablePlan, provider: provider, now: now)
            if case .unsupported(let unsupported) = result {
                return .unsupported(unsupported)
            }
            return .handled(
                MarinaQueryExecution(
                    executablePlan: executablePlan,
                    aggregationResult: result,
                    workspaceAggregationCard: nil
                )
            )
        }

        switch composableWorkspaceQueryExecutor.execute(
            candidate: candidate,
            resolved: resolved,
            plan: plan,
            provider: provider,
            now: now
        ) {
        case .handled(let card):
            return .handled(
                MarinaQueryExecution(
                    executablePlan: nil,
                    aggregationResult: .workspaceCard(card),
                    workspaceAggregationCard: card
                )
            )
        case .unsupported:
            break
        }

        switch workspaceAggregationExecutor.execute(plan: plan, provider: provider, now: now) {
        case .handled(let card):
            return .handled(
                MarinaQueryExecution(
                    executablePlan: nil,
                    aggregationResult: .workspaceCard(card),
                    workspaceAggregationCard: card
                )
            )
        case .unsupported:
            return .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: "No shared Marina executor supports this plan shape.",
                    candidate: candidate
                )
            )
        }
    }
}

struct MarinaResponseBuilder {
    let aggregationBridge: MarinaAggregationResponseBridge
    let workspaceBridge: MarinaWorkspaceAggregationResponseBridge

    init(
        aggregationBridge: MarinaAggregationResponseBridge = MarinaAggregationResponseBridge(),
        workspaceBridge: MarinaWorkspaceAggregationResponseBridge = MarinaWorkspaceAggregationResponseBridge()
    ) {
        self.aggregationBridge = aggregationBridge
        self.workspaceBridge = workspaceBridge
    }

    func responseCompatibleAnswer(from outcome: MarinaPlanValidationOutcome) -> HomeAnswer? {
        aggregationBridge.responseCompatibleAnswer(from: outcome)
    }

    func responseCompatibleAnswer(from result: MarinaAggregationResult) -> HomeAnswer {
        switch result {
        case .workspaceCard(let card):
            return workspaceBridge.responseCompatibleAnswer(from: card)
        default:
            return aggregationBridge.responseCompatibleAnswer(from: result)
        }
    }
}

struct MarinaSuggestionContext {
    let candidate: MarinaQueryPlanCandidate
    let executablePlan: MarinaExecutableAggregationPlan?
    let result: MarinaAggregationResult
    let answerKind: HomeAnswerKind
}

struct MarinaSuggestionBuilder {
    func suggestions(
        candidate: MarinaQueryPlanCandidate,
        executablePlan: MarinaExecutableAggregationPlan?,
        result: MarinaAggregationResult,
        answer: HomeAnswer
    ) -> [HomeAssistantSuggestion] {
        let context = MarinaSuggestionContext(
            candidate: candidate,
            executablePlan: executablePlan,
            result: result,
            answerKind: answer.kind
        )
        return suggestions(context: context, answer: answer)
    }

    func suggestions(
        context: MarinaSuggestionContext,
        answer: HomeAnswer
    ) -> [HomeAssistantSuggestion] {
        HomeAssistantPersonaFormatter().followUpSuggestions(
            after: answer,
            executedQuery: context.executablePlan?.homeQueryPlan.query,
            personaID: .marina
        )
    }
}
