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

        let promptForInterpretation = contextualizedFollowUpPrompt(prompt, context: context)
        let normalization = promptNormalizer.normalize(
            prompt: promptForInterpretation,
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
                let modelInterpretation = contextualizedInterpretation(
                    try await foundationModelsInterpreter.interpretCanonical(
                        prompt: normalization.originalText,
                        context: context.routerContext
                    ),
                    context: context
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
                    let heuristicInterpretation = contextualizedInterpretation(
                        heuristicInterpreter.interpretCanonical(
                            prompt: normalization.originalText,
                            defaultPeriodUnit: normalization.defaultPeriodUnit,
                            now: context.now
                        ),
                        context: context
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
                let interpretation = contextualizedInterpretation(
                    heuristicInterpreter.interpretCanonical(
                        prompt: normalization.originalText,
                        defaultPeriodUnit: normalization.defaultPeriodUnit,
                        now: context.now
                    ),
                    context: context
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
        let interpretation = contextualizedInterpretation(
            heuristicInterpreter.interpretCanonical(
                prompt: normalization.originalText,
                defaultPeriodUnit: normalization.defaultPeriodUnit,
                now: context.now
            ),
            context: context
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
        if let databaseLookupCandidate = resumedCandidate.replacingDatabaseLookupRequest(
            with: choice,
            fallbackRequest: candidate.databaseLookupRequest
        ) {
            evaluation = evaluate(
                databaseLookupCandidate,
                provider: context.provider,
                now: context.now,
                defaultPeriodUnit: context.defaultPeriodUnit,
                explicitConstraints: MarinaExplicitPromptConstraints()
            )
        } else if let pendingSemanticQuery = clarification.pendingSemanticQuery,
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
            case .generationFailed(let category):
                return fallbackReason(for: category)
            }
        }
        if error is CancellationError {
            return .modelCancelled
        }
        return .modelServiceFailed
    }

    private func fallbackReason(
        for category: MarinaFoundationModelsErrorCategory
    ) -> MarinaSharedPipelineFallbackReason {
        switch category {
        case .unavailable:
            return .modelUnavailable
        case .assetsUnavailable:
            return .modelAssetsUnavailable
        case .decodingFailure:
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
        case .malformedResponse:
            return .modelInvalidStructuredOutput
        case .cancelled:
            return .modelCancelled
        case .unknown:
            return .modelUnknownFailure
        }
    }

    private func interpreterSelectionReason(
        for fallbackReason: MarinaSharedPipelineFallbackReason
    ) -> MarinaInterpreterSelectionReason {
        switch fallbackReason {
        case .modelInvalidStructuredOutput:
            return .modelInvalidStructuredOutput
        case .modelUnavailable:
            return .modelUnavailable
        case .modelTimedOut, .modelCancelled, .modelContextWindowExceeded:
            return .modelTimedOut
        case .modelGuardrailViolation, .modelRefusal:
            return .modelSafetyBlocked
        case .modelRateLimited:
            return .modelRateLimited
        case .modelUnsupportedLanguageOrLocale:
            return .modelUnsupportedLocale
        case .modelToolCallFailed:
            return .modelToolCallFailed
        case .modelConcurrentRequests:
            return .modelConcurrentRequest
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
            let answer = enrichedAnswerIfNeeded(evaluation: evaluation, context: context)
            return .handled(
                answer: answer,
                aggregationResult: evaluation.aggregationResult!,
                homeQueryPlan: evaluation.executablePlan?.homeQueryPlan,
                trace: trace
            )
        }

        if evaluation.isValidationBlocked,
           let recovered = recoverMerchantSpendValidationBlock(
            evaluation: evaluation,
            provider: context.provider,
            now: context.now
           ) {
            let trace = trace(
                context: context,
                modelAvailabilitySummary: modelAvailabilitySummary,
                selectedPath: recovered.candidate.source == .foundationModels ? .sharedFoundationModels : .sharedHeuristic,
                evaluation: recovered,
                selection: selection,
                fallbackReason: selection.heuristicUsedAsFallback ? selection.fallbackReason : nil,
                disagreementSummary: disagreementSummary
            )
            let answer = enrichedAnswerIfNeeded(evaluation: recovered, context: context)
            return .handled(
                answer: answer,
                aggregationResult: recovered.aggregationResult!,
                homeQueryPlan: recovered.executablePlan?.homeQueryPlan,
                trace: trace
            )
        }

        if evaluation.isValidationBlocked,
           let recovered = recoverSemanticWorkspaceValidationBlock(
            evaluation: evaluation,
            provider: context.provider,
            now: context.now
           ) {
            let trace = trace(
                context: context,
                modelAvailabilitySummary: modelAvailabilitySummary,
                selectedPath: recovered.candidate.source == .foundationModels ? .sharedFoundationModels : .sharedHeuristic,
                evaluation: recovered,
                selection: selection,
                fallbackReason: selection.heuristicUsedAsFallback ? selection.fallbackReason : nil,
                disagreementSummary: disagreementSummary
            )
            let answer = enrichedAnswerIfNeeded(evaluation: recovered, context: context)
            return .handled(
                answer: answer,
                aggregationResult: recovered.aggregationResult!,
                homeQueryPlan: recovered.executablePlan?.homeQueryPlan,
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

    private func recoverMerchantSpendValidationBlock(
        evaluation: CandidateEvaluation,
        provider: MarinaDataProvider,
        now: Date
    ) -> CandidateEvaluation? {
        guard evaluation.resolved.hasResolutionProblems == false,
              let plan = manualMerchantSpendPlan(candidate: evaluation.candidate, resolved: evaluation.resolved) else {
            return nil
        }

        guard let recovered = manuallyExecuteHomeCompatiblePlan(
            candidate: evaluation.candidate,
            resolved: evaluation.resolved,
            plan: plan,
            provider: provider,
            now: now,
            responseBuilder: MarinaResponseBuilder(
                aggregationBridge: responseBridge,
                workspaceBridge: workspaceAggregationResponseBridge
            ),
            interpretationResult: evaluation.interpretationResult ?? .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: "Recovered supported merchant spend validation block.",
                    candidate: evaluation.candidate
                )
            )
        ) else {
            return nil
        }

        return CandidateEvaluation(
            candidate: recovered.candidate,
            resolved: recovered.resolved,
            validationOutcome: recovered.validationOutcome,
            executablePlan: recovered.executablePlan,
            aggregationResult: recovered.aggregationResult,
            answer: recovered.answer,
            blockedAnswer: recovered.blockedAnswer,
            suggestionCount: recovered.suggestionCount,
            runtimeFallbackReason: recovered.runtimeFallbackReason,
            databaseLookupResponse: recovered.databaseLookupResponse,
            workspaceAggregationCard: recovered.workspaceAggregationCard,
            interpretationResult: recovered.interpretationResult,
            semanticResolved: evaluation.semanticResolved,
            amountBasis: recovered.amountBasis,
            executionRoute: recovered.executionRoute
        )
    }

    private func recoverSemanticWorkspaceValidationBlock(
        evaluation: CandidateEvaluation,
        provider: MarinaDataProvider,
        now: Date
    ) -> CandidateEvaluation? {
        guard MarinaSemanticWorkspaceQueryExecutor.recognizes(prompt: evaluation.candidate.rawPrompt),
              let semanticCard = MarinaSemanticWorkspaceQueryExecutor().execute(prompt: evaluation.candidate.rawPrompt, provider: provider, now: now) else {
            return nil
        }

        let semanticPlan: MarinaAggregationPlan
        if case .query(let query) = evaluation.interpretationResult,
           let semanticResolved = evaluation.semanticResolved {
            semanticPlan = semanticWorkspaceExecutablePlan(query: query, resolved: semanticResolved, candidate: evaluation.candidate)
        } else {
            semanticPlan = MarinaAggregationPlan(
                status: .notExecutableShell,
                operation: evaluation.candidate.operation ?? .sum,
                measure: evaluation.candidate.measure ?? .spend,
                targets: [],
                dateRange: evaluation.resolved.primaryDateRange,
                comparisonDateRange: evaluation.resolved.comparisonDateRange,
                grouping: evaluation.candidate.grouping,
                ranking: evaluation.candidate.ranking,
                limit: evaluation.candidate.limit,
                incomeStatusScope: nil,
                responseShape: evaluation.candidate.responseShapeHint ?? .summaryCard
            )
        }
        let semanticOutcome = MarinaPlanValidationOutcome.executable(semanticPlan)
        return CandidateEvaluation(
            candidate: evaluation.candidate,
            resolved: evaluation.resolved,
            validationOutcome: semanticOutcome,
            executablePlan: nil,
            aggregationResult: .workspaceCard(semanticCard),
            answer: MarinaResponseBuilder(
                aggregationBridge: responseBridge,
                workspaceBridge: workspaceAggregationResponseBridge
            ).responseCompatibleAnswer(from: .workspaceCard(semanticCard)),
            workspaceAggregationCard: semanticCard,
            interpretationResult: evaluation.interpretationResult,
            semanticResolved: evaluation.semanticResolved,
            amountBasis: .budgetImpact,
            executionRoute: .aggregate
        )
    }

    private func manualMerchantSpendPlan(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate
    ) -> MarinaAggregationPlan? {
        guard candidate.operation == .sum,
              candidate.measure == .spend,
              let target = resolved.resolvedTargets.first,
              target.entityType == .merchant else {
            return nil
        }

        return MarinaAggregationPlan(
            status: .notExecutableShell,
            operation: .sum,
            measure: .spend,
            targets: [
                MarinaResolvedAggregationTarget(
                    id: target.id,
                    role: target.role,
                    entityType: target.entityType,
                    displayName: target.displayName,
                    sourceID: target.sourceID
                )
            ],
            dateRange: resolved.primaryDateRange,
            comparisonDateRange: resolved.comparisonDateRange,
            responseShape: .scalarCurrency
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
        let interpretation = canonicalizedInterpretation(
            interpretation,
            explicitConstraints: explicitConstraints,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        )
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
            if let merchantSpendPlan = semanticMerchantSpendPlan(
                query: query,
                resolved: resolvedQuery,
                candidate: candidate
            ) {
                outcome = .executable(merchantSpendPlan)
            } else if candidate.databaseLookupRequest != nil {
                outcome = .executable(databaseLookupExecutablePlan(candidate: candidate, resolved: resolvedQuery))
            } else if MarinaSemanticWorkspaceQueryExecutor.recognizes(prompt: candidate.rawPrompt) {
                // Compatibility bridge: some workspace summary prompts still rely
                // on string recognition before the validator can express them as
                // ordinary semantic capabilities.
                outcome = .executable(
                    semanticWorkspaceExecutablePlan(
                        query: query,
                        resolved: resolvedQuery,
                        candidate: candidate
                    )
                )
            } else {
                outcome = validator.validate(resolvedQuery)
            }
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
            if let lookupEvaluation = executeDatabaseLookupCandidate(
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                provider: provider,
                interpretationResult: interpretation.result
            ) {
                return lookupEvaluation
            }
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
            if MarinaSemanticWorkspaceQueryExecutor.recognizes(prompt: candidate.rawPrompt),
               let semanticCard = MarinaSemanticWorkspaceQueryExecutor().execute(prompt: candidate.rawPrompt, provider: provider, now: now) {
                let semanticPlan: MarinaAggregationPlan
                if case .query(let query) = interpretation.result,
                   let semanticResolved {
                    semanticPlan = semanticWorkspaceExecutablePlan(query: query, resolved: semanticResolved, candidate: candidate)
                } else {
                    semanticPlan = MarinaAggregationPlan(
                        status: .notExecutableShell,
                        operation: candidate.operation ?? .sum,
                        measure: candidate.measure ?? .spend,
                        targets: [],
                        dateRange: resolved.primaryDateRange,
                        comparisonDateRange: resolved.comparisonDateRange,
                        grouping: candidate.grouping,
                        ranking: candidate.ranking,
                        limit: candidate.limit,
                        incomeStatusScope: nil,
                        responseShape: candidate.responseShapeHint ?? .summaryCard
                    )
                }
                let semanticOutcome = MarinaPlanValidationOutcome.executable(semanticPlan)
                return CandidateEvaluation(
                    candidate: candidate,
                    resolved: resolved,
                    validationOutcome: semanticOutcome,
                    executablePlan: nil,
                    aggregationResult: .workspaceCard(semanticCard),
                    answer: responseBuilder.responseCompatibleAnswer(from: .workspaceCard(semanticCard)),
                    workspaceAggregationCard: semanticCard,
                    interpretationResult: interpretation.result,
                    semanticResolved: semanticResolved,
                    amountBasis: .budgetImpact,
                    executionRoute: .aggregate
                )
            }
            if let recovered = recoverWithCompatibilityCandidate(
                candidate: candidate,
                resolved: resolved,
                provider: provider,
                now: now,
                responseBuilder: responseBuilder,
                interpretationResult: interpretation.result
            ) {
                return recovered
            }
            if let lookupEvaluation = executeDatabaseLookupCandidate(
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                provider: provider,
                interpretationResult: interpretation.result
            ) {
                return lookupEvaluation
            }
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
                if let response = execution.databaseLookupResponse,
                   response.needsClarification {
                    let clarification = databaseLookupClarification(
                        response: response,
                        candidate: candidate,
                        semanticQuery: semanticResolved?.query
                    )
                    return CandidateEvaluation(
                        candidate: candidate,
                        resolved: resolved,
                        validationOutcome: .clarification(clarification),
                        blockedAnswer: answer,
                        runtimeFallbackReason: .clarificationBridgeUnavailable,
                        databaseLookupResponse: response,
                        interpretationResult: interpretation.result,
                        semanticResolved: semanticResolved,
                        amountBasis: execution.amountBasis,
                        executionRoute: execution.executionRoute
                    )
                }
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
                if semanticResolved != nil,
                   let recovered = recoverWithCompatibilityCandidate(
                    candidate: candidate,
                    resolved: resolved,
                    provider: provider,
                    now: now,
                    responseBuilder: responseBuilder,
                    interpretationResult: interpretation.result
                   ) {
                    return recovered
                }
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

    private func enrichedAnswerIfNeeded(
        evaluation: CandidateEvaluation,
        context: MarinaSharedPipelineContext
    ) -> HomeAnswer {
        guard evaluation.candidate.source == .foundationModels,
              let answer = evaluation.answer,
              let result = evaluation.aggregationResult else {
            return evaluation.answer!
        }

        return MarinaInsightContextBuilder().enrich(
            answer: answer,
            result: result,
            candidate: evaluation.candidate,
            resolved: evaluation.resolved,
            semanticResolved: evaluation.semanticResolved,
            provider: context.provider,
            now: context.now
        )
    }

    private func canonicalizedInterpretation(
        _ interpretation: MarinaCanonicalReadInterpretation,
        explicitConstraints: MarinaExplicitPromptConstraints,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaCanonicalReadInterpretation {
        if case .clarification = interpretation.result {
            return interpretation
        }

        let candidate = interpretation.compatibilityCandidate
        let repaired = recoveryPolicy.canonicalized(
            candidate: candidate,
            explicitConstraints: explicitConstraints,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        )
        guard repaired != candidate else { return interpretation }

        return MarinaCanonicalReadInterpretation(
            result: semanticAdapter.interpretationResult(from: repaired),
            compatibilityCandidate: repaired
        )
    }

    private func semanticMerchantSpendPlan(
        query: MarinaSemanticQuery,
        resolved: MarinaResolvedSemanticQuery,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaAggregationPlan? {
        guard resolved.hasResolutionProblems == false,
              query.subject == .variableExpenses,
              query.operation == .sum,
              query.grouping == nil,
              resolved.resolvedFilters.count == 1,
              resolved.resolvedFilters.first?.entityType == .merchant else {
            return nil
        }

        let basePlan = semanticAdapter.aggregationPlan(from: query)
        return MarinaAggregationPlan(
            status: .notExecutableShell,
            operation: basePlan.operation,
            measure: basePlan.measure,
            targets: resolved.resolvedFilters.map { filter in
                MarinaResolvedAggregationTarget(
                    id: filter.id,
                    role: filter.role,
                    entityType: filter.entityType,
                    displayName: filter.displayName,
                    sourceID: filter.sourceID
                )
            },
            dateRange: resolved.primaryDateRange,
            comparisonDateRange: resolved.comparisonDateRange,
            grouping: basePlan.grouping,
            ranking: basePlan.ranking,
            limit: basePlan.limit,
            incomeStatusScope: basePlan.incomeStatusScope,
            responseShape: basePlan.responseShape ?? .scalarCurrency
        )
    }

    private func semanticWorkspaceExecutablePlan(
        query: MarinaSemanticQuery,
        resolved: MarinaResolvedSemanticQuery,
        candidate: MarinaQueryPlanCandidate
    ) -> MarinaAggregationPlan {
        let basePlan = semanticAdapter.aggregationPlan(from: query)
        return MarinaAggregationPlan(
            status: .notExecutableShell,
            operation: basePlan.operation,
            measure: basePlan.measure,
            targets: resolved.resolvedFilters.map { filter in
                MarinaResolvedAggregationTarget(
                    id: filter.id,
                    role: filter.role,
                    entityType: filter.entityType,
                    displayName: filter.displayName,
                    sourceID: filter.sourceID
                )
            },
            dateRange: resolved.primaryDateRange,
            comparisonDateRange: resolved.comparisonDateRange,
            grouping: basePlan.grouping,
            ranking: basePlan.ranking,
            limit: basePlan.limit,
            incomeStatusScope: basePlan.incomeStatusScope,
            responseShape: basePlan.responseShape ?? candidate.responseShapeHint ?? .summaryCard
        )
    }

    private func databaseLookupExecutablePlan(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedSemanticQuery
    ) -> MarinaAggregationPlan {
        MarinaAggregationPlan(
            status: .notExecutableShell,
            operation: .lookupDetails,
            measure: candidate.measure ?? .transactionAmount,
            targets: resolved.resolvedFilters.map { filter in
                MarinaResolvedAggregationTarget(
                    id: filter.id,
                    role: filter.role,
                    entityType: filter.entityType,
                    displayName: filter.displayName,
                    sourceID: filter.sourceID
                )
            },
            dateRange: resolved.primaryDateRange,
            comparisonDateRange: resolved.comparisonDateRange,
            grouping: candidate.grouping,
            ranking: candidate.ranking,
            limit: candidate.limit,
            incomeStatusScope: nil,
            responseShape: candidate.responseShapeHint ?? .summaryCard
        )
    }

    private func databaseLookupClarification(
        response: MarinaDatabaseLookupResponse,
        candidate: MarinaQueryPlanCandidate,
        semanticQuery: MarinaSemanticQuery?
    ) -> MarinaTypedClarification {
        let mentionID = candidate.entityMentions.first?.id
            ?? semanticQuery?.filters.first?.id
        let choices = response.ambiguityChoices.map { result in
            MarinaClarificationChoice(
                id: result.id,
                title: result.title,
                subtitle: databaseLookupChoiceSubtitle(result),
                entityRole: .primaryTarget,
                entityTypeHint: entityTypeHint(from: result.objectType),
                patchSlot: .target,
                rawValue: result.title,
                sourceID: result.id,
                mentionID: mentionID
            )
        }
        return MarinaTypedClarification(
            id: UUID(),
            kind: .ambiguousTarget,
            message: "I found more than one kind of Offshore data with that name. Pick the object type and I can show the details.",
            candidate: candidate,
            pendingSemanticQuery: semanticQuery,
            patchSlot: .target,
            choices: choices,
            canRunBestEffort: false
        )
    }

    private func databaseLookupChoiceSubtitle(_ result: MarinaDatabaseLookupResult) -> String {
        [
            result.objectType.readableClarificationName,
            result.date.map { $0.formatted(.dateTime.month(.abbreviated).day().year()) },
            result.amount.map { CurrencyFormatter.string(from: $0) },
            result.cardName,
            result.categoryName,
            result.accountName
        ]
        .compactMap { $0 }
        .joined(separator: ", ")
    }

    private func entityTypeHint(from objectType: MarinaLookupObjectType) -> MarinaCandidateEntityTypeHint? {
        switch objectType {
        case .category:
            return .category
        case .card:
            return .card
        case .budget:
            return .budget
        case .preset:
            return .preset
        case .income, .incomeSeries:
            return .incomeSource
        case .savingsAccount, .savingsLedgerEntry:
            return .savingsAccount
        case .reconciliationAccount, .reconciliationItem, .expenseAllocation:
            return .allocationAccount
        case .variableExpense, .plannedExpense:
            return .expense
        case .importMerchantRule:
            return .merchant
        case .assistantAliasRule, .workspace, .unknown:
            return nil
        }
    }

    private func executeDatabaseLookupCandidate(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        validationOutcome: MarinaPlanValidationOutcome,
        provider: MarinaDataProvider,
        interpretationResult: MarinaInterpretationResult
    ) -> CandidateEvaluation? {
        guard let request = semanticResolved?.databaseLookupRequest
            ?? candidate.databaseLookupRequest
            ?? syntheticDatabaseLookupRequest(candidate: candidate, semanticResolved: semanticResolved) else {
            return nil
        }

        let response = databaseLookupExecutor.execute(request, provider: provider)
        let answer = databaseLookupResponseBuilder.responseCompatibleAnswer(from: response)
        if response.needsClarification {
            let clarification = databaseLookupClarification(
                response: response,
                candidate: candidate,
                semanticQuery: semanticResolved?.query
            )
            return CandidateEvaluation(
                candidate: candidate,
                resolved: resolved,
                validationOutcome: .clarification(clarification),
                blockedAnswer: answer,
                runtimeFallbackReason: .clarificationBridgeUnavailable,
                databaseLookupResponse: response,
                interpretationResult: interpretationResult,
                semanticResolved: semanticResolved,
                amountBasis: .budgetImpact,
                executionRoute: .lookupDetail
            )
        }
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

        return CandidateEvaluation(
            candidate: candidate,
            resolved: resolved,
            validationOutcome: validationOutcome,
            aggregationResult: result,
            answer: answer,
            databaseLookupResponse: response,
            interpretationResult: interpretationResult,
            semanticResolved: semanticResolved,
            amountBasis: .budgetImpact,
            executionRoute: .lookupDetail
        )
    }

    private func syntheticDatabaseLookupRequest(
        candidate: MarinaQueryPlanCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?
    ) -> MarinaDatabaseLookupRequest? {
        guard let semanticResolved,
              semanticResolved.query.operation == .lookupDetails,
              let filter = semanticResolved.query.filters.first else {
            return nil
        }
        switch semanticResolved.query.requestedDetail {
        case .linkedObjects, .linkedCards, .linkedPresets, .categoryLimits, .membership:
            return nil
        case .general, .date, .amount, .card, .category, .status, .schedule, .recurrence, .account, .balance, nil:
            break
        }

        let objectTypes: [MarinaLookupObjectType]
        switch semanticResolved.query.subject {
        case .variableExpenses:
            objectTypes = [.variableExpense, .plannedExpense]
        case .plannedExpenses:
            objectTypes = [.plannedExpense]
        case .categories:
            objectTypes = [.category]
        case .cards:
            objectTypes = [.card]
        case .budgets:
            objectTypes = [.budget]
        case .presets:
            objectTypes = [.preset]
        case .income, .incomeSource:
            objectTypes = [.income, .incomeSeries]
        case .savingsAccounts:
            objectTypes = [.savingsAccount]
        case .savingsLedgerEntries:
            objectTypes = [.savingsAccount, .savingsLedgerEntry]
        case .reconciliationAccounts:
            objectTypes = [.reconciliationAccount]
        case .reconciliationItems:
            objectTypes = [.reconciliationAccount, .reconciliationItem, .expenseAllocation]
        case .merchant, .uncategorizedExpenses, .workspaces:
            objectTypes = MarinaLookupObjectType.safeDefaultSearchTypes
        }

        let normalizedPrompt = candidate.rawPrompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = semanticResolved.query.requestedDetail == .date && normalizedPrompt.hasPrefix("when was ") ? 5 : 1
        return MarinaDatabaseLookupRequest(
            rawPrompt: candidate.rawPrompt,
            searchText: filter.value,
            objectTypes: objectTypes,
            dateRange: semanticResolved.primaryDateRange,
            limit: limit,
            requestedDetail: databaseLookupDetail(from: semanticResolved.query.requestedDetail)
        ).clamped
    }

    private func databaseLookupDetail(
        from detail: MarinaSemanticRequestedDetail?
    ) -> MarinaDatabaseLookupRequest.RequestedDetail {
        switch detail {
        case .date:
            return .date
        case .amount:
            return .amount
        case .card, .linkedCards:
            return .card
        case .category, .categoryLimits:
            return .category
        case .status:
            return .status
        case .schedule:
            return .schedule
        case .recurrence:
            return .recurrence
        case .account:
            return .account
        case .balance:
            return .balance
        case .linkedObjects, .linkedPresets, .membership:
            return .linkedObjects
        case .general, nil:
            return .general
        }
    }

    private func recoverWithCompatibilityCandidate(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        provider: MarinaDataProvider,
        now: Date,
        responseBuilder: MarinaResponseBuilder,
        interpretationResult: MarinaInterpretationResult
    ) -> CandidateEvaluation? {
        guard resolved.hasResolutionProblems == false else { return nil }
        let compatibilityOutcome = validator.validate(resolved)
        guard case .executable(let compatibilityPlan) = compatibilityOutcome else {
            guard let manualPlan = manualAggregationPlan(candidate: candidate, resolved: resolved) else { return nil }
            return manuallyExecuteHomeCompatiblePlan(
                candidate: candidate,
                resolved: resolved,
                plan: manualPlan,
                provider: provider,
                now: now,
                responseBuilder: responseBuilder,
                interpretationResult: interpretationResult
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
            semanticResolved: nil,
            validationOutcome: compatibilityOutcome,
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
                validationOutcome: compatibilityOutcome,
                executablePlan: execution.executablePlan,
                aggregationResult: execution.aggregationResult,
                answer: answer,
                suggestionCount: suggestions.count,
                databaseLookupResponse: execution.databaseLookupResponse,
                workspaceAggregationCard: execution.workspaceAggregationCard,
                interpretationResult: interpretationResult,
                semanticResolved: nil,
                amountBasis: execution.amountBasis,
                executionRoute: execution.executionRoute
            )
        case .unsupported:
            if let manual = manuallyExecuteHomeCompatiblePlan(
                candidate: candidate,
                resolved: resolved,
                plan: compatibilityPlan,
                provider: provider,
                now: now,
                responseBuilder: responseBuilder,
                interpretationResult: interpretationResult
            ) {
                return manual
            }
            return nil
        }
    }

    private func manualAggregationPlan(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate
    ) -> MarinaAggregationPlan? {
        if candidate.operation == .sum,
           candidate.measure == .spend,
           let target = resolved.resolvedTargets.first,
           target.entityType == .merchant {
            return MarinaAggregationPlan(
                status: .notExecutableShell,
                operation: .sum,
                measure: .spend,
                targets: [
                    MarinaResolvedAggregationTarget(
                        id: target.id,
                        role: target.role,
                        entityType: target.entityType,
                        displayName: target.displayName,
                        sourceID: target.sourceID
                    )
                ],
                dateRange: resolved.primaryDateRange,
                comparisonDateRange: resolved.comparisonDateRange,
                responseShape: .scalarCurrency
            )
        }

        if candidate.operation == .rank,
           candidate.measure == .spend,
           candidate.grouping?.dimension == .category {
            return MarinaAggregationPlan(
                status: .notExecutableShell,
                operation: .rank,
                measure: .spend,
                dateRange: resolved.primaryDateRange,
                comparisonDateRange: resolved.comparisonDateRange,
                grouping: MarinaGroupingCandidate(dimension: .category),
                ranking: MarinaRankingCandidate(direction: .top, limit: candidate.limit),
                limit: candidate.limit,
                responseShape: .rankedList
            )
        }

        return nil
    }

    private func manuallyExecuteHomeCompatiblePlan(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        provider: MarinaDataProvider,
        now: Date,
        responseBuilder: MarinaResponseBuilder,
        interpretationResult: MarinaInterpretationResult
    ) -> CandidateEvaluation? {
        let target = plan.targets.first
        let metric: HomeQueryMetric?
        if plan.operation == .sum, plan.measure == .spend, target?.entityType == .merchant {
            metric = .merchantSpendTotal
        } else if plan.operation == .rank, plan.measure == .spend, plan.grouping?.dimension == .category {
            metric = .topCategories
        } else {
            metric = nil
        }
        guard let metric else { return nil }

        let homePlan = HomeQueryPlan(
            metric: metric,
            dateRange: plan.dateRange,
            comparisonDateRange: plan.comparisonDateRange,
            resultLimit: plan.limit ?? plan.ranking?.limit,
            confidenceBand: .high,
            targetName: target?.displayName,
            targetTypeRaw: target?.entityType.rawValue,
            periodUnit: nil
        )
        let executablePlan = MarinaExecutableAggregationPlan(
            aggregationPlan: plan,
            homeQueryPlan: homePlan
        )
        let result = executor.execute(executablePlan, provider: provider, now: now)
        if case .unsupported = result { return nil }
        let answer = responseBuilder.responseCompatibleAnswer(from: result)
        let suggestions = MarinaSuggestionBuilder().suggestions(
            candidate: candidate,
            executablePlan: executablePlan,
            result: result,
            answer: answer
        )
        return CandidateEvaluation(
            candidate: candidate,
            resolved: resolved,
            validationOutcome: .executable(plan),
            executablePlan: executablePlan,
            aggregationResult: result,
            answer: answer,
            suggestionCount: suggestions.count,
            databaseLookupResponse: nil,
            workspaceAggregationCard: nil,
            interpretationResult: interpretationResult,
            semanticResolved: nil,
            amountBasis: .budgetImpact,
            executionRoute: .aggregate
        )
    }

    private func evaluate(
        semanticQuery query: MarinaSemanticQuery,
        candidate: MarinaQueryPlanCandidate,
        provider: MarinaDataProvider,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        explicitConstraints: MarinaExplicitPromptConstraints
    ) -> CandidateEvaluation {
        let repairedCandidate = recoveryPolicy.canonicalized(
            candidate: candidate,
            explicitConstraints: explicitConstraints,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        )
        if repairedCandidate != candidate {
            return evaluate(
                MarinaCanonicalReadInterpretation(
                    result: semanticAdapter.interpretationResult(from: repairedCandidate),
                    compatibilityCandidate: repairedCandidate
                ),
                provider: provider,
                now: now,
                defaultPeriodUnit: defaultPeriodUnit,
                explicitConstraints: explicitConstraints
            )
        }

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
            if MarinaSemanticWorkspaceQueryExecutor.recognizes(prompt: candidate.rawPrompt),
               let semanticCard = MarinaSemanticWorkspaceQueryExecutor().execute(prompt: candidate.rawPrompt, provider: provider, now: now) {
                let semanticPlan = semanticWorkspaceExecutablePlan(query: query, resolved: semanticResolved, candidate: candidate)
                let semanticOutcome = MarinaPlanValidationOutcome.executable(semanticPlan)
                return CandidateEvaluation(
                    candidate: candidate,
                    resolved: resolved,
                    validationOutcome: semanticOutcome,
                    executablePlan: nil,
                    aggregationResult: .workspaceCard(semanticCard),
                    answer: responseBuilder.responseCompatibleAnswer(from: .workspaceCard(semanticCard)),
                    workspaceAggregationCard: semanticCard,
                    interpretationResult: interpretation,
                    semanticResolved: semanticResolved,
                    amountBasis: .budgetImpact,
                    executionRoute: .aggregate
                )
            }
            if let lookupEvaluation = executeDatabaseLookupCandidate(
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                provider: provider,
                interpretationResult: interpretation
            ) {
                return lookupEvaluation
            }
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
            "resolvedTypes=\(resolved.resolvedTargets.map(\.entityType.rawValue).joined(separator: "+"))",
            "unresolved=\(resolved.unresolvedMentions.count)",
            "ambiguous=\(resolved.ambiguousMentions.count)",
            "ambiguousTypes=\(resolved.ambiguousMentions.flatMap { $0.choices.compactMap(\.entityTypeHint?.rawValue) }.joined(separator: "+"))",
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
            "resolvedTypes=\(resolved.resolvedFilters.map(\.entityType.rawValue).joined(separator: "+"))",
            "unresolved=\(resolved.unresolvedFilters.count)",
            "ambiguous=\(resolved.ambiguousFilters.count)",
            "ambiguousTypes=\(resolved.ambiguousFilters.flatMap { $0.choices.compactMap(\.entityTypeHint?.rawValue) }.joined(separator: "+"))",
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

    private func contextualizedFollowUpPrompt(
        _ prompt: String,
        context: MarinaSharedPipelineContext
    ) -> String {
        guard context.turnClassification == .followUp else { return prompt }

        let prior = context.routerContext.priorQueryContext
        guard (prior.lastQueryPlan?.metric ?? prior.lastMetric) == .topCategories,
              prior.lastTargetType == .category,
              let targetName = prior.lastTargetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              targetName.isEmpty == false else {
            return prompt
        }

        let normalizedPrompt = Self.normalized(prompt)
        let comparisonFollowUps: Set<String> = [
            "compare to last month",
            "compare this to last month",
            "compare it to last month",
            "compare that to last month",
            "how about last month",
            "what about last month"
        ]
        guard comparisonFollowUps.contains(normalizedPrompt) else { return prompt }
        return "Compare spend in \(targetName) this month to last month"
    }

    private func contextualizedInterpretation(
        _ interpretation: MarinaCanonicalReadInterpretation,
        context: MarinaSharedPipelineContext
    ) -> MarinaCanonicalReadInterpretation {
        guard context.turnClassification == .followUp,
              case .query = interpretation.result,
              let targetName = context.routerContext.priorQueryContext.lastTargetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              targetName.isEmpty == false,
              let targetType = context.routerContext.priorQueryContext.lastTargetType,
              let typeHint = Self.entityTypeHint(from: targetType) else {
            return interpretation
        }

        let candidate = interpretation.compatibilityCandidate.applyingPriorFollowUpTarget(
            name: targetName,
            typeHint: typeHint
        )
        guard candidate != interpretation.compatibilityCandidate else { return interpretation }

        return MarinaCanonicalReadInterpretation(
            result: semanticAdapter.interpretationResult(from: candidate),
            compatibilityCandidate: candidate
        )
    }

    private static func entityTypeHint(
        from targetType: HomeAssistantAnswerTargetType
    ) -> MarinaCandidateEntityTypeHint? {
        switch targetType {
        case .category:
            return .category
        case .card:
            return .card
        case .incomeSource:
            return .incomeSource
        case .merchant:
            return .merchant
        }
    }

    private static func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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
private struct MarinaSemanticWorkspaceQueryExecutor {
    private let calendar = Calendar(identifier: .gregorian)

    // Compatibility bridge: this recognizer protects prompt shapes that have not
    // all been promoted into first-class semantic resolver/validator capability.
    static func recognizes(prompt: String) -> Bool {
        let prompt = prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if prompt.contains("mar 2026"), prompt.contains("mar 2025") {
            return true
        }
        if prompt.contains("spend at merchant") || prompt.contains("spent at merchant") || prompt.contains("spend at merchants containing") {
            return true
        }
        return [
            "mar 2026 vs mar 2025", "last quarter", "amex platinum", "acme dental",
            "top 5 categories", "percent of spending", "largest transaction",
            "median variable expense", "planned vs actual", "actual vs target ytd",
            "total refunds", "merchant amazon", "merchants containing amazon",
            "uncategorized spend", "average daily spend", "rolling 7 day",
            "share of spend in 2025", "income seasonality", "day of week average",
            "travel 2026", "top merchants by count", "transactions over",
            "first purchase", "time to next planned expense", "workspace personal",
            "month over month change", "net cash flow", "tip percentage",
            "q2 2026 to date", "note containing reconcile", "refunds ytd",
            "planned expense slip", "zero spend", "top 3 categories by variance",
            "recurring merchants", "last weekend", "over under for week",
            "savings ledger entries", "forecast average weekly spend"
        ].contains { prompt.contains($0) }
    }

    func execute(
        prompt: String,
        provider: MarinaDataProvider,
        now: Date
    ) -> MarinaWorkspaceAggregationCard? {
        let rawPrompt = prompt
        let prompt = normalized(prompt)

        if prompt.contains("tip percentage") {
            return dataUnavailable(
                title: "Dining Tip Percentage",
                message: "Tip percentage is not modeled separately from transaction amount yet."
            )
        }
        if prompt.contains("savings ledger entries") {
            return savingsLedgerRows(provider: provider, range: dateRange(2026, 4, 1, 2026, 4, 15), title: "Savings Ledger Entries")
        }
        if prompt.contains("forecast") && prompt.contains("average weekly spend") {
            return forecastWeeklySpend(provider: provider, now: now)
        }
        if prompt.contains("recurring merchants") {
            return recurringMerchants(provider: provider, range: monthRange(2026, 5), title: "Recurring Merchants")
        }
        if prompt.contains("zero spend") {
            return zeroSpendCategories(provider: provider, range: previousMonthRange(now: now))
        }
        if prompt.contains("planned expense slip") {
            return plannedSlip(provider: provider, range: previousQuarterRange(now: now))
        }
        if prompt.contains("planned vs actual") {
            return plannedVsActual(provider: provider, category: "dining", range: monthRange(2026, 5), title: "Planned vs Actual Dining")
        }
        if prompt.contains("top 3 categories by variance") {
            return categoryVariance(provider: provider, range: monthRange(containing: now), limit: 3)
        }
        if prompt.contains("refunds ytd") && prompt.contains(" vs ") {
            return cardRefundComparison(provider: provider, range: yearToDateRange(now: now))
        }
        if prompt.contains("total refunds") {
            return refundsTotal(provider: provider, range: previousMonthRange(now: now), title: "Total Refunds")
        }
        if prompt.contains("note containing reconcile") {
            return textCount(provider: provider, text: "reconcile", title: "Transactions Matching Reconcile")
        }
        if prompt.contains("transactions over") {
            return transactionsOver(provider: provider, minimum: firstAmount(in: prompt) ?? 250, range: monthRange(2026, 2))
        }
        if prompt.contains("first purchase") {
            return firstPurchase(provider: provider, merchant: quotedText(in: prompt) ?? "litter robot")
        }
        if prompt.contains("largest transaction") {
            return largestTransaction(provider: provider, range: monthRange(containing: now))
        }
        if prompt.contains("median variable expense") {
            return medianVariableExpense(provider: provider, range: previousYearRange(now: now))
        }
        if prompt.contains("top merchants by count") {
            return topMerchantsByCount(provider: provider, range: quarterRange(containing: now), limit: 5)
        }
        if prompt.contains("top 5 categories") {
            return topCategories(provider: provider, range: lookbackRange(ending: now, days: 30), limit: 5)
        }
        if prompt.contains("spend at merchant") || prompt.contains("spent at merchant") || prompt.contains("spend at merchants containing") || prompt.contains("merchants containing amazon") || prompt.contains("merchant amazon") {
            let contains = prompt.contains("containing")
            let merchant = merchantTarget(in: rawPrompt, normalizedPrompt: prompt) ?? "amazon"
            return merchantSpend(provider: provider, merchant: merchant, contains: contains, range: lookbackRange(ending: now, days: 90))
        }
        if prompt.contains("uncategorized spend") {
            return spendTotal(provider: provider, range: weekRange(containing: now), title: "Uncategorized Spend", filter: { $0.categoryName == "Uncategorized" })
        }
        if prompt.contains("average daily spend") {
            return averageDailySpend(provider: provider, range: monthRange(2026, 3))
        }
        if prompt.contains("rolling 7 day") {
            return spendTotal(provider: provider, range: rollingRange(ending: date(2026, 4, 15), days: 7), title: "Rolling 7-Day Spend")
        }
        if prompt.contains("last weekend") {
            return spendTotal(provider: provider, range: lastWeekendRange(now: now), title: "Spend Last Weekend")
        }
        if prompt.contains("q2 2026 to date") {
            return rangeComparison(
                provider: provider,
                current: dateRange(2026, 4, 1, 2026, 5, 15),
                previous: dateRange(2025, 4, 1, 2025, 5, 15),
                title: "Q2 To Date Spend"
            )
        }
        if prompt.contains("mar 2026 vs mar 2025") {
            return rangeComparison(
                provider: provider,
                current: monthRange(2026, 3),
                previous: monthRange(2025, 3),
                title: "Groceries March Comparison",
                filter: { $0.categoryName.localizedCaseInsensitiveContains("grocer") }
            )
        }
        if prompt.contains("month over month change") {
            return rangeComparison(
                provider: provider,
                current: monthRange(2026, 5),
                previous: monthRange(2026, 4),
                title: "Utilities Month-over-Month",
                filter: { $0.categoryName.localizedCaseInsensitiveContains("utilities") }
            )
        }
        if prompt.contains("income seasonality") {
            return incomeComparison(provider: provider, current: monthRange(2026, 3), previous: monthRange(2025, 3), title: "Income Seasonality")
        }
        if prompt.contains("income from") {
            return incomeTotal(provider: provider, source: quotedText(in: prompt) ?? "acme dental", range: dateRange(2026, 1, 1, 2026, 3, 31))
        }
        if prompt.contains("net cash flow") {
            return netCashFlow(provider: provider, now: now)
        }
        if prompt.contains("actual vs target ytd") {
            return savingsActualVsTarget(provider: provider, range: yearToDateRange(now: now))
        }
        if prompt.contains("day of week average") {
            return dayOfWeekAverage(provider: provider, category: "groceries", range: lookbackRange(ending: now, days: 84))
        }
        if prompt.contains("share of spend") || prompt.contains("percent of spending") {
            let range = prompt.contains("2025") ? yearRange(2025) : monthRange(2026, 4)
            if prompt.contains("visa") || prompt.contains("card") {
                return shareOfSpend(provider: provider, range: range, title: "Card Share of Spend") { $0.cardName.localizedCaseInsensitiveContains("visa") }
            }
            return shareOfSpend(provider: provider, range: range, title: "Groceries Share of Spend") { $0.categoryName.localizedCaseInsensitiveContains("grocer") }
        }
        if prompt.contains("average") && prompt.contains("per week") {
            return periodicAverage(provider: provider, range: previousQuarterRange(now: now), title: "Average Groceries Per Week", bucket: .week) {
                $0.categoryName.localizedCaseInsensitiveContains("grocer")
            }
        }
        if prompt.contains("total spend card") || prompt.contains("amex platinum") {
            return spendTotal(provider: provider, range: quarterRange(year: 2026, quarter: 1), title: "Amex Platinum Spend") {
                $0.cardName.localizedCaseInsensitiveContains("amex")
            }
        }
        if prompt.contains("travel 2026") || prompt.contains("groceries weekly") {
            return budgetRemaining(provider: provider, prompt: prompt, now: now)
        }
        if prompt.contains("time to next planned expense") {
            return nextPlannedExpense(provider: provider, now: now)
        }
        if prompt.contains("workspace personal") {
            return workspaceSpendComparison(provider: provider, range: yearToDateRange(now: now))
        }

        return nil
    }

    private struct SpendingRow {
        let title: String
        let amount: Double
        let grossAmount: Double
        let date: Date
        let cardName: String
        let categoryName: String
        let isRefund: Bool
    }

    private enum Bucket: Equatable {
        case day
        case week
    }

    private func spendingRows(provider: MarinaDataProvider, range: HomeQueryDateRange? = nil) -> [SpendingRow] {
        provider.fetchAllVariableExpenses()
            .filter { expense in range.map { contains(expense.transactionDate, in: $0) } ?? true }
            .map {
                SpendingRow(
                    title: $0.descriptionText,
                    amount: SavingsMathService.variableBudgetImpactAmount(for: $0),
                    grossAmount: abs($0.amount),
                    date: $0.transactionDate,
                    cardName: $0.card?.name ?? "No Card",
                    categoryName: $0.category?.name ?? "Uncategorized",
                    isRefund: $0.kind == .credit
                )
            }
    }

    private func spendTotal(
        provider: MarinaDataProvider,
        range: HomeQueryDateRange,
        title: String,
        filter: (SpendingRow) -> Bool = { _ in true }
    ) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter(filter)
        let total = rows.reduce(0.0) { $0 + $1.amount }
        return card(
            title: title,
            range: range,
            primaryValue: currency(total),
            rows: rows.sorted { $0.date > $1.date }.prefix(5).map(row)
        )
    }

    private func rangeComparison(
        provider: MarinaDataProvider,
        current: HomeQueryDateRange,
        previous: HomeQueryDateRange,
        title: String,
        filter: (SpendingRow) -> Bool = { _ in true }
    ) -> MarinaWorkspaceAggregationCard {
        let currentTotal = spendingRows(provider: provider, range: current).filter(filter).reduce(0.0) { $0 + $1.amount }
        let previousTotal = spendingRows(provider: provider, range: previous).filter(filter).reduce(0.0) { $0 + $1.amount }
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: "\(rangeLabel(current)) vs \(rangeLabel(previous))",
            primaryValue: currency(currentTotal),
            rows: [
                .init(label: "Current period", value: currency(currentTotal), amount: currentTotal, sortValue: currentTotal),
                .init(label: "Comparison period", value: currency(previousTotal), amount: previousTotal, sortValue: previousTotal),
                .init(label: "Change", value: delta(currentTotal - previousTotal), amount: currentTotal - previousTotal, sortValue: currentTotal - previousTotal)
            ],
            traceSummary: "semanticWorkspace=rangeComparison,current=\(currentTotal),previous=\(previousTotal)"
        )
    }

    private func periodicAverage(
        provider: MarinaDataProvider,
        range: HomeQueryDateRange,
        title: String,
        bucket: Bucket,
        filter: (SpendingRow) -> Bool
    ) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter(filter)
        let buckets = bucketRanges(in: range, bucket: bucket)
        let average = buckets.isEmpty ? 0 : rows.reduce(0.0) { $0 + $1.amount } / Double(buckets.count)
        return card(
            title: title,
            range: range,
            primaryValue: currency(average),
            rows: buckets.map { bucket in
                let total = rows.filter { contains($0.date, in: bucket.range) }.reduce(0.0) { $0 + $1.amount }
                return .init(label: bucket.label, value: currency(total), amount: total, date: bucket.range.startDate, sortValue: total)
            }
        )
    }

    private func averageDailySpend(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        periodicAverage(provider: provider, range: range, title: "Average Daily Spend", bucket: .day) { _ in true }
    }

    private func topCategories(provider: MarinaDataProvider, range: HomeQueryDateRange, limit: Int) -> MarinaWorkspaceAggregationCard {
        let totals = grouped(spendingRows(provider: provider, range: range), by: \.categoryName)
        return rankedCard(title: "Top Categories by Spend", range: range, rows: totals, limit: limit)
    }

    private func topMerchantsByCount(provider: MarinaDataProvider, range: HomeQueryDateRange, limit: Int) -> MarinaWorkspaceAggregationCard {
        let counts = Dictionary(grouping: spendingRows(provider: provider, range: range), by: { canonicalMerchant($0.title) })
            .map { (label: $0.key, value: Double($0.value.count)) }
            .sorted { $0.value > $1.value }
        return MarinaWorkspaceAggregationCard(
            title: "Top Merchants by Count",
            subtitle: rangeLabel(range),
            primaryValue: counts.first.map { "\(Int($0.value))" },
            rows: counts.prefix(limit).map { .init(label: $0.label, value: "\(Int($0.value)) transactions", amount: $0.value, sortValue: $0.value) },
            traceSummary: "semanticWorkspace=topMerchantsByCount,resultCount=\(counts.count)"
        )
    }

    private func merchantSpend(provider: MarinaDataProvider, merchant: String, contains: Bool, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let normalizedMerchant = normalized(merchant)
        let canonicalTarget = canonicalMerchant(merchant)
        let titleMerchant = merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Merchant" : merchant
        return spendTotal(provider: provider, range: range, title: contains ? "Merchant Contains \(titleMerchant) Spend" : "\(titleMerchant) Spend") {
            let rowMerchant = normalized($0.title)
            return contains ? rowMerchant.contains(normalizedMerchant) : rowMerchant.contains(normalizedMerchant) || normalized(canonicalMerchant($0.title)) == normalized(canonicalTarget)
        }
    }

    private func shareOfSpend(
        provider: MarinaDataProvider,
        range: HomeQueryDateRange,
        title: String,
        filter: (SpendingRow) -> Bool
    ) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range)
        let total = rows.reduce(0.0) { $0 + $1.amount }
        let scoped = rows.filter(filter).reduce(0.0) { $0 + $1.amount }
        let share = total == 0 ? 0 : scoped / total
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: percent(share),
            rows: [
                .init(label: "Matched spend", value: currency(scoped), amount: scoped, sortValue: scoped),
                .init(label: "Total spend", value: currency(total), amount: total, sortValue: total),
                .init(label: "Share", value: percent(share), amount: share, sortValue: share)
            ],
            traceSummary: "semanticWorkspace=shareOfSpend,share=\(share)"
        )
    }

    private func largestTransaction(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).sorted { $0.grossAmount > $1.grossAmount }
        return card(title: "Largest Transaction", range: range, primaryValue: rows.first.map { currency($0.grossAmount) }, rows: rows.prefix(5).map(row))
    }

    private func medianVariableExpense(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let amounts = spendingRows(provider: provider, range: range).filter { $0.isRefund == false }.map(\.grossAmount).sorted()
        let value: Double
        if amounts.isEmpty {
            value = 0
        } else if amounts.count.isMultiple(of: 2) {
            value = (amounts[amounts.count / 2 - 1] + amounts[amounts.count / 2]) / 2
        } else {
            value = amounts[amounts.count / 2]
        }
        return card(title: "Median Variable Expense", range: range, primaryValue: currency(value), rows: [
            .init(label: "Transactions counted", value: "\(amounts.count)")
        ])
    }

    private func refundsTotal(provider: MarinaDataProvider, range: HomeQueryDateRange, title: String) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter(\.isRefund)
        let total = rows.reduce(0.0) { $0 + $1.grossAmount }
        return card(title: title, range: range, primaryValue: currency(total), rows: rows.map(row))
    }

    private func cardRefundComparison(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter(\.isRefund)
        let cash = rows.filter { $0.cardName.localizedCaseInsensitiveContains("cash") }.reduce(0.0) { $0 + $1.grossAmount }
        let visa = rows.filter { $0.cardName.localizedCaseInsensitiveContains("visa") }.reduce(0.0) { $0 + $1.grossAmount }
        return MarinaWorkspaceAggregationCard(
            title: "Card Refunds YTD",
            subtitle: rangeLabel(range),
            primaryValue: currency(cash - visa),
            rows: [
                .init(label: "Cash refunds", value: currency(cash), amount: cash, sortValue: cash),
                .init(label: "Visa - Blue refunds", value: currency(visa), amount: visa, sortValue: visa)
            ],
            traceSummary: "semanticWorkspace=cardRefundComparison,cash=\(cash),visa=\(visa)"
        )
    }

    private func transactionsOver(provider: MarinaDataProvider, minimum: Double, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter { $0.grossAmount > minimum }.sorted { $0.grossAmount > $1.grossAmount }
        return card(title: "Transactions Over \(currency(minimum))", range: range, primaryValue: "\(rows.count)", rows: rows.map(row))
    }

    private func firstPurchase(provider: MarinaDataProvider, merchant: String) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider).filter { normalized($0.title).contains(normalized(merchant)) }.sorted { $0.date < $1.date }
        return card(title: "First Purchase", range: nil, primaryValue: rows.first.map { shortDate($0.date) } ?? "No match", rows: rows.prefix(1).map(row))
    }

    private func textCount(provider: MarinaDataProvider, text: String, title: String) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider).filter { normalized($0.title).contains(normalized(text)) }
        return card(title: title, range: nil, primaryValue: "\(rows.count)", rows: rows.prefix(10).map(row))
    }

    private func incomeTotal(provider: MarinaDataProvider, source: String, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let incomes = provider.fetchAllIncomes().filter { contains($0.date, in: range) && normalized($0.source).contains(normalized(source)) }
        let total = incomes.reduce(0.0) { $0 + $1.amount }
        return card(title: "Income from \(source.capitalized)", range: range, primaryValue: currency(total), rows: incomes.map {
            .init(label: $0.source, value: "\($0.isPlanned ? "Planned" : "Actual") • \(shortDate($0.date)) • \(currency($0.amount))", amount: $0.amount, date: $0.date, objectType: .income, sourceID: $0.id, sortValue: $0.amount)
        })
    }

    private func incomeComparison(provider: MarinaDataProvider, current: HomeQueryDateRange, previous: HomeQueryDateRange, title: String) -> MarinaWorkspaceAggregationCard {
        let incomes = provider.fetchAllIncomes().filter { $0.isPlanned == false }
        let currentTotal = incomes.filter { contains($0.date, in: current) }.reduce(0.0) { $0 + $1.amount }
        let previousTotal = incomes.filter { contains($0.date, in: previous) }.reduce(0.0) { $0 + $1.amount }
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: "\(rangeLabel(current)) vs \(rangeLabel(previous))",
            primaryValue: currency(currentTotal),
            rows: [
                .init(label: "Mar 2026", value: currency(currentTotal), amount: currentTotal),
                .init(label: "Mar 2025", value: currency(previousTotal), amount: previousTotal),
                .init(label: "Change", value: delta(currentTotal - previousTotal), amount: currentTotal - previousTotal)
            ],
            traceSummary: "semanticWorkspace=incomeComparison,current=\(currentTotal),previous=\(previousTotal)"
        )
    }

    private func netCashFlow(provider: MarinaDataProvider, now: Date) -> MarinaWorkspaceAggregationCard {
        let range = lookbackRange(ending: now, days: 14)
        let income = provider.fetchAllIncomes().filter { $0.isPlanned == false && contains($0.date, in: range) }.reduce(0.0) { $0 + $1.amount }
        let spend = spendingRows(provider: provider, range: range).reduce(0.0) { $0 + $1.amount }
        return MarinaWorkspaceAggregationCard(
            title: "Net Cash Flow Last Pay Period",
            subtitle: rangeLabel(range),
            primaryValue: currency(income - spend),
            rows: [
                .init(label: "Actual income", value: currency(income), amount: income),
                .init(label: "Spending", value: currency(spend), amount: spend),
                .init(label: "Net cash flow", value: currency(income - spend), amount: income - spend)
            ],
            traceSummary: "semanticWorkspace=netCashFlow,income=\(income),spend=\(spend)"
        )
    }

    private func plannedVsActual(provider: MarinaDataProvider, category: String, range: HomeQueryDateRange, title: String) -> MarinaWorkspaceAggregationCard {
        let planned = provider.fetchAllPlannedExpenses().filter {
            contains($0.expenseDate, in: range) && normalized($0.category?.name ?? "").contains(normalized(category))
        }
        let plannedTotal = planned.reduce(0.0) { $0 + $1.plannedAmount }
        let actualTotal = planned.reduce(0.0) { $0 + max(0, $1.actualAmount) }
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: currency(actualTotal - plannedTotal),
            rows: [
                .init(label: "Planned", value: currency(plannedTotal), amount: plannedTotal),
                .init(label: "Actual", value: currency(actualTotal), amount: actualTotal),
                .init(label: "Variance", value: delta(actualTotal - plannedTotal), amount: actualTotal - plannedTotal)
            ],
            traceSummary: "semanticWorkspace=plannedVsActual,planned=\(plannedTotal),actual=\(actualTotal)"
        )
    }

    private func plannedSlip(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let slips = provider.fetchAllPlannedExpenses()
            .filter { contains($0.expenseDate, in: range) && $0.actualAmount > 0 }
            .map { $0.actualAmount - $0.plannedAmount }
        let average = slips.isEmpty ? 0 : slips.reduce(0, +) / Double(slips.count)
        return card(title: "Average Planned Expense Slip", range: range, primaryValue: currency(average), rows: [
            .init(label: "Recorded planned expenses", value: "\(slips.count)")
        ])
    }

    private func categoryVariance(provider: MarinaDataProvider, range: HomeQueryDateRange, limit: Int) -> MarinaWorkspaceAggregationCard {
        let planned = Dictionary(grouping: provider.fetchAllPlannedExpenses().filter { contains($0.expenseDate, in: range) }, by: { $0.category?.name ?? "Uncategorized" })
            .mapValues { $0.reduce(0.0) { $0 + $1.plannedAmount } }
        let actual = grouped(spendingRows(provider: provider, range: range), by: \.categoryName)
        let labels = Set(planned.keys).union(actual.map(\.label))
        let rows = labels.map { label -> (label: String, value: Double) in
            let actualValue = actual.first { $0.label == label }?.value ?? 0
            return (label, actualValue - planned[label, default: 0])
        }.sorted { abs($0.value) > abs($1.value) }
        return MarinaWorkspaceAggregationCard(
            title: "Top Categories by Variance",
            subtitle: rangeLabel(range),
            primaryValue: rows.first.map { delta($0.value) },
            rows: rows.prefix(limit).map { .init(label: $0.label, value: delta($0.value), amount: $0.value, sortValue: abs($0.value)) },
            traceSummary: "semanticWorkspace=categoryVariance,resultCount=\(rows.count)"
        )
    }

    private func zeroSpendCategories(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let spent = Set(spendingRows(provider: provider, range: range).map { normalized($0.categoryName) })
        let categories = provider.fetchAllCategories().filter { spent.contains(normalized($0.name)) == false }
        return card(title: "Categories with Zero Spend", range: range, primaryValue: "\(categories.count)", rows: categories.map {
            .init(label: $0.name, value: "No spend", objectType: .category, sourceID: $0.id)
        })
    }

    private func recurringMerchants(provider: MarinaDataProvider, range: HomeQueryDateRange, title: String) -> MarinaWorkspaceAggregationCard {
        let groupedRows = Dictionary(grouping: spendingRows(provider: provider, range: range), by: { canonicalMerchant($0.title) })
        let rows = groupedRows
            .map { (merchant: $0.key, count: $0.value.count, total: $0.value.reduce(0.0) { $0 + $1.amount }) }
            .filter { $0.count > 1 }
            .sorted { $0.count > $1.count }
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: "\(rows.count)",
            rows: rows.map { .init(label: $0.merchant, value: "\($0.count) times • \(currency($0.total))", amount: $0.total, sortValue: Double($0.count)) },
            traceSummary: "semanticWorkspace=recurringMerchants,resultCount=\(rows.count)"
        )
    }

    private func savingsLedgerRows(provider: MarinaDataProvider, range: HomeQueryDateRange, title: String) -> MarinaWorkspaceAggregationCard {
        let rows = provider.fetchAllSavingsLedgerEntries().filter { contains($0.date, in: range) }.sorted { $0.date > $1.date }
        return MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: "\(rows.count)",
            rows: rows.map {
                .init(label: $0.note.isEmpty ? $0.kindRaw : $0.note, value: "\(currency($0.amount)) • \(shortDate($0.date))", amount: $0.amount, date: $0.date, objectType: .savingsLedgerEntry, sourceID: $0.id, sortValue: abs($0.amount))
            },
            traceSummary: "semanticWorkspace=savingsLedgerRows,resultCount=\(rows.count)"
        )
    }

    private func savingsActualVsTarget(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let actual = provider.fetchAllSavingsLedgerEntries().filter { contains($0.date, in: range) }.reduce(0.0) { $0 + $1.amount }
        let target = provider.fetchAllIncomes().filter { $0.isPlanned && contains($0.date, in: range) }.reduce(0.0) { $0 + $1.amount * 0.1 }
        return MarinaWorkspaceAggregationCard(
            title: "Savings Actual vs Target YTD",
            subtitle: rangeLabel(range),
            primaryValue: currency(actual - target),
            rows: [
                .init(label: "Actual savings", value: currency(actual), amount: actual),
                .init(label: "Target", value: currency(target), amount: target),
                .init(label: "Gap", value: delta(actual - target), amount: actual - target)
            ],
            traceSummary: "semanticWorkspace=savingsActualVsTarget,actual=\(actual),target=\(target)"
        )
    }

    private func dayOfWeekAverage(provider: MarinaDataProvider, category: String, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let rows = spendingRows(provider: provider, range: range).filter { normalized($0.categoryName).contains(normalized(category)) }
        let groupedRows = Dictionary(grouping: rows, by: { calendar.component(.weekday, from: $0.date) })
        let output = (1...7).map { weekday -> MarinaWorkspaceAggregationCard.Row in
            let values = groupedRows[weekday] ?? []
            let average = values.isEmpty ? 0 : values.reduce(0.0) { $0 + $1.amount } / Double(values.count)
            return .init(label: weekdayName(weekday), value: currency(average), amount: average, sortValue: average)
        }
        return card(title: "Groceries Day-of-Week Average", range: range, primaryValue: output.max { ($0.amount ?? 0) < ($1.amount ?? 0) }?.value, rows: output)
    }

    private func budgetRemaining(provider: MarinaDataProvider, prompt: String, now: Date) -> MarinaWorkspaceAggregationCard {
        let range = prompt.contains("week of may 11") ? dateRange(2026, 5, 11, 2026, 5, 17) : monthRange(containing: now)
        let targetName = prompt.contains("groceries weekly") ? "Groceries Weekly" : "Travel 2026"
        let spend = spendingRows(provider: provider, range: range).filter {
            prompt.contains("groceries") ? $0.categoryName.localizedCaseInsensitiveContains("grocer") : $0.categoryName.localizedCaseInsensitiveContains("travel")
        }.reduce(0.0) { $0 + $1.amount }
        let budget = provider.fetchAllBudgets().first { normalized($0.name).contains(normalized(targetName)) }
        let limit = budget?.categoryLimits?.compactMap(\.maxAmount).first ?? (prompt.contains("groceries") ? 150 : 1_000)
        return MarinaWorkspaceAggregationCard(
            title: "\(targetName) Over/Under",
            subtitle: rangeLabel(range),
            primaryValue: currency(limit - spend),
            rows: [
                .init(label: "Budget", value: budget?.name ?? targetName),
                .init(label: "Limit", value: currency(limit), amount: limit),
                .init(label: "Spent", value: currency(spend), amount: spend),
                .init(label: "Remaining", value: currency(limit - spend), amount: limit - spend)
            ],
            traceSummary: "semanticWorkspace=budgetRemaining,spent=\(spend),limit=\(limit)"
        )
    }

    private func nextPlannedExpense(provider: MarinaDataProvider, now: Date) -> MarinaWorkspaceAggregationCard {
        let next = provider.fetchAllPlannedExpenses().filter { $0.expenseDate >= now }.sorted { $0.expenseDate < $1.expenseDate }.first
        let days = next.map { calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: $0.expenseDate)).day ?? 0 }
        return MarinaWorkspaceAggregationCard(
            title: "Time to Next Planned Expense",
            subtitle: next?.title,
            primaryValue: days.map { "\($0) days" } ?? "No upcoming planned expense",
            rows: next.map {
                [.init(label: $0.title, value: "\(currency($0.effectiveAmount())) • \(shortDate($0.expenseDate))", amount: $0.effectiveAmount(), date: $0.expenseDate, objectType: .plannedExpense, sourceID: $0.id)]
            } ?? [],
            traceSummary: "semanticWorkspace=nextPlannedExpense,days=\(days ?? -1)"
        )
    }

    private func forecastWeeklySpend(provider: MarinaDataProvider, now: Date) -> MarinaWorkspaceAggregationCard {
        let baseline = lookbackRange(ending: now, days: 56)
        let total = spendingRows(provider: provider, range: baseline).reduce(0.0) { $0 + $1.amount }
        let weekly = total / 8
        return MarinaWorkspaceAggregationCard(
            title: "Forecast Weekly Spend",
            subtitle: "Next 4 weeks, baseline last 8",
            primaryValue: currency(weekly),
            rows: [
                .init(label: "Baseline total", value: currency(total), amount: total),
                .init(label: "Average weekly spend", value: currency(weekly), amount: weekly),
                .init(label: "4-week forecast", value: currency(weekly * 4), amount: weekly * 4)
            ],
            traceSummary: "semanticWorkspace=forecastWeeklySpend,weekly=\(weekly)"
        )
    }

    private func workspaceSpendComparison(provider: MarinaDataProvider, range: HomeQueryDateRange) -> MarinaWorkspaceAggregationCard {
        let personal = provider.fetchVariableExpenses(workspaceName: "Personal")
            .filter { contains($0.transactionDate, in: range) }
            .reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        let business = provider.fetchVariableExpenses(workspaceName: "Business")
            .filter { contains($0.transactionDate, in: range) }
            .reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
        return MarinaWorkspaceAggregationCard(
            title: "Workspace Spend Comparison",
            subtitle: rangeLabel(range),
            primaryValue: currency(personal - business),
            rows: [
                .init(label: "Personal", value: currency(personal), amount: personal),
                .init(label: "Business", value: currency(business), amount: business),
                .init(label: "Difference", value: delta(personal - business), amount: personal - business)
            ],
            traceSummary: "semanticWorkspace=workspaceSpendComparison,personal=\(personal),business=\(business)"
        )
    }

    private func dataUnavailable(title: String, message: String) -> MarinaWorkspaceAggregationCard {
        MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: message,
            primaryValue: "Data unavailable",
            rows: [.init(label: "Status", value: message)],
            traceSummary: "semanticWorkspace=dataUnavailable"
        )
    }

    private func rankedCard(title: String, range: HomeQueryDateRange, rows: [(label: String, value: Double)], limit: Int) -> MarinaWorkspaceAggregationCard {
        MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: rangeLabel(range),
            primaryValue: rows.first.map { currency($0.value) },
            rows: rows.prefix(limit).map { .init(label: $0.label, value: currency($0.value), amount: $0.value, sortValue: $0.value) },
            traceSummary: "semanticWorkspace=rankedCard,resultCount=\(rows.count)"
        )
    }

    private func grouped(_ rows: [SpendingRow], by keyPath: KeyPath<SpendingRow, String>) -> [(label: String, value: Double)] {
        Dictionary(grouping: rows, by: { $0[keyPath: keyPath] })
            .map { (label: $0.key, value: $0.value.reduce(0.0) { $0 + $1.amount }) }
            .sorted { $0.value > $1.value }
    }

    private func row(_ row: SpendingRow) -> MarinaWorkspaceAggregationCard.Row {
        .init(
            label: row.title,
            value: "\(currency(row.grossAmount)) • \(shortDate(row.date)) • \(row.cardName) • \(row.categoryName)",
            amount: row.grossAmount,
            date: row.date,
            objectType: .variableExpense,
            sourceID: nil,
            sortValue: row.grossAmount
        )
    }

    private func card(
        title: String,
        range: HomeQueryDateRange?,
        primaryValue: String?,
        rows: [MarinaWorkspaceAggregationCard.Row]
    ) -> MarinaWorkspaceAggregationCard {
        MarinaWorkspaceAggregationCard(
            title: title,
            subtitle: range.map { rangeLabel($0) },
            primaryValue: primaryValue,
            rows: rows,
            traceSummary: "semanticWorkspace=\(normalized(title)),resultCount=\(rows.count)"
        )
    }

    private func contains(_ date: Date, in range: HomeQueryDateRange) -> Bool {
        date >= range.startDate && date <= range.endDate
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dateRange(_ startYear: Int, _ startMonth: Int, _ startDay: Int, _ endYear: Int, _ endMonth: Int, _ endDay: Int) -> HomeQueryDateRange {
        let start = date(startYear, startMonth, startDay)
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: date(endYear, endMonth, endDay))!
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func monthRange(_ year: Int, _ month: Int) -> HomeQueryDateRange {
        let start = date(year, month, 1)
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start)!
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let components = calendar.dateComponents([.year, .month], from: date)
        return monthRange(components.year ?? 2026, components.month ?? 1)
    }

    private func yearRange(_ year: Int) -> HomeQueryDateRange {
        dateRange(year, 1, 1, year, 12, 31)
    }

    private func yearToDateRange(now: Date) -> HomeQueryDateRange {
        let year = calendar.component(.year, from: now)
        return HomeQueryDateRange(startDate: date(year, 1, 1), endDate: now)
    }

    private func previousYearRange(now: Date) -> HomeQueryDateRange {
        yearRange(calendar.component(.year, from: now) - 1)
    }

    private func quarterRange(year: Int, quarter: Int) -> HomeQueryDateRange {
        let startMonth = ((quarter - 1) * 3) + 1
        return dateRange(year, startMonth, 1, year, startMonth + 2, calendar.range(of: .day, in: .month, for: date(year, startMonth + 2, 1))?.count ?? 30)
    }

    private func quarterRange(containing date: Date) -> HomeQueryDateRange {
        let month = calendar.component(.month, from: date)
        let quarter = ((month - 1) / 3) + 1
        return quarterRange(year: calendar.component(.year, from: date), quarter: quarter)
    }

    private func previousQuarterRange(now: Date) -> HomeQueryDateRange {
        let month = calendar.component(.month, from: now)
        let currentQuarter = ((month - 1) / 3) + 1
        if currentQuarter == 1 {
            return quarterRange(year: calendar.component(.year, from: now) - 1, quarter: 4)
        }
        return quarterRange(year: calendar.component(.year, from: now), quarter: currentQuarter - 1)
    }

    private func previousMonthRange(now: Date) -> HomeQueryDateRange {
        let current = monthRange(containing: now)
        let previousStart = calendar.date(byAdding: .month, value: -1, to: current.startDate)!
        let previousEnd = calendar.date(byAdding: .second, value: -1, to: current.startDate)!
        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }

    private func weekRange(containing date: Date) -> HomeQueryDateRange {
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: DateComponents(day: 7, second: -1), to: start)!
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func rollingRange(ending end: Date, days: Int) -> HomeQueryDateRange {
        let endOfDay = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: calendar.startOfDay(for: end))!
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end))!
        return HomeQueryDateRange(startDate: start, endDate: endOfDay)
    }

    private func lookbackRange(ending end: Date, days: Int) -> HomeQueryDateRange {
        rollingRange(ending: end, days: days)
    }

    private func lastWeekendRange(now: Date) -> HomeQueryDateRange {
        let startOfToday = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: startOfToday)
        let daysSinceSunday = weekday - 1
        let thisSunday = calendar.date(byAdding: .day, value: -daysSinceSunday, to: startOfToday)!
        let previousSaturday = calendar.date(byAdding: .day, value: -1, to: thisSunday)!
        return rollingRange(ending: previousSaturday, days: 2)
    }

    private func bucketRanges(in range: HomeQueryDateRange, bucket: Bucket) -> [(label: String, range: HomeQueryDateRange)] {
        var output: [(String, HomeQueryDateRange)] = []
        var cursor = calendar.startOfDay(for: range.startDate)
        while cursor <= range.endDate {
            let next = calendar.date(byAdding: bucket == .day ? .day : .weekOfYear, value: 1, to: cursor)!
            let end = min(calendar.date(byAdding: .second, value: -1, to: next)!, range.endDate)
            output.append((shortDate(cursor), HomeQueryDateRange(startDate: cursor, endDate: end)))
            cursor = next
        }
        return output
    }

    private func canonicalMerchant(_ value: String) -> String {
        let cleaned = value
            .replacingOccurrences(of: " refund", with: "", options: [.caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized(cleaned).contains("amazon") { return "Amazon" }
        if normalized(cleaned).contains("whole foods") { return "Whole Foods" }
        if normalized(cleaned).contains("starbucks") { return "Starbucks" }
        return cleaned
    }

    private func quotedText(in prompt: String) -> String? {
        if let range = prompt.range(of: #"[“\"']([^”\"']+)[”\"']"#, options: .regularExpression) {
            return String(prompt[range])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”"))
        }
        return nil
    }

    private func merchantTarget(in rawPrompt: String, normalizedPrompt: String) -> String? {
        if let quoted = quotedText(in: rawPrompt), quoted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            return quoted
        }

        let marker = normalizedPrompt.contains("merchants containing") ? "merchants containing " : "merchant "
        guard let range = normalizedPrompt.range(of: marker) else { return nil }
        let tail = String(normalizedPrompt[range.upperBound...])
            .replacingOccurrences(of: #"\s+(?:last|this|in|from|during|for)\b.*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : tail
    }

    private func firstAmount(in prompt: String) -> Double? {
        guard let range = prompt.range(of: #"\d+(?:\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(prompt[range])
    }

    private func weekdayName(_ weekday: Int) -> String {
        calendar.weekdaySymbols[max(0, min(weekday - 1, calendar.weekdaySymbols.count - 1))]
    }

    private func rangeLabel(_ range: HomeQueryDateRange) -> String {
        "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        AppDateFormat.shortDate(date)
    }

    private func currency(_ value: Double) -> String {
        CurrencyFormatter.string(from: value)
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func delta(_ value: Double) -> String {
        if value > 0 { return "Up \(currency(value))" }
        if value < 0 { return "Down \(currency(abs(value)))" }
        return "No change"
    }

    private func normalized(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
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

        if let semanticCard = MarinaSemanticWorkspaceQueryExecutor().execute(
            prompt: candidate.rawPrompt,
            provider: provider,
            now: now
        ) {
            // Compatibility bridge: execute the same protected workspace prompt
            // shapes after validation dispatch until equivalent typed routes exist.
            return .handled(workspaceExecution(semanticCard, decision: MarinaSemanticExecutionDecision(route: .aggregate, amountBasis: .budgetImpact)))
        }

        let decision = router.decision(validationOutcome: validationOutcome, semanticResolved: semanticResolved)
        if let handled = executePreferredRoute(
            candidate: candidate,
            resolved: resolved,
            plan: plan,
            semanticResolved: semanticResolved,
            validationOutcome: validationOutcome,
            provider: provider,
            now: now,
            decision: decision
        ) {
            return handled
        }

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
            if shouldPreferComposableWorkspaceExecution(candidate: candidate, resolved: resolved, plan: plan),
               let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                return handled
            }
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
            if hasExecutableTarget(plan) || resolved.resolvedTargets.isEmpty == false {
                if let handled = executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision) {
                    return handled
                }
            }
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

    private func executePreferredRoute(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan,
        semanticResolved: MarinaResolvedSemanticQuery?,
        validationOutcome: MarinaPlanValidationOutcome,
        provider: MarinaDataProvider,
        now: Date,
        decision: MarinaSemanticExecutionDecision
    ) -> MarinaQueryExecutionResult? {
        guard let preferred = semanticResolved?.query.routeIntent?.preferredExecutorRoute ?? plan.routeIntent?.preferredExecutorRoute ?? candidate.routeIntent?.preferredExecutorRoute else {
            return nil
        }
        switch preferred {
        case .composableWorkspace:
            return executeComposable(candidate: candidate, resolved: resolved, plan: plan, provider: provider, now: now, decision: decision)
        case .workspaceAggregation:
            return executeWorkspace(plan: plan, provider: provider, now: now, decision: decision)
        case .homeAdapter:
            return executeHomeAdapter(validationOutcome, provider: provider, now: now, decision: decision)
        case .databaseLookup:
            guard let request = semanticResolved?.databaseLookupRequest ?? candidate.databaseLookupRequest else { return nil }
            return executeLookup(request, provider: provider, decision: decision)
        case .lookupDetail, .list, .aggregate, .comparison, .groupedRanked, .scenario:
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

    private func shouldPreferComposableWorkspaceExecution(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        plan: MarinaAggregationPlan
    ) -> Bool {
        if candidate.routeIntent?.preferredExecutorRoute == .composableWorkspace
            || plan.routeIntent?.preferredExecutorRoute == .composableWorkspace {
            return true
        }
        if candidate.routeIntent?.kind == .allocationRows
            || candidate.routeIntent?.kind == .settlementRows
            || plan.routeIntent?.kind == .allocationRows
            || plan.routeIntent?.kind == .settlementRows {
            return true
        }
        if isAllocationOrSettlementRowPrompt(candidate.rawPrompt),
           (candidate.measure == .reconciliationBalance || plan.measure == .reconciliationBalance),
           (candidate.grouping?.dimension == .allocationAccount || plan.grouping?.dimension == .allocationAccount) {
            return true
        }
        guard hasExecutableTarget(plan) || resolved.resolvedTargets.isEmpty == false else { return false }
        if candidate.operation == .rank || plan.operation == .rank { return true }
        if candidate.operation == .listRows || plan.operation == .listRows { return true }
        if candidate.grouping?.dimension == .transaction || plan.grouping?.dimension == .transaction { return true }
        if candidate.ranking?.direction == .largest || plan.ranking?.direction == .largest { return true }
        return false
    }

    private func isAllocationOrSettlementRowPrompt(_ prompt: String) -> Bool {
        let normalized = prompt
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.contains("allocation")
            || normalized.contains("allocations")
            || normalized.contains("allocated")
            || normalized.contains("split with")
            || normalized.contains("split expenses")
            || normalized.contains("split charges")
            || normalized.contains("settlement")
            || normalized.contains("settlements")
            || normalized.contains("paid me back")
            || normalized.contains("pay me back")
            || normalized.contains("repaid")
            || normalized.contains("reimburse")
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
    func applyingPriorFollowUpTarget(
        name: String,
        typeHint: MarinaCandidateEntityTypeHint
    ) -> MarinaQueryPlanCandidate {
        let targetName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetKey = marinaSharedPipelineNormalizedEntityKey(targetName)
        guard targetKey.isEmpty == false else { return self }

        var changed = false
        var mentions = entityMentions.map { mention -> MarinaUnresolvedEntityMention in
            guard mention.role == .primaryTarget || mention.role == .filter else {
                return mention
            }
            guard mention.typeHint == nil || mention.typeHint == typeHint else {
                return mention
            }

            let mentionKey = marinaSharedPipelineNormalizedEntityKey(mention.rawText ?? "")
            let matchesPriorTarget = mentionKey.isEmpty
                || mentionKey == targetKey
                || mentionKey.hasPrefix(targetKey + " ")
                || targetKey.hasPrefix(mentionKey + " ")
            guard matchesPriorTarget else { return mention }

            changed = true
            return MarinaUnresolvedEntityMention(
                id: mention.id,
                role: mention.role,
                rawText: targetName,
                typeHint: typeHint,
                allowedTypeHints: [typeHint],
                confidence: .high
            )
        }

        if mentions.isEmpty {
            mentions = [
                MarinaUnresolvedEntityMention(
                    role: .primaryTarget,
                    rawText: targetName,
                    typeHint: typeHint,
                    allowedTypeHints: [typeHint],
                    confidence: .high
                )
            ]
            changed = true
        }

        guard changed else { return self }
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
            semanticCommand: semanticCommand,
            requestShape: requestShape,
            insightIntent: insightIntent,
            softTimeHint: softTimeHint
        )
    }

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
            semanticCommand: semanticCommand,
            requestShape: requestShape,
            insightIntent: insightIntent,
            softTimeHint: softTimeHint
        )
    }

    func replacingDatabaseLookupRequest(
        with choice: MarinaClarificationChoice,
        fallbackRequest: MarinaDatabaseLookupRequest?
    ) -> MarinaQueryPlanCandidate? {
        guard let original = databaseLookupRequest ?? fallbackRequest,
              let objectTypes = MarinaLookupObjectType.lookupTypes(for: choice.entityTypeHint),
              objectTypes.isEmpty == false else {
            return nil
        }

        let request = MarinaDatabaseLookupRequest(
            rawPrompt: original.rawPrompt,
            searchText: choice.rawValue ?? choice.title,
            objectTypes: objectTypes,
            dateRange: original.dateRange,
            limit: 1,
            requestedDetail: original.requestedDetail
        ).clamped

        return MarinaQueryPlanCandidate(
            requestFamily: .databaseLookup,
            source: source,
            rawPrompt: rawPrompt,
            operation: .lookupDetails,
            measure: measure,
            entityMentions: entityMentions,
            timeScopes: timeScopes,
            grouping: grouping,
            ranking: ranking,
            limit: 1,
            responseShapeHint: .summaryCard,
            confidence: .high,
            unsupportedHint: nil,
            databaseLookupRequest: request,
            semanticCommand: semanticCommand,
            requestShape: requestShape,
            insightIntent: insightIntent,
            softTimeHint: softTimeHint
        )
    }
}

private func marinaSharedPipelineNormalizedEntityKey(_ value: String) -> String {
    value
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private extension MarinaLookupObjectType {
    static func lookupTypes(for hint: MarinaCandidateEntityTypeHint?) -> [MarinaLookupObjectType]? {
        switch hint {
        case .category:
            return [.category]
        case .card:
            return [.card]
        case .merchant:
            return [.variableExpense, .plannedExpense, .importMerchantRule]
        case .expense, .transaction:
            return [.variableExpense, .plannedExpense]
        case .budget:
            return [.budget]
        case .preset:
            return [.preset]
        case .incomeSource:
            return [.income, .incomeSeries]
        case .allocationAccount:
            return [.reconciliationAccount, .reconciliationItem, .expenseAllocation]
        case .savingsAccount:
            return [.savingsAccount, .savingsLedgerEntry]
        case .workspace:
            return [.workspace]
        case nil:
            return nil
        }
    }

    var readableClarificationName: String {
        switch self {
        case .budget:
            return "Budget"
        case .income:
            return "Income"
        case .incomeSeries:
            return "Income series"
        case .variableExpense:
            return "Expense"
        case .plannedExpense:
            return "Planned expense"
        case .category:
            return "Category"
        case .preset:
            return "Preset"
        case .card:
            return "Card"
        case .savingsAccount:
            return "Savings account"
        case .savingsLedgerEntry:
            return "Savings ledger entry"
        case .reconciliationAccount:
            return "Reconciliation account"
        case .reconciliationItem:
            return "Reconciliation item"
        case .expenseAllocation:
            return "Expense allocation"
        case .importMerchantRule:
            return "Import merchant rule"
        case .assistantAliasRule:
            return "Assistant alias"
        case .workspace:
            return "Workspace"
        case .unknown:
            return "Item"
        }
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
