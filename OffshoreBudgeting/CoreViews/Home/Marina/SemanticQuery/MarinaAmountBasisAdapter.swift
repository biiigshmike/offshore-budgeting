import Foundation

enum MarinaFinancialAmountBasis: String, Codable, Equatable, CaseIterable, Sendable {
    case homeSpend
    case cardDisplaySpend
    case debitSpend
    case budgetImpact
    case ownedSpend
    case ledgerSigned
    case gross
    case allocated
    case plannedAmount
    case plannedEffectiveAmount
    case recordedActualAmount
    case actualIncome
    case plannedIncome
    case savingsRunningTotal
    case savingsMovement
    case savingsAdjustment
    case savingsOffset
    case reconciliationBalance
    case reconciliationSettlement
    case count
    case dateWindow
}

struct MarinaAmountBasisAdapter {
    nonisolated init() {}

    func basis(
        plan: MarinaAggregationPlan,
        semanticQuery: MarinaSemanticQuery?
    ) -> MarinaFinancialAmountBasis {
        if plan.measure == .reconciliationBalance {
            return .reconciliationBalance
        }

        if plan.measure == .spend,
           plan.targets.contains(where: { $0.entityType == .allocationAccount })
            || semanticQuery?.filters.contains(where: { $0.entityTypeHint == .allocationAccount || $0.relationship == .allocationAccount }) == true {
            return .allocated
        }

        if let field = semanticQuery?.amountField {
            return basis(for: field, subject: semanticQuery?.subject)
        }

        if plan.measure == .spend,
           plan.operation == .rank,
           plan.grouping?.dimension == .card {
            return .budgetImpact
        }

        if plan.measure == .transactionAmount {
            return .budgetImpact
        }

        if plan.measure == .spend || plan.measure == .categoryShare {
            return .homeSpend
        }

        switch plan.measure {
        case .remainingBudget, .savings:
            return .budgetImpact
        case .reconciliationBalance:
            return .reconciliationBalance
        case .spend, .categoryShare, .income, .presetAmount, .transactionAmount, .transactionFrequency, .savingsMovement:
            return .homeSpend
        }
    }

    func variableAmount(
        for expense: VariableExpense,
        basis: MarinaFinancialAmountBasis
    ) -> Double {
        switch basis {
        case .homeSpend, .ledgerSigned:
            return expense.ledgerSignedAmount()
        case .cardDisplaySpend, .debitSpend:
            return expense.spendingAmount()
        case .budgetImpact:
            return SavingsMathService.variableBudgetImpactAmount(for: expense)
        case .ownedSpend:
            return SavingsMathService.ownedAmount(for: expense)
        case .gross:
            return SavingsMathService.variableGrossAmount(for: expense)
        case .allocated:
            return max(0, expense.allocation?.allocatedAmount ?? 0)
        case .plannedAmount, .plannedEffectiveAmount, .recordedActualAmount, .actualIncome, .plannedIncome, .savingsRunningTotal, .savingsMovement, .savingsAdjustment, .savingsOffset, .reconciliationBalance, .reconciliationSettlement, .count, .dateWindow:
            return 0
        }
    }

    func plannedAmount(
        for expense: PlannedExpense,
        basis: MarinaFinancialAmountBasis
    ) -> Double {
        switch basis {
        case .homeSpend, .cardDisplaySpend, .debitSpend, .ledgerSigned:
            return expense.effectiveAmount()
        case .budgetImpact:
            return SavingsMathService.plannedBudgetImpactAmount(for: expense)
        case .ownedSpend:
            return SavingsMathService.ownedEffectiveAmount(for: expense)
        case .gross:
            return SavingsMathService.grossEffectiveAmount(for: expense)
        case .allocated:
            return max(0, expense.allocation?.allocatedAmount ?? 0)
        case .plannedAmount:
            return max(0, expense.plannedAmount)
        case .plannedEffectiveAmount:
            return expense.effectiveAmount()
        case .recordedActualAmount:
            return max(0, expense.actualAmount)
        case .actualIncome, .plannedIncome, .savingsRunningTotal, .savingsMovement, .savingsAdjustment, .savingsOffset, .reconciliationBalance, .reconciliationSettlement, .count, .dateWindow:
            return 0
        }
    }

    func reconciliationBalance(for account: AllocationAccount) -> Double {
        AllocationLedgerService.balance(for: account)
    }

    private func basis(
        for field: MarinaAmountField,
        subject: MarinaSubject?
    ) -> MarinaFinancialAmountBasis {
        switch field {
        case .amount:
            return .homeSpend
        case .plannedAmount:
            return .plannedAmount
        case .actualAmount:
            return .recordedActualAmount
        case .effectivePlannedAmount:
            return .plannedEffectiveAmount
        case .spendingAmount:
            return subject == .cards ? .cardDisplaySpend : .homeSpend
        case .ledgerSignedAmount:
            return .ledgerSigned
        case .budgetImpactAmount:
            return .budgetImpact
        case .incomeAmount:
            return .actualIncome
        case .savingsAmount:
            return .savingsMovement
        case .allocatedAmount:
            return .allocated
        case .reconciliationBalance:
            return .reconciliationBalance
        }
    }
}
