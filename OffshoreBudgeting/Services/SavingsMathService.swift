import Foundation

struct SavingsMathService {

    // MARK: - Offset Helpers

    static func offsetAmount(for expense: VariableExpense) -> Double {
        guard let entry = expense.savingsLedgerEntry else { return 0 }
        guard entry.kind == .expenseOffset else { return 0 }
        return max(0, -entry.amount)
    }

    static func offsetAmount(for expense: PlannedExpense) -> Double {
        guard let entry = expense.savingsLedgerEntry else { return 0 }
        guard entry.kind == .expenseOffset else { return 0 }
        return max(0, -entry.amount)
    }

    // MARK: - Gross Helpers

    static func variableGrossAmount(for expense: VariableExpense) -> Double {
        let splitAmount = max(0, expense.allocation?.allocatedAmount ?? 0)

        if let allocation = expense.allocation, allocation.preservesGrossAmount == false {
            return max(0, expense.amount + splitAmount)
        }

        return max(0, expense.amount)
    }

    static func grossRecordedActualAmount(for expense: PlannedExpense) -> Double {
        let actual = max(0, expense.actualAmount)
        guard actual > 0 else { return 0 }

        let splitAmount = max(0, expense.allocation?.allocatedAmount ?? 0)
        if let allocation = expense.allocation, allocation.preservesGrossAmount == false {
            return max(0, actual + splitAmount)
        }

        return actual
    }

    static func grossEffectiveAmount(for expense: PlannedExpense) -> Double {
        let grossRecordedActual = grossRecordedActualAmount(for: expense)
        if grossRecordedActual > 0 {
            return grossRecordedActual
        }
        return max(0, expense.plannedAmount)
    }

    // MARK: - Owned Amount Helpers

    static func ownedAmount(for expense: VariableExpense) -> Double {
        let splitAmount = max(0, expense.allocation?.allocatedAmount ?? 0)
        return max(0, variableGrossAmount(for: expense) - splitAmount)
    }

    static func ownedPlannedAmount(for expense: PlannedExpense) -> Double {
        let splitAmount = max(0, expense.allocation?.allocatedAmount ?? 0)
        return max(0, expense.plannedAmount - splitAmount)
    }

    static func ownedEffectiveAmount(for expense: PlannedExpense) -> Double {
        let splitAmount = max(0, expense.allocation?.allocatedAmount ?? 0)
        return max(0, grossEffectiveAmount(for: expense) - splitAmount)
    }

    // MARK: - Budget Impact

    static func variableBudgetImpactAmount(for expense: VariableExpense) -> Double {
        max(0, ownedAmount(for: expense) - offsetAmount(for: expense))
    }

    static func plannedProjectedBudgetImpactAmount(for expense: PlannedExpense) -> Double {
        ownedPlannedAmount(for: expense)
    }

    static func plannedBudgetImpactAmount(for expense: PlannedExpense) -> Double {
        max(0, ownedEffectiveAmount(for: expense) - offsetAmount(for: expense))
    }

    // MARK: - Ledger Adjustment Helpers

    static func actualSavingsAdjustmentAmount(for entry: SavingsLedgerEntry) -> Double {
        switch entry.kind {
        case .manualAdjustment:
            return entry.amount
        case .periodClose, .expenseOffset, .reconciliationSettlement:
            return 0
        }
    }

    static func actualSavingsAdjustmentTotal(
        from entries: [SavingsLedgerEntry],
        startDate: Date,
        endDate: Date
    ) -> Double {
        entries
            .filter { $0.date >= startDate && $0.date <= endDate }
            .reduce(0) { $0 + actualSavingsAdjustmentAmount(for: $1) }
    }
}
