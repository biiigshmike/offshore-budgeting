//
//  BudgetRecordedPlannedExpensesReviewView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/29/26.
//

import SwiftUI
import SwiftData

struct BudgetRecordedPlannedExpensesReviewView: View {
    let workspace: Workspace
    let budget: Budget
    let card: Card?

    /// Called when the user confirms they want to delete the budget (after reviewing recorded items).
    let onDeleteBudget: () -> Void

    /// Called when the user just wants to leave this screen (budget remains).
    let onDone: () -> Void

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Environment(\.modelContext) private var modelContext

    @State private var recordedExpenses: [PlannedExpense] = []

    @State private var showingEditPlannedExpense: Bool = false
    @State private var editingPlannedExpense: PlannedExpense? = nil

    @State private var showingDeleteExpenseConfirm: Bool = false
    @State private var pendingExpenseDelete: (() -> Void)? = nil

    @State private var showingDeleteBudgetConfirm: Bool = false

    // MARK: - Init

    init(
        workspace: Workspace,
        budget: Budget,
        card: Card? = nil,
        onDeleteBudget: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.budget = budget
        self.card = card
        self.onDeleteBudget = onDeleteBudget
        self.onDone = onDone
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                Text(introText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                if recordedExpenses.isEmpty {
                    ContentUnavailableView(
                        "No recorded expenses found",
                        systemImage: "checkmark.circle",
                        description: Text("You can delete the budget now, or tap Done to keep it.")
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
                        }
                    }
                }
            } header: {
                Text("Recorded Planned Expenses")
            } footer: {
                Text("Deleting these will remove the expenses from their cards too.")
            }
        }
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    onDone()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(role: .destructive) {
                    showingDeleteBudgetConfirm = true
                } label: {
                    Text("Delete Budget")
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
        .alert("Delete Budget?", isPresented: $showingDeleteBudgetConfirm) {
            Button("Delete Budget", role: .destructive) {
                onDeleteBudget()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes the budget only. Any remaining expenses stay on their cards.")
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

    private var navigationTitleText: String {
        if let card {
            return "Review \(card.name)"
        }
        return "Review Recorded Expenses"
    }

    private var introText: String {
        if let card {
            return "Some planned expenses created by this budget on \(card.name) have recorded spending. Review them below if you want to delete any."
        }
        return "Some planned expenses created by this budget have recorded spending. Review them below if you want to delete any."
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
                Text(expense.expenseDate.formatted(date: .abbreviated, time: .omitted))
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
        let cardID: UUID? = card?.id

        if cardID == nil {
            let descriptor = FetchDescriptor<PlannedExpense>(
                predicate: #Predicate<PlannedExpense> { expense in
                    expense.sourceBudgetID == budgetID &&
                    expense.actualAmount > 0
                },
                sortBy: [
                    SortDescriptor(\.expenseDate, order: .reverse)
                ]
            )
            recordedExpenses = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            let descriptor = FetchDescriptor<PlannedExpense>(
                predicate: #Predicate<PlannedExpense> { expense in
                    expense.sourceBudgetID == budgetID &&
                    expense.actualAmount > 0 &&
                    expense.card?.id == cardID
                },
                sortBy: [
                    SortDescriptor(\.expenseDate, order: .reverse)
                ]
            )
            recordedExpenses = (try? modelContext.fetch(descriptor)) ?? []
        }
    }

    // MARK: - Delete

    private func requestDeleteExpense(_ expense: PlannedExpense) {
        if confirmBeforeDeleting {
            pendingExpenseDelete = {
                modelContext.delete(expense)
            }
            showingDeleteExpenseConfirm = true
        } else {
            modelContext.delete(expense)
            reload()
        }
    }
}
