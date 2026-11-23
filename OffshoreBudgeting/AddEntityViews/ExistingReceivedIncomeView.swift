import SwiftData
import SwiftUI

struct ExistingReceivedIncomeView: View {
    let workspaceID: UUID
    let plannedIncome: Income
    let incomes: [Income]
    let onLinked: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIncome: Income?
    @State private var showingConfirmation = false
    @State private var showingLinkError = false
    @State private var linkError: TransactionEntryService.ValidationError?

    static func candidates(in incomes: [Income], around planDate: Date) -> [Income] {
        incomes
            .filter { !$0.isPlanned && $0.sourcePlannedIncomeID == nil }
            .sorted { abs($0.date.timeIntervalSince(planDate)) < abs($1.date.timeIntervalSince(planDate)) }
    }

    var body: some View {
        List {
            if incomes.isEmpty {
                ContentUnavailableView("No Available Actual Income", systemImage: "tray")
            } else {
                Section {
                    ForEach(incomes) { income in
                        Button {
                            selectedIncome = income
                            showingConfirmation = true
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(income.source)
                                    .foregroundStyle(.primary)
                                Text(details(for: income))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Closest to the planned date first")
                }
            }
        }
        .navigationTitle("Use Existing Income")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .blocksAutomaticExpenseReview(while: showingConfirmation || showingLinkError)
        .alert("Use this Actual income?", isPresented: $showingConfirmation, presenting: selectedIncome) { income in
            Button("Cancel", role: .cancel) { }
            Button("Use Income") { link(income) }
        } message: { income in
            Text("\(income.source) · \(details(for: income))")
        }
        .alert("Couldn’t link income", isPresented: $showingLinkError) {
            Button("OK", role: .cancel) { }
        } message: {
            if let linkError {
                Text(linkError.localizedDescription)
            } else {
                Text("Try again in a moment.")
            }
        }
    }

    private func details(for income: Income) -> String {
        let date = income.date.formatted(date: .abbreviated, time: .omitted)
        let amount = CurrencyFormatter.string(from: income.amount)
        return String(localized: "\(date) · \(amount)")
    }

    private func link(_ income: Income) {
        do {
            try TransactionEntryService().linkReceivedIncome(
                income, to: plannedIncome, workspaceID: workspaceID, modelContext: modelContext
            )
            onLinked()
        } catch {
            linkError = error as? TransactionEntryService.ValidationError
            showingLinkError = true
        }
    }
}
