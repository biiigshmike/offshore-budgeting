//
//  AddExpenseView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct AddExpenseView: View {

    let workspace: Workspace

    /// Optional restriction, used when launching from BudgetDetailView.
    /// If nil, we show all cards in the workspace.
    let allowedCards: [Card]?

    /// Optional default card, used when launching from CardDetailView.
    let defaultCard: Card?

    let defaultDate: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cardsInWorkspace: [Card]
    @Query private var categories: [Category]

    // MARK: - Form State

    @State private var descriptionText: String = ""
    @State private var amountText: String = ""
    @State private var transactionDate: Date
    @State private var selectedCardID: UUID? = nil
    @State private var selectedCategoryID: UUID? = nil

    // MARK: - Alerts

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false

    init(
        workspace: Workspace,
        allowedCards: [Card]? = nil,
        defaultCard: Card? = nil,
        defaultDate: Date = .now
    ) {
        self.workspace = workspace
        self.allowedCards = allowedCards
        self.defaultCard = defaultCard
        self.defaultDate = defaultDate
        _transactionDate = State(initialValue: defaultDate)

        let workspaceID = workspace.id
        _cardsInWorkspace = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )
    }

    private var visibleCards: [Card] {
        if let allowedCards {
            return allowedCards.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return cardsInWorkspace
    }

    private var canSave: Bool {
        ExpenseFormView.canSave(
            descriptionText: descriptionText,
            amountText: amountText,
            selectedCardID: selectedCardID,
            hasAtLeastOneCard: !visibleCards.isEmpty
        )
    }

    var body: some View {
        ExpenseFormView(
            workspace: workspace,
            cards: visibleCards,
            categories: categories,
            descriptionText: $descriptionText,
            amountText: $amountText,
            transactionDate: $transactionDate,
            selectedCardID: $selectedCardID,
            selectedCategoryID: $selectedCategoryID
        )
        .navigationTitle("Add Transaction")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.glassProminent)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }
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
            // Preselect card when launched from CardDetailView.
            if selectedCardID == nil {
                if let defaultCard {
                    selectedCardID = defaultCard.id
                } else if visibleCards.count == 1 {
                    selectedCardID = visibleCards.first?.id
                }
            }
        }
    }

    private func save() {
        let trimmedDesc = ExpenseFormView.trimmedDescription(descriptionText)
        guard !trimmedDesc.isEmpty else { return }

        guard let amt = ExpenseFormView.parseAmount(amountText), amt > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        guard let selectedCard = visibleCards.first(where: { $0.id == selectedCardID }) else {
            showingMissingCardAlert = true
            return
        }

        let selectedCategory = categories.first(where: { $0.id == selectedCategoryID })

        let expense = VariableExpense(
            descriptionText: trimmedDesc,
            amount: amt,
            transactionDate: transactionDate,
            workspace: workspace,
            card: selectedCard,
            category: selectedCategory
        )

        modelContext.insert(expense)
        dismiss()
    }
}
