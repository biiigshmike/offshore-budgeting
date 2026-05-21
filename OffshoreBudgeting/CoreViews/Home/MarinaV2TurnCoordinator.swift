import Foundation

protocol MarinaCanonicalAIInterpreting {
    func interpretCanonicalV2(
        prompt: String,
        context: MarinaLanguageRouterContext
    ) async throws -> MarinaCanonicalReadInterpretation
}

struct MarinaV2FoundationAIInterpreter: MarinaCanonicalAIInterpreting {
    private let aiInterpreter: MarinaAIInterpreter
    private let legacyInterpreter = MarinaFoundationModelsInterpreter()

    init(aiInterpreter: MarinaAIInterpreter = MarinaFoundationModelsService()) {
        self.aiInterpreter = aiInterpreter
    }

    func interpretCanonicalV2(
        prompt: String,
        context: MarinaLanguageRouterContext
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
        from intent: MarinaAIIntentV2,
        prompt: String,
        defaultPeriodUnit: HomeQueryPeriodUnit
    ) -> MarinaCanonicalReadInterpretation {
        switch intent {
        case .scenario(let scenario):
            let scenarioFilters: [MarinaSemanticCommandFilter]
            if let targetName = scenario.targetName?.nilIfBlankForV2 {
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
            return legacyInterpreter.canonicalInterpretation(
                from: structuredIntent,
                prompt: prompt,
                defaultPeriodUnit: defaultPeriodUnit
            )
        case .readQuery, .lookup, .clarification, .unsupported:
            return legacyInterpreter.canonicalInterpretation(
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

    private func dateRange(from intent: MarinaAIDateRangeV2?) -> HomeQueryDateRange? {
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

    func interpretCanonicalV2(
        prompt: String,
        context _: MarinaLanguageRouterContext
    ) async throws -> MarinaCanonicalReadInterpretation {
        guard let interpretation = interpretationsByPrompt[prompt] else {
            throw Failure.missingInterpretation
        }
        return interpretation
    }
}

struct MarinaV2TurnContext {
    let provider: MarinaDataProvider
    let routerContext: MarinaLanguageRouterContext
    let defaultPeriodUnit: HomeQueryPeriodUnit
    let aiEnabled: Bool
    let now: Date
    let turnClassification: MarinaPromptTurnClassification

    init(
        provider: MarinaDataProvider,
        routerContext: MarinaLanguageRouterContext,
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

enum MarinaV2TurnResult {
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
struct MarinaV2TurnCoordinator {
    private let availability: MarinaModelAvailabilityProviding
    private let interpreter: MarinaCanonicalAIInterpreting
    private let resolver: MarinaQueryResolver
    private let validator: MarinaQueryValidator
    private let queryExecutor: MarinaQueryExecutor
    private let responseBuilder: MarinaResponseBuilder
    private let recoveryPolicy = MarinaQueryRecoveryPolicy()
    private let semanticAdapter = MarinaSemanticQueryAdapter()

    init(
        availability: MarinaModelAvailabilityProviding? = nil,
        interpreter: MarinaCanonicalAIInterpreting? = nil,
        resolver: MarinaQueryResolver? = nil,
        validator: MarinaQueryValidator? = nil,
        queryExecutor: MarinaQueryExecutor? = nil,
        responseBuilder: MarinaResponseBuilder? = nil
    ) {
        self.availability = availability ?? MarinaModelAvailability()
        self.interpreter = interpreter ?? MarinaV2FoundationAIInterpreter()
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
        context: MarinaV2TurnContext
    ) async -> MarinaV2TurnResult {
        guard context.aiEnabled else {
            MarinaV2TraceBridge.recordUnavailable(context: context, reason: "ai_opt_out")
            return .unavailable(Self.unavailableAnswer(
                prompt: prompt,
                reason: "Apple Intelligence is turned off for Marina."
            ))
        }

        let availabilityStatus = availability.currentStatus()
        MarinaTraceRecorder.shared.recordModelAvailability(availabilityStatus)
        guard availabilityStatus == .available else {
            MarinaV2TraceBridge.recordUnavailable(
                context: context,
                reason: Self.availabilityReason(availabilityStatus)
            )
            return .unavailable(Self.unavailableAnswer(
                prompt: prompt,
                reason: "Apple Intelligence is not available right now: \(Self.availabilityReason(availabilityStatus))."
            ))
        }

        do {
            let rawInterpretation = try await interpreter.interpretCanonicalV2(
                prompt: prompt,
                context: context.routerContext
            )
            let explicitConstraints = MarinaExplicitConstraintDetector().constraints(
                in: prompt,
                context: context.routerContext
            )
            let interpretation = canonicalizedInterpretation(
                rawInterpretation,
                explicitConstraints: explicitConstraints,
                now: context.now,
                defaultPeriodUnit: context.defaultPeriodUnit
            )
            return evaluate(
                interpretation,
                context: context,
                explicitConstraints: explicitConstraints
            )
        } catch {
            MarinaDebugLogger.log("Marina v2 AI interpretation failed prompt='\(prompt)' error=\(error)")
            let diagnostic = Self.foundationDiagnostic(from: error)
            MarinaTraceRecorder.shared.recordFoundationModelsFailure(diagnostic)
            MarinaV2TraceBridge.recordFoundationFailure(context: context, diagnostic: diagnostic)
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
        context: MarinaV2TurnContext
    ) async -> MarinaV2TurnResult {
        let presetAdapter = HomeAssistantPresetPromptQueryAdapter()
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
            MarinaV2TraceBridge.record(
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
        MarinaV2TraceBridge.record(
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

    func resume(
        clarification: MarinaTypedClarification,
        choice: MarinaClarificationChoice,
        context: MarinaV2TurnContext
    ) async -> MarinaV2TurnResult {
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

        if let databaseLookupCandidate = resumedCandidate.replacingDatabaseLookupRequest(
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
            title: "Marina v2 is read-only for now",
            subtitle: "I can search, summarize, calculate, and run what-if scenarios first. Create, edit, and delete commands are paused until the confirmation flow is rebuilt.",
            rows: [
                HomeAnswerRow(title: "Status", value: "CRUD deferred"),
                HomeAnswerRow(title: "Safe next step", value: "Use the app forms for changes that alter saved records.")
            ]
        )
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

    private func evaluate(
        _ interpretation: MarinaCanonicalReadInterpretation,
        context: MarinaV2TurnContext,
        explicitConstraints: MarinaExplicitPromptConstraints,
        allowSingleChoiceAutoResolve: Bool = true
    ) -> MarinaV2TurnResult {
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

        if let unsupported = explicitConstraints.unsupportedIfDropped(
            by: candidate,
            resolvedQuery: semanticResolved,
            outcome: outcome
        ) {
            let blockedOutcome = MarinaPlanValidationOutcome.unsupported(unsupported)
            MarinaV2TraceBridge.record(
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

            MarinaV2TraceBridge.record(
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
            MarinaV2TraceBridge.record(
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
                    message: "That request is outside Marina v2's safe read model."
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
                    semanticResolved: semanticResolved
                )
                MarinaV2TraceBridge.record(
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
                MarinaV2TraceBridge.record(
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
        choice.sourceID != nil
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

    private func interpretationByApplying(
        choice: MarinaClarificationChoice,
        to clarification: MarinaTypedClarification,
        context: MarinaV2TurnContext
    ) -> MarinaCanonicalReadInterpretation? {
        guard let candidate = clarification.candidate else { return nil }

        let resumedCandidate = candidate.replacingClarifiedMention(with: choice)
        let result: MarinaInterpretationResult
        let compatibilityCandidate: MarinaQueryPlanCandidate

        if let databaseLookupCandidate = resumedCandidate.replacingDatabaseLookupRequest(
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

    private func answerWithEvidence(
        _ answer: HomeAnswer,
        execution: MarinaQueryExecution,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?
    ) -> HomeAnswer {
        var evidenceRows: [HomeAnswerRow] = []
        evidenceRows.append(HomeAnswerRow(title: "Amount basis", value: displayName(for: execution.amountBasis)))
        evidenceRows.append(HomeAnswerRow(title: "Execution route", value: execution.executionRoute.traceName))

        let targets = resolved.resolvedTargets.map(\.displayName)
            + (semanticResolved?.resolvedFilters.map(\.displayName) ?? [])
        let uniqueTargets = Array(Set(targets)).sorted()
        if uniqueTargets.isEmpty == false {
            evidenceRows.append(HomeAnswerRow(title: "Matched", value: uniqueTargets.prefix(4).joined(separator: ", ")))
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

    private func displayName(for basis: MarinaFinancialAmountBasis) -> String {
        switch basis {
        case .homeSpend:
            return "Home spend"
        case .cardDisplaySpend:
            return "Card display spend"
        case .budgetImpact:
            return "Budget impact"
        case .ledgerSigned:
            return "Ledger signed"
        case .gross:
            return "Gross amount"
        case .allocated:
            return "Allocated amount"
        case .reconciliationBalance:
            return "Reconciliation balance"
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
                HomeAnswerRow(title: "Availability", value: reason),
                HomeAnswerRow(title: "Fallback", value: "Use the app screens directly until Apple Intelligence is available.")
            ]
        )
    }

    private static func availabilityRecovery(for reason: String) -> (title: String, message: String) {
        if reason.contains("apple_intelligence_not_enabled") || reason.contains("turned off") {
            return (
                "Apple Intelligence is turned off",
                "Marina v2 needs Apple Intelligence to understand natural-language budgeting questions. Turn it on to use Marina, or use the app screens directly."
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
                "Marina v2 needs a supported Apple Intelligence language and locale before it can interpret budgeting questions."
            )
        }
        if reason.contains("device_not_eligible") {
            return (
                "Apple Intelligence is not available on this device",
                "This device is not eligible for the local Foundation Models runtime Marina v2 requires."
            )
        }
        if reason.contains("runtime_unavailable") || reason.contains("framework_unavailable") {
            return (
                "Apple Intelligence requires a newer runtime",
                "This app build still supports older OS versions, but natural-language Marina v2 requires Foundation Models at runtime."
            )
        }
        return (
            "Apple Intelligence Required",
            "Marina v2 uses Apple Intelligence to understand natural-language budgeting questions. Apple Intelligence is not available right now: \(reason)."
        )
    }

    private static func foundationFailureAnswer(
        prompt: String,
        diagnostic: MarinaFoundationModelsFailureDiagnostic
    ) -> HomeAnswer {
        var rows = [
            HomeAnswerRow(title: "Data safety", value: "Offshore did not query or change your financial records."),
            HomeAnswerRow(title: "Failure type", value: diagnostic.category.rawValue),
            HomeAnswerRow(title: "Failure step", value: diagnostic.step.rawValue)
        ]
        if let availabilityReason = diagnostic.availabilityReason {
            rows.append(HomeAnswerRow(title: "Availability", value: availabilityReason))
        }
        #if DEBUG
        if MarinaRuntimeSettings.resolve().realDeviceSmoke.isEnabled {
            let exportPath = MarinaSmokeTraceStore.currentExportURL?.path ?? "enabled"
            rows.append(HomeAnswerRow(title: "Smoke trace", value: exportPath))
        }
        #endif

        return HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: prompt,
            title: diagnostic.userTitle,
            subtitle: diagnostic.userMessage,
            rows: rows
        )
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
            subtitle: "Marina produced a clarification that was not actionable, so Offshore did not query your financial data.",
            rows: [
                HomeAnswerRow(title: "Data safety", value: "Offshore did not query or change your financial records."),
                HomeAnswerRow(title: "Recovery", value: "Ask again with a named card, budget, category, merchant, income source, savings account, or reconciliation account."),
                HomeAnswerRow(title: "Clarification shape", value: "\(clarification.kind.rawValue), choices=\(clarification.choices.count)")
            ]
        )
    }

    private static func availabilityReason(_ status: MarinaModelAvailability.Status) -> String {
        switch status {
        case .available:
            return "available"
        case .unavailable(let reason):
            return reason
        }
    }
}

private extension String {
    var nilIfBlankForV2: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension MarinaQueryPlanCandidate {
    func replacingClarifiedMention(with choice: MarinaClarificationChoice) -> MarinaQueryPlanCandidate {
        var mentions = entityMentions
        let replacementText = choice.rawValue?.nilIfBlankForV2 ?? choice.title
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
        request.searchText = choice.rawValue?.nilIfBlankForV2 ?? choice.title
        if let objectType = choice.entityTypeHint?.databaseLookupObjectType {
            request.objectTypes = [objectType]
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
                    rawText: choice.rawValue?.nilIfBlankForV2 ?? choice.title
                )
            )
        case .comparison:
            return copy(
                comparisonDateRange: MarinaDateRangeRequest(
                    role: .comparison,
                    rawText: choice.rawValue?.nilIfBlankForV2 ?? choice.title
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
            value: choice.rawValue?.nilIfBlankForV2 ?? choice.title,
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
