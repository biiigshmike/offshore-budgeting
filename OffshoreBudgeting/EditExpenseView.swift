//
//  EditExpenseView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct EditExpenseView: View {

    let workspace: Workspace
    let expense: VariableExpense

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]
    @Query private var categories: [Category]

    // MARK: - Form State

    @State private var descriptionText: String = ""
    @State private var amountText: String = ""
    @State private var transactionDate: Date = .now
    @State private var selectedCardID: UUID? = nil
    @State private var selectedCategoryID: UUID? = nil

    // MARK: - Alerts

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false

    init(workspace: Workspace, expense: VariableExpense) {
        self.workspace = workspace
        self.expense = expense

        let workspaceID = workspace.id
        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )
    }

    private var canSave: Bool {
        ExpenseFormView.canSave(
            descriptionText: descriptionText,
            amountText: amountText,
            selectedCardID: selectedCardID,
            hasAtLeastOneCard: !cards.isEmpty
        )
    }

    var body: some View {
        ExpenseFormView(
            workspace: workspace,
            cards: cards,
            categories: categories,
            descriptionText: $descriptionText,
            amountText: $amountText,
            transactionDate: $transactionDate,
            selectedCardID: $selectedCardID,
            selectedCategoryID: $selectedCategoryID
        )
        .navigationTitle("Edit Transaction")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(!canSave)
                    .tint(.accentColor)
                    .controlSize(.large)
                    .buttonStyle(.glassProminent)
            }
        }
        .alert("Invalid Amount", isPresented: $showingInvalidAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter an amount greater than 0.")
        }
        .alert("Select a Card", isPresented: $showingMissingCardAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Choose a card for this transaction.")
        }
        .onAppear {
            // Seed fields once.
            descriptionText = expense.descriptionText
            amountText = CurrencyFormatter.editingString(from: expense.amount)
            transactionDate = expense.transactionDate
            selectedCardID = expense.card?.id
            selectedCategoryID = expense.category?.id
        }
    }

    private func save() {
        let trimmedDesc = ExpenseFormView.trimmedDescription(descriptionText)
        guard !trimmedDesc.isEmpty else { return }

        guard let amt = ExpenseFormView.parseAmount(amountText), amt > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        guard let selectedCard = cards.first(where: { $0.id == selectedCardID }) else {
            showingMissingCardAlert = true
            return
        }

        let selectedCategory = categories.first(where: { $0.id == selectedCategoryID })

        // SwiftData models are reference types, so updating properties is enough.
        expense.descriptionText = trimmedDesc
        expense.amount = amt
        expense.transactionDate = transactionDate
        expense.workspace = workspace
        expense.card = selectedCard
        expense.category = selectedCategory

        // Not strictly required, but harmless and explicit.
        try? modelContext.save()

        dismiss()
    }
}
