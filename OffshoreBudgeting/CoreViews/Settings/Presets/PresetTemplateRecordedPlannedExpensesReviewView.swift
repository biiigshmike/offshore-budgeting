//
//  PresetTemplateRecordedPlannedExpensesReviewView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/29/26.
//

import SwiftUI
import SwiftData

struct PresetTemplateRecordedPlannedExpensesReviewView: View {
    let preset: Preset
    let onDone: () -> Void

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Environment(\.modelContext) private var modelContext

    @State private var recordedExpenses: [PlannedExpense] = []

    @State private var showingDeleteExpenseConfirm: Bool = false
    @State private var pendingExpenseDelete: (() -> Void)? = nil

    var body: some View {
        List {
            Section {
                Text("These expenses have recorded spending. Review them if you want to delete any.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                if recordedExpenses.isEmpty {
                    ContentUnavailableView(
                        "No recorded expenses found",
                        systemImage: "checkmark.circle",
                        description: Text("Nothing to review.")
                    )
                } else {
                    ForEach(recordedExpenses, id: \.id) { expense in
                        row(expense)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    requestDeleteExpense(expense)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(Color("OffshoreDepth"))
                            }
                    }
                }
            } header: {
                Text("Recorded Planned Expenses")
            } footer: {
                Text("Deleting these removes them from their cards too.")
            }
        }
        .navigationTitle("Review \(preset.title)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    onDone()
                }
            }
        }
        .onAppear {
            reload()
        }
        .alert("Delete Expense?", isPresented: $showingDeleteExpenseConfirm) {
            Button("Delete", role: .destructive) {
                pendingExpenseDelete?()
                pendingExpenseDelete = nil
                reload()
            }
            Button("Cancel", role: .cancel) {
                pendingExpenseDelete = nil
            }
        }
    }

    // MARK: - Row

    private func row(_ expense: PlannedExpense) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(expense.title)
                    .font(.body)

                Spacer(minLength: 0)

                Text(expense.actualAmount, format: CurrencyFormatter.currencyStyle())
                    .font(.headline.weight(.semibold))
            }

            HStack(spacing: 8) {
                Text(AppDateFormat.abbreviatedDate(expense.expenseDate))

                if let cardName = expense.card?.name {
                    Text("•")
                    Text(cardName)
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Data

    private func reload() {
        let presetID: UUID? = preset.id

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourcePresetID == presetID &&
                expense.actualAmount > 0
            },
            sortBy: [
                SortDescriptor(\.expenseDate, order: .reverse)
            ]
        )

        recordedExpenses = (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Delete

    private func requestDeleteExpense(_ expense: PlannedExpense) {
        if confirmBeforeDeleting {
            pendingExpenseDelete = {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
            showingDeleteExpenseConfirm = true
        } else {
            PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            reload()
        }
    }
}
