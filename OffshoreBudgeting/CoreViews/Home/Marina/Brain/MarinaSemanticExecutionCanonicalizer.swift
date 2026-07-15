import Foundation

nonisolated struct MarinaCanonicalExecutionShape: Equatable, Sendable {
    let surface: MarinaUniversalEntitySurface
    let projection: MarinaSemanticProjection
}

nonisolated enum MarinaSemanticExecutionCanonicalizationResult: Equatable, Sendable {
    case shape(MarinaCanonicalExecutionShape)
    case unsupported(MarinaCapabilityFailureReason)
}

/// Converts semantic intent into the one public execution surface that owns the
/// requested data. The mapping is deliberately closed: supporting models never
/// become query surfaces merely because they contributed to a projection.
struct MarinaSemanticExecutionCanonicalizer: Sendable {
    func canonicalize(
        _ request: MarinaSemanticRequest
    ) -> MarinaSemanticExecutionCanonicalizationResult {
        let projection = canonicalProjection(for: request)

        switch projection {
        case .records:
            return recordsShape(for: request)
        case .summary:
            return request.entity == .budget
                ? .shape(.init(surface: .semantic(.budget), projection: .summary))
                : .unsupported(.unsupportedCombination)
        case .activity:
            switch request.entity {
            case .savingsAccount:
                return .shape(.init(surface: .savingsLedgerEntries, projection: .activity))
            case .reconciliationAccount:
                return .shape(.init(surface: .reconciliationLedgerEntries, projection: .activity))
            case .workspace,
                 .budget,
                 .card,
                 .plannedExpense,
                 .variableExpense,
                 .income,
                 .incomeSeries,
                 .category,
                 .preset:
                return .unsupported(.unsupportedCombination)
            }
        case .occurrences:
            return request.entity == .incomeSeries
                ? .shape(.init(surface: .semantic(.incomeSeries), projection: .occurrences))
                : .unsupported(.unsupportedCombination)
        case .linkedBudgets:
            return request.entity == .preset
                ? .shape(.init(surface: .semantic(.preset), projection: .linkedBudgets))
                : .unsupported(.unsupportedCombination)
        case .income, .expenses, .linkedCards, .linkedPresets:
            return request.entity == .budget
                ? .shape(.init(surface: .semantic(.budget), projection: projection))
                : .unsupported(.unsupportedCombination)
        }
    }

    private func canonicalProjection(
        for request: MarinaSemanticRequest
    ) -> MarinaSemanticProjection {
        guard request.entity == .budget,
              request.projection == .records,
              let measure = request.measure,
              Self.budgetSummaryMeasures.contains(measure) else {
            return request.projection
        }
        return .summary
    }

    private func recordsShape(
        for request: MarinaSemanticRequest
    ) -> MarinaSemanticExecutionCanonicalizationResult {
        if Self.unifiedSpendEntities.contains(request.entity),
           request.measure == .budgetImpact {
            return .shape(.init(surface: .unifiedExpenses, projection: .records))
        }

        guard let expenseScope = request.expenseScope else {
            return .shape(.init(surface: .semantic(request.entity), projection: .records))
        }

        switch expenseScope {
        case .variable:
            return .shape(.init(surface: .semantic(.variableExpense), projection: .records))
        case .planned:
            return .shape(.init(surface: .semantic(.plannedExpense), projection: .records))
        case .unified:
            guard request.entity == .variableExpense || request.entity == .plannedExpense else {
                return .unsupported(.unsupportedCombination)
            }
            return .shape(.init(surface: .unifiedExpenses, projection: .records))
        }
    }

    private static let unifiedSpendEntities: Set<MarinaSemanticEntity> = [.card, .category]

    private static let budgetSummaryMeasures: Set<MarinaSemanticMeasure> = [
        .budgetImpact,
        .projectedBudgetImpact,
        .plannedIncomeTotal,
        .actualIncomeTotal,
        .plannedExpenseProjectedTotal,
        .plannedExpenseActualTotal,
        .plannedExpenseEffectiveTotal,
        .variableExpenseTotal,
        .unifiedExpenseTotal,
        .maximumSavings,
        .projectedSavings,
        .actualSavings
    ]
}
