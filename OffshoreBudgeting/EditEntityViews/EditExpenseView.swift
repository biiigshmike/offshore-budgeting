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
    @Query private var allocationAccounts: [AllocationAccount]

    // MARK: - Form State

    @State private var descriptionText: String = ""
    @State private var amountText: String = ""
    @State private var transactionDate: Date = .now
    @State private var selectedCardID: UUID? = nil
    @State private var selectedCategoryID: UUID? = nil
    @State private var selectedAllocationAccountID: UUID? = nil
    @State private var allocationAmountText: String = ""
    @State private var selectedOffsetAccountID: UUID? = nil
    @State private var offsetAmountText: String = ""
    @State private var sharedBalanceWasEdited: Bool = false

    // MARK: - Alerts

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false
    @State private var showingInvalidAllocationAlert: Bool = false
    @State private var showingInvalidOffsetAlert: Bool = false

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

        _allocationAccounts = Query(
            filter: #Predicate<AllocationAccount> {
                $0.workspace?.id == workspaceID && $0.isArchived == false
            },
            sort: [SortDescriptor(\AllocationAccount.name, order: .forward)]
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
            onSharedBalanceChanged: {
                sharedBalanceWasEdited = true
            }
        )
        .navigationTitle("Edit Expense")
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
        .onAppear {
            // Seed fields once.
            descriptionText = expense.descriptionText
            amountText = CurrencyFormatter.editingString(from: expense.amount)
            transactionDate = expense.transactionDate
            selectedCardID = expense.card?.id
            selectedCategoryID = expense.category?.id
            selectedAllocationAccountID = expense.allocation?.account?.id
            if let allocation = expense.allocation, allocation.allocatedAmount > 0 {
                allocationAmountText = CurrencyFormatter.editingString(from: allocation.allocatedAmount)
            } else {
                allocationAmountText = ""
            }

            selectedOffsetAccountID = expense.offsetSettlement?.account?.id
            if let settlement = expense.offsetSettlement, settlement.amount < 0 {
                offsetAmountText = CurrencyFormatter.editingString(from: -settlement.amount)
            } else {
                offsetAmountText = ""
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

        guard let selectedCard = cards.first(where: { $0.id == selectedCardID }) else {
            showingMissingCardAlert = true
            return
        }

        let selectedCategory = categories.first(where: { $0.id == selectedCategoryID })
        var resolvedAllocationAccount = allocationAccounts.first(where: { $0.id == selectedAllocationAccountID })
        var resolvedOffsetAccount = allocationAccounts.first(where: { $0.id == selectedOffsetAccountID })

        if sharedBalanceWasEdited {
            if resolvedAllocationAccount != nil {
                resolvedOffsetAccount = nil
            } else if resolvedOffsetAccount != nil {
                resolvedAllocationAccount = nil
            }
        }

        let offsetAmount: Double
        if let selectedOffsetAccount = resolvedOffsetAccount {
            let trimmed = offsetAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                offsetAmount = 0
            } else {
                guard let parsed = CurrencyFormatter.parseAmount(trimmed), parsed >= 0, parsed <= amt else {
                    showingInvalidOffsetAlert = true
                    return
                }
                let available = availableOffsetBalance(for: selectedOffsetAccount)
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

        let allocationAmount: Double
        if resolvedAllocationAccount != nil {
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

        // SwiftData models are reference types, so updating properties is enough.
        expense.descriptionText = trimmedDesc
        expense.amount = netAmount
        expense.transactionDate = transactionDate
        expense.workspace = workspace
        expense.card = selectedCard
        expense.category = selectedCategory

        if let selectedAllocationAccount = resolvedAllocationAccount, allocationAmount > 0 {
            if let existing = expense.allocation {
                existing.allocatedAmount = AllocationLedgerService.cappedAllocationAmount(allocationAmount, expenseAmount: netAmount)
                existing.updatedAt = .now
                existing.account = selectedAllocationAccount
                existing.workspace = workspace
            } else {
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
        } else if let existing = expense.allocation {
            expense.allocation = nil
            modelContext.delete(existing)
        }

        if let selectedOffsetAccount = resolvedOffsetAccount, offsetAmount > 0 {
            if let existing = expense.offsetSettlement {
                existing.date = transactionDate
                existing.note = offsetNote(for: trimmedDesc)
                existing.amount = -offsetAmount
                existing.workspace = workspace
                existing.account = selectedOffsetAccount
                existing.expense = expense
            } else {
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
        } else if let existing = expense.offsetSettlement {
            expense.offsetSettlement = nil
            modelContext.delete(existing)
        }

        // Not strictly required, but harmless and explicit.
        try? modelContext.save()

        dismiss()
    }

    private func availableOffsetBalance(for account: AllocationAccount) -> Double {
        let currentBalance = max(0, AllocationLedgerService.balance(for: account))
        guard let existing = expense.offsetSettlement else { return currentBalance }
        guard existing.account?.id == account.id else { return currentBalance }
        return max(0, currentBalance + max(0, -existing.amount))
    }

    private func offsetNote(for description: String) -> String {
        "Offset applied to \(description)"
    }
}
