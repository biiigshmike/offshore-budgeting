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
    private let presenter: MarinaAnswerPresenter

    init(
        interpreter: (any MarinaModelInterpreting)? = nil,
        planner: MarinaQueryPlanner? = nil,
        snapshotProvider: MarinaWorkspaceSnapshotProvider? = nil,
        validator: MarinaSemanticRequestValidator? = nil,
        executor: MarinaQueryExecutor? = nil,
        presenter: MarinaAnswerPresenter? = nil
    ) {
        self.interpreter = interpreter ?? MarinaModelInterpreterFactory.makeDefault()
        self.planner = planner ?? MarinaQueryPlanner()
        self.snapshotProvider = snapshotProvider ?? MarinaWorkspaceSnapshotProvider()
        self.validator = validator ?? MarinaSemanticRequestValidator()
        self.executor = executor ?? MarinaQueryExecutor()
        self.presenter = presenter ?? MarinaAnswerPresenter()
    }

    func answer(
        prompt: String,
        workspace: Workspace,
        modelContext: ModelContext,
        ambientDateRange: HomeQueryDateRange?,
        defaultBudgetingPeriod: BudgetingPeriod,
        now: Date = Date()
    ) async -> HomeAnswer {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = MarinaBrainContext(
            workspace: workspace,
            modelContext: modelContext,
            ambientDateRange: ambientDateRange,
            defaultBudgetingPeriod: defaultBudgetingPeriod,
            now: now
        )

        do {
            let interpreted = try await interpreter.interpretedSemanticRequest(for: trimmedPrompt, context: context)
            return try answer(interpreted: interpreted, prompt: trimmedPrompt, context: context)
        } catch {
            let result = MarinaExecutionResult(
                kind: .message,
                title: "Marina hit a snag",
                subtitle: error.localizedDescription
            )
            return presenter.present(result: result, prompt: trimmedPrompt, queryID: UUID())
        }
    }

    func answer(
        resolvedRequest: MarinaSemanticRequest,
        prompt: String,
        workspace: Workspace,
        modelContext: ModelContext,
        ambientDateRange: HomeQueryDateRange?,
        defaultBudgetingPeriod: BudgetingPeriod,
        now: Date = Date()
    ) async -> HomeAnswer {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let context = MarinaBrainContext(
            workspace: workspace,
            modelContext: modelContext,
            ambientDateRange: ambientDateRange,
            defaultBudgetingPeriod: defaultBudgetingPeriod,
            now: now
        )
        let interpreted = MarinaInterpretedSemanticRequest(
            request: resolvedRequest,
            confidence: .high,
            source: .ruleBased,
            diagnosticNotes: ["Resolved from Marina clarification choice."]
        )

        do {
            return try answer(interpreted: interpreted, prompt: trimmedPrompt, context: context)
        } catch {
            let result = MarinaExecutionResult(
                kind: .message,
                title: "Marina hit a snag",
                subtitle: error.localizedDescription
            )
            return presenter.present(result: result, prompt: trimmedPrompt, queryID: UUID())
        }
    }

    private func answer(
        interpreted: MarinaInterpretedSemanticRequest,
        prompt: String,
        context: MarinaBrainContext
    ) throws -> HomeAnswer {
        let snapshot = try snapshotProvider.snapshot(for: context.workspace, modelContext: context.modelContext)
        let validated = validator.validate(interpreted: interpreted, snapshot: snapshot)
        let queryPlan = planner.plan(
            request: validated.request,
            ambientDateRange: context.ambientDateRange,
            defaultBudgetingPeriod: context.defaultBudgetingPeriod,
            now: context.now,
            clarificationChoices: validated.clarificationChoices
        )
        let result = executor.execute(plan: queryPlan, snapshot: snapshot)
        return presenter.present(
            result: resultWithDebugTraceIfNeeded(result, interpreted: validated, plan: queryPlan),
            prompt: prompt,
            queryID: queryPlan.id
        )
    }

    private func resultWithDebugTraceIfNeeded(
        _ result: MarinaExecutionResult,
        interpreted: MarinaInterpretedSemanticRequest,
        plan: MarinaQueryPlan
    ) -> MarinaExecutionResult {
        guard DebugFeatureFlagResolver.isEnabled(key: Self.showSemanticTraceKey, fallback: false) else {
            return result
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
        let explanation = [result.explanation, trace]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n\n")

        return MarinaExecutionResult(
            kind: result.kind,
            title: result.title,
            subtitle: result.subtitle,
            primaryValue: result.primaryValue,
            rows: result.rows,
            attachment: result.attachment,
            explanation: explanation
        )
    }
}
