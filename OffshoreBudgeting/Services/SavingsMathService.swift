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

    // MARK: - Budget Impact

    static func variableBudgetImpactAmount(for expense: VariableExpense) -> Double {
        max(0, expense.amount - offsetAmount(for: expense))
    }

    static func plannedBudgetImpactAmount(for expense: PlannedExpense) -> Double {
        let effective = expense.effectiveAmount()
        return max(0, effective - offsetAmount(for: expense))
    }
}
