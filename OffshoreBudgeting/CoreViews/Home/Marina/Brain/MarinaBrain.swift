import Foundation
import SwiftData

@MainActor
struct MarinaBrain {
    private static let showSemanticTraceKey = "debug_marinaShowSemanticTrace"

    private let interpreter: any MarinaModelInterpreting
    private let planner: MarinaQueryPlanner
    private let snapshotProvider: MarinaWorkspaceSnapshotProvider
    private let validator: MarinaSemanticRequestValidator
    private let executor: MarinaQueryExecutor
    private let insightAnalyzer: MarinaInsightAnalyzer
    private let insightNarrator: any MarinaInsightNarrating
    private let presenter: MarinaAnswerPresenter
    private let followUpResolver: MarinaFollowUpResolver
    private let universalRoutingPolicyProvider: () -> MarinaUniversalRoutingPolicy

    init(
        interpreter: (any MarinaModelInterpreting)? = nil,
        planner: MarinaQueryPlanner? = nil,
        snapshotProvider: MarinaWorkspaceSnapshotProvider? = nil,
        validator: MarinaSemanticRequestValidator? = nil,
        executor: MarinaQueryExecutor? = nil,
        insightAnalyzer: MarinaInsightAnalyzer? = nil,
        insightNarrator: (any MarinaInsightNarrating)? = nil,
        presenter: MarinaAnswerPresenter? = nil,
        followUpResolver: MarinaFollowUpResolver? = nil,
        universalRoutingPolicyProvider: (() -> MarinaUniversalRoutingPolicy)? = nil
    ) {
        self.interpreter = interpreter ?? MarinaModelInterpreterFactory.makeDefault()
        self.planner = planner ?? MarinaQueryPlanner()
        self.snapshotProvider = snapshotProvider ?? MarinaWorkspaceSnapshotProvider()
        self.validator = validator ?? MarinaSemanticRequestValidator()
        self.executor = executor ?? MarinaQueryExecutor()
        self.insightAnalyzer = insightAnalyzer ?? MarinaInsightAnalyzer()
        self.insightNarrator = insightNarrator ?? MarinaInsightNarrator()
        self.presenter = presenter ?? MarinaAnswerPresenter()
        self.followUpResolver = followUpResolver ?? MarinaFollowUpResolver()
        self.universalRoutingPolicyProvider = universalRoutingPolicyProvider ?? {
            MarinaUniversalRoutingDebugFlagResolver.policy()
        }
    }

    func answer(
        prompt: String,
        workspace: Workspace,
        modelContext: ModelContext,
        ambientDateRange: HomeQueryDateRange?,
        homeContext: MarinaPanelHomeContext? = nil,
        defaultBudgetingPeriod: BudgetingPeriod,
        conversationContext: MarinaConversationContext = MarinaConversationContext(),
        now: Date = Date()
    ) async -> HomeAnswer {
        let seed = await answerSeed(
            prompt: prompt,
            workspace: workspace,
            modelContext: modelContext,
            ambientDateRange: ambientDateRange,
            homeContext: homeContext,
            defaultBudgetingPeriod: defaultBudgetingPeriod,
            conversationContext: conversationContext,
            now: now
        )
        return await completedAnswer(from: seed)
    }

    func answerSeed(
        prompt: String,
        workspace: Workspace,
        modelContext: ModelContext,
        ambientDateRange: HomeQueryDateRange?,
        homeContext: MarinaPanelHomeContext? = nil,
        defaultBudgetingPeriod: BudgetingPeriod,
        conversationContext: MarinaConversationContext = MarinaConversationContext(),
        now: Date = Date()
    ) async -> MarinaAnswerSeed {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = MarinaBrainContext(
            workspace: workspace,
            modelContext: modelContext,
            ambientDateRange: ambientDateRange,
            defaultBudgetingPeriod: defaultBudgetingPeriod,
            now: now,
            homeContext: homeContext
        )

        do {
            let interpreted: MarinaInterpretedSemanticRequest
            var promptTreatment: MarinaAnswerDebugTrace.PromptTreatment = .standalone
            var priorContextChangedRequest = false
            if let followUpResolution = followUpResolver.resolve(
                prompt: trimmedPrompt,
                conversationContext: conversationContext
            ) {
                switch followUpResolution {
                case .request(let followUpRequest, let diagnosticNote):
                    promptTreatment = diagnosticNote.contains("recommended Marina follow-up")
                        ? .recommendedFollowUpConfirmation
                        : .contextualFollowUp
                    priorContextChangedRequest = true
                    interpreted = MarinaInterpretedSemanticRequest(
                        request: followUpRequest,
                        confidence: .high,
                        source: .ruleBased,
                        diagnosticNotes: [diagnosticNote]
                    )
                case .prompt(let followUpPrompt, let diagnosticNote):
                    promptTreatment = .recommendedFollowUpConfirmation
                    priorContextChangedRequest = true
                    var promptInterpreted = try await interpreter.interpretedSemanticRequest(for: followUpPrompt, context: context)
                    promptInterpreted.diagnosticNotes.append(diagnosticNote)
                    interpreted = promptInterpreted
                case .declined:
                    let narration = MarinaL10n.string(
                        "marina.followUp.decline.narration",
                        defaultValue: "No problem. I’m here whenever you want to dig into something else.",
                        comment: "Marina narration when the user declines a recommended follow-up."
                    )
                    let result = MarinaExecutionResult(
                        kind: .message,
                        title: ""
                    )
                    let answer = presenter.present(result: result, prompt: trimmedPrompt, queryID: UUID())
                    return MarinaAnswerSeed(
                        answer: answer,
                        insightContext: nil,
                        finalExplanationSuffix: nil,
                        scriptedNarration: narration,
                        debugTrace: terminalDebugTrace(
                            prompt: trimmedPrompt,
                            treatment: .declinedFollowUp,
                            result: result,
                            now: context.now,
                            narrationRequested: true
                        )
                    )
                }
            } else {
                interpreted = try await interpreter.interpretedSemanticRequest(for: trimmedPrompt, context: context)
            }
            return try answerSeed(
                interpreted: interpreted,
                prompt: trimmedPrompt,
                context: context,
                conversationContext: conversationContext,
                promptTreatment: promptTreatment,
                priorContextChangedRequest: priorContextChangedRequest
            )
        } catch {
            let result = MarinaExecutionResult(
                kind: .message,
                title: MarinaL10n.string("marina.error.snagTitle", defaultValue: "I hit a snag", comment: "Marina error title when answer generation fails."),
                subtitle: error.localizedDescription
            )
            let answer = presenter.present(result: result, prompt: trimmedPrompt, queryID: UUID())
            return MarinaAnswerSeed(answer: answer, insightContext: nil, finalExplanationSuffix: nil)
        }
    }

    func answer(
        resolvedRequest: MarinaSemanticRequest,
        prompt: String,
        workspace: Workspace,
        modelContext: ModelContext,
        ambientDateRange: HomeQueryDateRange?,
        homeContext: MarinaPanelHomeContext? = nil,
        defaultBudgetingPeriod: BudgetingPeriod,
        now: Date = Date()
    ) async -> HomeAnswer {
        let seed = await answerSeed(
            resolvedRequest: resolvedRequest,
            prompt: prompt,
            workspace: workspace,
            modelContext: modelContext,
            ambientDateRange: ambientDateRange,
            homeContext: homeContext,
            defaultBudgetingPeriod: defaultBudgetingPeriod,
            now: now
        )
        return await completedAnswer(from: seed)
    }

    func answerSeed(
        resolvedRequest: MarinaSemanticRequest,
        prompt: String,
        workspace: Workspace,
        modelContext: ModelContext,
        ambientDateRange: HomeQueryDateRange?,
        homeContext: MarinaPanelHomeContext? = nil,
        defaultBudgetingPeriod: BudgetingPeriod,
        now: Date = Date()
    ) async -> MarinaAnswerSeed {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = MarinaBrainContext(
            workspace: workspace,
            modelContext: modelContext,
            ambientDateRange: ambientDateRange,
            defaultBudgetingPeriod: defaultBudgetingPeriod,
            now: now,
            homeContext: homeContext
        )
        let interpreted = MarinaInterpretedSemanticRequest(
            request: resolvedRequest,
            confidence: .high,
            source: .ruleBased,
            diagnosticNotes: ["Resolved from Marina clarification choice."]
        )

        do {
            return try answerSeed(
                interpreted: interpreted,
                prompt: trimmedPrompt,
                context: context,
                conversationContext: .empty,
                promptTreatment: .standalone,
                priorContextChangedRequest: false
            )
        } catch {
            let result = MarinaExecutionResult(
                kind: .message,
                title: MarinaL10n.string("marina.error.snagTitle", defaultValue: "I hit a snag", comment: "Marina error title when answer generation fails."),
                subtitle: error.localizedDescription
            )
            let answer = presenter.present(result: result, prompt: trimmedPrompt, queryID: UUID())
            return MarinaAnswerSeed(answer: answer, insightContext: nil, finalExplanationSuffix: nil)
        }
    }

    private func answerSeed(
        interpreted: MarinaInterpretedSemanticRequest,
        prompt: String,
        context: MarinaBrainContext,
        conversationContext: MarinaConversationContext,
        promptTreatment: MarinaAnswerDebugTrace.PromptTreatment,
        priorContextChangedRequest: Bool
    ) throws -> MarinaAnswerSeed {
        let snapshot = try snapshotProvider.snapshot(
            for: context.workspace,
            modelContext: context.modelContext,
            homeContext: context.homeContext,
            now: context.now
        )
        let validationTrace = validator.validateWithTrace(
            interpreted: interpreted,
            snapshot: snapshot,
            originalPrompt: prompt
        )
        let validated = validationTrace.interpreted
        let queryPlan = planner.plan(
            request: validated.request,
            ambientDateRange: context.ambientDateRange,
            defaultBudgetingPeriod: context.defaultBudgetingPeriod,
            now: context.now,
            clarificationChoices: validated.clarificationChoices
        )
        let execution = execute(plan: queryPlan, snapshot: snapshot, context: context)
        let result = execution.result
        let analyzedBundle = insightAnalyzer.insightBundle(for: result, plan: queryPlan)
        let memory = conversationContext.followUpMemory
        let memoryFilteredBundle = MarinaInsightBundle(
            headlineFact: analyzedBundle.headlineFact,
            meaning: analyzedBundle.meaning,
            signals: analyzedBundle.signals,
            followUps: MarinaRecommendedFollowUp.filteredFollowUps(
                from: analyzedBundle.followUps,
                memory: memory
            )
        )
        let insightBundle = memoryFilteredBundle.isEmpty ? nil : memoryFilteredBundle
        let insightContext = MarinaInsightContext(
            prompt: prompt,
            result: result,
            plan: queryPlan,
            insightBundle: insightBundle
        )
        let narratableContext = insightContext.isNarratable ? insightContext : nil
        let structuredTrace = MarinaAnswerDebugTrace(
            originalPrompt: prompt,
            promptTreatment: promptTreatment,
            priorContextChangedRequest: priorContextChangedRequest,
            interpretedRequest: interpreted.request,
            interpretedSource: interpreted.source,
            interpretedConfidence: interpreted.confidence,
            interpretedNotes: interpreted.diagnosticNotes,
            explicitPromptTargets: validationTrace.explicitPromptTargets,
            candidateSearches: validationTrace.candidateSearches,
            resolverOutput: validationTrace.resolverOutput.request,
            validatorOutput: validated.request,
            validatorAccepted: validated.request.expectedAnswerShape != .unsupported && validated.request.expectedAnswerShape != .clarification,
            validatorNotes: validated.diagnosticNotes,
            queryPlan: MarinaQueryPlanTrace(plan: queryPlan),
            executionRoute: execution.route,
            universalScenario: execution.universalDiagnostics?.scenario,
            universalFallbackReason: execution.universalDiagnostics?.fallbackReason,
            universalNotes: execution.universalDiagnostics?.notes ?? [],
            rowCount: result.rows.count,
            evidenceRowSummaries: evidenceRowSummaries(from: result.rows),
            answerKind: result.kind,
            answerTitle: result.title,
            answerPrimaryValue: result.primaryValue,
            narrationRequested: narratableContext != nil
        )
        let debugTrace = debugTraceIfNeeded(trace: structuredTrace)
        let seedResult = narratableContext == nil
            ? result.withAppendingExplanation(debugTrace)
            : result
        let answer = presenter.present(
            result: seedResult,
            prompt: prompt,
            queryID: queryPlan.id,
            semanticContext: MarinaAnswerSemanticContext(plan: queryPlan, result: seedResult),
            insightBundle: insightBundle
        )
        return MarinaAnswerSeed(
            answer: answer,
            insightContext: narratableContext,
            finalExplanationSuffix: narratableContext == nil ? nil : debugTrace,
            debugTrace: structuredTrace
        )
    }

    private struct MarinaBrainExecution {
        let result: MarinaExecutionResult
        let route: MarinaAnswerDebugTrace.ExecutionRoute
        let universalDiagnostics: MarinaUniversalRoutingDiagnostics?
    }

    private func execute(
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot,
        context: MarinaBrainContext
    ) -> MarinaBrainExecution {
        let policy = universalRoutingPolicyProvider()
        guard policy.isEnabled else {
            return MarinaBrainExecution(
                result: executor.execute(plan: plan, snapshot: snapshot),
                route: .legacy,
                universalDiagnostics: nil
            )
        }

        let calendar = Calendar.current
        let planningContext = MarinaUniversalPlanningContext(
            ambientDateRange: context.ambientDateRange,
            defaultBudgetingPeriod: context.defaultBudgetingPeriod,
            now: context.now,
            calendar: calendar
        )
        let formulaRegistry = MarinaFormulaRegistry(now: context.now, calendar: calendar)
        let harness = MarinaUniversalRoutingHarness(
            bridge: MarinaSemanticUniversalPlanBridge(formulaRegistry: formulaRegistry),
            runner: MarinaUniversalQueryRunner(formulaRegistry: formulaRegistry),
            presenter: MarinaUniversalResultPresenter(),
            policy: policy
        )
        let result = MarinaDualPathQueryExecutor(
            legacyExecutor: executor,
            universalHarness: harness,
            policy: policy
        )
        .executeResult(
            plan: plan,
            snapshot: snapshot,
            planningContext: planningContext
        )

        switch result {
        case let .legacy(executionResult, diagnostics):
            return MarinaBrainExecution(
                result: executionResult,
                route: diagnostics == nil ? .legacy : .legacyFallback,
                universalDiagnostics: diagnostics
            )
        case let .universal(executionResult, diagnostics):
            return MarinaBrainExecution(
                result: executionResult,
                route: .universal,
                universalDiagnostics: diagnostics
            )
        }
    }

    private func completedAnswer(from seed: MarinaAnswerSeed) async -> HomeAnswer {
        if let scriptedNarration = seed.scriptedNarration {
            return answer(
                seed.answer,
                replacingExplanationWith: combinedExplanation(
                    base: seed.answer.explanation,
                    insight: scriptedNarration,
                    suffix: seed.finalExplanationSuffix
                )
            )
        }

        guard let context = seed.insightContext else {
            return seed.answer
        }

        do {
            let narration = try await insightNarrator.narration(for: context)
            return answer(
                seed.answer,
                replacingExplanationWith: combinedExplanation(
                    base: seed.answer.explanation,
                    insight: narration,
                    suffix: seed.finalExplanationSuffix
                )
            )
        } catch {
            return seed.answer
        }
    }

    private func debugTraceIfNeeded(trace: MarinaAnswerDebugTrace) -> String? {
        guard DebugFeatureFlagResolver.isEnabled(key: Self.showSemanticTraceKey, fallback: false) else {
            return nil
        }

        let description = trace.debugDescription
        let consoleMessage = "Marina QA Trace\n\(description)\n"
        FileHandle.standardError.write(Data(consoleMessage.utf8))
        NSLog("%@", consoleMessage)
        return nil
    }

    private func terminalDebugTrace(
        prompt: String,
        treatment: MarinaAnswerDebugTrace.PromptTreatment,
        result: MarinaExecutionResult,
        now: Date,
        narrationRequested: Bool
    ) -> MarinaAnswerDebugTrace {
        let request = MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: .unsupportedCombination
        )
        let plan = MarinaQueryPlan(
            id: UUID(),
            semanticRequest: request,
            dateRange: nil,
            comparisonDateRange: nil,
            now: now
        )
        return MarinaAnswerDebugTrace(
            originalPrompt: prompt,
            promptTreatment: treatment,
            priorContextChangedRequest: treatment != .standalone,
            interpretedRequest: request,
            interpretedSource: .ruleBased,
            interpretedConfidence: .high,
            interpretedNotes: [],
            explicitPromptTargets: [],
            candidateSearches: [],
            resolverOutput: request,
            validatorOutput: request,
            validatorAccepted: false,
            validatorNotes: [],
            queryPlan: MarinaQueryPlanTrace(plan: plan),
            executionRoute: .legacy,
            universalScenario: nil,
            universalFallbackReason: nil,
            universalNotes: [],
            rowCount: result.rows.count,
            evidenceRowSummaries: evidenceRowSummaries(from: result.rows),
            answerKind: result.kind,
            answerTitle: result.title,
            answerPrimaryValue: result.primaryValue,
            narrationRequested: narrationRequested
        )
    }

    private func evidenceRowSummaries(from rows: [HomeAnswerRow]) -> [String] {
        rows.prefix(8).map { row in
            [
                row.role.rawValue,
                row.objectType?.rawValue ?? "unknown",
                row.title,
                row.value,
                row.amount.map { "\($0)" } ?? "nil"
            ].joined(separator: ":")
        }
    }

    func completedAnswer(
        from seed: MarinaAnswerSeed,
        streamingNarration narration: String?
    ) -> HomeAnswer {
        answer(
            seed.answer,
            replacingExplanationWith: combinedExplanation(
                base: seed.answer.explanation,
                insight: narration ?? seed.scriptedNarration,
                suffix: seed.finalExplanationSuffix
            )
        )
    }

    func insightNarrationStream(for context: MarinaInsightContext) -> AsyncThrowingStream<String, Error> {
        insightNarrator.narrationStream(for: context)
    }

    private func combinedExplanation(base: String?, insight: String?, suffix: String?) -> String? {
        let pieces = [base, insight, suffix]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n\n")
    }

    private func answer(_ answer: HomeAnswer, replacingExplanationWith explanation: String?) -> HomeAnswer {
        HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            attachment: answer.attachment,
            explanation: explanation,
            semanticContext: answer.semanticContext,
            insightBundle: answer.insightBundle,
            generatedAt: answer.generatedAt
        )
    }
}

enum MarinaFollowUpResolution: Equatable, Sendable {
    case request(MarinaSemanticRequest, diagnosticNote: String)
    case prompt(String, diagnosticNote: String)
    case declined
}

private enum MarinaPromptContextIntent {
    case explicitFollowUp
    case possibleFollowUp
    case standalone
}

struct MarinaFollowUpResolver {
    func resolve(
        prompt: String,
        conversationContext: MarinaConversationContext
    ) -> MarinaFollowUpResolution? {
        let normalized = normalize(prompt)
        guard normalized.isEmpty == false else { return nil }

        if let confirmation = recommendedFollowUpConfirmation(normalized: normalized, conversationContext: conversationContext) {
            return confirmation
        }

        guard shouldResolveFromConversation(prompt: normalized) else {
            return nil
        }

        if let visibleFollowUp = visibleRecommendedFollowUpPrompt(normalized: normalized, conversationContext: conversationContext) {
            return visibleFollowUp
        }

        if isShowMoreConfirmationPrompt(normalized) {
            if let semanticContext = conversationContext.lastSemanticContext,
               let request = showMoreRequest(from: semanticContext) {
                return .request(request, diagnosticNote: "Resolved from recent Marina conversation context.")
            }

            return .request(unsupportedDependentFollowUpRequest(), diagnosticNote: "Resolved dependent Marina follow-up without usable recent context.")
        }

        if let semanticContext = conversationContext.lastSemanticContext,
           let request = request(from: prompt, normalized: normalized, context: semanticContext) {
            return .request(request, diagnosticNote: "Resolved from recent Marina conversation context.")
        }

        return legacyCategoryAvailabilityRequest(normalized: normalized, conversationContext: conversationContext)
            .map { .request($0, diagnosticNote: "Resolved from recent Marina conversation context.") }
    }

    private func shouldResolveFromConversation(prompt normalized: String) -> Bool {
        if contextIntent(for: normalized) == .standalone {
            return false
        }

        return isShortContinuationPrompt(normalized)
            || isCorrectionPrompt(normalized)
            || isFollowUpCue(normalized)
            || hasExplicitRefinement(normalized)
            || containsAny(normalized, ["drove", "driving", "behind", "made up", "what caused", "caused", "changed"])
    }

    private func contextIntent(for normalized: String) -> MarinaPromptContextIntent {
        if isExplicitDependentFollowUp(normalized) {
            return .explicitFollowUp
        }

        if isStandalonePrompt(normalized) {
            return .standalone
        }

        return .possibleFollowUp
    }

    private func isExplicitDependentFollowUp(_ normalized: String) -> Bool {
        if isDateOnlyFollowUp(normalized) {
            return true
        }

        if normalized == "more" {
            return true
        }

        if containsAny(normalized, [
            "show more",
            "show me more",
            "break that down",
            "breakdown",
            "compare that",
            "compare this",
            "show details",
            "details",
            "drill down",
            "which ones",
            "which one",
            "behind this",
            "behind it",
            "what made this up",
            "what caused this",
            "what caused it"
        ]) {
            return true
        }

        if containsContextualReference(normalized) {
            return true
        }

        return false
    }

    private func isStandalonePrompt(_ normalized: String) -> Bool {
        if containsAny(normalized, [
            "category availability",
            "spend trends",
            "safe spend",
            "projected spend",
            "savings outlook",
            "income progress",
            "next planned expense",
            "what is eating my budget"
        ]) {
            return true
        }

        if categoryAvailabilityFilter(in: normalized) != nil,
           containsAny(normalized, ["category", "categories"]) {
            return true
        }

        let hasStandaloneAction = containsAny(normalized, [
            "show",
            "list",
            "summarize",
            "compare",
            "how much",
            "what did",
            "what is",
            "what are",
            "which",
            "where",
            "does"
        ])
        let hasStandaloneDomain = containsAny(normalized, [
            "expense",
            "expenses",
            "spend",
            "spent",
            "spending",
            "income",
            "card",
            "budget",
            "category",
            "categories",
            "merchant",
            "savings",
            "subscription",
            "subscriptions",
            "preset",
            "planned expense",
            "variable expense"
        ])
        guard hasStandaloneAction, hasStandaloneDomain else {
            return false
        }

        let hasPersonalReference = containsAny(normalized, ["my ", " i ", " me "])
            || normalized.hasPrefix("my ")
            || normalized.hasPrefix("i ")
        let hasExplicitTargetPhrase = containsAny(normalized, [" on ", " for ", " from ", " tied to ", " assigned to ", " linked to "])
        let hasDatePhrase = explicitDateToken(in: normalized) != nil || normalized.contains("today")
        let hasComparisonTargets = containsAny(normalized, [" to ", " or ", " vs ", " versus "])
        return hasPersonalReference
            || hasExplicitTargetPhrase
            || hasDatePhrase
            || hasComparisonTargets
            || wordCount(in: normalized) >= 6
    }

    private func containsContextualReference(_ normalized: String) -> Bool {
        let contextualPronouns: Set<String> = ["that", "these", "those", "it", "ones", "one"]
        let words = normalized.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if words.contains(where: { contextualPronouns.contains($0) }) {
            return true
        }

        if words.contains("this"),
           isStandaloneDatePhrase(normalized) == false {
            return true
        }

        return containsAny(normalized, [
            "increase",
            "decrease",
            "behind",
            "drove",
            "driving",
            "caused",
            "made up"
        ])
    }

    private func isDateOnlyFollowUp(_ normalized: String) -> Bool {
        [
            "last month",
            "this month",
            "previous month",
            "last period",
            "this period",
            "previous period",
            "current period",
            "all time",
            "today"
        ].contains(normalized)
    }

    private func isStandaloneDatePhrase(_ normalized: String) -> Bool {
        containsAny(normalized, [
            "this month",
            "last month",
            "previous month",
            "this period",
            "current period",
            "last period",
            "previous period",
            "today"
        ])
    }

    private func isShortContinuationPrompt(_ normalized: String) -> Bool {
        wordCount(in: normalized) <= 5
    }

    private func recommendedFollowUpConfirmation(
        normalized: String,
        conversationContext: MarinaConversationContext
    ) -> MarinaFollowUpResolution? {
        guard let followUp = conversationContext.lastRecommendedFollowUp else {
            return nil
        }

        if MarinaRecommendedFollowUp.isNegative(normalized) {
            return .declined
        }

        guard MarinaRecommendedFollowUp.isAffirmative(normalized)
                || isShowMoreConfirmationPrompt(normalized, for: followUp) else {
            return nil
        }

        if let request = followUp.semanticRequest {
            return .request(request, diagnosticNote: "Resolved from recommended Marina follow-up confirmation.")
        }

        guard followUp.executionMode == .clarificationRequired else {
            return nil
        }
        return .prompt(followUp.prompt, diagnosticNote: "Resolved from recommended Marina follow-up confirmation.")
    }

    private func visibleRecommendedFollowUpPrompt(
        normalized: String,
        conversationContext: MarinaConversationContext
    ) -> MarinaFollowUpResolution? {
        guard let followUp = conversationContext.lastRecommendedFollowUp,
              let request = followUp.semanticRequest else {
            return nil
        }

        let visiblePrompt = normalize(followUp.prompt)
        let visibleTitle = normalize(followUp.title)
        guard normalized == visiblePrompt || normalized == visibleTitle else {
            return nil
        }

        return .request(request, diagnosticNote: "Resolved from recent Marina conversation context.")
    }

    private func isShowMoreConfirmationPrompt(
        _ normalized: String,
        for followUp: MarinaFollowUpSuggestion
    ) -> Bool {
        followUp.reason == .showMore && isShowMoreConfirmationPrompt(normalized)
    }

    private func isShowMoreConfirmationPrompt(_ normalized: String) -> Bool {
        normalized == "more"
            || normalized == "show more"
            || normalized == "show me more"
    }

    private func showMoreRequest(from context: MarinaAnswerSemanticContext) -> MarinaSemanticRequest? {
        guard context.answerKind == .list else { return nil }

        var request = context.request
        request.expectedAnswerShape = .list
        request.resultLimit = min(max((context.request.resultLimit ?? context.rowReferences.count) + 5, 10), HomeQuery.maxResultLimit)
        return request
    }

    private func unsupportedDependentFollowUpRequest() -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .workspace,
            operation: .list,
            expectedAnswerShape: .unsupported,
            unsupportedReason: .unsupportedCombination
        )
    }

    private func request(
        from prompt: String,
        normalized: String,
        context: MarinaAnswerSemanticContext
    ) -> MarinaSemanticRequest? {
        if context.request.expectedAnswerShape == .clarification {
            return clarificationCorrectionRequest(from: prompt, normalized: normalized, context: context)
        }

        guard context.request.expectedAnswerShape != .unsupported,
              context.request.unsupportedReason == nil else {
            return nil
        }

        if let expenseDrivers = expenseDriverRequest(normalized: normalized, context: context) {
            return expenseDrivers
        }

        if let comparisonDriver = comparisonDriverRequest(normalized: normalized, context: context) {
            return comparisonDriver
        }

        if let categoryAvailability = categoryAvailabilityRequest(normalized: normalized, context: context) {
            return categoryAvailability
        }

        if let drillDown = drillDownRequest(normalized: normalized, context: context) {
            return drillDown
        }

        if let correction = targetCorrectionRequest(from: prompt, normalized: normalized, context: context) {
            return correction
        }

        if let refinement = refinementRequest(normalized: normalized, context: context) {
            return refinement
        }

        return nil
    }

    private func expenseDriverRequest(
        normalized: String,
        context: MarinaAnswerSemanticContext
    ) -> MarinaSemanticRequest? {
        guard asksForExpenseRows(normalized),
              containsAny(normalized, ["drove", "driving", "behind", "made up", "what made", "what caused", "caused"]) else {
            return nil
        }

        var request = expenseListRequest(from: context.request)
        applyRefinements(from: normalized, to: &request)
        request.resultLimit = firstInteger(in: normalized) ?? request.resultLimit ?? 5
        request.sort = sort(in: normalized) ?? request.sort ?? .amountDescending
        return request
    }

    private func legacyCategoryAvailabilityRequest(
        normalized: String,
        conversationContext: MarinaConversationContext
    ) -> MarinaSemanticRequest? {
        let lastTitle = conversationContext.lastTurn?.title
        let categoryAvailabilityTitle = MarinaL10n.string("marina.answer.categoryAvailability.title", defaultValue: "Category Availability", comment: "Marina answer title for category availability.")
        guard (lastTitle == "Category Availability" || lastTitle == categoryAvailabilityTitle),
              isCategoryAvailabilityFollowUp(normalized) else {
            return nil
        }

        return categoryAvailabilityListRequest(
            base: nil,
            normalized: normalized,
            filter: categoryAvailabilityFilter(in: normalized) ?? .all
        )
    }

    private func categoryAvailabilityRequest(
        normalized: String,
        context: MarinaAnswerSemanticContext
    ) -> MarinaSemanticRequest? {
        guard context.request.measure == .categoryAvailability,
              isCategoryAvailabilityFollowUp(normalized) else {
            return nil
        }

        return categoryAvailabilityListRequest(
            base: context.request,
            normalized: normalized,
            filter: categoryAvailabilityFilter(in: normalized) ?? context.request.categoryAvailabilityFilter ?? .all
        )
    }

    private func categoryAvailabilityListRequest(
        base: MarinaSemanticRequest?,
        normalized: String,
        filter: MarinaCategoryAvailabilityFilter
    ) -> MarinaSemanticRequest {
        MarinaSemanticRequest(
            entity: .category,
            operation: .list,
            measure: .categoryAvailability,
            dimensions: [.category],
            dateRangeToken: explicitDateToken(in: normalized) ?? base?.dateRangeToken ?? .currentPeriod,
            resultLimit: firstInteger(in: normalized) ?? base?.resultLimit ?? 5,
            sort: sort(in: normalized) ?? base?.sort,
            categoryAvailabilityFilter: filter,
            expectedAnswerShape: .list
        )
    }

    private func drillDownRequest(
        normalized: String,
        context: MarinaAnswerSemanticContext
    ) -> MarinaSemanticRequest? {
        guard isDrillDownPrompt(normalized) else { return nil }

        let base = context.request
        if base.entity == .income {
            var request = base
            request.operation = .list
            request.expectedAnswerShape = .list
            applyRefinements(from: normalized, to: &request)
            return request
        }

        if base.entity == .preset {
            var request = base
            request.operation = .list
            request.expectedAnswerShape = .list
            request.resultLimit = firstInteger(in: normalized) ?? request.resultLimit ?? 5
            request.sort = sort(in: normalized) ?? request.sort ?? .amountDescending
            return request
        }

        var request = expenseListRequest(from: base)
        applyRefinements(from: normalized, to: &request)
        if request.resultLimit == nil {
            request.resultLimit = 5
        }
        if request.sort == nil {
            request.sort = sort(in: normalized) ?? .amountDescending
        }
        if let transactionTarget = transactionTarget(in: normalized) {
            request = requestByApplying(target: transactionTarget, to: request, normalized: normalized)
        }
        return request
    }

    private func comparisonDriverRequest(
        normalized: String,
        context: MarinaAnswerSemanticContext
    ) -> MarinaSemanticRequest? {
        guard context.answerKind == .comparison,
              asksForExpenseRows(normalized) == false,
              containsAny(normalized, ["what drove", "why did", "caused", "cause", "driving", "behind the increase", "behind the decrease", "changed"]) else {
            return nil
        }

        var request = MarinaSemanticRequest(
            entity: .category,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: context.request.dateRangeToken,
            resultLimit: firstInteger(in: normalized) ?? 5,
            sort: .amountDescending,
            expenseScope: .unified,
            expectedAnswerShape: .list
        )
        applyRefinements(from: normalized, to: &request)
        return request
    }

    private func targetCorrectionRequest(
        from prompt: String,
        normalized: String,
        context: MarinaAnswerSemanticContext
    ) -> MarinaSemanticRequest? {
        guard let target = correctionTarget(from: prompt, normalized: normalized) else {
            return nil
        }

        let base = context.request
        if containsAny(normalized, ["transactions", "expenses", "details"]) {
            var request = expenseListRequest(from: base)
            request = requestByApplying(target: target, to: request, normalized: normalized)
            applyRefinements(from: normalized, to: &request)
            return request
        }

        var request = base
        request = requestByApplying(target: target, to: request, normalized: normalized)
        applyRefinements(from: normalized, to: &request)
        return request
    }

    private func refinementRequest(
        normalized: String,
        context: MarinaAnswerSemanticContext
    ) -> MarinaSemanticRequest? {
        var request = context.request
        let original = request
        applyRefinements(from: normalized, to: &request)

        if containsAny(normalized, ["only variable", "variable only", "actual expenses only", "actual only"]),
           original.entity == .budget {
            request = MarinaSemanticRequest(
                entity: .variableExpense,
                operation: .sum,
                measure: .budgetImpact,
                dateRangeToken: explicitDateToken(in: normalized) ?? original.dateRangeToken,
                sort: sort(in: normalized),
                expenseScope: .variable,
                expectedAnswerShape: .metric
            )
        }

        if request != original,
           isFollowUpCue(normalized) || hasExplicitRefinement(normalized) {
            return request
        }

        return nil
    }

    private func clarificationCorrectionRequest(
        from prompt: String,
        normalized: String,
        context: MarinaAnswerSemanticContext
    ) -> MarinaSemanticRequest? {
        guard isCorrectionPrompt(normalized) || isFollowUpCue(normalized) else { return nil }
        let target = correctionTarget(from: prompt, normalized: normalized)
            ?? context.request.targetName
            ?? context.request.textQuery
        guard let target else { return nil }

        var request = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .sum,
            measure: .budgetImpact,
            dateRangeToken: context.request.dateRangeToken,
            targetName: target,
            expenseScope: .unified,
            expectedAnswerShape: .metric
        )
        applyRefinements(from: normalized, to: &request)
        return request
    }

    private func expenseListRequest(from base: MarinaSemanticRequest) -> MarinaSemanticRequest {
        var request = base
        request.entity = base.entity == .plannedExpense ? .plannedExpense : .variableExpense
        request.operation = .list
        request.measure = .budgetImpact
        request.dimensions = expenseRowDimensions(from: base)
        request.resultLimit = base.resultLimit
        request.sort = base.sort
        request.expenseScope = base.expenseScope ?? .unified
        request.expectedAnswerShape = .list
        request.unsupportedReason = nil

        switch base.entity {
        case .card:
            request.entity = .variableExpense
            request.expenseScope = .unified
        case .category:
            request.entity = .variableExpense
            request.expenseScope = .unified
        case .reconciliationAccount:
            request.entity = .variableExpense
            request.expenseScope = .unified
        case .budget, .savingsAccount, .workspace:
            request.entity = .variableExpense
            request.dimensions = []
            request.targetName = nil
            request.textQuery = nil
            request.targetDisplayName = nil
            request.expenseScope = .unified
        case .income, .preset:
            break
        case .plannedExpense:
            request.expenseScope = .planned
        case .variableExpense:
            request.expenseScope = base.expenseScope ?? .unified
        }

        return request
    }

    private func expenseRowDimensions(from request: MarinaSemanticRequest) -> [MarinaSemanticDimension] {
        var dimensions: [MarinaSemanticDimension] = []

        if request.dimensions.contains(.merchantText),
           trimmed(request.textQuery) != nil {
            dimensions.append(.merchantText)
        }
        if request.dimensions.contains(.card),
           trimmed(request.targetName) != nil {
            dimensions.append(.card)
        }
        if request.dimensions.contains(.category),
           trimmed(request.targetName) != nil,
           request.measure != .categoryAvailability {
            dimensions.append(.category)
        }
        if request.dimensions.contains(.reconciliationAccount),
           trimmed(request.targetName) != nil {
            dimensions.append(.reconciliationAccount)
        }

        return dimensions
    }

    private func requestByApplying(
        target: String,
        to base: MarinaSemanticRequest,
        normalized: String
    ) -> MarinaSemanticRequest {
        var request = base
        let explicitDimension = explicitTargetDimension(in: normalized, target: target)

        switch explicitDimension {
        case .merchantText:
            request.entity = .variableExpense
            request.dimensions = [.merchantText]
            request.targetName = nil
            request.textQuery = target
            request.targetDisplayName = target
            request.expenseScope = request.expenseScope ?? .unified
        case .card:
            if request.expectedAnswerShape == .list || request.operation == .list {
                request.entity = .variableExpense
                request.operation = .list
            } else {
                request.entity = .card
            }
            request.dimensions = [.card]
            request.targetName = target
            request.textQuery = nil
            request.targetDisplayName = target
        case .category:
            if request.expectedAnswerShape == .list || request.operation == .list || containsAny(normalized, ["transactions", "expenses"]) {
                request.entity = .variableExpense
                request.operation = .list
            } else {
                request.entity = .category
            }
            request.dimensions = [.category]
            request.targetName = target
            request.textQuery = nil
            request.targetDisplayName = target
            request.expenseScope = request.expenseScope ?? .unified
        case .incomeSource:
            request.entity = .income
            request.dimensions = [.incomeSource]
            request.targetName = target
            request.textQuery = nil
            request.targetDisplayName = target
        case .preset:
            request.entity = .preset
            request.dimensions = [.preset]
            request.targetName = target
            request.textQuery = nil
            request.targetDisplayName = target
        case .savingsAccount:
            request.entity = .savingsAccount
            request.dimensions = [.savingsAccount]
            request.targetName = target
            request.textQuery = nil
            request.targetDisplayName = target
        case .reconciliationAccount:
            request.entity = .reconciliationAccount
            request.dimensions = [.reconciliationAccount]
            request.targetName = target
            request.textQuery = nil
            request.targetDisplayName = target
        case .budget:
            request.entity = .budget
            request.dimensions = [.budget]
            request.targetName = target
            request.textQuery = nil
            request.targetDisplayName = target
        case .workspace, .date, nil:
            if request.dimensions.contains(.merchantText) {
                request.textQuery = target
                request.targetDisplayName = target
                request.targetName = nil
            } else if request.dimensions.contains(.incomeSource) || request.entity == .income {
                request.entity = .income
                request.dimensions = unique(request.dimensions + [.incomeSource])
                request.targetName = target
                request.targetDisplayName = target
            } else if request.dimensions.contains(.savingsAccount) || request.entity == .savingsAccount {
                request.dimensions = [.savingsAccount]
                request.targetName = target
                request.targetDisplayName = target
            } else if request.dimensions.contains(.reconciliationAccount) || request.entity == .reconciliationAccount {
                request.dimensions = [.reconciliationAccount]
                request.targetName = target
                request.targetDisplayName = target
            } else if request.dimensions.contains(.preset) || request.entity == .preset {
                request.dimensions = [.preset]
                request.targetName = target
                request.targetDisplayName = target
            } else if request.dimensions.contains(.budget) || request.entity == .budget {
                request.dimensions = [.budget]
                request.targetName = target
                request.targetDisplayName = target
            } else if request.dimensions.contains(.card) || request.entity == .card {
                request.dimensions = [.card]
                request.targetName = target
                request.targetDisplayName = target
            } else if request.dimensions.contains(.category) || request.entity == .category {
                request.dimensions = [.category]
                request.targetName = target
                request.targetDisplayName = target
            } else {
                request.entity = .variableExpense
                request.dimensions = []
                request.targetName = target
                request.textQuery = nil
                request.targetDisplayName = target
                request.expenseScope = request.expenseScope ?? .unified
            }
        }

        return request
    }

    private func applyRefinements(from normalized: String, to request: inout MarinaSemanticRequest) {
        if let dateToken = explicitDateToken(in: normalized) {
            request.dateRangeToken = dateToken
        }
        if let limit = firstInteger(in: normalized) {
            request.resultLimit = min(max(limit, 1), HomeQuery.maxResultLimit)
        }
        if let sort = sort(in: normalized) {
            request.sort = sort
        }
        if let expenseScope = expenseScope(in: normalized) {
            request.expenseScope = expenseScope
        }
        if let incomeState = incomeState(in: normalized) {
            request.incomeState = incomeState
            if request.entity == .income, request.operation == .share {
                request.operation = .sum
                request.expectedAnswerShape = .metric
            }
        }
    }

    private func isCategoryAvailabilityFollowUp(_ normalized: String) -> Bool {
        guard containsAny(normalized, ["which", "what", "list", "show"]) else {
            return false
        }

        if categoryAvailabilityFilter(in: normalized) != nil {
            return true
        }

        return containsAny(normalized, ["categories", "category", "ones", "available", "availability"])
    }

    private func isDrillDownPrompt(_ normalized: String) -> Bool {
        containsAny(normalized, [
            "show details",
            "details",
            "drill down",
            "transactions",
            "expenses",
            "expense rows",
            "expense row",
            "which ones",
            "which one",
            "what caused",
            "what made up",
            "what made this up",
            "driving",
            "behind this",
            "behind it",
            "largest",
            "biggest",
            "highest",
            "top ",
            "recent",
            "latest"
        ])
    }

    private func asksForExpenseRows(_ normalized: String) -> Bool {
        containsAny(normalized, [
            "expense",
            "expenses",
            "transaction",
            "transactions",
            "charge",
            "charges",
            "purchase",
            "purchases",
            "expense row",
            "expense rows",
            "behind this",
            "behind it"
        ])
    }

    private func isFollowUpCue(_ normalized: String) -> Bool {
        containsAny(normalized, [
            "what about",
            "how about",
            "which",
            "show",
            "list",
            "only",
            "instead",
            "i meant",
            "not ",
            "for ",
            "last month",
            "this month",
            "last period",
            "previous period",
            "current period",
            "all time",
            "largest",
            "smallest",
            "recent",
            "actual",
            "planned"
        ])
    }

    private func hasExplicitRefinement(_ normalized: String) -> Bool {
        explicitDateToken(in: normalized) != nil
            || firstInteger(in: normalized) != nil
            || sort(in: normalized) != nil
            || expenseScope(in: normalized) != nil
            || incomeState(in: normalized) != nil
    }

    private func isCorrectionPrompt(_ normalized: String) -> Bool {
        containsAny(normalized, ["i meant", "instead", "not ", "what about", "how about", "for "])
    }

    private func categoryAvailabilityFilter(in normalized: String) -> MarinaCategoryAvailabilityFilter? {
        if containsAny(normalized, ["over limit", "over budget", "over category limit", "categories over", "category over"]) {
            return .over
        }

        if containsAny(normalized, ["near limit", "near budget", "near category limit", "categories near", "category near"]) {
            return .near
        }

        if containsAny(normalized, ["under limit", "under budget", "within limit", "below limit", "under category limit", "categories under", "category under"]) {
            return .underLimit
        }

        return nil
    }

    private func explicitDateToken(in normalized: String) -> MarinaSemanticDateRangeToken? {
        if normalized.contains("this month") {
            return .currentMonth
        }
        if normalized.contains("last month") || normalized.contains("previous month") {
            return .previousMonth
        }
        if normalized.contains("last period") || normalized.contains("previous period") {
            return .previousPeriod
        }
        if normalized.contains("next 7 days") || normalized.contains("next seven days") {
            return .nextSevenDays
        }
        if normalized.contains("all time") || normalized.contains("ever") {
            return .allTime
        }
        if normalized.contains("this period") || normalized.contains("current period") {
            return .currentPeriod
        }
        return nil
    }

    private func sort(in normalized: String) -> MarinaSemanticSort? {
        if containsAny(normalized, ["largest", "biggest", "highest", "most expensive", "largest first", "amount descending", "by amount"]) {
            return .amountDescending
        }
        if containsAny(normalized, ["smallest", "lowest", "cheapest", "smallest first", "amount ascending"]) {
            return .amountAscending
        }
        if containsAny(normalized, ["oldest", "date ascending"]) {
            return .dateAscending
        }
        if containsAny(normalized, ["recent", "latest", "newest", "date descending"]) {
            return .dateDescending
        }
        if containsAny(normalized, ["alphabetical", "by name", "name ascending"]) {
            return .nameAscending
        }
        return nil
    }

    private func expenseScope(in normalized: String) -> MarinaSemanticExpenseScope? {
        if containsAny(normalized, ["only planned", "planned only"]) {
            return .planned
        }
        if containsAny(normalized, ["only variable", "variable only", "actual expenses only"]) {
            return .variable
        }
        if containsAny(normalized, ["include planned", "planned and variable", "all expenses"]) {
            return .unified
        }
        return nil
    }

    private func incomeState(in normalized: String) -> MarinaSemanticIncomeState? {
        if containsAny(normalized, ["actual only", "only actual", "actual income", "received income"]) {
            return .actual
        }
        if containsAny(normalized, ["planned only", "only planned", "planned income", "expected income"]) {
            return .planned
        }
        if containsAny(normalized, ["all income", "include planned income", "planned and actual income"]) {
            return .all
        }
        return nil
    }

    private func explicitTargetDimension(in normalized: String, target: String) -> MarinaSemanticDimension? {
        let target = target.lowercased()
        if containsAny(normalized, ["merchant ", " merchant", "store ", " store", "vendor ", " vendor", "description ", " description", "title ", " title"])
            || target.contains(" store") {
            return .merchantText
        }
        if normalized.contains(" card") {
            return .card
        }
        if normalized.contains(" categor") {
            return .category
        }
        if normalized.contains(" income source") || normalized.contains(" paycheck") || normalized.contains(" income") {
            return .incomeSource
        }
        if normalized.contains(" preset") {
            return .preset
        }
        if normalized.contains(" savings") {
            return .savingsAccount
        }
        if normalized.contains(" reconciliation") || normalized.contains(" balance") {
            return .reconciliationAccount
        }
        if normalized.contains(" budget") {
            return .budget
        }
        return nil
    }

    private func correctionTarget(from prompt: String, normalized: String) -> String? {
        if let commaTarget = targetAfterNotComma(in: prompt) {
            return commaTarget
        }

        return targetAfterAnyMarkerWithStop(
            in: normalized,
            markers: ["i meant ", "what about ", "how about ", "instead of ", "for ", "use "],
            stopMarkers: stopMarkers
        )
    }

    private func transactionTarget(in normalized: String) -> String? {
        if let target = targetBeforeAnyMarker(in: normalized, markers: [" transactions", " expenses"]) {
            return target
        }
        return nil
    }

    private func targetAfterNotComma(in prompt: String) -> String? {
        let pattern = #"(?i)\bnot\s+.+?,\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = prompt as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: prompt, range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        return cleanedTarget(ns.substring(with: match.range(at: 1)))
    }

    private var stopMarkers: [String] {
        [
            " instead",
            " this month",
            " current month",
            " last month",
            " previous month",
            " this period",
            " current period",
            " last period",
            " previous period",
            " all time",
            " ever",
            " transactions",
            " expenses",
            " details",
            " only",
            " largest",
            " biggest",
            " highest",
            " recent",
            " latest"
        ]
    }

    private func targetAfterAnyMarkerWithStop(
        in normalized: String,
        markers: [String],
        stopMarkers: [String]
    ) -> String? {
        for marker in markers {
            guard let range = normalized.range(of: marker) else { continue }
            let tail = String(normalized[range.upperBound...])
            let stopped = prefixBeforeAnyMarker(in: tail, markers: stopMarkers) ?? tail
            if let target = cleanedTarget(stopped) {
                return target
            }
        }
        return nil
    }

    private func targetBeforeAnyMarker(in normalized: String, markers: [String]) -> String? {
        for marker in markers {
            guard let range = normalized.range(of: marker) else { continue }
            let head = String(normalized[..<range.lowerBound])
            if let target = cleanedTarget(head) {
                return target
            }
        }
        return nil
    }

    private func prefixBeforeAnyMarker(in value: String, markers: [String]) -> String? {
        let matches = markers.compactMap { marker -> String.Index? in
            value.range(of: marker)?.lowerBound
        }
        guard let first = matches.min() else { return nil }
        return String(value[..<first])
    }

    private func cleanedTarget(_ value: String) -> String? {
        var target = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        for prefix in [
            "show my ",
            "show the ",
            "show ",
            "list my ",
            "list the ",
            "list ",
            "what about ",
            "how about ",
            "for ",
            "use ",
            "i meant ",
            "my ",
            "the ",
            "a ",
            "an ",
            "card ",
            "category ",
            "merchant ",
            "store ",
            "vendor ",
            "income source ",
            "preset ",
            "budget ",
            "savings account "
        ] {
            if target.lowercased().hasPrefix(prefix) {
                target.removeFirst(prefix.count)
            }
        }

        for suffix in [" instead", " only"] {
            if target.lowercased().hasSuffix(suffix) {
                target.removeLast(suffix.count)
            }
        }

        target = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard target.isEmpty == false,
              ["this", "that", "those", "ones", "one", "last month", "this month", "last period", "current period"].contains(target.lowercased()) == false else {
            return nil
        }

        return target
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")
    }

    private func firstInteger(in normalized: String) -> Int? {
        let pattern = #"(?<![.])\b([0-9]+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = normalized as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: normalized, range: range),
              match.numberOfRanges > 1 else {
            return nil
        }
        return Int(ns.substring(with: match.range(at: 1)))
    }

    private func containsAny(_ value: String, _ needles: [String]) -> Bool {
        needles.contains { value.contains($0) }
    }

    private func wordCount(in value: String) -> Int {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .count
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func unique(_ dimensions: [MarinaSemanticDimension]) -> [MarinaSemanticDimension] {
        var result: [MarinaSemanticDimension] = []
        for dimension in dimensions where result.contains(dimension) == false {
            result.append(dimension)
        }
        return result
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
    }
}
