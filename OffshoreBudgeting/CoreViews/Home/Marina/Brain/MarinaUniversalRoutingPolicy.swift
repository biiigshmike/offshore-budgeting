import Foundation

nonisolated enum MarinaUniversalRoutingScenario: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case merchantVariableSpend
    case categoryVariableSpend
    case cardVariableSpend
    case plannedExpenseSum
    case latestVariableExpense
    case biggestVariableExpenseRows
    case nextPlannedExpense
    case unifiedExpenseCategoryGroups
    case unifiedExpenseCardGroups
    case incomeTotal
    case incomeBySource
    case savingsTotalExplicitAccount
    case reconciliationBalanceExplicitAccount
    case budgetRemainingRoom
    case safeDailySpend
    case budgetBurnRate
    case budgetProjectedSpend
    case budgetPaceDifference
    case budgetCoverageRatio
    case incomeCoverageRatio
    case categoryAvailability
    case categoryConcentration
    case presetRecurringBurden
    case forecastSavings
}

nonisolated struct MarinaUniversalRoutingPolicy: Equatable, Sendable {
    let isEnabled: Bool
    let allowedScenarios: Set<MarinaUniversalRoutingScenario>

    func allows(_ request: MarinaSemanticRequest) -> Bool {
        guard isEnabled,
              let scenario = scenario(for: request) else {
            return false
        }
        return allowedScenarios.contains(scenario)
    }

    func scenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        guard request.expectedAnswerShape != .clarification,
              request.expectedAnswerShape != .unsupported,
              request.unsupportedReason == nil,
              request.comparisonTargetName == nil,
              request.whatIfAmount == nil,
              blockedOperations.contains(request.operation) == false else {
            return nil
        }

        switch request.entity {
        case .variableExpense:
            return variableExpenseScenario(for: request)
        case .plannedExpense:
            return plannedExpenseScenario(for: request)
        case .income:
            return incomeScenario(for: request)
        case .savingsAccount:
            return savingsScenario(for: request)
        case .reconciliationAccount:
            return reconciliationScenario(for: request)
        case .budget:
            return budgetScenario(for: request)
        case .category:
            return categoryScenario(for: request)
        case .preset:
            return presetScenario(for: request)
        case .workspace, .card:
            return nil
        }
    }

    private var blockedOperations: Set<MarinaSemanticOperation> {
        [.whatIf]
    }

    private func variableExpenseScenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        guard expenseScopeIsNilOr(request, .variable) else {
            if request.expenseScope == .unified {
                return unifiedExpenseScenario(for: request)
            }
            return nil
        }

        if request.operation == .sum,
           request.measure == .budgetImpact,
           request.expectedAnswerShape == .metric,
           exactDimensions(request, [.merchantText]),
           hasTextQuery(request),
           hasNoTargetName(request) {
            return .merchantVariableSpend
        }

        if request.operation == .sum,
           request.measure == .budgetImpact,
           request.expectedAnswerShape == .metric,
           exactDimensions(request, [.category]),
           hasTargetName(request),
           hasNoTextQuery(request) {
            return .categoryVariableSpend
        }

        if request.operation == .sum,
           request.measure == .budgetImpact,
           request.expectedAnswerShape == .metric,
           exactDimensions(request, [.card]),
           hasTargetName(request),
           hasNoTextQuery(request) {
            return .cardVariableSpend
        }

        if request.operation == .last,
           request.measure == .budgetImpact,
           request.expectedAnswerShape == .metric,
           exactDimensions(request, []),
           hasNoNamedTargets(request),
           request.sort == nil {
            return .latestVariableExpense
        }

        if request.operation == .list,
           request.measure == .budgetImpact,
           request.expectedAnswerShape == .list,
           exactDimensions(request, []),
           hasNoNamedTargets(request),
           request.sort == .amountDescending {
            return .biggestVariableExpenseRows
        }

        return nil
    }

    private func unifiedExpenseScenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        guard request.operation == .group,
              request.measure == .budgetImpact,
              request.expectedAnswerShape == .list,
              request.expenseScope == .unified,
              hasNoNamedTargets(request),
              request.sort == nil else {
            return nil
        }

        if exactDimensions(request, [.category]) {
            return .unifiedExpenseCategoryGroups
        }

        if exactDimensions(request, [.card]),
           request.dateRangeToken != .allTime {
            return .unifiedExpenseCardGroups
        }

        return nil
    }

    private func plannedExpenseScenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        if request.expenseScope == .unified {
            return unifiedExpenseScenario(for: request)
        }

        guard expenseScopeIsNilOr(request, .planned) else {
            return nil
        }

        if request.operation == .sum,
           request.measure == .budgetImpact,
           request.expectedAnswerShape == .metric,
           exactDimensions(request, []),
           hasNoNamedTargets(request) {
            return .plannedExpenseSum
        }

        if request.operation == .next,
           request.measure == .effectiveAmount,
           request.expectedAnswerShape == .metric,
           exactDimensions(request, []),
           hasNoNamedTargets(request),
           request.dateRangeToken != .allTime,
           request.sort == nil {
            return .nextPlannedExpense
        }

        return nil
    }

    private func incomeScenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        if request.operation == .sum,
           request.measure == .incomeAmount,
           request.expectedAnswerShape == .metric,
           exactDimensions(request, []),
           hasNoNamedTargets(request),
           request.incomeState == nil || request.incomeState == .all,
           request.sort == nil {
            return .incomeTotal
        }

        if request.operation == .group,
           request.measure == .incomeAmount,
           request.expectedAnswerShape == .list,
           exactDimensions(request, [.incomeSource]),
           hasNoNamedTargets(request),
           request.incomeState == nil || request.incomeState == .all,
           request.dateRangeToken != .allTime,
           request.sort == nil {
            return .incomeBySource
        }

        if request.operation == .share,
           request.measure == .coverageRatio,
           request.expectedAnswerShape == .metric,
           exactDimensions(request, []),
           hasNoNamedTargets(request),
           request.incomeState == nil || request.incomeState == .all,
           request.dateRangeToken != .allTime,
           request.sort == nil {
            return .incomeCoverageRatio
        }

        return nil
    }

    private func savingsScenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        if request.operation == .forecast,
           request.measure == .savingsTotal,
           request.expectedAnswerShape == .metric,
           exactDimensions(request, []),
           hasNoNamedTargets(request),
           request.dateRangeToken != .allTime,
           request.sort == nil {
            return .forecastSavings
        }

        guard request.operation == .sum,
              request.measure == .savingsTotal,
              request.expectedAnswerShape == .metric,
              exactDimensions(request, []),
              hasTargetName(request),
              hasNoTextQuery(request),
              request.dateRangeToken == .allTime,
              request.sort == nil else {
            return nil
        }
        return .savingsTotalExplicitAccount
    }

    private func presetScenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        guard request.operation == .sum,
              request.measure == .recurringBurden,
              request.expectedAnswerShape == .metric,
              exactDimensions(request, []),
              hasNoNamedTargets(request),
              request.dateRangeToken != .allTime,
              request.sort == nil else {
            return nil
        }
        return .presetRecurringBurden
    }

    private func reconciliationScenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        guard request.operation == .sum,
              request.measure == .reconciliationBalance,
              request.expectedAnswerShape == .metric,
              exactDimensions(request, []),
              hasTargetName(request),
              hasNoTextQuery(request),
              request.dateRangeToken == .allTime,
              request.sort == nil else {
            return nil
        }
        return .reconciliationBalanceExplicitAccount
    }

    private func budgetScenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        guard exactDimensions(request, []),
              hasNoNamedTargets(request),
              request.dateRangeToken != .allTime,
              request.sort == nil else {
            return nil
        }

        switch (request.operation, request.measure, request.expectedAnswerShape) {
        case (.forecast, .remainingRoom, .metric):
            return .budgetRemainingRoom
        case (.forecast, .safeDailySpend, .metric):
            return .safeDailySpend
        case (.average, .burnRate, .metric):
            return .budgetBurnRate
        case (.forecast, .projectedSpend, .metric):
            return .budgetProjectedSpend
        case (.compare, .paceDifference, .comparison):
            return .budgetPaceDifference
        case (.forecast, .coverageRatio, .metric):
            return .budgetCoverageRatio
        default:
            return nil
        }
    }

    private func categoryScenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        guard exactDimensions(request, []),
              hasNoNamedTargets(request),
              request.dateRangeToken != .allTime,
              request.sort == nil,
              request.categoryAvailabilityFilter == nil else {
            return nil
        }

        switch (request.operation, request.measure, request.expectedAnswerShape) {
        case (.forecast, .categoryAvailability, .metric):
            return .categoryAvailability
        case (.share, .concentration, .metric):
            return .categoryConcentration
        default:
            return nil
        }
    }

    private func expenseScopeIsNilOr(
        _ request: MarinaSemanticRequest,
        _ expectedScope: MarinaSemanticExpenseScope
    ) -> Bool {
        request.expenseScope == nil || request.expenseScope == expectedScope
    }

    private func exactDimensions(
        _ request: MarinaSemanticRequest,
        _ expectedDimensions: [MarinaSemanticDimension]
    ) -> Bool {
        request.dimensions == expectedDimensions
    }

    private func hasTargetName(_ request: MarinaSemanticRequest) -> Bool {
        trimmed(request.targetName).isEmpty == false
    }

    private func hasNoTargetName(_ request: MarinaSemanticRequest) -> Bool {
        trimmed(request.targetName).isEmpty
    }

    private func hasTextQuery(_ request: MarinaSemanticRequest) -> Bool {
        trimmed(request.textQuery).isEmpty == false
    }

    private func hasNoTextQuery(_ request: MarinaSemanticRequest) -> Bool {
        trimmed(request.textQuery).isEmpty
    }

    private func hasNoNamedTargets(_ request: MarinaSemanticRequest) -> Bool {
        hasNoTargetName(request) && hasNoTextQuery(request)
    }

    private func trimmed(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension MarinaUniversalRoutingPolicy {
    nonisolated static let disabled = MarinaUniversalRoutingPolicy(
        isEnabled: false,
        allowedScenarios: []
    )

    nonisolated static let internalParityProven = MarinaUniversalRoutingPolicy(
        isEnabled: true,
        allowedScenarios: [
            .merchantVariableSpend,
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
            .reconciliationBalanceExplicitAccount,
            .budgetRemainingRoom,
            .safeDailySpend,
            .budgetBurnRate,
            .budgetProjectedSpend,
            .budgetPaceDifference,
            .budgetCoverageRatio,
            .incomeCoverageRatio,
            .categoryAvailability,
            .categoryConcentration,
            .presetRecurringBurden,
            .forecastSavings
        ]
    )
}
