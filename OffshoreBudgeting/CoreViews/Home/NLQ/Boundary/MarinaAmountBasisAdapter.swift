import Foundation

enum MarinaFinancialAmountBasis: String, Codable, Equatable, CaseIterable, Sendable {
    case homeSpend
    case cardDisplaySpend
    case budgetImpact
    case ledgerSigned
    case gross
    case allocated
    case reconciliationBalance
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
        case .cardDisplaySpend:
            return expense.spendingAmount()
        case .budgetImpact:
            return SavingsMathService.variableBudgetImpactAmount(for: expense)
        case .gross:
            return SavingsMathService.variableGrossAmount(for: expense)
        case .allocated:
            return max(0, expense.allocation?.allocatedAmount ?? 0)
        case .reconciliationBalance:
            return 0
        }
    }

    func plannedAmount(
        for expense: PlannedExpense,
        basis: MarinaFinancialAmountBasis
    ) -> Double {
        switch basis {
        case .homeSpend, .cardDisplaySpend, .ledgerSigned:
            return expense.effectiveAmount()
        case .budgetImpact:
            return SavingsMathService.plannedBudgetImpactAmount(for: expense)
        case .gross:
            return SavingsMathService.grossEffectiveAmount(for: expense)
        case .allocated:
            return max(0, expense.allocation?.allocatedAmount ?? 0)
        case .reconciliationBalance:
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
        case .plannedAmount, .actualAmount, .effectivePlannedAmount:
            return subject == .cards ? .cardDisplaySpend : .homeSpend
        case .spendingAmount:
            return .cardDisplaySpend
        case .ledgerSignedAmount:
            return .ledgerSigned
        case .budgetImpactAmount:
            return .budgetImpact
        case .incomeAmount:
            return .homeSpend
        case .savingsAmount:
            return .budgetImpact
        case .allocatedAmount:
            return .allocated
        case .reconciliationBalance:
            return .reconciliationBalance
        }
    }
}
