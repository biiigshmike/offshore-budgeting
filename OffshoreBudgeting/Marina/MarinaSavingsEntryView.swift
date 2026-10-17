import SwiftUI

/// A live savings ledger record, without creating or normalizing account history.
@available(iOS 26.0, macOS 26.0, *)
struct MarinaSavingsEntryView: View {
    let entry: SavingsLedgerEntry

    private var kindTitle: String {
        switch entry.kind {
        case .periodClose: "Period close"
        case .manualAdjustment: "Manual adjustment"
        case .expenseOffset: "Expense offset"
        case .reconciliationSettlement: "Legacy reconciliation settlement"
        }
    }

    var body: some View {
        Form {
            Section("Savings record") {
                LabeledContent("Account", value: entry.account?.name ?? "Unavailable")
                LabeledContent("Kind", value: kindTitle)
                LabeledContent("Date") {
                    Text(entry.date, format: .dateTime.month().day().year())
                }
                LabeledContent("Amount") {
                    Text(entry.amount, format: CurrencyFormatter.currencyStyle())
                }
                if !entry.note.isEmpty {
                    Text(entry.note).textSelection(.enabled)
                }
            }
            if let start = entry.periodStartDate, let end = entry.periodEndDate {
                Section("Budget period") {
                    LabeledContent("Start") { Text(start, format: .dateTime.month().day().year()) }
                    LabeledContent("End") { Text(end, format: .dateTime.month().day().year()) }
                }
            }
        }
        .navigationTitle("Savings record")
    }
}
