import Foundation

/// Describes the existing ledger, gross-spending, and budget-impact rules separately.
enum ExpenseEntryGuidance {
    static func transactionExplanation(for kind: VariableExpenseKind) -> LocalizedStringResource {
        switch kind {
        case .debit:
            return "A purchase or charge, even on a credit card. Adds to your card ledger and gross spending totals. Splits and Pay From Savings can reduce its budget impact."
        case .credit:
            return "A refund or credit. Subtracts from your card ledger and budget impact. Gross spending totals still show debit purchases before refunds."
        case .adjustment:
            return "A positive ledger correction. Adds to your card ledger, but is excluded from gross spending totals and savings calculations."
        }
    }

    static let reconciliationOverview: LocalizedStringResource = "Split assigns part of an expense to a reconciliation balance. Offset records a settlement against that balance. These actions are separate from Pay From Savings."
    static let splitExplanation: LocalizedStringResource = "The split amount increases this reconciliation balance. For debit purchases and planned expenses, it also reduces your share in budget calculations. The full transaction stays in your card history."
    static let offsetExplanation: LocalizedStringResource = "The offset records a settlement that reduces this reconciliation balance. It does not reduce this expense’s budget impact or use Offshore Savings."
    static let payFromSavingsExplanation: LocalizedStringResource = "Choose how much to cover with Offshore Savings. The full transaction stays in your card history; only the remaining amount counts toward this period’s budget impact."
    static let nonPurchaseSavingsExplanation: LocalizedStringResource = "Pay From Savings reduces the available Offshore Savings balance. A credit keeps its full negative budget impact; an adjustment still has zero budget impact. This action does not turn either entry into a purchase."
    static let plannedActualExplanation: LocalizedStringResource = "When this bill is paid, enter the amount here. Leave it blank to use the planned amount. You do not need to add a separate expense for this payment."
}
