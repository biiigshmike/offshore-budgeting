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
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(recordedExpenses, id: \.id) { expense in
                        row(expense)
                            .rowActions(allowsFullTrailingSwipe: false) {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    requestDeleteExpense(expense)
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
            SheetCloseToolbarItem { onDone() }
        }
        .onAppear {
            reload()
        }
        .blocksAutomaticExpenseReview(while: showingDeleteExpenseConfirm)
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
        SharedPlannedExpenseRow(expense: expense, showsCard: true, showsRecordedAmount: true)
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
