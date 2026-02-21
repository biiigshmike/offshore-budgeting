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
    /// If nil,  show all cards in the workspace.
    let allowedCards: [Card]?

    /// Optional default card, used when launching from CardDetailView.
    let defaultCard: Card?

    /// Optional prefilled description, used when launching from notification shortcuts.
    let prefilledDescription: String?

    let defaultDate: Date

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cardsInWorkspace: [Card]
    @Query private var categories: [Category]
    @Query private var allocationAccounts: [AllocationAccount]
    @Query private var savingsAccounts: [SavingsAccount]

    // MARK: - Form State

    @State private var descriptionText: String = ""
    @State private var amountText: String = ""
    @State private var transactionDate: Date
    @State private var selectedCardID: UUID? = nil
    @State private var selectedCategoryID: UUID? = nil
    @State private var selectedAllocationAccountID: UUID? = nil
    @State private var allocationAmountText: String = ""
    @State private var selectedOffsetAccountID: UUID? = nil
    @State private var offsetAmountText: String = ""
    @State private var applySavingsOffset: Bool = false
    @State private var savingsOffsetAmountText: String = ""

    // MARK: - Alerts

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false
    @State private var showingInvalidAllocationAlert: Bool = false
    @State private var showingInvalidOffsetAlert: Bool = false
    @State private var showingInvalidSavingsOffsetAlert: Bool = false

    init(
        workspace: Workspace,
        allowedCards: [Card]? = nil,
        defaultCard: Card? = nil,
        prefilledDescription: String? = nil,
        defaultDate: Date = .now
    ) {
        self.workspace = workspace
        self.allowedCards = allowedCards
        self.defaultCard = defaultCard
        self.prefilledDescription = prefilledDescription
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

        _allocationAccounts = Query(
            filter: #Predicate<AllocationAccount> {
                $0.workspace?.id == workspaceID && $0.isArchived == false
            },
            sort: [SortDescriptor(\AllocationAccount.name, order: .forward)]
        )

        _savingsAccounts = Query(
            filter: #Predicate<SavingsAccount> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\SavingsAccount.createdAt, order: .forward)]
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

    private var availableSavingsBalance: Double {
        max(0, savingsAccounts.first?.total ?? 0)
    }

    var body: some View {
        ExpenseFormView(
            workspace: workspace,
            cards: visibleCards,
            categories: categories,
            allocationAccounts: allocationAccounts,
            descriptionText: $descriptionText,
            amountText: $amountText,
            transactionDate: $transactionDate,
            selectedCardID: $selectedCardID,
            selectedCategoryID: $selectedCategoryID,
            selectedAllocationAccountID: $selectedAllocationAccountID,
            allocationAmountText: $allocationAmountText,
            selectedOffsetAccountID: $selectedOffsetAccountID,
            offsetAmountText: $offsetAmountText,
            applySavingsOffset: $applySavingsOffset,
            savingsOffsetAmountText: $savingsOffsetAmountText,
            availableSavingsBalance: availableSavingsBalance,
            onSharedBalanceChanged: nil
        )
        .navigationTitle("Add Expense")
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
            Text("Choose a card for this expense.")
        }
        .alert("Invalid Split Amount", isPresented: $showingInvalidAllocationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Split amount must be 0 or greater and cannot exceed the expense amount.")
        }
        .alert("Invalid Offset Amount", isPresented: $showingInvalidOffsetAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Offset amount must be 0 or greater, cannot exceed the expense amount, and cannot exceed the selected account balance.")
        }
        .alert("Invalid Savings Offset", isPresented: $showingInvalidSavingsOffsetAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Savings offset must be 0 or greater, cannot exceed the expense amount, and cannot exceed available savings.")
        }
        .onAppear {
            if descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let text = (prefilledDescription ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    descriptionText = text
                }
            }

            if DebugScreenshotFormDefaults.isEnabled {
                if descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    descriptionText = DebugScreenshotFormDefaults.expenseDescription
                }

                let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedAmount.isEmpty {
                    amountText = DebugScreenshotFormDefaults.expenseAmountText
                }
            }

            // Preselect card when launched from CardDetailView.
            if selectedCardID == nil {
                if let defaultCard {
                    selectedCardID = defaultCard.id
                } else if visibleCards.count == 1 {
                    selectedCardID = visibleCards.first?.id
                } else if DebugScreenshotFormDefaults.isEnabled {
                    selectedCardID = DebugScreenshotFormDefaults.preferredCardID(in: visibleCards)
                }
            }

            if DebugScreenshotFormDefaults.isEnabled, selectedCategoryID == nil {
                selectedCategoryID = DebugScreenshotFormDefaults.preferredCategoryID(in: categories)
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
        let selectedAllocationAccount = allocationAccounts.first(where: { $0.id == selectedAllocationAccountID })
        let selectedOffsetAccount = allocationAccounts.first(where: { $0.id == selectedOffsetAccountID })

        let offsetAmount: Double
        if let selectedOffsetAccount {
            let trimmed = offsetAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                offsetAmount = 0
            } else {
                guard let parsed = CurrencyFormatter.parseAmount(trimmed), parsed >= 0, parsed <= amt else {
                    showingInvalidOffsetAlert = true
                    return
                }
                let available = max(0, AllocationLedgerService.balance(for: selectedOffsetAccount))
                guard parsed <= available else {
                    showingInvalidOffsetAlert = true
                    return
                }
                offsetAmount = parsed
            }
        } else {
            offsetAmount = 0
        }

        let netAmount = max(0, amt - offsetAmount)

        let savingsOffsetAmount: Double
        if applySavingsOffset {
            let trimmed = savingsOffsetAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                savingsOffsetAmount = 0
            } else {
                guard let parsed = CurrencyFormatter.parseAmount(trimmed), parsed >= 0, parsed <= netAmount else {
                    showingInvalidSavingsOffsetAlert = true
                    return
                }
                guard parsed <= availableSavingsBalance else {
                    showingInvalidSavingsOffsetAlert = true
                    return
                }
                savingsOffsetAmount = parsed
            }
        } else {
            savingsOffsetAmount = 0
        }

        let allocationAmount: Double
        if selectedAllocationAccount != nil {
            let trimmed = allocationAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                allocationAmount = 0
            } else {
                guard let parsed = CurrencyFormatter.parseAmount(trimmed), parsed >= 0, parsed <= netAmount else {
                    showingInvalidAllocationAlert = true
                    return
                }
                allocationAmount = parsed
            }
        } else {
            allocationAmount = 0
        }

        let expense = VariableExpense(
            descriptionText: trimmedDesc,
            amount: netAmount,
            transactionDate: transactionDate,
            workspace: workspace,
            card: selectedCard,
            category: selectedCategory
        )

        modelContext.insert(expense)

        if let selectedAllocationAccount, allocationAmount > 0 {
            let allocation = ExpenseAllocation(
                allocatedAmount: AllocationLedgerService.cappedAllocationAmount(allocationAmount, expenseAmount: netAmount),
                createdAt: .now,
                updatedAt: .now,
                workspace: workspace,
                account: selectedAllocationAccount,
                expense: expense
            )
            modelContext.insert(allocation)
            expense.allocation = allocation
        }

        if let selectedOffsetAccount, offsetAmount > 0 {
            let settlement = AllocationSettlement(
                date: transactionDate,
                note: offsetNote(for: trimmedDesc),
                amount: -offsetAmount,
                workspace: workspace,
                account: selectedOffsetAccount,
                expense: expense
            )
            modelContext.insert(settlement)
            expense.offsetSettlement = settlement
        }

        if savingsOffsetAmount > 0 {
            SavingsAccountService.upsertSavingsOffset(
                workspace: workspace,
                variableExpense: expense,
                offsetAmount: savingsOffsetAmount,
                note: savingsOffsetNote(for: trimmedDesc),
                date: transactionDate,
                modelContext: modelContext
            )
        } else {
            SavingsAccountService.removeSavingsOffset(for: expense, modelContext: modelContext)
        }

        dismiss()
    }

    private func offsetNote(for description: String) -> String {
        "Offset applied to \(description)"
    }

    private func savingsOffsetNote(for description: String) -> String {
        "Savings offset applied to \(description)"
    }
}
