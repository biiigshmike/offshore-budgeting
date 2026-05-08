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
    private let responseBridge: MarinaAggregationResponseBridge

    init(
        availability: MarinaModelAvailabilityProviding? = nil,
        structuredInterpreter: MarinaStructuredIntentInterpreting? = nil,
        heuristicInterpreter: MarinaHeuristicInterpreter? = nil,
        resolver: MarinaQueryResolver? = nil,
        validator: MarinaQueryValidator? = nil,
        adapter: MarinaAggregationPlanHomeQueryAdapter? = nil,
        executor: MarinaAggregationExecutor? = nil,
        responseBridge: MarinaAggregationResponseBridge? = nil
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
        self.responseBridge = responseBridge ?? MarinaAggregationResponseBridge()
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

        let modelAvailability = context.aiOptInEnabled ? availability.currentStatus() : nil
        let modelAvailabilitySummary = modelAvailability.map(Self.modelAvailabilitySummary)
        var modelEvaluation: CandidateEvaluation?
        var modelFailureReason: MarinaSharedPipelineFallbackReason?

        if context.aiOptInEnabled, modelAvailability == .available {
            do {
                let candidate = try await foundationModelsInterpreter.interpret(
                    prompt: prompt,
                    context: context.routerContext
                )
                modelEvaluation = evaluate(
                    candidate,
                    provider: context.provider,
                    now: context.now
                )
            } catch {
                modelFailureReason = .modelServiceFailed
            }
        } else if context.aiOptInEnabled {
            modelFailureReason = .modelUnavailable
        }

        let shouldEvaluateHeuristic = modelEvaluation == nil
            || context.aiOptInEnabled
            || modelEvaluation?.isExecutableHandled == false
            || modelEvaluation?.candidate.confidence == .low
            || modelEvaluation?.candidate.unsupportedHint != nil

        let heuristicEvaluation = shouldEvaluateHeuristic
            ? evaluate(
                heuristicInterpreter.interpret(
                    prompt: prompt,
                    defaultPeriodUnit: context.defaultPeriodUnit
                ),
                provider: context.provider,
                now: context.now
            )
            : nil

        let disagreementSummary = disagreementSummary(
            modelEvaluation: modelEvaluation,
            heuristicEvaluation: heuristicEvaluation
        )

        if let selected = selectExecutable(
            modelEvaluation: modelEvaluation,
            heuristicEvaluation: heuristicEvaluation
        ) {
            let trace = trace(
                context: context,
                modelAvailabilitySummary: modelAvailabilitySummary,
                selectedPath: selected.candidate.source == .foundationModels ? .sharedFoundationModels : .sharedHeuristic,
                evaluation: selected,
                fallbackReason: nil,
                disagreementSummary: disagreementSummary ?? modelFailureReason?.rawValue
            )
            return .handled(
                answer: selected.answer!,
                aggregationResult: selected.aggregationResult!,
                homeQueryPlan: selected.executablePlan?.homeQueryPlan,
                trace: trace
            )
        }

        if let blocked = selectValidationBlocked(
            modelEvaluation: modelEvaluation,
            heuristicEvaluation: heuristicEvaluation
        ) {
            let trace = trace(
                context: context,
                modelAvailabilitySummary: modelAvailabilitySummary,
                selectedPath: blocked.candidate.source == .foundationModels ? .sharedFoundationModels : .sharedHeuristic,
                evaluation: blocked,
                fallbackReason: nil,
                disagreementSummary: disagreementSummary ?? modelFailureReason?.rawValue
            )
            return .validationBlocked(
                answer: blocked.blockedAnswer!,
                validationOutcome: blocked.validationOutcome,
                trace: trace
            )
        }

        let fallbackReason = fallbackReason(
            modelFailureReason: modelFailureReason,
            modelEvaluation: modelEvaluation,
            heuristicEvaluation: heuristicEvaluation
        )
        let traceEvaluation = fallbackTraceEvaluation(
            modelEvaluation: modelEvaluation,
            heuristicEvaluation: heuristicEvaluation
        )
        return .fallbackToLegacy(
            trace: trace(
                context: context,
                modelAvailabilitySummary: modelAvailabilitySummary,
                selectedPath: .sharedAttemptedThenLegacyFallback,
                evaluation: traceEvaluation,
                fallbackReason: fallbackReason,
                disagreementSummary: disagreementSummary
            )
        )
    }

    private func evaluate(
        _ candidate: MarinaQueryPlanCandidate,
        provider: MarinaDataProvider,
        now: Date
    ) -> CandidateEvaluation {
        let resolved = resolver.resolve(candidate: candidate, provider: provider)
        let outcome = validator.validate(resolved)

        switch outcome {
        case .clarification:
            return CandidateEvaluation(
                candidate: candidate,
                resolved: resolved,
                validationOutcome: outcome,
                blockedAnswer: responseBridge.responseCompatibleAnswer(from: outcome),
                runtimeFallbackReason: .clarificationBridgeUnavailable
            )
        case .unsupported:
            return CandidateEvaluation(
                candidate: candidate,
                resolved: resolved,
                validationOutcome: outcome,
                blockedAnswer: responseBridge.responseCompatibleAnswer(from: outcome),
                runtimeFallbackReason: .unsupportedBridgeUnavailable
            )
        case .executable:
            switch adapter.executablePlan(from: outcome) {
            case .success(let executablePlan):
                let result = executor.execute(executablePlan, provider: provider, now: now)
                switch result {
                case .unsupported:
                    return CandidateEvaluation(
                        candidate: candidate,
                        resolved: resolved,
                        validationOutcome: outcome,
                        executablePlan: executablePlan,
                        aggregationResult: result,
                        runtimeFallbackReason: .executorUnsupported
                    )
                default:
                    let answer = responseBridge.responseCompatibleAnswer(from: result)
                    return CandidateEvaluation(
                        candidate: candidate,
                        resolved: resolved,
                        validationOutcome: outcome,
                        executablePlan: executablePlan,
                        aggregationResult: result,
                        answer: answer
                    )
                }
            case .failure:
                return CandidateEvaluation(
                    candidate: candidate,
                    resolved: resolved,
                    validationOutcome: outcome,
                    runtimeFallbackReason: .adapterUnsupported
                )
            }
        }
    }

    private func selectExecutable(
        modelEvaluation: CandidateEvaluation?,
        heuristicEvaluation: CandidateEvaluation?
    ) -> CandidateEvaluation? {
        let modelExecutable = modelEvaluation?.isExecutableHandled == true ? modelEvaluation : nil
        let heuristicExecutable = heuristicEvaluation?.isExecutableHandled == true ? heuristicEvaluation : nil

        switch (modelExecutable, heuristicExecutable) {
        case (.some(let model), .some(let heuristic)):
            return materiallyDiffer(model: model, heuristic: heuristic) ? heuristic : model
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

        if let modelBlocked {
            return modelBlocked
        }
        return heuristicBlocked
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
        fallbackReason: MarinaSharedPipelineFallbackReason?,
        disagreementSummary: String?
    ) -> MarinaSharedPipelineTrace {
        MarinaSharedPipelineTrace(
            sharedPipelineEnabled: context.sharedPipelineEnabled,
            aiOptInEnabled: context.aiOptInEnabled,
            modelAvailabilitySummary: modelAvailabilitySummary,
            selectedPath: selectedPath,
            interpreterSource: evaluation?.candidate.source,
            candidateSummary: evaluation.map { MarinaCandidateTrace(candidate: $0.candidate).compactSummary },
            resolverSummary: evaluation.map { resolverSummary($0.resolved) },
            validatorOutcomeSummary: evaluation.map { validatorSummary($0.validationOutcome) },
            executorResultSummary: evaluation?.aggregationResult.map(Self.aggregationResultSummary),
            responseBridgeSummary: (evaluation?.answer ?? evaluation?.blockedAnswer)?.traceSummary,
            fallbackReason: fallbackReason,
            disagreementSummary: disagreementSummary
        )
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
            return "executable:\(plan.operation.rawValue):\(plan.measure.rawValue)"
        case .clarification(let clarification):
            return "clarification:\(clarification.kind.rawValue)"
        case .unsupported(let unsupported):
            return "unsupported:\(unsupported.kind.rawValue)"
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

private struct CandidateEvaluation {
    let candidate: MarinaQueryPlanCandidate
    let resolved: MarinaResolvedQueryCandidate
    let validationOutcome: MarinaPlanValidationOutcome
    let executablePlan: MarinaExecutableAggregationPlan?
    let aggregationResult: MarinaAggregationResult?
    let answer: HomeAnswer?
    let blockedAnswer: HomeAnswer?
    let runtimeFallbackReason: MarinaSharedPipelineFallbackReason?

    init(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        validationOutcome: MarinaPlanValidationOutcome,
        executablePlan: MarinaExecutableAggregationPlan? = nil,
        aggregationResult: MarinaAggregationResult? = nil,
        answer: HomeAnswer? = nil,
        blockedAnswer: HomeAnswer? = nil,
        runtimeFallbackReason: MarinaSharedPipelineFallbackReason? = nil
    ) {
        self.candidate = candidate
        self.resolved = resolved
        self.validationOutcome = validationOutcome
        self.executablePlan = executablePlan
        self.aggregationResult = aggregationResult
        self.answer = answer
        self.blockedAnswer = blockedAnswer
        self.runtimeFallbackReason = runtimeFallbackReason
    }

    var isExecutableHandled: Bool {
        answer != nil && aggregationResult != nil && executablePlan != nil
    }

    var isValidationBlocked: Bool {
        blockedAnswer != nil && executablePlan == nil && aggregationResult == nil
    }
}
