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
    case categoryAvailabilityFilteredList
    case categoryConcentration
    case presetRecurringBurden
    case forecastSavings
    case rowBackedQuery
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

        let provenScenario: MarinaUniversalRoutingScenario?
        switch request.entity {
        case .variableExpense:
            provenScenario = variableExpenseScenario(for: request)
        case .plannedExpense:
            provenScenario = plannedExpenseScenario(for: request)
        case .income:
            provenScenario = incomeScenario(for: request)
        case .savingsAccount:
            provenScenario = savingsScenario(for: request)
        case .reconciliationAccount:
            provenScenario = reconciliationScenario(for: request)
        case .budget:
            provenScenario = budgetScenario(for: request)
        case .category:
            provenScenario = categoryScenario(for: request)
        case .preset:
            provenScenario = presetScenario(for: request)
        case .workspace, .card:
            provenScenario = nil
        }

        if let provenScenario {
            return provenScenario
        }

        return rowBackedScenario(for: request)
    }

    private func rowBackedScenario(for request: MarinaSemanticRequest) -> MarinaUniversalRoutingScenario? {
        guard rowBackedOperations.contains(request.operation),
              request.categoryAvailabilityFilter == nil,
              request.comparisonTargetName == nil,
              request.whatIfAmount == nil,
              request.operation != .next || request.dateRangeToken != .allTime,
              rowBackedShapeIsSupported(request),
              targetShapeIsSupported(request) else {
            return nil
        }

        if request.expenseScope == .unified {
            switch request.entity {
            case .variableExpense, .plannedExpense:
                guard rowBackedUnifiedExpenseOperations.contains(request.operation),
                      rowBackedMeasure(request.measure, isIn: unifiedExpenseMeasures),
                      dimensionsAreSupported(request, allowed: unifiedExpenseDimensions) else {
                    return nil
                }
                return .rowBackedQuery
            case .workspace, .budget, .card, .reconciliationAccount, .savingsAccount, .income, .category, .preset:
                return nil
            }
        }

        switch request.entity {
        case .variableExpense:
            guard expenseScopeIsNilOr(request, .variable),
                  rowBackedVariableExpenseOperations.contains(request.operation),
                  rowBackedMeasure(request.measure, isIn: variableExpenseMeasures),
                  dimensionsAreSupported(request, allowed: expenseDimensions) else {
                return nil
            }
            return .rowBackedQuery
        case .plannedExpense:
            guard expenseScopeIsNilOr(request, .planned),
                  rowBackedPlannedExpenseOperations.contains(request.operation),
                  rowBackedMeasure(request.measure, isIn: plannedExpenseMeasures),
                  dimensionsAreSupported(request, allowed: plannedExpenseDimensions) else {
                return nil
            }
            return .rowBackedQuery
        case .income:
            guard request.expenseScope == nil,
                  rowBackedIncomeOperations.contains(request.operation),
                  rowBackedMeasure(request.measure, isIn: incomeMeasures),
                  dimensionsAreSupported(request, allowed: incomeDimensions) else {
                return nil
            }
            return .rowBackedQuery
        case .category:
            guard request.expenseScope == nil,
                  rowBackedMetadataOperations.contains(request.operation),
                  rowBackedMeasure(request.measure, isIn: categoryMetadataMeasures),
                  dimensionsAreSupported(request, allowed: []) else {
                return nil
            }
            return .rowBackedQuery
        case .card:
            guard request.expenseScope == nil,
                  rowBackedMetadataOperations.contains(request.operation),
                  rowBackedMeasure(request.measure, isIn: cardMetadataMeasures),
                  dimensionsAreSupported(request, allowed: []) else {
                return nil
            }
            return .rowBackedQuery
        case .preset:
            guard request.expenseScope == nil,
                  rowBackedPresetOperations.contains(request.operation),
                  rowBackedMeasure(request.measure, isIn: presetMeasures),
                  dimensionsAreSupported(request, allowed: presetDimensions) else {
                return nil
            }
            return .rowBackedQuery
        case .workspace, .budget, .reconciliationAccount, .savingsAccount:
            return nil
        }
    }

    private var blockedOperations: Set<MarinaSemanticOperation> {
        [.whatIf]
    }

    private var rowBackedOperations: Set<MarinaSemanticOperation> {
        [.list, .count, .sum, .average, .group, .last, .next]
    }

    private var rowBackedVariableExpenseOperations: Set<MarinaSemanticOperation> {
        [.list, .count, .sum, .average, .group, .last]
    }

    private var rowBackedPlannedExpenseOperations: Set<MarinaSemanticOperation> {
        [.list, .count, .sum, .average, .group, .last, .next]
    }

    private var rowBackedUnifiedExpenseOperations: Set<MarinaSemanticOperation> {
        [.list, .count, .sum, .average, .group, .last, .next]
    }

    private var rowBackedIncomeOperations: Set<MarinaSemanticOperation> {
        [.list, .count, .sum, .average, .group]
    }

    private var rowBackedMetadataOperations: Set<MarinaSemanticOperation> {
        [.list, .count]
    }

    private var rowBackedPresetOperations: Set<MarinaSemanticOperation> {
        [.list, .sum, .group]
    }

    private var variableExpenseMeasures: Set<MarinaSemanticMeasure> {
        [.amount, .budgetImpact]
    }

    private var plannedExpenseMeasures: Set<MarinaSemanticMeasure> {
        [.amount, .plannedAmount, .actualAmount, .effectiveAmount, .budgetImpact]
    }

    private var unifiedExpenseMeasures: Set<MarinaSemanticMeasure> {
        [.budgetImpact]
    }

    private var incomeMeasures: Set<MarinaSemanticMeasure> {
        [.amount, .incomeAmount]
    }

    private var categoryMetadataMeasures: Set<MarinaSemanticMeasure> {
        [.name, .color]
    }

    private var cardMetadataMeasures: Set<MarinaSemanticMeasure> {
        [.name]
    }

    private var presetMeasures: Set<MarinaSemanticMeasure> {
        [.plannedAmount, .actualAmount, .name]
    }

    private var expenseDimensions: Set<MarinaSemanticDimension> {
        [.category, .card, .merchantText]
    }

    private var plannedExpenseDimensions: Set<MarinaSemanticDimension> {
        [.category, .card, .merchantText, .preset, .budget]
    }

    private var unifiedExpenseDimensions: Set<MarinaSemanticDimension> {
        [.category, .card, .merchantText, .preset, .budget]
    }

    private var incomeDimensions: Set<MarinaSemanticDimension> {
        [.incomeSource, .card]
    }

    private var presetDimensions: Set<MarinaSemanticDimension> {
        [.category, .card, .budget]
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
              request.sort == nil else {
            return nil
        }

        if request.operation == .list,
           request.measure == .categoryAvailability,
           request.expectedAnswerShape == .list,
           filteredCategoryAvailabilityListFilter(request.categoryAvailabilityFilter) {
            return .categoryAvailabilityFilteredList
        }

        guard request.categoryAvailabilityFilter == nil else {
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

    private func filteredCategoryAvailabilityListFilter(
        _ filter: MarinaCategoryAvailabilityFilter?
    ) -> Bool {
        switch filter {
        case .over, .near, .underLimit:
            return true
        case .all, nil:
            return false
        }
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

    private func rowBackedMeasure(
        _ measure: MarinaSemanticMeasure?,
        isIn allowedMeasures: Set<MarinaSemanticMeasure>
    ) -> Bool {
        guard let measure else {
            return true
        }
        return allowedMeasures.contains(measure)
    }

    private func rowBackedShapeIsSupported(_ request: MarinaSemanticRequest) -> Bool {
        switch request.expectedAnswerShape {
        case .clarification, .unsupported, .comparison:
            return false
        case .list:
            return request.operation == .list
                || request.operation == .group
                || request.operation == .last
                || request.operation == .next
        case .metric:
            return request.operation == .count
                || request.operation == .sum
                || request.operation == .average
                || request.operation == .last
                || request.operation == .next
        }
    }

    private func targetShapeIsSupported(_ request: MarinaSemanticRequest) -> Bool {
        if hasNoTargetName(request) {
            return true
        }

        let relationshipDimensions = request.dimensions.filter {
            relationshipBackedDimensions.contains($0)
        }
        return relationshipDimensions.count == 1
    }

    private var relationshipBackedDimensions: Set<MarinaSemanticDimension> {
        [.category, .card, .incomeSource, .preset, .budget]
    }

    private func dimensionsAreSupported(
        _ request: MarinaSemanticRequest,
        allowed allowedDimensions: Set<MarinaSemanticDimension>
    ) -> Bool {
        guard request.dimensions.allSatisfy({ allowedDimensions.contains($0) }) else {
            return false
        }

        if request.operation == .group {
            guard hasNoTargetName(request), request.sort == nil else {
                return false
            }
            let groupableDimensions = request.dimensions.filter {
                relationshipBackedDimensions.contains($0)
            }
            return groupableDimensions.count == 1
        }

        if hasTargetName(request) {
            let filterDimensions = request.dimensions.filter {
                relationshipBackedDimensions.contains($0)
            }
            return filterDimensions.count == 1
        }

        return true
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
            .categoryAvailabilityFilteredList,
            .categoryConcentration,
            .presetRecurringBurden,
            .forecastSavings,
            .rowBackedQuery
        ]
    )
}
