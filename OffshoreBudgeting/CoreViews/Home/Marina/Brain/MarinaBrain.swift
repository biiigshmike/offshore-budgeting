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
    private let insightNarrator: any MarinaInsightNarrating
    private let presenter: MarinaAnswerPresenter

    init(
        interpreter: (any MarinaModelInterpreting)? = nil,
        planner: MarinaQueryPlanner? = nil,
        snapshotProvider: MarinaWorkspaceSnapshotProvider? = nil,
        validator: MarinaSemanticRequestValidator? = nil,
        executor: MarinaQueryExecutor? = nil,
        insightNarrator: (any MarinaInsightNarrating)? = nil,
        presenter: MarinaAnswerPresenter? = nil
    ) {
        self.interpreter = interpreter ?? MarinaModelInterpreterFactory.makeDefault()
        self.planner = planner ?? MarinaQueryPlanner()
        self.snapshotProvider = snapshotProvider ?? MarinaWorkspaceSnapshotProvider()
        self.validator = validator ?? MarinaSemanticRequestValidator()
        self.executor = executor ?? MarinaQueryExecutor()
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
        now: Date = Date()
    ) async -> HomeAnswer {
        let seed = await answerSeed(
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

        do {
            let interpreted = try await interpreter.interpretedSemanticRequest(for: trimmedPrompt, context: context)
            return try answerSeed(interpreted: interpreted, prompt: trimmedPrompt, context: context)
        } catch {
            let result = MarinaExecutionResult(
                kind: .message,
                title: "I hit a snag",
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
            return try answerSeed(interpreted: interpreted, prompt: trimmedPrompt, context: context)
        } catch {
            let result = MarinaExecutionResult(
                kind: .message,
                title: "I hit a snag",
                subtitle: error.localizedDescription
            )
            let answer = presenter.present(result: result, prompt: trimmedPrompt, queryID: UUID())
            return MarinaAnswerSeed(answer: answer, insightContext: nil, finalExplanationSuffix: nil)
        }
    }

    private func answerSeed(
        interpreted: MarinaInterpretedSemanticRequest,
        prompt: String,
        context: MarinaBrainContext
    ) throws -> MarinaAnswerSeed {
        let snapshot = try snapshotProvider.snapshot(
            for: context.workspace,
            modelContext: context.modelContext,
            homeContext: context.homeContext,
            now: context.now
        )
        let validated = validator.validate(interpreted: interpreted, snapshot: snapshot)
        let queryPlan = planner.plan(
            request: validated.request,
            ambientDateRange: context.ambientDateRange,
            defaultBudgetingPeriod: context.defaultBudgetingPeriod,
            now: context.now,
            clarificationChoices: validated.clarificationChoices
        )
        let result = executor.execute(plan: queryPlan, snapshot: snapshot)
        let insightContext = MarinaInsightContext(
            prompt: prompt,
            result: result,
            plan: queryPlan
        )
        let narratableContext = insightContext.isNarratable ? insightContext : nil
        let debugTrace = debugTraceIfNeeded(interpreted: validated, plan: queryPlan)
        let seedResult = narratableContext == nil
            ? result.withAppendingExplanation(debugTrace)
            : result
        let answer = presenter.present(
            result: seedResult,
            prompt: prompt,
            queryID: queryPlan.id
        )
        return MarinaAnswerSeed(
            answer: answer,
            insightContext: narratableContext,
            finalExplanationSuffix: narratableContext == nil ? nil : debugTrace
        )
    }

    private func completedAnswer(from seed: MarinaAnswerSeed) async -> HomeAnswer {
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

    private func debugTraceIfNeeded(
        interpreted: MarinaInterpretedSemanticRequest,
        plan: MarinaQueryPlan
    ) -> String? {
        guard DebugFeatureFlagResolver.isEnabled(key: Self.showSemanticTraceKey, fallback: false) else {
            return nil
        }

        let trace = [
            "source=\(interpreted.source.rawValue)",
            "confidence=\(interpreted.confidence.rawValue)",
            "entity=\(plan.entity.rawValue)",
            "operation=\(plan.operation.rawValue)",
            "measure=\(plan.measure?.rawValue ?? "none")",
            "shape=\(plan.semanticRequest.expectedAnswerShape.rawValue)",
            "notes=\(interpreted.diagnosticNotes.joined(separator: " | "))"
        ].joined(separator: "\n")
        return trace
    }

    func completedAnswer(
        from seed: MarinaAnswerSeed,
        streamingNarration narration: String?
    ) -> HomeAnswer {
        answer(
            seed.answer,
            replacingExplanationWith: combinedExplanation(
                base: seed.answer.explanation,
                insight: narration,
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
            generatedAt: answer.generatedAt
        )
    }
}
