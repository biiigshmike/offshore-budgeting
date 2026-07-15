import Foundation

@MainActor
protocol MarinaUniversalRoutingAttempting {
    func attemptUniversalResult(
        request: MarinaSemanticRequest,
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot,
        context: MarinaUniversalPlanningContext
    ) -> MarinaUniversalRoutingResult
}

extension MarinaUniversalRoutingHarness: MarinaUniversalRoutingAttempting {}

enum MarinaDualPathQueryResult: Equatable {
    case legacy(MarinaExecutionResult, diagnostics: MarinaUniversalRoutingDiagnostics?)
    case universal(MarinaExecutionResult, diagnostics: MarinaUniversalRoutingDiagnostics)

    var executionResult: MarinaExecutionResult {
        switch self {
        case let .legacy(result, _),
             let .universal(result, _):
            return result
        }
    }
}

@MainActor
struct MarinaDualPathQueryExecutor {
    let legacyExecutor: MarinaQueryExecutor
    let universalHarness: (any MarinaUniversalRoutingAttempting)?
    let policy: MarinaUniversalRoutingPolicy

    init(
        legacyExecutor: MarinaQueryExecutor,
        universalHarness: (any MarinaUniversalRoutingAttempting)?,
        policy: MarinaUniversalRoutingPolicy
    ) {
        self.legacyExecutor = legacyExecutor
        self.universalHarness = universalHarness
        self.policy = policy
    }

    func execute(
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot,
        planningContext: MarinaUniversalPlanningContext
    ) -> MarinaExecutionResult {
        executeResult(
            plan: plan,
            snapshot: snapshot,
            planningContext: planningContext
        )
        .executionResult
    }

    func executeResult(
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot,
        planningContext: MarinaUniversalPlanningContext
    ) -> MarinaDualPathQueryResult {
        guard policy.isEnabled else {
            return .legacy(
                legacyExecutor.execute(plan: plan, snapshot: snapshot),
                diagnostics: nil
            )
        }

        guard let universalHarness else {
            return .legacy(
                legacyExecutor.execute(plan: plan, snapshot: snapshot),
                diagnostics: nil
            )
        }

        let attempt = universalHarness.attemptUniversalResult(
            request: plan.semanticRequest,
            plan: plan,
            snapshot: snapshot,
            context: planningContext
        )

        switch attempt {
        case let .universal(result, diagnostics):
            return .universal(result, diagnostics: diagnostics)
        case let .fallback(_, diagnostics):
            return .legacy(
                legacyExecutor.execute(plan: plan, snapshot: snapshot),
                diagnostics: diagnostics
            )
        }
    }
}
