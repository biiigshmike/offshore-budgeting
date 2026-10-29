import SwiftUI

struct MarinaTransactionDetailsView: View {
    let transaction: MarinaReport.Transaction
    let displayedAmount: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let displayedAmount, abs(displayedAmount - transaction.grossAmount) > 0.005 {
                MarinaMetricView(metric: .init(label: "Original charge", value: transaction.grossAmount), prominent: false)
            }
            if let recorded = transaction.recordedAmount {
                MarinaMetricView(metric: .init(label: "Recorded amount", value: recorded), prominent: false)
            }
            if transaction.transactionKind == "planned",
               let displayedAmount, abs(displayedAmount - transaction.effectiveAmount) > 0.005 {
                MarinaMetricView(metric: .init(label: "Effective amount", value: transaction.effectiveAmount), prominent: false)
            }
            if transaction.splitAmount > 0 {
                MarinaMetricView(metric: .init(label: "Shared split", value: transaction.splitAmount), prominent: false)
            }
            if transaction.reconciliationOffset > 0 {
                MarinaMetricView(metric: .init(label: "Reconciliation offset", value: transaction.reconciliationOffset), prominent: false)
            }
            if transaction.savingsOffset > 0 {
                MarinaMetricView(metric: .init(label: "Savings offset", value: transaction.savingsOffset), prominent: false)
            }
            if transaction.splitAmount > 0 || transaction.reconciliationOffset > 0 || transaction.savingsOffset > 0
                || transaction.transactionKind == "adjustment" || abs(transaction.budgetImpact - transaction.effectiveAmount) > 0.005 {
                MarinaMetricView(metric: .init(label: "Budget impact", value: transaction.budgetImpact), prominent: false)
            }
            if let account = transaction.accountName {
                Text("Account: \(account)").font(.caption).foregroundStyle(.secondary)
            }
            if let preset = transaction.sourcePresetName {
                Text("From preset: \(preset)").font(.caption).foregroundStyle(.secondary)
            }
            if let budget = transaction.sourceBudgetName {
                Text("Generated for: \(budget)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
