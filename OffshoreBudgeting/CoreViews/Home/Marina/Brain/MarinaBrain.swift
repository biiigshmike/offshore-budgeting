import Foundation
import SwiftData

@MainActor
struct MarinaBrain {
    private static let showSemanticTraceKey = "debug_marinaShowSemanticTrace"

    private let interpreter: any MarinaModelInterpreting
    private let planner: MarinaQueryPlanner
    private let snapshotProvider: MarinaWorkspaceSnapshotProvider
    private let validator: MarinaSemanticRequestValidator
    private let insightAnalyzer: MarinaInsightAnalyzer
    private let insightNarrator: any MarinaInsightNarrating
    private let presenter: MarinaAnswerPresenter

    init(
        interpreter: (any MarinaModelInterpreting)? = nil,
        planner: MarinaQueryPlanner? = nil,
        snapshotProvider: MarinaWorkspaceSnapshotProvider? = nil,
        validator: MarinaSemanticRequestValidator? = nil,
        insightAnalyzer: MarinaInsightAnalyzer? = nil,
        insightNarrator: (any MarinaInsightNarrating)? = nil,
        presenter: MarinaAnswerPresenter? = nil
    ) {
        self.interpreter = interpreter ?? MarinaModelInterpreterFactory.makeDefault()
        self.planner = planner ?? MarinaQueryPlanner()
        self.snapshotProvider = snapshotProvider ?? MarinaWorkspaceSnapshotProvider()
        self.validator = validator ?? MarinaSemanticRequestValidator()
        self.insightAnalyzer = insightAnalyzer ?? MarinaInsightAnalyzer()
        self.insightNarrator = insightNarrator ?? MarinaInsightNarrator()
        self.presenter = presenter ?? MarinaAnswerPresenter()
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
            homeContext: homeContext,
            conversationContext: conversationContext
        )

        do {
            let modelOutput = try await interpreter.interpretedSemanticRequest(
                for: trimmedPrompt,
                context: context
            )
            if modelOutput.attemptDiagnostics.last?.status == .terminal {
                return terminalCompilerAttemptSeed(
                    interpreted: modelOutput,
                    prompt: trimmedPrompt,
                    now: now
                )
            }
            let conversationContract = MarinaTypedConversationContract()
            let interpreted = conversationContract.interpretedRequest(
                modelOutput,
                conversationContext: conversationContext
            )
            let promptTreatment = conversationContract.promptTreatment(
                for: interpreted.request,
                conversationContext: conversationContext
            )
            return try answerSeed(
                interpreted: interpreted,
                prompt: trimmedPrompt,
                context: context,
                conversationContext: conversationContext,
                promptTreatment: promptTreatment,
                priorContextChangedRequest: promptTreatment != .standalone
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

    private func terminalCompilerAttemptSeed(
        interpreted: MarinaInterpretedSemanticRequest,
        prompt: String,
        now: Date
    ) -> MarinaAnswerSeed {
        let queryID = UUID()
        let plan = MarinaQueryPlan(
            id: queryID,
            semanticRequest: interpreted.request,
            dateRange: nil,
            comparisonDateRange: nil,
            now: now
        )
        let resultPresenter = MarinaUniversalResultPresenter()
        let result = resultPresenter.semanticBoundaryResult(
            for: interpreted.request,
            clarificationChoices: interpreted.clarificationChoices
        ) ?? resultPresenter.capabilityUnsupportedResult(.unsupportedCombination)
        let skippedNote = "Skipped candidate resolution, validation, planning, and execution after a terminal semantic compiler attempt."
        let trace = MarinaAnswerDebugTrace(
            originalPrompt: prompt,
            promptTreatment: .standalone,
            priorContextChangedRequest: false,
            interpretedRequest: interpreted.request,
            interpretedSource: interpreted.source,
            interpretedConfidence: interpreted.confidence,
            interpretedNotes: interpreted.diagnosticNotes,
            compilerAttempts: interpreted.attemptDiagnostics,
            candidateSearches: [],
            resolverOutput: interpreted.request,
            validatorOutput: interpreted.request,
            validatorAccepted: false,
            validatorNotes: [skippedNote],
            queryPlan: MarinaQueryPlanTrace(plan: plan),
            executionRoute: .notExecuted,
            executionSucceeded: false,
            rowCount: 0,
            evidenceRowSummaries: [],
            answerKind: result.kind,
            answerTitle: result.title,
            answerPrimaryValue: result.primaryValue,
            narrationRequested: false
        )
        let debugTrace = debugTraceIfNeeded(trace: trace)
        let answer = presenter.present(
            result: result.withAppendingExplanation(debugTrace),
            prompt: prompt,
            queryID: queryID,
            semanticContext: MarinaAnswerSemanticContext(plan: plan, result: result)
        )
        return MarinaAnswerSeed(
            answer: answer,
            insightContext: nil,
            finalExplanationSuffix: nil,
            debugTrace: trace
        )
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
            source: .foundationModel,
            diagnosticNotes: ["Executed deterministic Marina clarification choice request."]
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
        let defaultsToNamedBudgetRange = interpreted.request.dateRangeSource == .defaulted
            && interpreted.request.constraints.contains { $0.dimension == .budget }
        let candidateDateRange = defaultsToNamedBudgetRange
            ? nil
            : planner.plan(
                request: interpreted.request,
                ambientDateRange: context.ambientDateRange,
                defaultBudgetingPeriod: context.defaultBudgetingPeriod,
                now: context.now
            ).dateRange
        let validationTrace = validator.validateWithTrace(
            interpreted: interpreted,
            snapshot: snapshot,
            candidateDateRange: candidateDateRange
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
        let displayResult = resultWithTypedRecommendedFollowUp(result, insightBundle: insightBundle)
        let insightContext = MarinaInsightContext(
            prompt: prompt,
            result: displayResult,
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
            compilerAttempts: interpreted.attemptDiagnostics,
            candidateSearches: validationTrace.candidateSearches,
            resolverOutput: validationTrace.resolverOutput.request,
            validatorOutput: validated.request,
            validatorAccepted: validated.request.expectedAnswerShape != .unsupported && validated.request.expectedAnswerShape != .clarification,
            validatorNotes: validated.diagnosticNotes,
            queryPlan: MarinaQueryPlanTrace(plan: queryPlan),
            executionRoute: execution.route,
            executionSucceeded: execution.succeeded,
            rowCount: displayResult.rows.count,
            evidenceRowSummaries: evidenceRowSummaries(from: displayResult.rows),
            answerKind: displayResult.kind,
            answerTitle: displayResult.title,
            answerPrimaryValue: displayResult.primaryValue,
            narrationRequested: narratableContext != nil
        )
        let debugTrace = debugTraceIfNeeded(trace: structuredTrace)
        let seedResult = narratableContext == nil
            ? displayResult.withAppendingExplanation(debugTrace)
            : displayResult
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

    private func resultWithTypedRecommendedFollowUp(
        _ result: MarinaExecutionResult,
        insightBundle: MarinaInsightBundle?
    ) -> MarinaExecutionResult {
        guard result.kind == .message,
              let followUp = MarinaRecommendedFollowUp.suggestion(from: insightBundle?.followUps ?? []) else {
            return result
        }

        let question = MarinaRecommendedFollowUp.confirmationQuestion(for: followUp)
        let existingExplanation = result.explanation?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard question.isEmpty == false,
              existingExplanation?.range(of: question, options: [.caseInsensitive, .diacriticInsensitive]) == nil else {
            return result
        }

        let explanation = [existingExplanation, question]
            .compactMap { $0 }
            .filter { $0.isEmpty == false }
            .joined(separator: " ")

        return MarinaExecutionResult(
            kind: result.kind,
            title: result.title,
            subtitle: result.subtitle,
            primaryValue: result.primaryValue,
            rows: result.rows,
            attachment: result.attachment,
            explanation: explanation.isEmpty ? result.explanation : explanation,
            displayedRowCount: result.displayedRowCount,
            totalRowCount: result.totalRowCount,
            fullTotalAmount: result.fullTotalAmount,
            hasMore: result.hasMore,
            nextOffset: result.nextOffset
        )
    }

    private struct MarinaBrainExecution {
        let result: MarinaExecutionResult
        let route: MarinaAnswerDebugTrace.ExecutionRoute
        let succeeded: Bool
    }

    private func execute(
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot,
        context: MarinaBrainContext
    ) -> MarinaBrainExecution {
        let calendar = Calendar.current
        let resultPresenter = MarinaUniversalResultPresenter()
        if let boundaryResult = resultPresenter.semanticBoundaryResult(
            for: plan.semanticRequest,
            clarificationChoices: plan.clarificationChoices
        ) {
            return MarinaBrainExecution(
                result: boundaryResult,
                route: .universal,
                succeeded: plan.semanticRequest.expectedAnswerShape == .acknowledgement
            )
        }

        let planningContext = MarinaUniversalPlanningContext(
            ambientDateRange: context.ambientDateRange,
            defaultBudgetingPeriod: context.defaultBudgetingPeriod,
            now: context.now,
            calendar: calendar
        )
        let formulaRegistry = MarinaFormulaRegistry(now: context.now, calendar: calendar)
        let bridge = MarinaSemanticUniversalPlanBridge(formulaRegistry: formulaRegistry)
        switch bridge.makePlan(
            from: plan.semanticRequest,
            planningContext: planningContext
        ) {
        case let .unsupported(reason):
            return MarinaBrainExecution(
                result: resultPresenter.capabilityUnsupportedResult(reason),
                route: .universal,
                succeeded: false
            )
        case let .plan(universalPlan):
            let universalResult = MarinaUniversalQueryRunner(formulaRegistry: formulaRegistry)
                .runFormulaAware(plan: universalPlan, snapshot: snapshot)
            let executionSucceeded: Bool
            if case .unsupported = universalResult {
                executionSucceeded = false
            } else {
                executionSucceeded = true
            }
            let executionResult = resultPresenter.presentationResult(
                for: universalResult,
                plan: universalPlan,
                context: MarinaUniversalPresentationContext(
                    dateRange: universalPlan.dateRange,
                    comparisonDateRange: universalPlan.comparisonDateRange,
                    semanticRequest: plan.semanticRequest,
                    now: context.now,
                    calendar: calendar
                )
            )
            return MarinaBrainExecution(
                result: executionResult,
                route: .universal,
                succeeded: executionSucceeded
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

struct MarinaTypedConversationContract {
    func interpretedRequest(
        _ interpreted: MarinaInterpretedSemanticRequest,
        conversationContext: MarinaConversationContext
    ) -> MarinaInterpretedSemanticRequest {
        guard interpreted.request.continuationIntent == .showMore else {
            return interpreted
        }

        var typed = interpreted
        guard let previous = conversationContext.lastSemanticContext,
              previous.answerKind == .list,
              previous.hasMore != false,
              let nextOffset = previous.nextOffset else {
            typed.request = MarinaSemanticRequest(
                entity: .workspace,
                operation: .list,
                expectedAnswerShape: .unsupported,
                unsupportedReason: .unsupportedCombination
            )
            typed.diagnosticNotes.append("Rejected typed show-more outcome without a usable list continuation.")
            return typed
        }

        var continuation = previous.request
        continuation.continuationIntent = .showMore
        continuation.resultLimit = previous.request.resultLimit
        continuation.resultOffset = nextOffset
        continuation.expectedAnswerShape = .list
        continuation.clarificationQuestion = nil
        continuation.unsupportedReason = nil
        typed.request = continuation
        typed.diagnosticNotes.append("Applied typed show-more continuation using the prior next offset and page limit.")
        return typed
    }

    func promptTreatment(
        for request: MarinaSemanticRequest,
        conversationContext: MarinaConversationContext
    ) -> MarinaAnswerDebugTrace.PromptTreatment {
        if request.expectedAnswerShape == .acknowledgement {
            return .declinedFollowUp
        }

        if let followUpRequest = conversationContext.lastRecommendedFollowUp?.semanticRequest,
           request == followUpRequest {
            return .recommendedFollowUpConfirmation
        }

        if request.continuationIntent == .showMore
            || request.dateRangeSource == .conversationContext
            || conversationContext.lastTurn?.clarificationOptions.contains(where: {
                $0.executableRequest == request
            }) == true {
            return .contextualFollowUp
        }

        return .standalone
    }
}
