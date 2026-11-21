import Foundation

/// A workspace-scoped preview. The confirmation token also covers the posted ledger state.
struct SavingsPeriodReviewSummary: Identifiable {
    let id: String
    let workspaceID: UUID
    let start: Date
    let end: Date
    let incomes: [Income]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let budgets: [Budget]
    let calculatedAmount: Double
    let currentTotal: Double
    let postedAmount: Double
    let existingEntry: SavingsLedgerEntry?
    let inputFingerprint: String
    let confirmationToken: String
    let hasOverlapConflict: Bool

    var isPending: Bool { existingEntry == nil }
    var needsReview: Bool {
        guard let fingerprint = existingEntry?.reviewedInputFingerprint else { return false }
        return fingerprint != inputFingerprint
    }
    var receivedIncome: Double { incomes.filter { !$0.isPlanned }.reduce(0) { $0 + $1.amount } }
    var plannedImpact: Double {
        plannedExpenses.reduce(0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }
    }
    var variableImpact: Double {
        variableExpenses.reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
    }
}
