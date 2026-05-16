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
    private let semanticAdapter = MarinaSemanticQueryAdapter()

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
        let explicitConstraints = MarinaExplicitConstraintDetector().constraints(
            in: normalization.originalText,
            context: context.routerContext
        )
        let modelAvailability = context.aiOptInEnabled ? availability.currentStatus() : nil
        let modelAvailabilitySummary = modelAvailability.map(Self.modelAvailabilitySummary)
        let aiAvailable = modelAvailability == .available
        let aiRouteEligible = context.sharedPipelineEnabled && context.aiOptInEnabled && aiAvailable
        var selection = MarinaInterpreterSelectionTrace(
            aiAvailable: modelAvailability.map { $0 == .available },
            aiOptIn: context.aiOptInEnabled,
            aiRouteEligible: aiRouteEligible,
            selectedInterpreter: nil,
            interpreterSelectionReason: aiRouteEligible ? .modelEligible : (context.aiOptInEnabled ? .modelUnavailable : .aiOptOut),
            modelAttempted: false,
            heuristicAttempted: false,
            heuristicUsedAsFallback: false,
            fallbackReason: nil
        )

        if aiRouteEligible {
            selection.modelAttempted = true
            do {
                let modelInterpretation = try await foundationModelsInterpreter.interpretCanonical(
                    prompt: normalization.originalText,
                    context: context.routerContext
                )
                let modelEvaluation = evaluate(
                    modelInterpretation,
                    provider: context.provider,
                    now: context.now,
                    defaultPeriodUnit: context.defaultPeriodUnit,
                    explicitConstraints: explicitConstraints
                )

                if shouldUseDeterministicFallback(for: modelEvaluation) {
                    selection.heuristicAttempted = true
                    let heuristicInterpretation = heuristicInterpreter.interpretCanonical(
                        prompt: normalization.originalText,
                        defaultPeriodUnit: normalization.defaultPeriodUnit
                    )
                    let heuristicEvaluation = evaluate(
                        heuristicInterpretation,
                        provider: context.provider,
                        now: context.now,
                        defaultPeriodUnit: context.defaultPeriodUnit,
                        explicitConstraints: explicitConstraints
                    )
                    if shouldSelectDeterministicFallback(
                        heuristicEvaluation,
                        over: modelEvaluation,
                        turnClassification: context.turnClassification
                    ) {
                        selection.selectedInterpreter = .heuristic
                        selection.heuristicUsedAsFallback = true
                        let reason = deterministicFallbackReason(for: modelEvaluation)
                        selection.interpreterSelectionReason = interpreterSelectionReason(forDeterministicFallback: reason)
                        selection.fallbackReason = reason
                        return runtimeResult(
                            evaluation: heuristicEvaluation,
                            context: context,
                            modelAvailabilitySummary: modelAvailabilitySummary,
                            selection: selection,
                            disagreementSummary: disagreementSummary(modelEvaluation: modelEvaluation, heuristicEvaluation: heuristicEvaluation)
                        )
                    }
                }

                selection.selectedInterpreter = .foundationModels
                return runtimeResult(
                    evaluation: modelEvaluation,
                    context: context,
                    modelAvailabilitySummary: modelAvailabilitySummary,
                    selection: selection,
                    disagreementSummary: nil
                )
            } catch {
                let failureReason = fallbackReason(forModelError: error)
                selection.modelAttempted = true
                selection.heuristicAttempted = true
                selection.heuristicUsedAsFallback = true
                selection.selectedInterpreter = .heuristic
                selection.interpreterSelectionReason = interpreterSelectionReason(for: failureReason)
                selection.fallbackReason = failureReason
                let interpretation = heuristicInterpreter.interpretCanonical(
                    prompt: normalization.originalText,
                    defaultPeriodUnit: normalization.defaultPeriodUnit
                )
                let evaluation = evaluate(
                    interpretation,
                    provider: context.provider,
                    now: context.now,
                    defaultPeriodUnit: context.defaultPeriodUnit,
                    explicitConstraints: explicitConstraints
                )
                return runtimeResult(
                    evaluation: evaluation,
                    context: context,
                    modelAvailabilitySummary: modelAvailabilitySummary,
                    selection: selection,
                    disagreementSummary: failureReason.rawValue
                )
            }
        }

        selection.heuristicAttempted = true
        selection.selectedInterpreter = .heuristic
        selection.fallbackReason = context.aiOptInEnabled ? .modelUnavailable : .aiOptOut
        let interpretation = heuristicInterpreter.interpretCanonical(
            prompt: normalization.originalText,
            defaultPeriodUnit: normalization.defaultPeriodUnit
        )
        let evaluation = evaluate(
            interpretation,
            provider: context.provider,
            now: context.now,
            defaultPeriodUnit: context.defaultPeriodUnit,
            explicitConstraints: explicitConstraints
        )
        return runtimeResult(
            evaluation: evaluation,
            context: context,
            modelAvailabilitySummary: modelAvailabilitySummary,
            selection: selection,
            disagreementSummary: selection.fallbackReason?.rawValue
        )
    }

    func resume(
        clarification: MarinaTypedClarification,
        choice: MarinaClarificationChoice,
        context: MarinaSharedPipelineContext
    ) async -> MarinaSharedPipelineRuntimeResult {
        guard let candidate = clarification.candidate else {
            return fallback(
                context: context,
                modelAvailabilitySummary: nil,
                reason: .validationDidNotProduceExecutablePlan
            )
        }

        let resumedCandidate = candidate.replacingClarifiedMention(with: choice)
        let evaluation: CandidateEvaluation
        if let pendingSemanticQuery = clarification.pendingSemanticQuery,
           let patchedQuery = pendingSemanticQuery.patching(
            choice: choice,
            fallbackSlot: clarification.patchSlot,
            now: context.now,
            defaultPeriodUnit: context.defaultPeriodUnit
           ) {
            evaluation = evaluate(
                semanticQuery: patchedQuery,
                candidate: resumedCandidate,
                provider: context.provider,
                now: context.now,
                defaultPeriodUnit: context.defaultPeriodUnit,
                explicitConstraints: MarinaExplicitPromptConstraints()
            )
        } else {
            evaluation = evaluate(
                resumedCandidate,
                provider: context.provider,
                now: context.now,
                defaultPeriodUnit: context.defaultPeriodUnit,
                explicitConstraints: MarinaExplicitPromptConstraints()
            )
        }
        let selection = MarinaInterpreterSelectionTrace(
            aiAvailable: nil,
            aiOptIn: context.aiOptInEnabled,
            aiRouteEligible: false,
            selectedInterpreter: resumedCandidate.source,
            interpreterSelectionReason: .clarificationResume,
            modelAttempted: resumedCandidate.source == .foundationModels,
            heuristicAttempted: resumedCandidate.source == .heuristic,
            heuristicUsedAsFallback: false,
            fallbackReason: nil
        )
        let trace = trace(
            context: context,
            modelAvailabilitySummary: nil,
            selectedPath: resumedCandidate.source == .foundationModels ? .sharedFoundationModels : .sharedHeuristic,
            evaluation: evaluation,
            selection: selection,
            fallbackReason: nil,
            disagreementSummary: "clarificationChoice=\(choice.patchSlot?.rawValue ?? clarification.patchSlot?.rawValue ?? choice.entityTypeHint?.rawValue ?? "unknown"):\(choice.title)"
        )

        if evaluation.isExecutableHandled {
            return .handled(
                answer: evaluation.answer!,
                aggregationResult: evaluation.aggregationResult!,
                homeQueryPlan: evaluation.executablePlan?.homeQueryPlan,
                trace: trace
            )
        }

        if evaluation.isValidationBlocked {
            return .validationBlocked(
                answer: evaluation.blockedAnswer!,
                validationOutcome: evaluation.validationOutcome,
                trace: trace
            )
        }

        let blocked = unsupportedEvaluation(
            candidate: resumedCandidate,
            resolved: evaluation.resolved,
            reason: evaluation.runtimeFallbackReason ?? .validationDidNotProduceExecutablePlan
        )
        return .validationBlocked(
            answer: blocked.blockedAnswer!,
            validationOutcome: blocked.validationOutcome,
            trace: trace
        )
    }

    private func shouldUseDeterministicFallback(for evaluation: CandidateEvaluation) -> Bool {
        if case .unsupported = evaluation.validationOutcome {
            return true
        }
        if case .clarification = evaluation.validationOutcome {
            return true
        }
        return false
    }

    private func deterministicFallbackReason(for evaluation: CandidateEvaluation) -> MarinaSharedPipelineFallbackReason {
        if case .clarification = evaluation.validationOutcome {
            return .modelClarificationHeuristicExactMatch
        }
        return .modelUnsupportedHeuristicExactMatch
    }

    private func interpreterSelectionReason(
        forDeterministicFallback reason: MarinaSharedPipelineFallbackReason
    ) -> MarinaInterpreterSelectionReason {
        switch reason {
        case .modelClarificationHeuristicExactMatch:
            return .modelClarificationHeuristicExactMatch
        default:
            return .modelUnsupportedHeuristicExactMatch
        }
    }

    private func isExactExecutableFallback(_ evaluation: CandidateEvaluation) -> Bool {
        evaluation.candidate.confidence == .high
            && evaluation.candidate.unsupportedHint == nil
            && evaluation.isExecutableHandled
            && evaluation.runtimeFallbackReason != .droppedExplicitConstraint
    }

    private func shouldSelectDeterministicFallback(
        _ heuristicEvaluation: CandidateEvaluation,
        over modelEvaluation: CandidateEvaluation,
        turnClassification: MarinaPromptTurnClassification
    ) -> Bool {
        if turnClassification == .freshQuestion || turnClassification == .followUp {
            return heuristicEvaluation.isExecutableHandled
                && heuristicEvaluation.runtimeFallbackReason != .droppedExplicitConstraint
        }
        if case .clarification = modelEvaluation.validationOutcome {
            return heuristicEvaluation.isExecutableHandled
                && heuristicEvaluation.runtimeFallbackReason != .droppedExplicitConstraint
        }
        return isExactExecutableFallback(heuristicEvaluation)
    }

    private func fallbackReason(forModelError error: Error) -> MarinaSharedPipelineFallbackReason {
        if let serviceError = error as? MarinaFoundationModelsServiceError {
            switch serviceError {
            case .malformedResponse:
                return .modelInvalidStructuredOutput
            case .unavailable:
                return .modelUnavailable
            }
        }
        if error is CancellationError {
            return .modelTimedOut
        }
        return .modelServiceFailed
    }

    private func interpreterSelectionReason(
        for fallbackReason: MarinaSharedPipelineFallbackReason
    ) -> MarinaInterpreterSelectionReason {
        switch fallbackReason {
        case .modelInvalidStructuredOutput:
            return .modelInvalidStructuredOutput
        case .modelUnavailable:
            return .modelUnavailable
        case .modelTimedOut:
            return .modelTimedOut
        default:
            return .modelServiceFailed
        }
    }

    private func runtimeResult(
        evaluation: CandidateEvaluation,
        context: MarinaSharedPipelineContext,
        modelAvailabilitySummary: String?,
        selection: MarinaInterpreterSelectionTrace,
        disagreementSummary: String?
    ) -> MarinaSharedPipelineRuntimeResult {
        if evaluation.isExecutableHandled {
            let trace = trace(
                context: context,
                modelAvailabilitySummary: modelAvailabilitySummary,
                selectedPath: evaluation.candidate.source == .foundationModels ? .sharedFoundationModels : .sharedHeuristic,
                evaluation: evaluation,
                selection: selection,
                fallbackReason: selection.heuristicUsedAsFallback ? selection.fallbackReason : nil,
                disagreementSummary: disagreementSummary
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
                selection: selection,
                fallbackReason: selection.heuristicUsedAsFallback ? selection.fallbackReason : nil,
                disagreementSummary: disagreementSummary
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
            reason: evaluation.runtimeFallbackReason ?? selection.fallbackReason ?? .validationDidNotProduceExecutablePlan
        )
        let trace = trace(
            context: context,
            modelAvailabilitySummary: modelAvailabilitySummary,
            selectedPath: blocked.candidate.source == .foundationModels ? .sharedFoundationModels : .sharedHeuristic,
            evaluation: blocked,
            selection: selection,
            fallbackReason: selection.heuristicUsedAsFallback ? selection.fallbackReason : nil,
            disagreementSummary: disagreementSummary
        )
        return .validationBlocked(
            answer: blocked.blockedAnswer!,
            validationOutcome: blocked.validationOutcome,
            trace: trace
        )
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
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        explicitConstraints: MarinaExplicitPromptConstraints
    ) -> CandidateEvaluation {
        evaluate(
            MarinaCanonicalReadInterpretation(
                result: semanticAdapter.interpretationResult(from: candidate),
                compatibilityCandidate: candidate
            ),
            provider: provider,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit,
            explicitConstraints: explicitConstraints
        )
    }

    private func evaluate(
        _ interpretation: MarinaCanonicalReadInterpretation,
        provider: MarinaDataProvider,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        explicitConstraints: MarinaExplicitPromptConstraints
    ) -> CandidateEvaluation {
        let candidate = interpretation.compatibilityCandidate
        let resolved = resolver.resolve(
            candidate: candidate,
            provider: provider,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        )
        let semanticResolved: MarinaResolvedSemanticQuery?
        let outcome: MarinaPlanValidationOutcome

        switch interpretation.result {
        case .query(let query):
            let resolvedQuery = resolver.resolve(
                query: query,
                provider: provider,
                candidate: candidate,
                now: now,
                defaultPeriodUnit: defaultPeriodUnit
            )
            semanticResolved = resolvedQuery
            outcome = validator.validate(resolvedQuery)
        case .clarification(let clarification):
            semanticResolved = nil
            outcome = .clarification(clarification)
        case .unsupported(let unsupported):
            semanticResolved = nil
            outcome = .unsupported(unsupported)
        }

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
                runtimeFallbackReason: .clarificationBridgeUnavailable,
                interpretationResult: interpretation.result,
                semanticResolved: semanticResolved
            )
        case .unsupported:
            return CandidateEvaluation(
                candidate: candidate,
                resolved: resolved,
                validationOutcome: outcome,
                blockedAnswer: responseBuilder.responseCompatibleAnswer(from: outcome),
                runtimeFallbackReason: .unsupportedBridgeUnavailable,
                interpretationResult: interpretation.result,
                semanticResolved: semanticResolved
            )
        case .executable:
            if let unsupported = explicitConstraints.unsupportedIfDropped(by: candidate, resolvedQuery: semanticResolved, outcome: outcome) {
                let unsupportedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                return CandidateEvaluation(
                    candidate: candidate,
                    resolved: resolved,
                    validationOutcome: unsupportedOutcome,
                    blockedAnswer: responseBuilder.responseCompatibleAnswer(from: unsupportedOutcome),
                    runtimeFallbackReason: .droppedExplicitConstraint,
                    interpretationResult: interpretation.result,
                    semanticResolved: semanticResolved
                )
            }
            let queryExecutor = MarinaQueryExecutor(
                adapter: adapter,
                executor: executor,
                composableWorkspaceQueryExecutor: composableWorkspaceQueryExecutor,
                workspaceAggregationExecutor: workspaceAggregationExecutor,
                databaseLookupExecutor: databaseLookupExecutor,
                databaseLookupResponseBuilder: databaseLookupResponseBuilder
            )
            switch queryExecutor.execute(
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                provider: provider,
                now: now
            ) {
            case .handled(let execution):
                let answer = execution.databaseLookupResponse.map(databaseLookupResponseBuilder.responseCompatibleAnswer)
                    ?? responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult)
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
                    databaseLookupResponse: execution.databaseLookupResponse,
                    workspaceAggregationCard: execution.workspaceAggregationCard,
                    interpretationResult: interpretation.result,
                    semanticResolved: semanticResolved,
                    amountBasis: execution.amountBasis,
                    executionRoute: execution.executionRoute
                )
            case .unsupported(let unsupported):
                let unsupportedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                return CandidateEvaluation(
                    candidate: candidate,
                    resolved: resolved,
                    validationOutcome: unsupportedOutcome,
                    blockedAnswer: responseBuilder.responseCompatibleAnswer(from: unsupportedOutcome),
                    runtimeFallbackReason: .executorUnsupported,
                    interpretationResult: interpretation.result,
                    semanticResolved: semanticResolved
                )
            }
        }
    }

    private func evaluate(
        semanticQuery query: MarinaSemanticQuery,
        candidate: MarinaQueryPlanCandidate,
        provider: MarinaDataProvider,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        explicitConstraints: MarinaExplicitPromptConstraints
    ) -> CandidateEvaluation {
        let interpretation = MarinaInterpretationResult.query(query)
        let resolved = resolver.resolve(
            candidate: candidate,
            provider: provider,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        )
        let semanticResolved = resolver.resolve(
            query: query,
            provider: provider,
            candidate: candidate,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        )
        let outcome = validator.validate(semanticResolved)
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
                runtimeFallbackReason: .clarificationBridgeUnavailable,
                interpretationResult: interpretation,
                semanticResolved: semanticResolved
            )
        case .unsupported:
            return CandidateEvaluation(
                candidate: candidate,
                resolved: resolved,
                validationOutcome: outcome,
                blockedAnswer: responseBuilder.responseCompatibleAnswer(from: outcome),
                runtimeFallbackReason: .unsupportedBridgeUnavailable,
                interpretationResult: interpretation,
                semanticResolved: semanticResolved
            )
        case .executable:
            if let unsupported = explicitConstraints.unsupportedIfDropped(by: candidate, resolvedQuery: semanticResolved, outcome: outcome) {
                let unsupportedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                return CandidateEvaluation(
                    candidate: candidate,
                    resolved: resolved,
                    validationOutcome: unsupportedOutcome,
                    blockedAnswer: responseBuilder.responseCompatibleAnswer(from: unsupportedOutcome),
                    runtimeFallbackReason: .droppedExplicitConstraint,
                    interpretationResult: interpretation,
                    semanticResolved: semanticResolved
                )
            }
            let queryExecutor = MarinaQueryExecutor(
                adapter: adapter,
                executor: executor,
                composableWorkspaceQueryExecutor: composableWorkspaceQueryExecutor,
                workspaceAggregationExecutor: workspaceAggregationExecutor,
                databaseLookupExecutor: databaseLookupExecutor,
                databaseLookupResponseBuilder: databaseLookupResponseBuilder
            )
            switch queryExecutor.execute(
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                provider: provider,
                now: now
            ) {
            case .handled(let execution):
                let answer = execution.databaseLookupResponse.map(databaseLookupResponseBuilder.responseCompatibleAnswer)
                    ?? responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult)
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
                    databaseLookupResponse: execution.databaseLookupResponse,
                    workspaceAggregationCard: execution.workspaceAggregationCard,
                    interpretationResult: interpretation,
                    semanticResolved: semanticResolved,
                    amountBasis: execution.amountBasis,
                    executionRoute: execution.executionRoute
                )
            case .unsupported(let unsupported):
                let unsupportedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                return CandidateEvaluation(
                    candidate: candidate,
                    resolved: resolved,
                    validationOutcome: unsupportedOutcome,
                    blockedAnswer: responseBuilder.responseCompatibleAnswer(from: unsupportedOutcome),
                    runtimeFallbackReason: .executorUnsupported,
                    interpretationResult: interpretation,
                    semanticResolved: semanticResolved
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
                aiAvailable: nil,
                aiOptIn: context.aiOptInEnabled,
                aiRouteEligible: false,
                selectedInterpreter: nil,
                interpreterSelectionReason: .gateDisabled,
                modelAttempted: false,
                heuristicAttempted: false,
                heuristicUsedAsFallback: false,
                modelAvailabilitySummary: modelAvailabilitySummary,
                selectedPath: .legacy,
                fallbackReason: reason,
                turnClassification: context.turnClassification,
                priorContextIncluded: context.routerContext.priorQueryContext.hasContext
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
        selection: MarinaInterpreterSelectionTrace,
        fallbackReason: MarinaSharedPipelineFallbackReason?,
        disagreementSummary: String?
    ) -> MarinaSharedPipelineTrace {
        MarinaSharedPipelineTrace(
            sharedPipelineEnabled: context.sharedPipelineEnabled,
            aiOptInEnabled: context.aiOptInEnabled,
            aiAvailable: selection.aiAvailable,
            aiOptIn: selection.aiOptIn,
            aiRouteEligible: selection.aiRouteEligible,
            selectedInterpreter: selection.selectedInterpreter,
            interpreterSelectionReason: selection.interpreterSelectionReason,
            modelAttempted: selection.modelAttempted,
            heuristicAttempted: selection.heuristicAttempted,
            heuristicUsedAsFallback: selection.heuristicUsedAsFallback,
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
            semanticInterpretationSummary: evaluation.flatMap { semanticInterpretationSummary($0.interpretationResult) },
            semanticResolverSummary: evaluation?.semanticResolved.map(semanticResolverSummary),
            validatorOutcomeSummary: evaluation.map { validatorSummary($0.validationOutcome) },
            semanticValidationSummary: evaluation.map { validatorSummary($0.validationOutcome) },
            executorResultSummary: Self.executorSummary(evaluation),
            responseBridgeSummary: responseBridgeSummary(evaluation),
            responseShapeSummary: evaluation.map(responseShapeSummary),
            fallbackReason: fallbackReason,
            disagreementSummary: disagreementSummary,
            selectionRank: evaluation.map(recoveryPolicy.selectionRank),
            rejectedReason: evaluation.flatMap {
                recoveryPolicy.rejectedReason(selected: $0, other: competingEvaluation)
            },
            operationPreserved: evaluation?.operationPreserved,
            turnClassification: context.turnClassification,
            priorContextIncluded: context.routerContext.priorQueryContext.hasContext
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

    private func semanticInterpretationSummary(_ result: MarinaInterpretationResult?) -> String? {
        guard let result else { return nil }
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

    private func semanticResolverSummary(_ resolved: MarinaResolvedSemanticQuery) -> String {
        [
            "resolved=\(resolved.resolvedFilters.count)",
            "unresolved=\(resolved.unresolvedFilters.count)",
            "ambiguous=\(resolved.ambiguousFilters.count)",
            "primary=\(resolved.primaryDateRange?.traceSummary ?? "nil")",
            "comparison=\(resolved.comparisonDateRange?.traceSummary ?? "nil")"
        ].joined(separator: ",")
    }

    private func validatorSummary(_ outcome: MarinaPlanValidationOutcome) -> String {
        switch outcome {
        case .executable(let plan):
            return "executable:\(plan.operation.rawValue):\(plan.measure.rawValue):incomeStatus=\(plan.incomeStatusScope?.rawValue ?? "nil"):shape=\(plan.responseShape?.rawValue ?? "nil")"
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
        case .noData(let result):
            return "noData:\(result.title)"
        case .unsupported(let unsupported):
            return "unsupported:\(unsupported.kind.rawValue)"
        }
    }

    private static func executorSummary(_ evaluation: CandidateEvaluation?) -> String? {
        guard let evaluation else { return nil }
        let base = evaluation.databaseLookupResponse?.traceSummary
            ?? evaluation.workspaceAggregationCard?.traceSummary
            ?? evaluation.aggregationResult.map(Self.aggregationResultSummary)
        let route = evaluation.executionRoute.map { "route=\($0.traceName)" }
        let basis = evaluation.amountBasis.map { "amountBasis=\($0.rawValue)" }
        let prefix = [route, basis].compactMap { $0 }.joined(separator: ";")
        guard prefix.isEmpty == false else { return base }
        guard let base else { return prefix }
        return "\(prefix);\(base)"
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
    let interpretationResult: MarinaInterpretationResult?
    let semanticResolved: MarinaResolvedSemanticQuery?
    let amountBasis: MarinaFinancialAmountBasis?
    let executionRoute: MarinaSemanticExecutionRoute?

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
        workspaceAggregationCard: MarinaWorkspaceAggregationCard? = nil,
        interpretationResult: MarinaInterpretationResult? = nil,
        semanticResolved: MarinaResolvedSemanticQuery? = nil,
        amountBasis: MarinaFinancialAmountBasis? = nil,
        executionRoute: MarinaSemanticExecutionRoute? = nil
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
        self.interpretationResult = interpretationResult
        self.semanticResolved = semanticResolved
        self.amountBasis = amountBasis
        self.executionRoute = executionRoute
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
    let databaseLookupResponse: MarinaDatabaseLookupResponse?
    let workspaceAggregationCard: MarinaWorkspaceAggregationCard?
    let amountBasis: MarinaFinancialAmountBasis
    let executionRoute: MarinaSemanticExecutionRoute
}

private struct MarinaInterpreterSelectionTrace {
    let aiAvailable: Bool?
    let aiOptIn: Bool
    let aiRouteEligible: Bool
    var selectedInterpreter: MarinaInterpreterSource?
    var interpreterSelectionReason: MarinaInterpreterSelectionReason?
    var modelAttempted: Bool
    var heuristicAttempted: Bool
    var heuristicUsedAsFallback: Bool
    var fallbackReason: MarinaSharedPipelineFallbackReason?
}

struct MarinaExplicitPromptConstraints: Equatable {
    var categories: Set<String> = []
    var cards: Set<String> = []
    var hasDateConstraint = false
    var limit: Int?
    var sort: MarinaRankingDirectionCandidate?

    var isEmpty: Bool {
        categories.isEmpty && cards.isEmpty && hasDateConstraint == false && limit == nil && sort == nil
    }

    func unsupportedIfDropped(
        by candidate: MarinaQueryPlanCandidate,
        resolvedQuery: MarinaResolvedSemanticQuery?,
        outcome: MarinaPlanValidationOutcome
    ) -> MarinaTypedUnsupportedResponse? {
        guard isEmpty == false,
              case .executable(let plan) = outcome else {
            return nil
        }

        var dropped: [String] = []
        if categories.isEmpty == false,
           preserves(names: categories, type: .category, plan: plan, resolvedQuery: resolvedQuery, candidate: candidate) == false {
            dropped.append("category")
        }
        if cards.isEmpty == false,
           preserves(names: cards, type: .card, plan: plan, resolvedQuery: resolvedQuery, candidate: candidate) == false {
            dropped.append("card")
        }
        if hasDateConstraint,
           plan.dateRange == nil,
           resolvedQuery?.primaryDateRange == nil,
           candidate.timeScopes.isEmpty,
           usesAppSurfaceDefaultDatePolicy(plan) == false {
            dropped.append("date")
        }
        if let limit,
           plan.limit != limit,
           candidate.limit != limit,
           resolvedQuery?.query.limit != limit {
            dropped.append("limit")
        }
        if let sort,
           plan.ranking?.direction != sort,
           candidate.ranking?.direction != sort,
           resolvedQuery?.query.ranking?.direction != sort {
            dropped.append("sort")
        }

        guard dropped.isEmpty == false else { return nil }
        return MarinaTypedUnsupportedResponse(
            kind: .unsupportedCombination,
            message: "I found an explicit \(dropped.joined(separator: ", ")) constraint in your prompt, but the selected interpretation did not preserve it.",
            candidate: candidate
        )
    }

    private func preserves(
        names: Set<String>,
        type: MarinaCandidateEntityTypeHint,
        plan: MarinaAggregationPlan,
        resolvedQuery: MarinaResolvedSemanticQuery?,
        candidate: MarinaQueryPlanCandidate
    ) -> Bool {
        let planNames = Set(plan.targets.filter { $0.entityType == type }.map { Self.normalized($0.displayName) })
        let resolvedNames = Set((resolvedQuery?.resolvedFilters ?? []).filter { $0.entityType == type }.map { Self.normalized($0.displayName) })
        let rawNames = Set(candidate.entityMentions.compactMap { mention -> String? in
            let allowed = mention.typeHint == type || mention.allowedTypeHints?.contains(type) == true
            guard allowed, let raw = mention.rawText else { return nil }
            return Self.normalized(raw)
        })
        let semanticRawNames = Set((resolvedQuery?.query.filters ?? []).compactMap { filter -> String? in
            let allowed = filter.entityTypeHint == type || filter.allowedEntityTypeHints?.contains(type) == true
            guard allowed else { return nil }
            return Self.normalized(filter.value)
        })
        let preservedNames = planNames.union(resolvedNames).union(rawNames).union(semanticRawNames)
        return names.allSatisfy { preservedNames.contains($0) }
    }

    private func usesAppSurfaceDefaultDatePolicy(_ plan: MarinaAggregationPlan) -> Bool {
        switch (plan.operation, plan.measure) {
        case (.lookupDetails, .savings),
             (.lookupDetails, .remainingBudget),
             (.lookupDetails, .presetAmount),
             (.forecast, .savings):
            return true
        default:
            return false
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct MarinaExplicitConstraintDetector {
    func constraints(
        in prompt: String,
        context: MarinaLanguageRouterContext
    ) -> MarinaExplicitPromptConstraints {
        let normalizedPrompt = normalized(prompt)
        let explicitCards = explicitNames(context.cardNames, in: normalizedPrompt)
        let explicitCategories = explicitNames(context.categoryNames, in: normalizedPrompt)
        return MarinaExplicitPromptConstraints(
            categories: explicitCategories.filter { category in
                isLikelyCardNameFragment(category, cards: explicitCards, prompt: normalizedPrompt) == false
            },
            cards: explicitCards,
            hasDateConstraint: hasDateConstraint(in: normalizedPrompt),
            limit: explicitLimit(in: normalizedPrompt),
            sort: explicitSort(in: normalizedPrompt)
        )
    }

    private func explicitNames(_ names: [String], in normalizedPrompt: String) -> Set<String> {
        Set(names.compactMap { name in
            let normalizedName = normalized(name)
            guard normalizedName.isEmpty == false else { return nil }
            return containsWholePhrase(normalizedName, in: normalizedPrompt) ? normalizedName : nil
        })
    }

    private func isLikelyCardNameFragment(
        _ category: String,
        cards: Set<String>,
        prompt: String
    ) -> Bool {
        guard cards.isEmpty == false else { return false }
        if containsWholePhrase("\(category) card", in: prompt) {
            return true
        }
        return cards.contains { card in
            card != category && card.contains(category) && containsWholePhrase(card, in: prompt)
        }
    }

    private func hasDateConstraint(in prompt: String) -> Bool {
        let phrases = [
            "today", "yesterday", "this week", "last week", "this month", "last month",
            "this budget", "this period", "last period", "january", "february", "march",
            "april", "may", "june", "july", "august", "september", "october",
            "november", "december"
        ]
        return phrases.contains { containsWholePhrase($0, in: prompt) }
    }

    private func explicitLimit(in prompt: String) -> Int? {
        let listWords = ["list", "show", "top", "largest", "biggest"]
        guard listWords.contains(where: { containsWholePhrase($0, in: prompt) }) else { return nil }
        return prompt
            .split(separator: " ")
            .compactMap { Int($0) }
            .first
    }

    private func explicitSort(in prompt: String) -> MarinaRankingDirectionCandidate? {
        if ["recent", "newest", "latest"].contains(where: { containsWholePhrase($0, in: prompt) }) {
            return .newest
        }
        if containsWholePhrase("last", in: prompt),
           ["list", "show"].contains(where: { containsWholePhrase($0, in: prompt) }),
           containsWholePhrase("last month", in: prompt) == false,
           containsWholePhrase("last week", in: prompt) == false,
           containsWholePhrase("last period", in: prompt) == false {
            return .newest
        }
        if ["largest", "biggest"].contains(where: { containsWholePhrase($0, in: prompt) }) {
            return .largest
        }
        return nil
    }

    private func containsWholePhrase(_ phrase: String, in prompt: String) -> Bool {
        let pattern = "(^|\\s)\(NSRegularExpression.escapedPattern(for: phrase))(\\s|$)"
        return prompt.range(of: pattern, options: .regularExpression) != nil
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
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
    let databaseLookupExecutor: MarinaDatabaseLookupExecutor
    let databaseLookupResponseBuilder: MarinaDatabaseLookupResponseBuilder
    let router: MarinaSemanticExecutionRouter = MarinaSemanticExecutionRouter()

    func execute(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
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

        let decision = router.decision(validationOutcome: validationOutcome, semanticResolved: semanticResolved)

        switch decision.route {
        case .lookupDetail:
            guard let request = semanticResolved?.databaseLookupRequest ?? candidate.databaseLookupRequest else {
                if let request = syntheticLookupRequest(for: plan, candidate: candidate) {
                    return executeLookup(request, provider: provider, decision: decision)
                }
                if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                    return handled
                }
                if let handled = executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision) {
                    return handled
                }
                return unsupported(candidate: candidate)
            }
            return executeLookup(request, provider: provider, decision: decision)
        case .aggregate:
            if let handled = executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision) {
                return handled
            }
            if hasExecutableTarget(plan) || resolved.resolvedTargets.isEmpty == false {
                if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                    return handled
                }
            }
            if let handled = executeWorkspace(plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            return unsupported(candidate: candidate)
        case .comparison, .groupedRanked:
            if let handled = executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeWorkspace(plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            return unsupported(candidate: candidate)
        case .list:
            if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeWorkspace(plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision) {
                return handled
            }
            return unsupported(candidate: candidate)
        case .scenario:
            if let handled = executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            if let handled = executeWorkspace(plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
            return unsupported(candidate: candidate)
        case .unsupported(let kind):
            return .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: kind,
                    message: "No shared Marina executor supports this plan shape.",
                    candidate: candidate
                )
            )
        }
    }

    private func syntheticLookupRequest(
        for plan: MarinaAggregationPlan,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaDatabaseLookupRequest? {
        guard plan.operation == .lookupDetails,
              let target = plan.targets.first else {
            return nil
        }

        let objectTypes: [MarinaLookupObjectType]
        switch target.entityType {
        case .expense, .transaction:
            objectTypes = [.variableExpense, .plannedExpense]
        case .merchant:
            objectTypes = [.variableExpense, .plannedExpense]
        case .card, .category, .preset, .budget, .savingsAccount, .allocationAccount, .incomeSource, .workspace:
            return nil
        }

        return MarinaDatabaseLookupRequest(
            rawPrompt: candidate.rawPrompt,
            searchText: target.displayName,
            objectTypes: objectTypes,
            dateRange: plan.dateRange,
            limit: plan.limit ?? 1,
            requestedDetail: .general
        ).clamped
    }

    private func executeLookup(
        _ request: MarinaDatabaseLookupRequest,
        provider: MarinaDataProvider,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecutionResult {
        let response = databaseLookupExecutor.execute(request, provider: provider)
        let answer = databaseLookupResponseBuilder.responseCompatibleAnswer(from: response)
        let result: MarinaAggregationResult = response.results.isEmpty && response.ambiguityChoices.isEmpty
            ? .noData(
                MarinaNoDataAggregationResult(
                    title: answer.title,
                    message: answer.subtitle ?? "No matching data found.",
                    sourceAnswer: answer
                )
            )
            : .message(
                MarinaMessageAggregationResult(
                    title: answer.title,
                    message: answer.subtitle,
                    sourceAnswer: answer
                )
            )
        return .handled(
            MarinaQueryExecution(
                executablePlan: nil,
                aggregationResult: result,
                databaseLookupResponse: response,
                workspaceAggregationCard: nil,
                amountBasis: decision.amountBasis,
                executionRoute: decision.route
            )
        )
    }

    private func executeHomeAdapter(
        _ validationOutcome: MarinaPlanValidationOutcome,
        provider: MarinaDataProvider,
        now: Date,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecutionResult? {
        guard case .success(let executablePlan) = adapter.executablePlan(from: validationOutcome) else {
            return nil
        }

        let result = noDataIfNeeded(executor.execute(executablePlan, provider: provider, now: now))
        if case .unsupported(let unsupported) = result {
            return .unsupported(unsupported)
        }
        return .handled(
            MarinaQueryExecution(
                executablePlan: executablePlan,
                aggregationResult: result,
                databaseLookupResponse: nil,
                workspaceAggregationCard: nil,
                amountBasis: decision.amountBasis,
                executionRoute: decision.route
            )
        )
    }

    private func executeComposable(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecutionResult? {
        switch composableWorkspaceQueryExecutor.execute(
            candidate: candidate,
            resolved: resolved,
            plan: plan,
            provider: provider,
            now: now,
            amountBasis: decision.amountBasis
        ) {
        case .handled(let card):
            return .handled(workspaceExecution(card, decision: decision))
        case .unsupported:
            return nil
        }
    }

    private func executeWorkspace(
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecutionResult? {
        switch workspaceAggregationExecutor.execute(plan: plan, provider: provider, now: now) {
        case .handled(let card):
            return .handled(workspaceExecution(card, decision: decision))
        case .unsupported:
            return nil
        }
    }

    private func workspaceExecution(
        _ card: MarinaWorkspaceAggregationCard,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecution {
        MarinaQueryExecution(
            executablePlan: nil,
            aggregationResult: .workspaceCard(card),
            databaseLookupResponse: nil,
            workspaceAggregationCard: card,
            amountBasis: decision.amountBasis,
            executionRoute: decision.route
        )
    }

    private func unsupported(candidate: MarinaQueryPlanCandidate) -> MarinaQueryExecutionResult {
        .unsupported(
            MarinaTypedUnsupportedResponse(
                kind: .unsupportedCombination,
                message: "No shared Marina executor supports this plan shape.",
                candidate: candidate
            )
        )
    }

    private func hasExecutableTarget(_ plan: MarinaAggregationPlan) -> Bool {
        plan.targets.contains { target in
            switch target.role {
            case .filter, .primaryTarget, .comparisonTarget, .simulationInput, .simulationOutput:
                return true
            case .excludeFilter, .groupingDimension:
                return false
            }
        }
    }

    private func noDataIfNeeded(_ result: MarinaAggregationResult) -> MarinaAggregationResult {
        switch result {
        case .rankedList(let list) where list.rows.isEmpty:
            return .noData(
                MarinaNoDataAggregationResult(
                    title: list.title,
                    message: "No data available for that range.",
                    sourceAnswer: list.sourceAnswer
                )
            )
        case .groupedBreakdown(let list) where list.rows.isEmpty:
            return .noData(
                MarinaNoDataAggregationResult(
                    title: list.title,
                    message: "No data available for that range.",
                    sourceAnswer: list.sourceAnswer
                )
            )
        default:
            return result
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

private extension MarinaQueryPlanCandidate {
    func replacingClarifiedMention(with choice: MarinaClarificationChoice) -> MarinaQueryPlanCandidate {
        let replacementRole = choice.entityRole ?? .filter
        let replacement = MarinaUnresolvedEntityMention(
            id: choice.mentionID ?? UUID(),
            role: replacementRole,
            rawText: choice.rawValue ?? choice.title,
            typeHint: choice.entityTypeHint,
            allowedTypeHints: choice.entityTypeHint.map { [$0] },
            confidence: .high
        )

        let mentions: [MarinaUnresolvedEntityMention]
        if let mentionID = choice.mentionID,
           entityMentions.contains(where: { $0.id == mentionID }) {
            mentions = entityMentions.map { $0.id == mentionID ? replacement : $0 }
        } else if entityMentions.isEmpty {
            mentions = [replacement]
        } else {
            mentions = [replacement] + entityMentions.dropFirst()
        }

        return MarinaQueryPlanCandidate(
            requestFamily: requestFamily,
            source: source,
            rawPrompt: rawPrompt,
            operation: operation,
            measure: measure,
            entityMentions: mentions,
            timeScopes: timeScopes,
            grouping: grouping,
            ranking: ranking,
            limit: limit,
            responseShapeHint: responseShapeHint,
            confidence: .high,
            unsupportedHint: unsupportedHint,
            databaseLookupRequest: databaseLookupRequest,
            semanticCommand: semanticCommand
        )
    }
}

private extension MarinaSemanticQuery {
    func patching(
        choice: MarinaClarificationChoice,
        fallbackSlot: MarinaClarificationPatchSlot?,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaSemanticQuery? {
        switch choice.patchSlot ?? fallbackSlot ?? inferredPatchSlot(from: choice) {
        case .target:
            return patchingTarget(choice)
        case .date:
            return patchingDate(choice, role: .primary, now: now, defaultPeriodUnit: defaultPeriodUnit)
        case .comparison:
            return patchingDate(choice, role: .comparison, now: now, defaultPeriodUnit: defaultPeriodUnit)
        case .amount:
            return patchingAmount()
        case .simulation:
            return patchingSimulation(choice)
        case nil:
            return nil
        }
    }

    private func patchingTarget(_ choice: MarinaClarificationChoice) -> MarinaSemanticQuery {
        let relationship = choice.entityTypeHint.map(Self.relationship) ?? filters.first?.relationship ?? .unknown
        let entityTypeHint = choice.entityTypeHint
        let shouldAdaptToLookup = operation != .lookupDetails
            && (entityTypeHint == .expense || entityTypeHint == .transaction)
        let patchedFilter = MarinaFilter(
            id: choice.mentionID ?? filters.first?.id ?? UUID(),
            role: resolvedRole(from: choice.entityRole) ?? filters.first?.role ?? .primaryTarget,
            relationship: relationship,
            value: choice.rawValue ?? choice.title,
            matchMode: choice.sourceID == nil ? .semanticOrAlias : .exact,
            entityTypeHint: choice.entityTypeHint,
            sourceID: choice.sourceID
        )

        let patchedFilters: [MarinaFilter]
        if let mentionID = choice.mentionID,
           filters.contains(where: { $0.id == mentionID }) {
            patchedFilters = filters.map { $0.id == mentionID ? patchedFilter : $0 }
        } else if filters.isEmpty {
            patchedFilters = [patchedFilter]
        } else {
            patchedFilters = [patchedFilter] + filters.dropFirst()
        }

        if shouldAdaptToLookup {
            return replacing(
                operation: .lookupDetails,
                filters: patchedFilters,
                clearAmountField: true,
                responseShape: .summaryCard
            )
        }

        return replacing(filters: patchedFilters)
    }

    private func patchingDate(
        _ choice: MarinaClarificationChoice,
        role: MarinaTimeScopeRole,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaSemanticQuery? {
        let rawText = choice.rawValue ?? choice.title
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let resolver = MarinaDateResolver(calendar: calendar, nowProvider: { now })
        guard let resolved = resolver.resolve(
            input: rawText,
            modelStartISO8601: nil,
            modelEndISO8601: nil,
            defaultPeriodUnit: defaultPeriodUnit
        ) else {
            return nil
        }

        let request = MarinaDateRangeRequest(
            role: role,
            rawText: rawText,
            resolvedRange: resolved.queryDateRange,
            periodUnit: defaultPeriodUnit
        )
        return role == .comparison
            ? replacing(comparisonDateRange: request)
            : replacing(dateRange: request)
    }

    private func patchingAmount() -> MarinaSemanticQuery {
        if amountField != nil { return self }
        return replacing(amountField: .amount)
    }

    private func patchingSimulation(_ choice: MarinaClarificationChoice) -> MarinaSemanticQuery {
        if filters.contains(where: { $0.role == .simulationInput }) {
            return patchingAmount()
        }
        return patchingTarget(
            MarinaClarificationChoice(
                title: choice.title,
                subtitle: choice.subtitle,
                entityRole: .simulationInput,
                entityTypeHint: choice.entityTypeHint ?? .category,
                patchSlot: .target,
                rawValue: choice.rawValue,
                sourceID: choice.sourceID,
                mentionID: choice.mentionID
            )
        )
    }

    private func inferredPatchSlot(from choice: MarinaClarificationChoice) -> MarinaClarificationPatchSlot? {
        if choice.entityTypeHint != nil || choice.entityRole != nil || choice.sourceID != nil {
            return .target
        }
        return nil
    }

    private func replacing(
        subject: MarinaSubject? = nil,
        operation: MarinaOperation? = nil,
        filters: [MarinaFilter]? = nil,
        amountField: MarinaAmountField? = nil,
        clearAmountField: Bool = false,
        dateRange: MarinaDateRangeRequest? = nil,
        comparisonDateRange: MarinaDateRangeRequest? = nil,
        responseShape: MarinaResponseShape? = nil
    ) -> MarinaSemanticQuery {
        MarinaSemanticQuery(
            id: id,
            subject: subject ?? self.subject,
            operation: operation ?? self.operation,
            filters: filters ?? self.filters,
            amountField: clearAmountField ? nil : (amountField ?? self.amountField),
            dateRange: dateRange ?? self.dateRange,
            comparisonDateRange: comparisonDateRange ?? self.comparisonDateRange,
            grouping: grouping,
            ranking: ranking,
            limit: limit,
            averageBasis: averageBasis,
            incomeStatusScope: incomeStatusScope,
            responseShape: responseShape ?? self.responseShape
        )
    }

    nonisolated private static func relationship(from typeHint: MarinaCandidateEntityTypeHint) -> MarinaRelationshipField {
        switch typeHint {
        case .category:
            return .category
        case .merchant:
            return .merchant
        case .expense, .transaction:
            return .transaction
        case .card:
            return .card
        case .budget:
            return .budget
        case .preset:
            return .preset
        case .incomeSource:
            return .incomeSource
        case .allocationAccount:
            return .allocationAccount
        case .savingsAccount:
            return .savingsAccount
        case .workspace:
            return .workspace
        }
    }

    private func resolvedRole(from role: MarinaEntityMentionRole?) -> MarinaResolvedTargetRole? {
        switch role {
        case .filter:
            return .filter
        case .excludeFilter:
            return .excludeFilter
        case .primaryTarget:
            return .primaryTarget
        case .comparisonTarget:
            return .comparisonTarget
        case .groupingDimension:
            return .groupingDimension
        case .simulationInput:
            return .simulationInput
        case .simulationOutput:
            return .simulationOutput
        case nil:
            return nil
        }
    }
}
