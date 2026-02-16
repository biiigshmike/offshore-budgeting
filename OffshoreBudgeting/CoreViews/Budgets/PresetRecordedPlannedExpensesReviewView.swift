//
//  PresetRecordedPlannedExpensesReviewView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/29/26.
//

import SwiftUI
import SwiftData

struct PresetRecordedPlannedExpensesReviewView: View {
    let workspace: Workspace
    let budget: Budget
    let preset: Preset

    let onDone: () -> Void

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Environment(\.modelContext) private var modelContext

    @State private var recordedExpenses: [PlannedExpense] = []

    @State private var showingEditPlannedExpense: Bool = false
    @State private var editingPlannedExpense: PlannedExpense? = nil

    @State private var showingDeleteExpenseConfirm: Bool = false
    @State private var pendingExpenseDelete: (() -> Void)? = nil

    // MARK: - Body

    var body: some View {
        List {
            Section {
                Text("Some planned expenses from this preset have recorded spending. Review them below if you want to delete any.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                if recordedExpenses.isEmpty {
                    ContentUnavailableView(
                        "No recorded expenses found",
                        systemImage: "checkmark.circle",
                        description: Text("You can tap Done to return.")
                    )
                } else {
                    ForEach(recordedExpenses, id: \.id) { expense in
                        Button {
                            editingPlannedExpense = expense
                            showingEditPlannedExpense = true
                        } label: {
                            row(expense)
                        }
                        .buttonStyle(.plain)
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
                Text("")
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
        .alert("Delete?", isPresented: $showingDeleteExpenseConfirm) {
            Button("Delete", role: .destructive) {
                pendingExpenseDelete?()
                pendingExpenseDelete = nil
                reload()
            }
            Button("Cancel", role: .cancel) {
                pendingExpenseDelete = nil
            }
        }
        .sheet(isPresented: $showingEditPlannedExpense, onDismiss: { editingPlannedExpense = nil }) {
            NavigationStack {
                if let editingPlannedExpense {
                    EditPlannedExpenseView(workspace: workspace, plannedExpense: editingPlannedExpense)
                } else {
                    EmptyView()
                }
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
                    .foregroundStyle(.primary)
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
        let budgetID: UUID? = budget.id
        let presetID: UUID? = preset.id

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID &&
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
