import Foundation

protocol MarinaCanonicalAIInterpreting {
    func interpretCanonical(
        prompt: String,
        context: MarinaInterpretationContext
    ) async throws -> MarinaCanonicalReadInterpretation
}

struct MarinaLegacyCanonicalTurnIntentAdapter: MarinaTurnIntentInterpreting {
    private let canonicalInterpreter: MarinaCanonicalAIInterpreting

    init(_ canonicalInterpreter: MarinaCanonicalAIInterpreting) {
        self.canonicalInterpreter = canonicalInterpreter
    }

    func interpretTurnIntent(
        prompt: String,
        context: MarinaInterpretationContext
    ) async throws -> MarinaTurnInterpretation {
        let canonical = try await canonicalInterpreter.interpretCanonical(
            prompt: prompt,
            context: context
        )
        return MarinaTurnInterpretation(
            result: canonical.result,
            compatibilityCandidate: canonical.compatibilityCandidate,
            repairSummary: canonical.repairSummary,
            generatedSchemaName: "legacyCanonicalAdapter"
        )
    }
}

struct MarinaFoundationAIInterpreter: MarinaCanonicalAIInterpreting {
    private let aiInterpreter: MarinaAIInterpreter
    private let foundationContractInterpreter = MarinaFoundationModelsInterpreter()

    init(aiInterpreter: MarinaAIInterpreter = MarinaFoundationModelsService()) {
        self.aiInterpreter = aiInterpreter
    }

    func interpretCanonical(
        prompt: String,
        context: MarinaInterpretationContext
    ) async throws -> MarinaCanonicalReadInterpretation {
        let intent = try await aiInterpreter.interpretAI(prompt: prompt, context: context)
        let interpretation = canonicalInterpretation(from: intent, prompt: prompt, defaultPeriodUnit: context.defaultPeriodUnit)
        return MarinaLiveIntentNormalizer().normalized(
            interpretation,
            prompt: prompt,
            context: context,
            defaultPeriodUnit: context.defaultPeriodUnit
        )
    }

    private func canonicalInterpretation(
        from intent: MarinaAIIntent,
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaCanonicalReadInterpretation {
        switch intent {
        case .semanticQuery:
            return foundationContractInterpreter.canonicalInterpretation(
                from: intent.structuredIntent,
                prompt: prompt,
                defaultPeriodUnit: defaultPeriodUnit
            )
        case .scenario(let scenario):
            let scenarioFilters: [MarinaSemanticCommandFilter]
            if let targetName = scenario.targetName?.marinaNilIfBlank {
                scenarioFilters = [
                    MarinaSemanticCommandFilter(
                        rawText: targetName,
                        allowedTypes: scenarioTargetTypes(from: scenario.targetTypeRaw)
                    )
                ]
            } else {
                scenarioFilters = []
            }
            let structuredIntent = MarinaStructuredIntent.semanticCommand(
                MarinaSemanticCommand(
                    family: .planning,
                    action: .simulate,
                    datasets: [.budgets],
                    measure: .remainingBudget,
                    includeFilters: scenarioFilters,
                    dateRange: dateRange(from: scenario.dateRange),
                    periodUnit: periodUnit(from: scenario.dateRange?.periodUnitRaw),
                    limit: nil
                )
            )
            return foundationContractInterpreter.canonicalInterpretation(
                from: structuredIntent,
                prompt: prompt,
                defaultPeriodUnit: defaultPeriodUnit
            )
        case .readQuery, .lookup, .clarification, .unsupported:
            return foundationContractInterpreter.canonicalInterpretation(
                from: intent.structuredIntent,
                prompt: prompt,
                defaultPeriodUnit: defaultPeriodUnit
            )
        }
    }

    private func scenarioTargetTypes(from rawValue: String?) -> [MarinaCandidateEntityTypeHint] {
        switch normalizedToken(rawValue) {
        case "category", "categories":
            return [.category]
        case "card", "cards":
            return [.card]
        case "budget", "budgets":
            return [.budget]
        case "merchant", "merchants":
            return [.merchant]
        case "savings", "savings_account", "savingsaccount":
            return [.savingsAccount]
        case nil:
            return [.category, .card, .budget]
        default:
            return [.category, .card, .budget]
        }
    }

    private func dateRange(from intent: MarinaAIDateRange?) -> HomeQueryDateRange? {
        MarinaDateOnlyRangeCodec.dateRange(
            start: intent?.startISO8601,
            end: intent?.endISO8601
        )
    }

    private func periodUnit(from rawValue: String?) -> HomeQueryPeriodUnit? {
        switch normalizedToken(rawValue) {
        case "day", "daily":
            return .day
        case "week", "weekly":
            return .week
        case "month", "monthly":
            return .month
        case "quarter", "quarterly":
            return .quarter
        case "year", "yearly":
            return .year
        default:
            return nil
        }
    }

    private func normalizedToken(_ value: String?) -> String? {
        let normalized = value?
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return normalized?.isEmpty == false ? normalized : nil
    }
}

struct MarinaFakeCanonicalAIInterpreter: MarinaCanonicalAIInterpreting {
    enum Failure: Error {
        case missingInterpretation
    }

    var interpretationsByPrompt: [String: MarinaCanonicalReadInterpretation]

    init(interpretationsByPrompt: [String: MarinaCanonicalReadInterpretation]) {
        self.interpretationsByPrompt = interpretationsByPrompt
    }

    func interpretCanonical(
        prompt: String,
        context _: MarinaInterpretationContext
    ) async throws -> MarinaCanonicalReadInterpretation {
        guard let interpretation = interpretationsByPrompt[prompt] else {
            throw Failure.missingInterpretation
        }
        return interpretation
    }
}

struct MarinaTurnContext {
    let provider: MarinaDataProvider
    let routerContext: MarinaInterpretationContext
    let defaultPeriodUnit: HomeQueryPeriodUnit
    let aiEnabled: Bool
    let now: Date
    let turnClassification: MarinaPromptTurnClassification

    init(
        provider: MarinaDataProvider,
        routerContext: MarinaInterpretationContext,
        defaultPeriodUnit: HomeQueryPeriodUnit,
        aiEnabled: Bool,
        now: Date,
        turnClassification: MarinaPromptTurnClassification = .freshQuestion
    ) {
        self.provider = provider
        self.routerContext = routerContext
        self.defaultPeriodUnit = defaultPeriodUnit
        self.aiEnabled = aiEnabled
        self.now = now
        self.turnClassification = turnClassification
    }
}

enum MarinaTurnResult {
    case handled(
        answer: HomeAnswer,
        aggregationResult: MarinaAggregationResult?,
        homeQueryPlan: HomeQueryPlan?,
        amountBasis: MarinaFinancialAmountBasis?,
        executionRoute: MarinaSemanticExecutionRoute?
    )
    case clarification(
        answer: HomeAnswer,
        clarification: MarinaTypedClarification
    )
    case blocked(
        answer: HomeAnswer,
        validationOutcome: MarinaPlanValidationOutcome?
    )
    case unavailable(HomeAnswer)
}

@MainActor
struct MarinaTurnCoordinator {
    private let availability: MarinaModelAvailabilityProviding
    private let interpreter: MarinaTurnIntentInterpreting
    private let resolver: MarinaQueryResolver
    private let validator: MarinaQueryValidator
    private let queryExecutor: MarinaQueryExecutor
    private let responseBuilder: MarinaResponseBuilder
    private let recoveryPolicy = MarinaQueryRecoveryPolicy()
    private let semanticAdapter = MarinaSemanticQueryAdapter()
    private let conversationalPlanner = MarinaConversationalQueryPlanner()
    private let compositePlanner = MarinaCompositeQueryPlanner()
    private let semanticContractResolver = MarinaSemanticInterpretationContractResolver()
    private let metricContractResolver = MarinaMetricContractResolver()
    private let metricContractResponseBuilder = MarinaMetricContractResponseBuilder()
    private let metricFormulaExecutor = MarinaMetricFormulaExecutor()
    private let answerPlanner = MarinaAnswerPlanner()
    private let universalQueryExecutor = MarinaUniversalQueryExecutor()
    private let canonicalQueryRewriter = MarinaCanonicalQueryRewriter()
    private let pipelineAuditCanonicalizer = MarinaFoundationPipelineAuditCanonicalizer()

    init(
        availability: MarinaModelAvailabilityProviding? = nil,
        interpreter: MarinaCanonicalAIInterpreting? = nil,
        turnInterpreter: MarinaTurnIntentInterpreting? = nil,
        resolver: MarinaQueryResolver? = nil,
        validator: MarinaQueryValidator? = nil,
        queryExecutor: MarinaQueryExecutor? = nil,
        responseBuilder: MarinaResponseBuilder? = nil
    ) {
        self.availability = availability ?? MarinaModelAvailability()
        self.interpreter = turnInterpreter
            ?? interpreter.map(MarinaLegacyCanonicalTurnIntentAdapter.init)
            ?? MarinaFoundationTurnIntentService()
        self.resolver = resolver ?? MarinaQueryResolver()
        self.validator = validator ?? MarinaQueryValidator()
        self.queryExecutor = queryExecutor ?? MarinaQueryExecutor(
            adapter: MarinaAggregationPlanHomeQueryAdapter(),
            executor: MarinaAggregationExecutor(),
            composableWorkspaceQueryExecutor: MarinaComposableWorkspaceQueryExecutor(),
            workspaceAggregationExecutor: MarinaWorkspaceAggregationExecutor(),
            databaseLookupExecutor: MarinaDatabaseLookupExecutor(),
            databaseLookupResponseBuilder: MarinaDatabaseLookupResponseBuilder()
        )
        self.responseBuilder = responseBuilder ?? MarinaResponseBuilder()
    }

    func run(
        prompt: String,
        context: MarinaTurnContext
    ) async -> MarinaTurnResult {
        guard context.aiEnabled else {
            MarinaFoundationTraceBridge.recordUnavailable(context: context, reason: "ai_opt_out")
            return .unavailable(Self.unavailableAnswer(
                prompt: prompt,
                reason: "Apple Intelligence is turned off for Marina."
            ))
        }

        let availabilityStatus = availability.currentStatus()
        MarinaTraceRecorder.shared.recordModelAvailability(availabilityStatus)
        guard availabilityStatus == .available else {
            MarinaFoundationTraceBridge.recordUnavailable(
                context: context,
                reason: Self.availabilityReason(availabilityStatus)
            )
            return .unavailable(Self.unavailableAnswer(
                prompt: prompt,
                reason: "Apple Intelligence is not available right now: \(Self.availabilityReason(availabilityStatus))."
            ))
        }

        do {
            let interpretation = try await interpreter.interpretTurnIntent(
                prompt: prompt,
                context: context.routerContext
            )
            return evaluateLinear(
                interpretation,
                prompt: prompt,
                context: context,
                allowSingleChoiceAutoResolve: true
            )
        } catch {
            MarinaDebugLogger.log("Marina AI interpretation failed prompt='\(prompt)' error=\(error)")
            let diagnostic = Self.foundationDiagnostic(from: error)
            if diagnostic.category == .decodingFailure,
               let auditedInterpretation = pipelineAuditCanonicalizer.interpretation(
                prompt: prompt,
                context: context
               ),
               shouldRecoverDecodingFailureWithAudit(auditedInterpretation) {
                return evaluateLinear(
                    preservingInterpreterSource(
                        in: MarinaTurnInterpretation(
                            result: auditedInterpretation.result,
                            compatibilityCandidate: auditedInterpretation.compatibilityCandidate,
                            repairSummary: malformedFoundationRecoverySummary(
                                original: nil,
                                recovery: auditedInterpretation.repairSummary,
                                diagnostic: diagnostic
                            ),
                            generatedSchemaName: auditedInterpretation.generatedSchemaName
                        ),
                        originalSource: .foundationModels
                    ),
                    prompt: prompt,
                    context: context,
                    allowSingleChoiceAutoResolve: true
                )
            }
            if diagnostic.category == .malformedResponse,
               let deterministicInterpretation = malformedFoundationRecoveryInterpretation(
                prompt: prompt,
                interpretation: nil,
                candidate: nil,
                context: context,
                diagnostic: diagnostic
               ) {
                return evaluateLinear(
                    deterministicInterpretation,
                    prompt: prompt,
                    context: context,
                    allowSingleChoiceAutoResolve: true
                )
            }
            MarinaTraceRecorder.shared.recordFoundationModelsFailure(diagnostic)
            MarinaFoundationTraceBridge.recordFoundationFailure(context: context, diagnostic: diagnostic)
            return .blocked(
                answer: Self.foundationFailureAnswer(
                    prompt: prompt,
                    diagnostic: diagnostic
                ),
                validationOutcome: nil
            )
        }
    }

    func run(
        query: HomeQuery,
        sourceTitle: String,
        context: MarinaTurnContext
    ) async -> MarinaTurnResult {
        let presetAdapter = MarinaPresetPromptQueryAdapter()
        let executablePlan = presetAdapter.executablePlan(for: query, sourceTitle: sourceTitle)
        let candidate = presetAdapter.candidate(for: query, sourceTitle: sourceTitle)
        let interpretation = MarinaCanonicalReadInterpretation(
            result: semanticAdapter.interpretationResult(from: candidate),
            compatibilityCandidate: candidate,
            repairSummary: "typedPresetPrompt:\(query.intent.rawValue)"
        )
        let resolved = resolver.resolve(
            candidate: candidate,
            provider: context.provider,
            now: context.now,
            defaultPeriodUnit: context.defaultPeriodUnit
        )
        let validationOutcome = MarinaPlanValidationOutcome.executable(executablePlan.aggregationPlan)
        let aggregationResult = MarinaAggregationExecutor().execute(
            executablePlan,
            provider: context.provider,
            now: context.now
        )

        if case .unsupported(let unsupported) = aggregationResult {
            let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: interpretation,
                resolved: resolved,
                semanticResolved: nil,
                validationOutcome: blockedOutcome,
                execution: nil
            )
            return .blocked(
                answer: responseBuilder.responseCompatibleAnswer(from: blockedOutcome) ?? Self.blockedAnswer(
                    prompt: sourceTitle,
                    title: "Marina cannot run that preset yet",
                    message: unsupported.message
                ),
                validationOutcome: blockedOutcome
            )
        }

        let baseAnswer = responseBuilder.responseCompatibleAnswer(from: aggregationResult)
        let titledAnswer = MarinaAnswerTitleResolver().applyingTitle(
            to: baseAnswer,
            query: query,
            userPrompt: sourceTitle,
            now: context.now
        )
        let execution = MarinaQueryExecution(
            executablePlan: executablePlan,
            aggregationResult: aggregationResult,
            databaseLookupResponse: nil,
            workspaceAggregationCard: nil,
            amountBasis: MarinaAmountBasisAdapter().basis(plan: executablePlan.aggregationPlan, semanticQuery: nil),
            executionRoute: executionRoute(for: executablePlan.aggregationPlan)
        )
        MarinaFoundationTraceBridge.record(
            context: context,
            interpretation: interpretation,
            resolved: resolved,
            semanticResolved: nil,
            validationOutcome: validationOutcome,
            execution: execution
        )
        return .handled(
            answer: titledAnswer,
            aggregationResult: aggregationResult,
            homeQueryPlan: executablePlan.homeQueryPlan,
            amountBasis: execution.amountBasis,
            executionRoute: execution.executionRoute
        )
    }

    func run(
        typedIntent: MarinaCanonicalTypedIntent,
        sourceTitle: String,
        context: MarinaTurnContext
    ) async -> MarinaTurnResult {
        let explicitConstraints = MarinaExplicitPromptConstraints()
        return evaluate(
            interpretation(for: typedIntent, sourceTitle: sourceTitle),
            context: context,
            explicitConstraints: explicitConstraints
        )
    }

    func resume(
        clarification: MarinaTypedClarification,
        choice: MarinaClarificationChoice,
        context: MarinaTurnContext
    ) async -> MarinaTurnResult {
        guard let candidate = clarification.candidate else {
            return .blocked(
                answer: Self.blockedAnswer(
                    prompt: choice.title,
                    title: "I need the original question again",
                    message: "That clarification state expired before Marina could apply the choice."
                ),
                validationOutcome: nil
            )
        }

        let resumedCandidate = candidate.replacingClarifiedMention(with: choice)
        let result: MarinaInterpretationResult
        let compatibilityCandidate: MarinaQueryPlanCandidate

        if let resumeInterpretation = interpretation(from: choice.resumeIntent, fallbackCandidate: resumedCandidate) {
            return evaluate(
                resumeInterpretation,
                context: context,
                explicitConstraints: MarinaExplicitPromptConstraints()
            )
        } else if let databaseLookupCandidate = resumedCandidate.replacingDatabaseLookupRequest(
            with: choice,
            fallbackRequest: candidate.databaseLookupRequest
        ) {
            compatibilityCandidate = databaseLookupCandidate
            result = semanticAdapter.interpretationResult(from: databaseLookupCandidate)
        } else if let pendingSemanticQuery = clarification.pendingSemanticQuery,
                  let patchedQuery = pendingSemanticQuery.patching(
                    choice: choice,
                    fallbackSlot: clarification.patchSlot,
                    now: context.now,
                    defaultPeriodUnit: context.defaultPeriodUnit
                  ) {
            compatibilityCandidate = resumedCandidate
            result = .query(patchedQuery)
        } else {
            compatibilityCandidate = resumedCandidate
            result = semanticAdapter.interpretationResult(from: resumedCandidate)
        }

        return evaluate(
            MarinaCanonicalReadInterpretation(
                result: result,
                compatibilityCandidate: compatibilityCandidate
            ),
            context: context,
            explicitConstraints: MarinaExplicitPromptConstraints()
        )
    }

    static func deferredCRUDAnswer(prompt: String) -> HomeAnswer {
        HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: prompt,
            title: "Marina is read-only for now",
            subtitle: "I can search, summarize, calculate, and run what-if scenarios first. Create, edit, and delete commands are paused until the confirmation flow is rebuilt.",
            rows: [
                HomeAnswerRow(title: "Status", value: "Saved changes are paused."),
                HomeAnswerRow(title: "Safe next step", value: "Use the app forms for changes that alter saved records.")
            ]
        )
    }

    private func interpretation(
        for typedIntent: MarinaCanonicalTypedIntent,
        sourceTitle: String
    ) -> MarinaCanonicalReadInterpretation {
        switch typedIntent {
        case .semanticQuery(let query):
            return MarinaCanonicalReadInterpretation(
                result: .query(query),
                compatibilityCandidate: semanticAdapter.compatibilityCandidate(
                    from: query,
                    prompt: sourceTitle,
                    source: .deterministic
                ),
                repairSummary: "typedIntent:\(typedIntent.traceSummary)"
            )
        case .currentWorkspace:
            let request = MarinaDatabaseLookupRequest(
                rawPrompt: sourceTitle,
                searchText: "",
                objectTypes: [.workspace],
                dateRange: nil,
                limit: 1,
                requestedDetail: .general,
                lookupMode: .entityDetail
            ).clamped
            let routeIntent = MarinaRouteIntent(
                kind: .currentWorkspace,
                subject: .workspaces,
                operation: .lookupDetails,
                measure: .transactionAmount,
                grouping: nil,
                targetTypes: [.workspace],
                requestedDetail: .general,
                responseShape: .summaryCard,
                preferredExecutorRoute: .databaseLookup
            )
            let candidate = MarinaQueryPlanCandidate(
                requestFamily: .databaseLookup,
                source: .deterministic,
                rawPrompt: sourceTitle,
                operation: .lookupDetails,
                measure: .transactionAmount,
                responseShapeHint: .summaryCard,
                confidence: .high,
                databaseLookupRequest: request,
                routeIntent: routeIntent
            )
            return MarinaCanonicalReadInterpretation(
                result: semanticAdapter.interpretationResult(from: candidate),
                compatibilityCandidate: candidate,
                repairSummary: "typedIntent:\(typedIntent.traceSummary)"
            )
        case .activeBudgetStatus:
            let routeIntent = MarinaRouteIntent(
                kind: .activeBudget,
                subject: .budgets,
                operation: .lookupDetails,
                measure: .remainingBudget,
                grouping: nil,
                targetTypes: [.budget],
                requestedDetail: .status,
                responseShape: .summaryCard,
                preferredExecutorRoute: .composableWorkspace
            )
            let query = MarinaSemanticQuery(
                subject: .budgets,
                operation: .lookupDetails,
                amountField: nil,
                responseShape: .summaryCard,
                requestedDetail: .status,
                routeIntent: routeIntent
            )
            let candidate = MarinaQueryPlanCandidate(
                source: .deterministic,
                rawPrompt: sourceTitle,
                operation: .lookupDetails,
                measure: .remainingBudget,
                responseShapeHint: .summaryCard,
                confidence: .high,
                routeIntent: routeIntent
            )
            return MarinaCanonicalReadInterpretation(
                result: .query(query),
                compatibilityCandidate: candidate,
                repairSummary: "typedIntent:\(typedIntent.traceSummary)"
            )
        case .clarification(let clarification):
            let candidate = clarification.candidate ?? MarinaQueryPlanCandidate(
                source: .deterministic,
                rawPrompt: sourceTitle,
                operation: .lookupDetails,
                measure: .transactionAmount,
                responseShapeHint: .clarification,
                confidence: .high
            )
            return MarinaCanonicalReadInterpretation(
                result: .clarification(clarification),
                compatibilityCandidate: candidate,
                repairSummary: "typedIntent:\(typedIntent.traceSummary)"
            )
        case .unsupported(let unsupported):
            let candidate = unsupported.candidate ?? MarinaQueryPlanCandidate(
                source: .deterministic,
                rawPrompt: sourceTitle,
                operation: .lookupDetails,
                measure: .transactionAmount,
                responseShapeHint: .unsupported,
                confidence: .high
            )
            return MarinaCanonicalReadInterpretation(
                result: .unsupported(unsupported),
                compatibilityCandidate: candidate,
                repairSummary: "typedIntent:\(typedIntent.traceSummary)"
            )
        }
    }

    private func canonicalizedInterpretation(
        _ interpretation: MarinaCanonicalReadInterpretation,
        explicitConstraints: MarinaExplicitPromptConstraints,
        now: Date,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaCanonicalReadInterpretation {
        let candidate = interpretation.compatibilityCandidate
        let repairedCandidate = recoveryPolicy.canonicalized(
            candidate: candidate,
            explicitConstraints: explicitConstraints,
            now: now,
            defaultPeriodUnit: defaultPeriodUnit
        )
        guard repairedCandidate != candidate else { return interpretation }
        return MarinaCanonicalReadInterpretation(
            result: semanticAdapter.interpretationResult(from: repairedCandidate),
            compatibilityCandidate: repairedCandidate,
            repairSummary: interpretation.repairSummary
        )
    }

    private func evaluateLinear(
        _ interpretation: MarinaTurnInterpretation,
        prompt: String,
        context: MarinaTurnContext,
        allowSingleChoiceAutoResolve: Bool = true
    ) -> MarinaTurnResult {
        let candidate = compatibilityCandidate(
            for: interpretation,
            prompt: prompt
        )
        let explicitConstraints = MarinaExplicitConstraintDetector().constraints(
            in: prompt,
            context: context.routerContext
        )
        if interpretation.generatedSchemaName == "legacyCanonicalAdapter" {
            let legacyInterpretation = MarinaCanonicalReadInterpretation(
                result: interpretation.result,
                compatibilityCandidate: candidate,
                repairSummary: interpretation.repairSummary
            )
            if let contractInterpretation = semanticContractResolver.resolve(
                prompt: prompt,
                context: context,
                priorInterpretation: legacyInterpretation
            ) {
                return evaluateLinear(
                    MarinaTurnInterpretation(
                        result: contractInterpretation.result,
                        compatibilityCandidate: contractInterpretation.compatibilityCandidate,
                        repairSummary: contractInterpretation.repairSummary,
                        generatedSchemaName: "legacyContractAdapter"
                    ),
                    prompt: prompt,
                    context: context,
                    allowSingleChoiceAutoResolve: allowSingleChoiceAutoResolve
                )
            }
        }
        if isMalformedTokenizedReadRequest(interpretation) {
            let diagnostic = MarinaFoundationModelsFailureDiagnostic(
                category: .malformedResponse,
                step: .typedEnvelope,
                debugSummary: "tokenizedReadRequest:malformed"
            )
            if let recoveredInterpretation = malformedFoundationRecoveryInterpretation(
                prompt: prompt,
                interpretation: interpretation,
                candidate: candidate,
                context: context,
                diagnostic: diagnostic
            ) {
                return evaluateLinear(
                    recoveredInterpretation,
                    prompt: prompt,
                    context: context,
                    allowSingleChoiceAutoResolve: allowSingleChoiceAutoResolve
                )
            }
            MarinaTraceRecorder.shared.recordFoundationModelsFailure(diagnostic)
            MarinaFoundationTraceBridge.recordFoundationFailure(context: context, diagnostic: diagnostic)
            return .blocked(
                answer: Self.foundationFailureAnswer(prompt: prompt, diagnostic: diagnostic),
                validationOutcome: nil
            )
        }
        let isTokenizedReadRequest = isTokenizedReadRequest(interpretation)
        let isPipelineAuditInterpretation = interpretation.generatedSchemaName == MarinaFoundationPipelineAuditCanonicalizer.generatedSchemaName
        let lateAuditInterpretation = shouldAttemptLateAuditRecovery(
            interpretation: interpretation,
            candidate: candidate,
            isTokenizedReadRequest: isTokenizedReadRequest,
            isPipelineAuditInterpretation: isPipelineAuditInterpretation
        ) ? pipelineAuditCanonicalizer.interpretation(prompt: prompt, context: context) : nil
        if isTokenizedReadRequest == false,
           interpretation.generatedSchemaName != "legacyCanonicalAdapter",
           lateAuditInterpretation == nil,
           shouldAttemptCanonicalRewrite(interpretation),
           let canonicalInterpretation = canonicalQueryRewriter.rewrite(
            prompt: prompt,
            interpretation: interpretation,
            candidate: candidate,
            context: context
        ) {
            return evaluateLinear(
                preservingInterpreterSource(
                    in: canonicalInterpretation,
                    originalSource: candidate.source
                ),
                prompt: prompt,
                context: context,
                allowSingleChoiceAutoResolve: allowSingleChoiceAutoResolve
            )
        }
        let traceInterpretation = MarinaCanonicalReadInterpretation(
            result: interpretation.result,
            compatibilityCandidate: candidate,
            repairSummary: interpretation.repairSummary
        )
        let isLegacyAdapter = interpretation.generatedSchemaName.hasPrefix("legacy")
        let resolved = resolver.resolve(
            candidate: candidate,
            provider: context.provider,
            now: context.now,
            defaultPeriodUnit: context.defaultPeriodUnit
        )

        let semanticResolved: MarinaResolvedSemanticQuery?
        let outcome: MarinaPlanValidationOutcome

        switch interpretation.result {
        case .query(let query):
            let resolvedQuery = resolver.resolve(
                query: query,
                provider: context.provider,
                candidate: candidate,
                now: context.now,
                defaultPeriodUnit: context.defaultPeriodUnit
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

        let shouldRunEarlyDroppedConstraintGuard: Bool
        if case .unsupported = outcome,
           isPipelineAuditInterpretation == false,
           isTokenizedReadRequest == false {
            shouldRunEarlyDroppedConstraintGuard = false
        } else {
            shouldRunEarlyDroppedConstraintGuard = true
        }
        if shouldRunEarlyDroppedConstraintGuard,
           let droppedConstraintResult = resultForDroppedExplicitConstraints(
            explicitConstraints: explicitConstraints,
            candidate: candidate,
            resolved: resolved,
            semanticResolved: semanticResolved,
            outcome: outcome,
            context: context,
            traceInterpretation: traceInterpretation
           ) {
            return droppedConstraintResult
        }

        if isTokenizedReadRequest,
           let universalQuery = candidate.universalQuery,
           isSimpleUniversalRead(universalQuery),
           case .clarification = outcome {
            // The tokenized path still lets Swift resolution stop for ambiguous or missing targets.
        } else if isTokenizedReadRequest,
                  let universalQuery = candidate.universalQuery,
                  isSimpleUniversalRead(universalQuery) {
            if let preflight = tokenizedUniversalPreflightResult(
                traceInterpretation: traceInterpretation,
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                context: context
            ) {
                return preflight
            }
            return evaluateUniversal(
                universalQuery,
                reason: "tokenizedReadRequest:universal",
                traceInterpretation: traceInterpretation,
                candidate: candidate,
                resolved: resolved,
                context: context,
                includeTokenizedEvidence: true
            )
        }

        let metricContractResolution: MarinaMetricContractResolution? = isPipelineAuditInterpretation
            ? nil
            : semanticMetricContractResolution(
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                outcome: outcome
            ) ?? metricContractResolver.resolve(
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                outcome: outcome
            )

        if let metricContractResolution {
            switch metricFormulaExecutor.execute(
                contract: metricContractResolution.contract,
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                context: context
            ) {
            case .handled(let card, let amountBasis, let route):
                let execution = MarinaQueryExecution(
                    executablePlan: nil,
                    aggregationResult: .workspaceCard(card),
                    databaseLookupResponse: nil,
                    workspaceAggregationCard: card,
                    amountBasis: amountBasis,
                    executionRoute: route
                )
                let answer = answerWithEvidence(
                    responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult),
                    execution: execution,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    metricContract: metricContractResolution.contract
                )
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: traceInterpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: outcome,
                    execution: execution
                )
                return .handled(
                    answer: answer,
                    aggregationResult: execution.aggregationResult,
                    homeQueryPlan: nil,
                    amountBasis: execution.amountBasis,
                    executionRoute: execution.executionRoute
                )
            case .blocked(let answer, let unsupported):
                let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: traceInterpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: blockedOutcome,
                    execution: nil
                )
                return .blocked(answer: answer, validationOutcome: blockedOutcome)
            case .notHandled:
                if metricContractResolution.isDirectFormulaSummon {
                    let answer = metricContractResponseBuilder.summonedFormulaAnswer(
                        contract: metricContractResolution.contract,
                        candidate: candidate
                    )
                    let unsupported = metricContractResponseBuilder.summonedFormulaUnsupportedResponse(
                        contract: metricContractResolution.contract,
                        candidate: candidate
                    )
                    let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                    MarinaFoundationTraceBridge.record(
                        context: context,
                        interpretation: traceInterpretation,
                        resolved: resolved,
                        semanticResolved: semanticResolved,
                        validationOutcome: blockedOutcome,
                        execution: nil
                    )
                    return .blocked(answer: answer, validationOutcome: blockedOutcome)
                }
                break
            }
        }

        if let metricContractResolution,
           metricContractResolution.shouldBlockExecution {
            let blocked = metricContractResponseBuilder.unsupportedResponse(
                contract: metricContractResolution.contract,
                candidate: candidate
            )
            let blockedOutcome = MarinaPlanValidationOutcome.unsupported(blocked)
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: traceInterpretation,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: blockedOutcome,
                execution: nil
            )
            return .blocked(
                answer: metricContractResponseBuilder.unsupportedAnswer(
                    contract: metricContractResolution.contract,
                    candidate: candidate
                ),
                validationOutcome: blockedOutcome
            )
        }

        if isTokenizedReadRequest == false,
           isPipelineAuditInterpretation == false,
           let composite = compositePlanner.plan(
            candidate: candidate,
            resolved: resolved,
            semanticResolved: semanticResolved,
            outcome: outcome,
            context: context
           ) {
            switch composite {
            case .handled(let card):
                let execution = MarinaQueryExecution(
                    executablePlan: nil,
                    aggregationResult: .workspaceCard(card),
                    databaseLookupResponse: nil,
                    workspaceAggregationCard: card,
                    amountBasis: .budgetImpact,
                    executionRoute: .scenario
                )
                let answer = answerWithEvidence(
                    responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult),
                    execution: execution,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    metricContract: metricContractResolution?.contract
                )
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: traceInterpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: outcome,
                    execution: execution
                )
                return .handled(
                    answer: answer,
                    aggregationResult: execution.aggregationResult,
                    homeQueryPlan: nil,
                    amountBasis: execution.amountBasis,
                    executionRoute: execution.executionRoute
                )
            case .clarification(let clarification):
                let clarificationOutcome = MarinaPlanValidationOutcome.clarification(clarification)
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: traceInterpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: clarificationOutcome,
                    execution: nil
                )
                return .clarification(
                    answer: responseBuilder.aggregationBridge.responseCompatibleAnswer(from: clarification),
                    clarification: clarification
                )
            }
        }

        if isLegacyAdapter,
           case .unsupported = outcome,
           let clarification = conversationalPlanner.clarification(
            candidate: candidate,
            outcome: outcome,
            context: context,
            explicitConstraints: MarinaExplicitConstraintDetector().constraints(
                in: prompt,
                context: context.routerContext
            )
           ) {
            let clarificationOutcome = MarinaPlanValidationOutcome.clarification(clarification)
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: traceInterpretation,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: clarificationOutcome,
                execution: nil
            )
            return .clarification(
                answer: responseBuilder.aggregationBridge.responseCompatibleAnswer(from: clarification),
                clarification: clarification
            )
        }

        if isTokenizedReadRequest == false,
           isPipelineAuditInterpretation == false {
            switch answerPlanner.plan(
                prompt: prompt,
                interpretation: interpretation,
                candidate: candidate,
                outcome: outcome,
                context: context
            ) {
            case .execute(.universal(let universalQuery), metadata: _, reason: let reason):
                return evaluateUniversal(
                    universalQuery,
                    reason: reason,
                    traceInterpretation: traceInterpretation,
                    candidate: candidate,
                    resolved: resolved,
                    context: context
                )
            case .execute(.formula(let formulaIR), metadata: _, reason: _):
                let card = MarinaFormulaExecutor().execute(
                    formulaIR: formulaIR,
                    candidate: candidate,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    context: context
                )
                let execution = MarinaQueryExecution(
                    executablePlan: nil,
                    aggregationResult: .workspaceCard(card),
                    databaseLookupResponse: nil,
                    workspaceAggregationCard: card,
                    amountBasis: .budgetImpact,
                    executionRoute: .scenario
                )
                let answer = answerWithEvidence(
                    responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult),
                    execution: execution,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    metricContract: nil
                )
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: traceInterpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: outcome,
                    execution: execution
                )
                return .handled(
                    answer: answer,
                    aggregationResult: execution.aggregationResult,
                    homeQueryPlan: nil,
                    amountBasis: execution.amountBasis,
                    executionRoute: execution.executionRoute
                )
            case .clarify, .refuse, .original:
                break
            }
        }

        switch outcome {
        case .clarification(let clarification):
            let actionableChoices = clarification.actionableChoices
            if allowSingleChoiceAutoResolve,
               actionableChoices.count == 1,
               let choice = actionableChoices.first,
               isResolverBacked(choice),
               let resumedInterpretation = interpretationByApplying(
                choice: choice,
                to: clarification,
                context: context
               ) {
                let resumedResult = evaluateLinear(
                    MarinaTurnInterpretation(
                        result: resumedInterpretation.result,
                        compatibilityCandidate: resumedInterpretation.compatibilityCandidate,
                        repairSummary: resumedInterpretation.repairSummary,
                        generatedSchemaName: interpretation.generatedSchemaName
                    ),
                    prompt: prompt,
                    context: context,
                    allowSingleChoiceAutoResolve: false
                )
                if case .handled = resumedResult {
                    return resumedResult
                }
            }

            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: traceInterpretation,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                execution: nil
            )
            guard actionableChoices.count > 1 else {
                return .blocked(
                    answer: Self.malformedClarificationAnswer(
                        prompt: candidate.rawPrompt,
                        clarification: clarification
                    ),
                    validationOutcome: outcome
                )
            }
            return .clarification(
                answer: responseBuilder.aggregationBridge.responseCompatibleAnswer(from: clarification),
                clarification: clarification
            )
        case .unsupported:
            if let auditedInterpretation = lateAuditInterpretation {
                return evaluateLinear(
                    preservingInterpreterSource(
                        in: auditedInterpretation,
                        originalSource: candidate.source
                    ),
                    prompt: prompt,
                    context: context,
                    allowSingleChoiceAutoResolve: allowSingleChoiceAutoResolve
                )
            }
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: traceInterpretation,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                execution: nil
            )
            return .blocked(
                answer: responseBuilder.responseCompatibleAnswer(from: outcome) ?? Self.blockedAnswer(
                    prompt: candidate.rawPrompt,
                    title: "Marina cannot run that yet",
                    message: "That request is outside Marina's safe read model."
                ),
                validationOutcome: outcome
            )
        case .executable:
            switch queryExecutor.execute(
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                provider: context.provider,
                now: context.now
            ) {
            case .handled(let execution):
                let baseAnswer = execution.databaseLookupResponse.map {
                    MarinaDatabaseLookupResponseBuilder().responseCompatibleAnswer(from: $0)
                } ?? responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult)
                let answer = answerWithEvidence(
                    baseAnswer,
                    execution: execution,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    metricContract: metricContractResolution?.contract
                )
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: traceInterpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: outcome,
                    execution: execution
                )
                return .handled(
                    answer: answer,
                    aggregationResult: execution.aggregationResult,
                    homeQueryPlan: execution.executablePlan?.homeQueryPlan,
                    amountBasis: execution.amountBasis,
                    executionRoute: execution.executionRoute
                )
            case .unsupported(let unsupported):
                let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: traceInterpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: blockedOutcome,
                    execution: nil
                )
                return .blocked(
                    answer: responseBuilder.responseCompatibleAnswer(from: blockedOutcome) ?? Self.blockedAnswer(
                        prompt: candidate.rawPrompt,
                        title: "Marina cannot run that yet",
                        message: unsupported.message
                    ),
                    validationOutcome: blockedOutcome
                )
            }
        }
    }

    private func tokenizedUniversalPreflightResult(
        traceInterpretation: MarinaCanonicalReadInterpretation,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        context: MarinaTurnContext
    ) -> MarinaTurnResult? {
        let outcome: MarinaPlanValidationOutcome?
        if candidate.confidence == .low {
            outcome = .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedCombination,
                    message: "That query is too uncertain to validate safely.",
                    candidate: candidate
                )
            )
        } else if let mutationViolation = MarinaRoutePatternRegistry.isReadOnlyStep5Mutation(candidate.rawPrompt) {
            outcome = .unsupported(
                MarinaTypedUnsupportedResponse(
                    kind: .unsupportedOperation,
                    message: mutationViolation.message,
                    candidate: candidate
                )
            )
        } else if let ambiguous = resolved.ambiguousMentions.first {
            outcome = .clarification(
                MarinaTypedClarification(
                    kind: .ambiguousTarget,
                    message: "I found multiple possible matches for that target.",
                    candidate: candidate,
                    patchSlot: .target,
                    choices: ambiguous.choices
                )
            )
        } else if let unresolved = resolved.unresolvedMentions.first {
            outcome = .clarification(
                MarinaTypedClarification(
                    kind: .missingTarget,
                    message: "I couldn't safely resolve that target.",
                    candidate: candidate,
                    patchSlot: .target,
                    choices: [
                        MarinaClarificationChoice(
                            title: unresolved.rawText ?? "Target",
                            entityRole: unresolved.role,
                            entityTypeHint: unresolved.typeHint,
                            patchSlot: .target,
                            rawValue: unresolved.rawText,
                            mentionID: unresolved.id
                        )
                    ]
                )
            )
        } else {
            outcome = nil
        }

        guard let outcome else { return nil }
        MarinaFoundationTraceBridge.record(
            context: context,
            interpretation: traceInterpretation,
            resolved: resolved,
            semanticResolved: semanticResolved,
            validationOutcome: outcome,
            execution: nil
        )

        switch outcome {
        case .clarification(let clarification):
            return .clarification(
                answer: responseBuilder.aggregationBridge.responseCompatibleAnswer(from: clarification),
                clarification: clarification
            )
        case .unsupported(let unsupported):
            return .blocked(
                answer: responseBuilder.responseCompatibleAnswer(from: outcome) ?? Self.blockedAnswer(
                    prompt: candidate.rawPrompt,
                    title: "Marina cannot run that yet",
                    message: unsupported.message
                ),
                validationOutcome: outcome
            )
        case .executable:
            return nil
        }
    }

    private func resultForDroppedExplicitConstraints(
        explicitConstraints: MarinaExplicitPromptConstraints,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        outcome: MarinaPlanValidationOutcome,
        context: MarinaTurnContext,
        traceInterpretation: MarinaCanonicalReadInterpretation
    ) -> MarinaTurnResult? {
        guard let unsupported = explicitConstraints.unsupportedIfDropped(
            by: candidate,
            resolvedQuery: semanticResolved,
            outcome: outcome
        ) else {
            return nil
        }

        if let clarification = conversationalPlanner.clarificationForDroppedConstraints(
            candidate: candidate,
            context: context,
            explicitConstraints: explicitConstraints,
            unsupported: unsupported
        ) {
            let clarificationOutcome = MarinaPlanValidationOutcome.clarification(clarification)
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: traceInterpretation,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: clarificationOutcome,
                execution: nil
            )
            return .clarification(
                answer: responseBuilder.aggregationBridge.responseCompatibleAnswer(from: clarification),
                clarification: clarification
            )
        }

        let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
        MarinaFoundationTraceBridge.record(
            context: context,
            interpretation: traceInterpretation,
            resolved: resolved,
            semanticResolved: semanticResolved,
            validationOutcome: blockedOutcome,
            execution: nil
        )
        return .blocked(
            answer: responseBuilder.responseCompatibleAnswer(from: blockedOutcome) ?? Self.blockedAnswer(
                prompt: candidate.rawPrompt,
                title: "That dropped a constraint",
                message: unsupported.message
            ),
            validationOutcome: blockedOutcome
        )
    }

    private func isSimpleUniversalRead(_ query: MarinaUniversalQueryIR) -> Bool {
        switch query.operation {
        case .lookup, .list, .count, .detail:
            return true
        case .sum, .average, .minimum, .maximum, .rank, .groupBreakdown, .compare, .simulate:
            return false
        }
    }

    private func isTokenizedReadRequest(_ interpretation: MarinaTurnInterpretation) -> Bool {
        interpretation.generatedSchemaName == MarinaFoundationLiveContractRegistry.liveGeneratedSchemaName
            && interpretation.repairSummary?.contains("tokenizedReadRequest") == true
            && isMalformedTokenizedReadRequest(interpretation) == false
    }

    private func isMalformedTokenizedReadRequest(_ interpretation: MarinaTurnInterpretation) -> Bool {
        interpretation.generatedSchemaName == MarinaFoundationLiveContractRegistry.liveGeneratedSchemaName
            && interpretation.repairSummary?.contains("tokenizedReadRequest:malformed") == true
    }

    private func shouldAttemptLateAuditRecovery(
        interpretation: MarinaTurnInterpretation,
        candidate: MarinaQueryPlanCandidate,
        isTokenizedReadRequest: Bool,
        isPipelineAuditInterpretation: Bool
    ) -> Bool {
        guard isTokenizedReadRequest == false,
              isPipelineAuditInterpretation == false,
              interpretation.generatedSchemaName != "legacyCanonicalAdapter",
              candidate.source == .foundationModels else {
            return false
        }
        if case .unsupported = interpretation.result {
            return true
        }
        return false
    }

    private func shouldAttemptCanonicalRewrite(_ interpretation: MarinaTurnInterpretation) -> Bool {
        switch interpretation.result {
        case .query:
            return false
        case .clarification, .unsupported:
            return true
        }
    }

    private func malformedFoundationRecoveryInterpretation(
        prompt: String,
        interpretation: MarinaTurnInterpretation?,
        candidate: MarinaQueryPlanCandidate?,
        context: MarinaTurnContext,
        diagnostic: MarinaFoundationModelsFailureDiagnostic
    ) -> MarinaTurnInterpretation? {
        let priorInterpretation = interpretation.map {
            MarinaCanonicalReadInterpretation(
                result: $0.result,
                compatibilityCandidate: candidate ?? compatibilityCandidate(for: $0, prompt: prompt),
                repairSummary: $0.repairSummary
            )
        }
        let auditedInterpretation = pipelineAuditCanonicalizer.interpretation(
            prompt: prompt,
            context: context
        )

        if interpretation != nil,
           let contractInterpretation = semanticContractResolver.resolve(
            prompt: prompt,
            context: context,
            priorInterpretation: priorInterpretation,
            failureDiagnostic: diagnostic
        ) {
            if let auditedInterpretation,
               shouldPreferAuditRecovery(over: contractInterpretation) {
                return preservingInterpreterSource(
                    in: MarinaTurnInterpretation(
                        result: auditedInterpretation.result,
                        compatibilityCandidate: auditedInterpretation.compatibilityCandidate,
                        repairSummary: malformedFoundationRecoverySummary(
                            original: interpretation?.repairSummary,
                            recovery: auditedInterpretation.repairSummary,
                            diagnostic: diagnostic
                        ),
                        generatedSchemaName: auditedInterpretation.generatedSchemaName
                    ),
                    originalSource: .foundationModels
                )
            }
            return MarinaTurnInterpretation(
                result: contractInterpretation.result,
                compatibilityCandidate: contractInterpretation.compatibilityCandidate,
                repairSummary: malformedFoundationRecoverySummary(
                    original: interpretation?.repairSummary,
                    recovery: contractInterpretation.repairSummary,
                    diagnostic: diagnostic
                ),
                generatedSchemaName: "malformedTokenizedContractRecovery"
            )
        }

        if let auditedInterpretation {
            return preservingInterpreterSource(
                in: MarinaTurnInterpretation(
                    result: auditedInterpretation.result,
                    compatibilityCandidate: auditedInterpretation.compatibilityCandidate,
                    repairSummary: malformedFoundationRecoverySummary(
                        original: interpretation?.repairSummary,
                        recovery: auditedInterpretation.repairSummary,
                        diagnostic: diagnostic
                    ),
                    generatedSchemaName: auditedInterpretation.generatedSchemaName
                ),
                originalSource: .foundationModels
            )
        }

        guard let deterministicInterpretation = canonicalQueryRewriter.deterministicInterpretation(
            prompt: prompt,
            context: context
        ) else {
            return nil
        }

        return preservingInterpreterSource(
            in: MarinaTurnInterpretation(
                result: deterministicInterpretation.result,
                compatibilityCandidate: deterministicInterpretation.compatibilityCandidate,
                repairSummary: malformedFoundationRecoverySummary(
                    original: interpretation?.repairSummary,
                    recovery: deterministicInterpretation.repairSummary,
                    diagnostic: diagnostic
                ),
                generatedSchemaName: "malformedTokenizedCanonicalRecovery"
            ),
            originalSource: .foundationModels
        )
    }

    private func shouldPreferAuditRecovery(over contractInterpretation: MarinaCanonicalReadInterpretation) -> Bool {
        guard let summary = contractInterpretation.repairSummary else { return false }
        return summary.contains("semanticContract=categorySpendRanking")
            || summary.contains("semanticContract=freeTextExpenseRows")
    }

    private func malformedFoundationRecoverySummary(
        original: String?,
        recovery: String?,
        diagnostic: MarinaFoundationModelsFailureDiagnostic
    ) -> String {
        [
            nonBlank(original),
            "foundationFailure=\(diagnostic.category.rawValue)",
            "foundationStep=\(diagnostic.step.rawValue)",
            nonBlank(recovery)
        ]
        .compactMap { $0 }
            .joined(separator: ";")
    }

    private func shouldRecoverDecodingFailureWithAudit(_ interpretation: MarinaTurnInterpretation) -> Bool {
        guard let summary = interpretation.repairSummary else { return false }
        return summary.contains("pipelineAudit=")
            && summary.contains("pipelineAudit=categorySpend") == false
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private func preservingInterpreterSource(
        in interpretation: MarinaTurnInterpretation,
        originalSource: MarinaInterpretationSource
    ) -> MarinaTurnInterpretation {
        guard originalSource == .foundationModels,
              let candidate = interpretation.compatibilityCandidate else {
            return interpretation
        }
        return MarinaTurnInterpretation(
            result: interpretation.result,
            compatibilityCandidate: candidate.replacingSource(originalSource),
            repairSummary: interpretation.repairSummary,
            generatedSchemaName: interpretation.generatedSchemaName
        )
    }

    private func evaluateUniversal(
        _ query: MarinaUniversalQueryIR,
        reason: String,
        traceInterpretation: MarinaCanonicalReadInterpretation,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        context: MarinaTurnContext,
        includeTokenizedEvidence: Bool = false
    ) -> MarinaTurnResult {
        let outcome = MarinaPlanValidationOutcome.executable(
            MarinaAggregationPlan(
                operation: candidateOperation(for: query.operation),
                measure: candidateMeasure(for: query),
                dateRange: query.dateRange,
                grouping: groupingCandidate(for: query.grouping),
                ranking: query.ranking.map { MarinaRankingCandidate(direction: $0, limit: query.limit, rawText: query.grouping) },
                limit: query.limit,
                responseShape: responseShapeHint(for: query.presentationShape)
            )
        )

        switch universalQueryExecutor.execute(query, provider: context.provider) {
        case .handled(let card):
            let route = executionRoute(for: query.operation)
            let execution = MarinaQueryExecution(
                executablePlan: nil,
                aggregationResult: .workspaceCard(card),
                databaseLookupResponse: nil,
                workspaceAggregationCard: card,
                amountBasis: amountBasis(for: query),
                executionRoute: route
            )
            let answer = answerWithEvidence(
                responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult),
                execution: execution,
                resolved: resolved,
                semanticResolved: nil,
                metricContract: nil,
                includeTokenizedEvidence: includeTokenizedEvidence
            )
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: MarinaCanonicalReadInterpretation(
                    result: traceInterpretation.result,
                    compatibilityCandidate: traceInterpretation.compatibilityCandidate,
                    repairSummary: [traceInterpretation.repairSummary, reason].compactMap { $0 }.joined(separator: ";")
                ),
                resolved: resolved,
                semanticResolved: nil,
                validationOutcome: outcome,
                execution: execution
            )
            return .handled(
                answer: answer,
                aggregationResult: execution.aggregationResult,
                homeQueryPlan: nil,
                amountBasis: execution.amountBasis,
                executionRoute: execution.executionRoute
            )
        case .unsupported(let unsupported):
            let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: traceInterpretation,
                resolved: resolved,
                semanticResolved: nil,
                validationOutcome: blockedOutcome,
                execution: nil
            )
            return .blocked(
                answer: responseBuilder.responseCompatibleAnswer(from: blockedOutcome) ?? Self.blockedAnswer(
                    prompt: candidate.rawPrompt,
                    title: "Marina cannot run that yet",
                    message: unsupported.message
                ),
                validationOutcome: blockedOutcome
            )
        }
    }

    private func compatibilityCandidate(
        for interpretation: MarinaTurnInterpretation,
        prompt: String
    ) -> MarinaQueryPlanCandidate {
        if let candidate = interpretation.compatibilityCandidate {
            return candidate
        }
        switch interpretation.result {
        case .query(let query):
            return semanticAdapter.compatibilityCandidate(from: query, prompt: prompt)
        case .clarification(let clarification):
            return clarification.candidate ?? MarinaQueryPlanCandidate(
                source: .foundationModels,
                rawPrompt: prompt,
                responseShapeHint: .clarification,
                confidence: .medium
            )
        case .unsupported(let unsupported):
            return unsupported.candidate ?? MarinaQueryPlanCandidate(
                source: .foundationModels,
                rawPrompt: prompt,
                responseShapeHint: .unsupported,
                confidence: .medium,
                unsupportedHint: .unsupportedOperation
            )
        }
    }

    private func semanticMetricContractResolution(
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        outcome: MarinaPlanValidationOutcome
    ) -> MarinaMetricContractResolution? {
        if let id = semanticResolved?.query.metricContractID,
           let contract = MarinaMetricContractRegistry.current.contract(for: id) {
            return MarinaMetricContractResolution(contract: contract, match: .semanticShape)
        }

        let routeKind = semanticResolved?.query.routeIntent?.kind ?? candidate.routeIntent?.kind
        if routeKind == .incomePlannedVsActual,
           let contract = MarinaMetricContractRegistry.current.contract(for: .incomeActualVsExpected) {
            return MarinaMetricContractResolution(contract: contract, match: .routeIntent)
        }

        let targets = resolved.resolvedTargets
            + (semanticResolved?.resolvedFilters.map { filter in
                MarinaResolvedEntityMention(
                    id: filter.id,
                    mention: MarinaUnresolvedEntityMention(
                        role: MarinaEntityMentionRole(rawValue: filter.role.rawValue) ?? .filter,
                        rawText: filter.displayName,
                        typeHint: filter.entityType
                    ),
                    role: filter.role,
                    entityType: filter.entityType,
                    displayName: filter.displayName,
                    sourceID: filter.sourceID
                )
            } ?? [])

        let planMeasure: MarinaCandidateMeasure? = {
            guard case .executable(let plan) = outcome else { return nil }
            return plan.measure
        }()

        if (candidate.measure == .spend || planMeasure == .spend),
           targets.contains(where: { $0.entityType == .allocationAccount }),
           targets.contains(where: { [.category, .merchant, .card, .preset, .transaction, .expense].contains($0.entityType) }),
           let contract = MarinaMetricContractRegistry.current.contract(for: .allocatedCategorySpend) {
            return MarinaMetricContractResolution(contract: contract, match: .semanticShape)
        }

        if candidate.measure == .income || planMeasure == .income,
           semanticResolved?.query.incomeStatusScope == .all,
           let contract = MarinaMetricContractRegistry.current.contract(for: .incomeActualVsExpected) {
            return MarinaMetricContractResolution(contract: contract, match: .semanticShape)
        }

        return nil
    }

    private func evaluate(
        _ interpretation: MarinaCanonicalReadInterpretation,
        context: MarinaTurnContext,
        explicitConstraints: MarinaExplicitPromptConstraints,
        allowSingleChoiceAutoResolve: Bool = true
    ) -> MarinaTurnResult {
        let candidate = interpretation.compatibilityCandidate
        let resolved = resolver.resolve(
            candidate: candidate,
            provider: context.provider,
            now: context.now,
            defaultPeriodUnit: context.defaultPeriodUnit
        )

        let semanticResolved: MarinaResolvedSemanticQuery?
        let outcome: MarinaPlanValidationOutcome

        switch interpretation.result {
        case .query(let query):
            let resolvedQuery = resolver.resolve(
                query: query,
                provider: context.provider,
                candidate: candidate,
                now: context.now,
                defaultPeriodUnit: context.defaultPeriodUnit
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

        let metricContractResolution = metricContractResolver.resolve(
            candidate: candidate,
            resolved: resolved,
            semanticResolved: semanticResolved,
            outcome: outcome
        )

        if let metricContractResolution {
            switch metricFormulaExecutor.execute(
                contract: metricContractResolution.contract,
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                context: context
            ) {
            case .handled(let card, let amountBasis, let route):
                let execution = MarinaQueryExecution(
                    executablePlan: nil,
                    aggregationResult: .workspaceCard(card),
                    databaseLookupResponse: nil,
                    workspaceAggregationCard: card,
                    amountBasis: amountBasis,
                    executionRoute: route
                )
                let answer = answerWithEvidence(
                    responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult),
                    execution: execution,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    metricContract: metricContractResolution.contract
                )
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: interpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: outcome,
                    execution: execution
                )
                return .handled(
                    answer: answer,
                    aggregationResult: execution.aggregationResult,
                    homeQueryPlan: nil,
                    amountBasis: execution.amountBasis,
                    executionRoute: execution.executionRoute
                )
            case .blocked(let answer, let unsupported):
                let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: interpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: blockedOutcome,
                    execution: nil
                )
                return .blocked(answer: answer, validationOutcome: blockedOutcome)
            case .notHandled:
                if metricContractResolution.isDirectFormulaSummon {
                    let answer = metricContractResponseBuilder.summonedFormulaAnswer(
                        contract: metricContractResolution.contract,
                        candidate: candidate
                    )
                    let unsupported = metricContractResponseBuilder.summonedFormulaUnsupportedResponse(
                        contract: metricContractResolution.contract,
                        candidate: candidate
                    )
                    let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                    MarinaFoundationTraceBridge.record(
                        context: context,
                        interpretation: interpretation,
                        resolved: resolved,
                        semanticResolved: semanticResolved,
                        validationOutcome: blockedOutcome,
                        execution: nil
                    )
                    return .blocked(answer: answer, validationOutcome: blockedOutcome)
                }
                break
            }
        }

        if let metricContractResolution,
           metricContractResolution.shouldBlockExecution {
            let blocked = metricContractResponseBuilder.unsupportedResponse(
                contract: metricContractResolution.contract,
                candidate: candidate
            )
            let blockedOutcome = MarinaPlanValidationOutcome.unsupported(blocked)
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: interpretation,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: blockedOutcome,
                execution: nil
            )
            return .blocked(
                answer: metricContractResponseBuilder.unsupportedAnswer(
                    contract: metricContractResolution.contract,
                    candidate: candidate
                ),
                validationOutcome: blockedOutcome
            )
        }

        if let composite = compositePlanner.plan(
            candidate: candidate,
            resolved: resolved,
            semanticResolved: semanticResolved,
            outcome: outcome,
            context: context
        ) {
            switch composite {
            case .handled(let card):
                let execution = MarinaQueryExecution(
                    executablePlan: nil,
                    aggregationResult: .workspaceCard(card),
                    databaseLookupResponse: nil,
                    workspaceAggregationCard: card,
                    amountBasis: .budgetImpact,
                    executionRoute: .scenario
                )
                let answer = answerWithEvidence(
                    responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult),
                    execution: execution,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    metricContract: metricContractResolution?.contract
                )
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: interpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: outcome,
                    execution: execution
                )
                return .handled(
                    answer: answer,
                    aggregationResult: execution.aggregationResult,
                    homeQueryPlan: nil,
                    amountBasis: execution.amountBasis,
                    executionRoute: execution.executionRoute
                )
            case .clarification(let clarification):
                let clarificationOutcome = MarinaPlanValidationOutcome.clarification(clarification)
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: interpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: clarificationOutcome,
                    execution: nil
                )
                return .clarification(
                    answer: responseBuilder.aggregationBridge.responseCompatibleAnswer(from: clarification),
                    clarification: clarification
                )
            }
        }

        if let unsupported = explicitConstraints.unsupportedIfDropped(
            by: candidate,
            resolvedQuery: semanticResolved,
            outcome: outcome
        ) {
            if let clarification = conversationalPlanner.clarificationForDroppedConstraints(
                candidate: candidate,
                context: context,
                explicitConstraints: explicitConstraints,
                unsupported: unsupported
            ) {
                let clarificationOutcome = MarinaPlanValidationOutcome.clarification(clarification)
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: interpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: clarificationOutcome,
                    execution: nil
                )
                return .clarification(
                    answer: responseBuilder.aggregationBridge.responseCompatibleAnswer(from: clarification),
                    clarification: clarification
                )
            }
            let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: interpretation,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: blockedOutcome,
                execution: nil
            )
            return .blocked(
                answer: responseBuilder.responseCompatibleAnswer(from: blockedOutcome) ?? Self.blockedAnswer(
                    prompt: candidate.rawPrompt,
                    title: "That dropped a constraint",
                    message: unsupported.message
                ),
                validationOutcome: blockedOutcome
            )
        }

        if let clarification = conversationalPlanner.clarification(
            candidate: candidate,
            outcome: outcome,
            context: context,
            explicitConstraints: explicitConstraints
        ) {
            let clarificationOutcome = MarinaPlanValidationOutcome.clarification(clarification)
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: interpretation,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: clarificationOutcome,
                execution: nil
            )
            return .clarification(
                answer: responseBuilder.aggregationBridge.responseCompatibleAnswer(from: clarification),
                clarification: clarification
            )
        }

        switch outcome {
        case .clarification(let clarification):
            let actionableChoices = clarification.actionableChoices
            if allowSingleChoiceAutoResolve,
               actionableChoices.count == 1,
               let choice = actionableChoices.first,
               isResolverBacked(choice),
               let resumedInterpretation = interpretationByApplying(
                choice: choice,
                to: clarification,
                context: context
               ) {
                let resumedResult = evaluate(
                    resumedInterpretation,
                    context: context,
                    explicitConstraints: explicitConstraints,
                    allowSingleChoiceAutoResolve: false
                )
                if case .handled = resumedResult {
                    return resumedResult
                }
            }

            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: interpretation,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                execution: nil
            )
            guard actionableChoices.count > 1 else {
                return .blocked(
                    answer: Self.malformedClarificationAnswer(
                        prompt: candidate.rawPrompt,
                        clarification: clarification
                    ),
                    validationOutcome: outcome
                )
            }
            return .clarification(
                answer: responseBuilder.aggregationBridge.responseCompatibleAnswer(from: clarification),
                clarification: clarification
            )
        case .unsupported:
            MarinaFoundationTraceBridge.record(
                context: context,
                interpretation: interpretation,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                execution: nil
            )
            return .blocked(
                answer: responseBuilder.responseCompatibleAnswer(from: outcome) ?? Self.blockedAnswer(
                    prompt: candidate.rawPrompt,
                    title: "Marina cannot run that yet",
                    message: "That request is outside Marina's safe read model."
                ),
                validationOutcome: outcome
            )
        case .executable:
            switch queryExecutor.execute(
                candidate: candidate,
                resolved: resolved,
                semanticResolved: semanticResolved,
                validationOutcome: outcome,
                provider: context.provider,
                now: context.now
            ) {
            case .handled(let execution):
                let baseAnswer = execution.databaseLookupResponse.map {
                    MarinaDatabaseLookupResponseBuilder().responseCompatibleAnswer(from: $0)
                } ?? responseBuilder.responseCompatibleAnswer(from: execution.aggregationResult)
                let answer = answerWithEvidence(
                    baseAnswer,
                    execution: execution,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    metricContract: metricContractResolution?.contract
                )
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: interpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: outcome,
                    execution: execution
                )
                return .handled(
                    answer: answer,
                    aggregationResult: execution.aggregationResult,
                    homeQueryPlan: execution.executablePlan?.homeQueryPlan,
                    amountBasis: execution.amountBasis,
                    executionRoute: execution.executionRoute
                )
            case .unsupported(let unsupported):
                let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
                MarinaFoundationTraceBridge.record(
                    context: context,
                    interpretation: interpretation,
                    resolved: resolved,
                    semanticResolved: semanticResolved,
                    validationOutcome: blockedOutcome,
                    execution: nil
                )
                return .blocked(
                    answer: responseBuilder.responseCompatibleAnswer(from: blockedOutcome) ?? Self.blockedAnswer(
                        prompt: candidate.rawPrompt,
                        title: "Marina cannot run that yet",
                        message: unsupported.message
                    ),
                    validationOutcome: blockedOutcome
                )
            }
        }
    }

    private func isResolverBacked(_ choice: MarinaClarificationChoice) -> Bool {
        choice.sourceID != nil || choice.resumeIntent != nil
    }

    private func executionRoute(for plan: MarinaAggregationPlan) -> MarinaSemanticExecutionRoute {
        switch plan.operation {
        case .compare:
            return plan.grouping == nil ? .comparison : .groupedRanked
        case .rank:
            return .groupedRanked
        case .listRows, .lookupDetails:
            return plan.operation == .lookupDetails ? .lookupDetail : .list
        case .trend:
            return .groupedRanked
        case .simulate, .forecast:
            return .scenario
        case .sum, .average, .count, .minimum, .maximum:
            return plan.grouping == nil ? .aggregate : .groupedRanked
        }
    }

    private func executionRoute(for operation: MarinaUniversalQueryOperation) -> MarinaSemanticExecutionRoute {
        switch operation {
        case .lookup, .detail:
            return .lookupDetail
        case .list:
            return .list
        case .rank, .groupBreakdown:
            return .groupedRanked
        case .compare:
            return .comparison
        case .simulate:
            return .scenario
        case .count, .sum, .average, .minimum, .maximum:
            return .aggregate
        }
    }

    private func candidateOperation(for operation: MarinaUniversalQueryOperation) -> MarinaCandidateOperation {
        switch operation {
        case .lookup, .detail:
            return .lookupDetails
        case .list:
            return .listRows
        case .count:
            return .count
        case .sum:
            return .sum
        case .average:
            return .average
        case .minimum:
            return .minimum
        case .maximum:
            return .maximum
        case .rank, .groupBreakdown:
            return .rank
        case .compare:
            return .compare
        case .simulate:
            return .simulate
        }
    }

    private func candidateMeasure(for query: MarinaUniversalQueryIR) -> MarinaCandidateMeasure {
        switch query.modelName {
        case "Income", "IncomeSeries":
            return .income
        case "SavingsAccount":
            return .savings
        case "SavingsLedgerEntry":
            return .savingsMovement
        case "AllocationAccount", "AllocationSettlement", "ExpenseAllocation":
            return .reconciliationBalance
        case "Preset", "PlannedExpense", "BudgetCategoryLimit":
            return .presetAmount
        case "VariableExpense", "Virtual: Merchant":
            return .spend
        default:
            return .transactionAmount
        }
    }

    private func amountBasis(for query: MarinaUniversalQueryIR) -> MarinaFinancialAmountBasis {
        switch query.amountBasis {
        case .budgetImpactAmount:
            return .budgetImpact
        case .ledgerSignedAmount:
            return .ledgerSigned
        case .spendingAmount:
            return .debitSpend
        case .effectivePlannedAmount:
            return .plannedEffectiveAmount
        case .plannedAmount:
            return .plannedAmount
        case .actualAmount:
            return .recordedActualAmount
        case .incomeAmount:
            return .actualIncome
        case .savingsAmount:
            return query.modelName == "SavingsAccount" ? .savingsRunningTotal : .savingsMovement
        case .allocatedAmount:
            return .allocated
        case .reconciliationBalance:
            return .reconciliationBalance
        case .amount, nil:
            return query.operation == .count || (query.operation == .list && query.amountBasis == nil) ? .count : .gross
        }
    }

    private func groupingCandidate(for grouping: String?) -> MarinaGroupingCandidate? {
        guard let grouping else { return nil }
        switch grouping.lowercased() {
        case "category":
            return MarinaGroupingCandidate(dimension: .category, rawText: grouping)
        case "card":
            return MarinaGroupingCandidate(dimension: .card, rawText: grouping)
        case "source", "income source":
            return MarinaGroupingCandidate(dimension: .incomeSource, rawText: grouping)
        case "account":
            return MarinaGroupingCandidate(dimension: .allocationAccount, rawText: grouping)
        case "kind", "type":
            return MarinaGroupingCandidate(dimension: .transaction, rawText: grouping)
        default:
            return nil
        }
    }

    private func responseShapeHint(for shape: MarinaResponseShape) -> MarinaResponseShapeHint {
        switch shape {
        case .scalarCurrency:
            return .scalarCurrency
        case .summaryCard:
            return .summaryCard
        case .relationshipList:
            return .relationshipList
        case .membershipStatus:
            return .membershipStatus
        case .comparison:
            return .comparison
        case .rankedList:
            return .rankedList
        case .groupedBreakdown:
            return .groupedBreakdown
        case .chartRows:
            return .chartRows
        case .clarification:
            return .clarification
        case .unsupported:
            return .unsupported
        }
    }

    private func interpretationByApplying(
        choice: MarinaClarificationChoice,
        to clarification: MarinaTypedClarification,
        context: MarinaTurnContext
    ) -> MarinaCanonicalReadInterpretation? {
        guard let candidate = clarification.candidate else { return nil }

        let resumedCandidate = candidate.replacingClarifiedMention(with: choice)
        let result: MarinaInterpretationResult
        let compatibilityCandidate: MarinaQueryPlanCandidate

        if let resumeInterpretation = interpretation(from: choice.resumeIntent, fallbackCandidate: resumedCandidate) {
            return resumeInterpretation
        } else if let databaseLookupCandidate = resumedCandidate.replacingDatabaseLookupRequest(
            with: choice,
            fallbackRequest: candidate.databaseLookupRequest
        ) {
            compatibilityCandidate = databaseLookupCandidate
            result = semanticAdapter.interpretationResult(from: databaseLookupCandidate)
        } else if let pendingSemanticQuery = clarification.pendingSemanticQuery,
                  let patchedQuery = pendingSemanticQuery.patching(
                    choice: choice,
                    fallbackSlot: clarification.patchSlot,
                    now: context.now,
                    defaultPeriodUnit: context.defaultPeriodUnit
                  ) {
            compatibilityCandidate = resumedCandidate
            result = .query(patchedQuery)
        } else {
            compatibilityCandidate = resumedCandidate
            result = semanticAdapter.interpretationResult(from: resumedCandidate)
        }

        return MarinaCanonicalReadInterpretation(
            result: result,
            compatibilityCandidate: compatibilityCandidate,
            repairSummary: "autoAppliedSingleClarification"
        )
    }

    private func interpretation(
        from resumeIntent: MarinaClarificationResumeIntent?,
        fallbackCandidate: MarinaQueryPlanCandidate
    ) -> MarinaCanonicalReadInterpretation? {
        guard let resumeIntent else { return nil }
        let compatibilityCandidate = resumeIntent.candidate ?? fallbackCandidate
        let result: MarinaInterpretationResult
        if let semanticQuery = resumeIntent.semanticQuery {
            result = .query(semanticQuery)
        } else {
            result = semanticAdapter.interpretationResult(from: compatibilityCandidate)
        }
        return MarinaCanonicalReadInterpretation(
            result: result,
            compatibilityCandidate: compatibilityCandidate,
            repairSummary: "clarificationResumeIntent"
        )
    }

    private func answerWithEvidence(
        _ answer: HomeAnswer,
        execution: MarinaQueryExecution,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        metricContract: MarinaMetricContract? = nil,
        includeTokenizedEvidence: Bool = false
    ) -> HomeAnswer {
        var evidenceRows: [HomeAnswerRow] = []
        if let metricContract {
            evidenceRows.append(contentsOf: metricContractResponseBuilder.evidenceRows(for: metricContract))
        }
        evidenceRows.append(HomeAnswerRow(title: "Amount basis", value: displayName(for: execution.amountBasis), role: .trace))
        evidenceRows.append(HomeAnswerRow(title: "Execution route", value: execution.executionRoute.traceName, role: .trace))
        if includeTokenizedEvidence,
           let universalQuery = resolved.candidate.universalQuery {
            evidenceRows.append(HomeAnswerRow(title: "Why this answer?", value: "model=\(universalQuery.modelName), operation=\(universalQuery.operation.rawValue), scope=\(universalQuery.workspaceScopePolicy.rawValue)", role: .trace))
            evidenceRows.append(HomeAnswerRow(title: "Row type", value: universalQuery.evidenceRowType, role: .trace))
            evidenceRows.append(HomeAnswerRow(title: "Model tokens", value: tokenSummary(for: universalQuery), role: .trace))
            evidenceRows.append(HomeAnswerRow(title: "Trace ID", value: answer.queryID.uuidString, role: .trace))
        }

        let targets = resolved.resolvedTargets.map(\.displayName)
            + (semanticResolved?.resolvedFilters.map(\.displayName) ?? [])
        let uniqueTargets = Array(Set(targets)).sorted()
        if uniqueTargets.isEmpty == false {
            evidenceRows.append(HomeAnswerRow(title: "Matched", value: uniqueTargets.prefix(4).joined(separator: ", "), role: .trace))
        }
        let sourceIDs = (resolved.resolvedTargets.compactMap(\.sourceID) + (semanticResolved?.resolvedFilters.compactMap(\.sourceID) ?? []))
            .map(\.uuidString)
        if sourceIDs.isEmpty == false {
            evidenceRows.append(HomeAnswerRow(title: "Source IDs", value: sourceIDs.prefix(4).joined(separator: ", "), role: .trace))
        }

        guard evidenceRows.isEmpty == false else { return answer }
        return HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows + evidenceRows,
            attachment: answer.attachment,
            explanation: answer.explanation,
            generatedAt: answer.generatedAt
        )
    }

    private func tokenSummary(for query: MarinaUniversalQueryIR) -> String {
        [
            "amountBasis=\(query.amountBasis?.rawValue ?? "nil")",
            "grouping=\(query.grouping ?? "nil")",
            "ranking=\(query.ranking?.rawValue ?? "nil")",
            "limit=\(query.limit.map(String.init) ?? "nil")",
            "shape=\(query.presentationShape.rawValue)",
            "filters=\(query.filters.map { "\($0.field ?? "*"):\($0.value):\($0.match.rawValue)" }.joined(separator: "+"))"
        ].joined(separator: ",")
    }

    private func displayName(for basis: MarinaFinancialAmountBasis) -> String {
        switch basis {
        case .homeSpend:
            return "Home spend"
        case .cardDisplaySpend:
            return "Card display spend"
        case .debitSpend:
            return "Debit spend"
        case .budgetImpact:
            return "Budget impact"
        case .ownedSpend:
            return "Owned spend"
        case .ledgerSigned:
            return "Ledger signed"
        case .gross:
            return "Gross amount"
        case .allocated:
            return "Allocated amount"
        case .plannedAmount:
            return "Planned amount"
        case .plannedEffectiveAmount:
            return "Planned effective amount"
        case .recordedActualAmount:
            return "Recorded actual amount"
        case .actualIncome:
            return "Actual income"
        case .plannedIncome:
            return "Planned income"
        case .savingsRunningTotal:
            return "Savings running total"
        case .savingsMovement:
            return "Savings movement"
        case .savingsAdjustment:
            return "Savings adjustment"
        case .savingsOffset:
            return "Savings offset"
        case .reconciliationBalance:
            return "Reconciliation balance"
        case .reconciliationSettlement:
            return "Reconciliation settlement"
        case .count:
            return "Count"
        case .dateWindow:
            return "Date window"
        }
    }

    private static func unavailableAnswer(prompt: String, reason: String) -> HomeAnswer {
        let recovery = availabilityRecovery(for: reason)
        return HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: prompt,
            title: recovery.title,
            subtitle: recovery.message,
            rows: [
                HomeAnswerRow(title: "Data safety", value: "Offshore did not query or change your financial records."),
                HomeAnswerRow(title: "Status", value: "Marina is waiting for Apple Intelligence."),
                HomeAnswerRow(title: "Safe next step", value: "Use the app screens directly until Marina is available.")
            ]
        )
    }

    private static func availabilityRecovery(for reason: String) -> (title: String, message: String) {
        if reason.contains("apple_intelligence_not_enabled") || reason.contains("turned off") {
            return (
                "Apple Intelligence is turned off",
                "Marina needs Apple Intelligence to understand natural-language budgeting questions. Turn it on to use Marina, or use the app screens directly."
            )
        }
        if reason.contains("model_not_ready") {
            return (
                "Apple Intelligence is still preparing",
                "The on-device model is not ready yet. Try again after Apple Intelligence finishes downloading or preparing."
            )
        }
        if reason.contains("unsupported_locale") {
            return (
                "Apple Intelligence locale unsupported",
                "Marina needs a supported Apple Intelligence language and locale before it can interpret budgeting questions."
            )
        }
        if reason.contains("device_not_eligible") {
            return (
                "Apple Intelligence is not available on this device",
                "This device is not eligible for the local Apple Intelligence runtime Marina requires."
            )
        }
        if reason.contains("runtime_unavailable") || reason.contains("framework_unavailable") {
            return (
                "Apple Intelligence requires a newer runtime",
                "This app build still supports older OS versions, but natural-language Marina requires a newer Apple Intelligence runtime."
            )
        }
        return (
            "Apple Intelligence Required",
            "Marina uses Apple Intelligence to understand natural-language budgeting questions. Apple Intelligence is not available right now: \(reason)."
        )
    }

    private static func foundationFailureAnswer(
        prompt: String,
        diagnostic: MarinaFoundationModelsFailureDiagnostic
    ) -> HomeAnswer {
        let rows = [
            HomeAnswerRow(title: "Data safety", value: "Offshore did not query or change your financial records."),
            HomeAnswerRow(title: "Status", value: "Marina paused before querying your data."),
            HomeAnswerRow(title: "Safe next step", value: failureSafeNextStep(for: diagnostic.category))
        ]

        return HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: prompt,
            title: diagnostic.userTitle,
            subtitle: diagnostic.userMessage,
            rows: rows
        )
    }

    private static func failureSafeNextStep(for category: MarinaFoundationModelsErrorCategory) -> String {
        switch category {
        case .rateLimited, .concurrentRequests:
            return "Try again after the current request settles."
        case .assetsUnavailable, .unavailable, .unsupportedLanguageOrLocale:
            return "Use the app screens directly until Apple Intelligence is available."
        case .exceededContextWindowSize:
            return "Try a shorter prompt with one card, category, merchant, budget, or date range."
        default:
            return "Try again with a more specific budget question."
        }
    }

    private static func foundationDiagnostic(from error: Error) -> MarinaFoundationModelsFailureDiagnostic {
        if let serviceError = error as? MarinaFoundationModelsServiceError {
            switch serviceError {
            case .diagnosedGenerationFailure(let diagnostic):
                return diagnostic
            case .generationFailed(let category):
                return MarinaFoundationModelsFailureDiagnostic(
                    category: category,
                    step: .typedEnvelope,
                    debugSummary: String(describing: error)
                )
            case .unavailable:
                return MarinaFoundationModelsFailureDiagnostic(
                    category: .unavailable,
                    step: .availability,
                    debugSummary: String(describing: error)
                )
            case .malformedResponse:
                return MarinaFoundationModelsFailureDiagnostic(
                    category: .malformedResponse,
                    step: .typedEnvelope,
                    debugSummary: String(describing: error)
                )
            }
        }
        if error is CancellationError {
            return MarinaFoundationModelsFailureDiagnostic(
                category: .cancelled,
                step: .typedEnvelope,
                debugSummary: String(describing: error)
            )
        }
        return MarinaFoundationModelsFailureDiagnostic(
            category: .unknown,
            step: .typedEnvelope,
            debugSummary: String(describing: error)
        )
    }

    private static func blockedAnswer(
        prompt: String,
        title: String,
        message: String
    ) -> HomeAnswer {
        HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: prompt,
            title: title,
            subtitle: message,
            rows: []
        )
    }

    private static func malformedClarificationAnswer(
        prompt: String,
        clarification: MarinaTypedClarification
    ) -> HomeAnswer {
        HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: prompt,
            title: "I need a clearer target",
            subtitle: "I could not turn that into a safe choice, so Offshore did not query your financial data.",
            rows: [
                HomeAnswerRow(title: "Data safety", value: "Offshore did not query or change your financial records."),
                HomeAnswerRow(title: "Try", value: "Ask again with a named card, budget, category, merchant, income source, savings account, or reconciliation account.")
            ]
        )
    }

    private static func availabilityReason(_ status: MarinaModelAvailability.Status) -> String {
        switch status {
        case .available:
            return "available"
        case .unavailable(let reason):
            return reason.rawValue
        }
    }
}

private extension String {
    var marinaNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension MarinaQueryPlanCandidate {
    func replacingClarifiedMention(with choice: MarinaClarificationChoice) -> MarinaQueryPlanCandidate {
        var mentions = entityMentions
        let replacementText = choice.rawValue?.marinaNilIfBlank ?? choice.title
        let replacementType = choice.entityTypeHint

        if let mentionID = choice.mentionID,
           let index = mentions.firstIndex(where: { $0.id == mentionID }) {
            let mention = mentions[index]
            mentions[index] = MarinaUnresolvedEntityMention(
                id: mention.id,
                role: choice.entityRole ?? mention.role,
                rawText: replacementText,
                typeHint: replacementType ?? mention.typeHint,
                allowedTypeHints: replacementType.map { [$0] } ?? mention.allowedTypeHints,
                confidence: .high
            )
        } else if let index = mentions.firstIndex(where: { mention in
            guard let role = choice.entityRole else {
                return mention.role == .primaryTarget || mention.role == .filter
            }
            return mention.role == role
        }) {
            let mention = mentions[index]
            mentions[index] = MarinaUnresolvedEntityMention(
                id: mention.id,
                role: choice.entityRole ?? mention.role,
                rawText: replacementText,
                typeHint: replacementType ?? mention.typeHint,
                allowedTypeHints: replacementType.map { [$0] } ?? mention.allowedTypeHints,
                confidence: .high
            )
        } else {
            mentions.append(
                MarinaUnresolvedEntityMention(
                    role: choice.entityRole ?? .primaryTarget,
                    rawText: replacementText,
                    typeHint: replacementType,
                    allowedTypeHints: replacementType.map { [$0] },
                    confidence: .high
                )
            )
        }

        return copy(entityMentions: mentions)
    }

    func replacingDatabaseLookupRequest(
        with choice: MarinaClarificationChoice,
        fallbackRequest: MarinaDatabaseLookupRequest?
    ) -> MarinaQueryPlanCandidate? {
        guard var request = databaseLookupRequest ?? fallbackRequest else { return nil }
        request.searchText = choice.rawValue?.marinaNilIfBlank ?? choice.title
        if let objectType = choice.entityTypeHint?.databaseLookupObjectType {
            request.objectTypes = [objectType]
            request.lookupMode = .entityDetail
        }
        return copy(databaseLookupRequest: request.clamped)
    }

    func copy(
        entityMentions: [MarinaUnresolvedEntityMention]? = nil,
        databaseLookupRequest: MarinaDatabaseLookupRequest? = nil
    ) -> MarinaQueryPlanCandidate {
        MarinaQueryPlanCandidate(
            requestFamily: requestFamily,
            source: source,
            rawPrompt: rawPrompt,
            operation: operation,
            measure: measure,
            entityMentions: entityMentions ?? self.entityMentions,
            timeScopes: timeScopes,
            grouping: grouping,
            ranking: ranking,
            limit: limit,
            responseShapeHint: responseShapeHint,
            confidence: confidence,
            unsupportedHint: unsupportedHint,
            databaseLookupRequest: databaseLookupRequest ?? self.databaseLookupRequest,
            semanticCommand: semanticCommand,
            requestShape: requestShape,
            insightIntent: insightIntent,
            softTimeHint: softTimeHint,
            routeIntent: routeIntent
        )
    }
}

private extension MarinaSemanticQuery {
    func patching(
        choice: MarinaClarificationChoice,
        fallbackSlot: MarinaClarificationPatchSlot?,
        now _: Date,
        defaultPeriodUnit _: HomeQueryPeriodUnit
    ) -> MarinaSemanticQuery? {
        let slot = choice.patchSlot ?? fallbackSlot
        switch slot {
        case .target:
            return copy(filters: filters.patchingTarget(with: choice))
        case .date:
            return copy(
                dateRange: MarinaDateRangeRequest(
                    role: .primary,
                    rawText: choice.rawValue?.marinaNilIfBlank ?? choice.title
                )
            )
        case .comparison:
            return copy(
                comparisonDateRange: MarinaDateRangeRequest(
                    role: .comparison,
                    rawText: choice.rawValue?.marinaNilIfBlank ?? choice.title
                )
            )
        case .amount, .simulation, nil:
            return nil
        }
    }

    func copy(
        filters: [MarinaFilter]? = nil,
        dateRange: MarinaDateRangeRequest? = nil,
        comparisonDateRange: MarinaDateRangeRequest? = nil
    ) -> MarinaSemanticQuery {
        MarinaSemanticQuery(
            id: id,
            subject: subject,
            operation: operation,
            metricContractID: metricContractID,
            filters: filters ?? self.filters,
            amountField: amountField,
            dateRange: dateRange ?? self.dateRange,
            comparisonDateRange: comparisonDateRange ?? self.comparisonDateRange,
            grouping: grouping,
            ranking: ranking,
            limit: limit,
            averageBasis: averageBasis,
            incomeStatusScope: incomeStatusScope,
            responseShape: responseShape,
            requestedDetail: requestedDetail,
            routeIntent: routeIntent
        )
    }
}

private extension Array where Element == MarinaFilter {
    func patchingTarget(with choice: MarinaClarificationChoice) -> [MarinaFilter] {
        var patched = self
        let replacement = MarinaFilter(
            id: choice.mentionID ?? first?.id ?? UUID(),
            role: choice.entityRole?.resolvedTargetRole ?? .primaryTarget,
            relationship: choice.entityTypeHint?.relationshipField ?? .unknown,
            value: choice.rawValue?.marinaNilIfBlank ?? choice.title,
            matchMode: choice.sourceID == nil ? .semanticOrAlias : .exact,
            entityTypeHint: choice.entityTypeHint,
            allowedEntityTypeHints: choice.entityTypeHint.map { [$0] },
            sourceID: choice.sourceID
        )

        if let mentionID = choice.mentionID,
           let index = patched.firstIndex(where: { $0.id == mentionID }) {
            patched[index] = replacement
        } else if let index = patched.firstIndex(where: { filter in
            filter.role == replacement.role || filter.matchMode == .unresolved
        }) {
            patched[index] = replacement
        } else {
            patched.append(replacement)
        }
        return patched
    }
}

private extension MarinaEntityMentionRole {
    var resolvedTargetRole: MarinaResolvedTargetRole {
        switch self {
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
        }
    }
}

private extension MarinaCandidateEntityTypeHint {
    var relationshipField: MarinaRelationshipField {
        switch self {
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

    var databaseLookupObjectType: MarinaLookupObjectType {
        switch self {
        case .category:
            return .category
        case .merchant, .expense, .transaction:
            return .variableExpense
        case .card:
            return .card
        case .budget:
            return .budget
        case .preset:
            return .preset
        case .incomeSource:
            return .income
        case .allocationAccount:
            return .reconciliationAccount
        case .savingsAccount:
            return .savingsAccount
        case .workspace:
            return .workspace
        }
    }
}
