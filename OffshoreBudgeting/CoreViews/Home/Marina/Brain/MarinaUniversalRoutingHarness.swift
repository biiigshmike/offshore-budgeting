import Foundation

enum MarinaUniversalRoutingResult: Equatable {
    case universal(MarinaExecutionResult, diagnostics: MarinaUniversalRoutingDiagnostics)
    case fallback(reason: MarinaUniversalFallbackReason, diagnostics: MarinaUniversalRoutingDiagnostics)
}

enum MarinaUniversalFallbackReason: String, Codable, Equatable, Sendable {
    case disabled
    case notAllowlisted
    case unsupportedBridge
    case unsupportedRunner
    case unsupportedPresentation
    case parityNotProven
    case missingDateContext
    case missingFormulaContext
    case ambiguousTarget
    case legacyPreferred
}

struct MarinaUniversalRoutingDiagnostics: Equatable, Sendable {
    let requestEntity: MarinaSemanticEntity
    let operation: MarinaSemanticOperation
    let measure: MarinaSemanticMeasure?
    let scenario: MarinaUniversalRoutingScenario?
    let usedUniversal: Bool
    let fallbackReason: MarinaUniversalFallbackReason?
    let notes: [String]

    init(
        requestEntity: MarinaSemanticEntity,
        operation: MarinaSemanticOperation,
        measure: MarinaSemanticMeasure?,
        scenario: MarinaUniversalRoutingScenario? = nil,
        usedUniversal: Bool,
        fallbackReason: MarinaUniversalFallbackReason?,
        notes: [String]
    ) {
        self.requestEntity = requestEntity
        self.operation = operation
        self.measure = measure
        self.scenario = scenario
        self.usedUniversal = usedUniversal
        self.fallbackReason = fallbackReason
        self.notes = notes
    }
}

@MainActor
struct MarinaUniversalRoutingHarness {
    let bridge: MarinaSemanticUniversalPlanBridge
    let runner: MarinaUniversalQueryRunner
    let presenter: MarinaUniversalResultPresenter
    let policy: MarinaUniversalRoutingPolicy

    func attemptUniversalResult(
        request: MarinaSemanticRequest,
        plan: MarinaQueryPlan,
        snapshot: MarinaWorkspaceSnapshot,
        context: MarinaUniversalPlanningContext
    ) -> MarinaUniversalRoutingResult {
        guard policy.isEnabled else {
            return fallback(.disabled, request: request, notes: ["Universal routing policy is disabled."])
        }

        guard let scenario = policy.scenario(for: request),
              policy.allowedScenarios.contains(scenario) else {
            return fallback(.notAllowlisted, request: request, notes: ["Request is not allowlisted for universal routing."])
        }

        if requiresDateContext(scenario), plan.dateRange == nil {
            return fallback(
                .missingDateContext,
                request: request,
                notes: ["Scenario \(scenario.rawValue) requires a resolved date context."]
            )
        }

        let bridgeResult = bridge.makePlan(from: request, planningContext: context)
        let universalPlan: MarinaUniversalQueryPlan
        switch bridgeResult {
        case let .plan(plan):
            universalPlan = plan
        case let .unsupported(reason):
            return fallback(
                fallbackReason(forBridgeFailure: reason),
                request: request,
                notes: [
                    "Scenario=\(scenario.rawValue)",
                    "Bridge unsupported=\(reason.rawValue)"
                ]
            )
        }

        let universalResult = runner.runFormulaAware(plan: universalPlan, snapshot: snapshot)
        if case let .unsupported(reason) = universalResult {
            return fallback(
                fallbackReason(forRunnerFailure: reason),
                request: request,
                notes: [
                    "Scenario=\(scenario.rawValue)",
                    "Runner unsupported=\(reason.rawValue)"
                ]
            )
        }

        let presentation = presenter.presentedResult(
            for: universalResult,
            plan: universalPlan,
            context: MarinaUniversalPresentationContext(
                dateRange: universalPlan.dateRange ?? plan.dateRange,
                comparisonDateRange: universalPlan.comparisonDateRange ?? plan.comparisonDateRange,
                now: context.now,
                calendar: context.calendar
            )
        )

        if let unsupportedReason = presentation.unsupportedReason {
            return fallback(
                .unsupportedPresentation,
                request: request,
                notes: [
                    "Scenario=\(scenario.rawValue)",
                    "Presentation unsupported=\(unsupportedReason.rawValue)"
                ]
            )
        }

        return .universal(
            presentation.executionResult,
            diagnostics: diagnostics(
                request: request,
                usedUniversal: true,
                fallbackReason: nil,
                notes: [
                    "Scenario=\(scenario.rawValue)",
                    "Universal routing succeeded."
                ]
            )
        )
    }

    private func fallback(
        _ reason: MarinaUniversalFallbackReason,
        request: MarinaSemanticRequest,
        notes: [String]
    ) -> MarinaUniversalRoutingResult {
        .fallback(
            reason: reason,
            diagnostics: diagnostics(
                request: request,
                usedUniversal: false,
                fallbackReason: reason,
                notes: notes
            )
        )
    }

    private func diagnostics(
        request: MarinaSemanticRequest,
        usedUniversal: Bool,
        fallbackReason: MarinaUniversalFallbackReason?,
        notes: [String]
    ) -> MarinaUniversalRoutingDiagnostics {
        MarinaUniversalRoutingDiagnostics(
            requestEntity: request.entity,
            operation: request.operation,
            measure: request.measure,
            scenario: policy.scenario(for: request),
            usedUniversal: usedUniversal,
            fallbackReason: fallbackReason,
            notes: notes
        )
    }

    private func requiresDateContext(_ scenario: MarinaUniversalRoutingScenario) -> Bool {
        switch scenario {
        case .budgetRemainingRoom,
             .safeDailySpend,
             .budgetBurnRate,
             .budgetProjectedSpend,
             .budgetPaceDifference,
             .budgetCoverageRatio,
             .incomeCoverageRatio:
            return true
        case .merchantVariableSpend,
             .categoryVariableSpend,
             .cardVariableSpend,
             .plannedExpenseSum,
             .latestVariableExpense,
             .biggestVariableExpenseRows,
             .nextPlannedExpense,
             .unifiedExpenseCategoryGroups,
             .unifiedExpenseCardGroups,
             .incomeTotal,
             .incomeBySource,
             .savingsTotalExplicitAccount,
             .reconciliationBalanceExplicitAccount:
            return false
        }
    }

    private func fallbackReason(
        forBridgeFailure reason: MarinaCapabilityFailureReason
    ) -> MarinaUniversalFallbackReason {
        switch reason {
        case .missingDateField:
            return .missingDateContext
        case .ambiguousEntity:
            return .ambiguousTarget
        case .missingEntityDescriptor,
             .internalOnly,
             .operationNotSupported,
             .fieldNotSearchable,
             .fieldNotFilterable,
             .fieldNotGroupable,
             .fieldNotSortable,
             .measureNotAvailable,
             .missingAmountField,
             .unresolvedEntity,
             .readOnly,
             .unsupportedCombination:
            return .unsupportedBridge
        }
    }

    private func fallbackReason(
        forRunnerFailure reason: MarinaCapabilityFailureReason
    ) -> MarinaUniversalFallbackReason {
        switch reason {
        case .missingDateField:
            return .missingDateContext
        case .ambiguousEntity:
            return .ambiguousTarget
        case .missingEntityDescriptor,
             .internalOnly,
             .operationNotSupported,
             .fieldNotSearchable,
             .fieldNotFilterable,
             .fieldNotGroupable,
             .fieldNotSortable,
             .measureNotAvailable,
             .missingAmountField,
             .unresolvedEntity,
             .readOnly,
             .unsupportedCombination:
            return .unsupportedRunner
        }
    }
}
