//
//  ManageCardsForBudgetSheet.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI
import SwiftData

struct ManageCardsForBudgetSheet: View {
    let workspace: Workspace
    let budget: Budget

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Query private var cards: [Card]

    // MARK: - Unlink Policy UI

    @State private var pendingCardForUnlink: Card? = nil
    @State private var showingUnlinkPolicyAlert: Bool = false

    @State private var showingDetachPresetsChoiceAlert: Bool = false

    @State private var showingNothingToDeleteAlert: Bool = false

    @State private var reviewCard: Card? = nil
    @State private var showingReviewRecordedExpenses: Bool = false

    init(workspace: Workspace, budget: Budget) {
        self.workspace = workspace
        self.budget = budget

        let workspaceID: UUID? = workspace.id
        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )
    }

    var body: some View {
        List {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No Cards",
                    systemImage: "creditcard",
                    description: Text("Create a card first, then you can link it to this budget.")
                )
            } else {
                ForEach(cards) { card in
                    Toggle(isOn: bindingForCard(card)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(card.name)

                            Text(isLinked(card) ? "Linked" : "Not linked")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color("AccentColor"))
                    .disabled(!canLink(card))
                }
            }
        }
        .navigationTitle("Linked Cards")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .onAppear {
            cleanupOrphanLinks()
        }

        // MARK: - Unlink Policy Prompt (native)

        .alert("Unlink Card?", isPresented: $showingUnlinkPolicyAlert) {
            Button("Keep All Expenses") {
                guard let card = pendingCardForUnlink else { return }
                unlink(card)
                pendingCardForUnlink = nil
            }

            Button("Delete Budget-Planned Expenses", role: .destructive) {
                // Give the user a choice to also detach presets, so re-linking the card
                // doesn't re-generate budget-planned expenses automatically.
                showingDetachPresetsChoiceAlert = true
            }

            Button("Cancel", role: .cancel) {
                pendingCardForUnlink = nil
            }
        } message: {
            Text("This card has planned expenses created for this budget. What should Offshore do with them?")
        }

        .alert("Also remove presets?", isPresented: $showingDetachPresetsChoiceAlert) {
            Button("Delete Expenses Only", role: .destructive) {
                guard let card = pendingCardForUnlink else { return }
                unlinkAndDeleteBudgetPlannedExpenses(for: card)
                pendingCardForUnlink = nil
            }

            Button("Delete Expenses and Detach Presets", role: .destructive) {
                guard let card = pendingCardForUnlink else { return }
                unlinkDeleteExpensesAndDetachPresets(for: card)
                pendingCardForUnlink = nil
            }

            Button("Cancel", role: .cancel) {
                // Keep the card linked, user backed out.
                pendingCardForUnlink = nil
            }
        } message: {
            Text("If presets stay linked to this budget, they may apply again when you re-link this card.")
        }

        .alert("Nothing to delete", isPresented: $showingNothingToDeleteAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("These planned expenses have actual spending recorded.")
        }

        .sheet(isPresented: $showingReviewRecordedExpenses) {
            if let reviewCard {
                NavigationStack {
                    BudgetRecordedPlannedExpensesReviewView(
                        workspace: workspace,
                        budget: budget,
                        card: reviewCard,
                        onDeleteBudget: {
                            showingReviewRecordedExpenses = false
                            modelContext.delete(budget)
                            dismiss()
                        },
                        onDone: {
                            showingReviewRecordedExpenses = false
                        }
                    )
                }
            }
        }
    }

    // MARK: - Guardrails

    private func canLink(_ card: Card) -> Bool {
        guard let budgetWorkspaceID = budget.workspace?.id else { return false }
        guard let cardWorkspaceID = card.workspace?.id else { return false }
        return budgetWorkspaceID == workspace.id && cardWorkspaceID == workspace.id
    }

    // MARK: - Link Helpers

    private func isLinked(_ card: Card) -> Bool {
        (budget.cardLinks ?? []).contains { $0.card?.id == card.id }
    }

    private func bindingForCard(_ card: Card) -> Binding<Bool> {
        Binding(
            get: { isLinked(card) },
            set: { newValue in
                guard canLink(card) else { return }

                if newValue {
                    link(card)
                } else {
                    handleToggleOff(card)
                }
            }
        )
    }

    private func handleToggleOff(_ card: Card) {
        // If there are no generated planned expenses for this budget + card, unlink quietly.
        if !hasAnyGeneratedPlannedExpenses(for: card) {
            unlink(card)
            return
        }

        // There are generated items, so show the policy prompt.
        pendingCardForUnlink = card
        showingUnlinkPolicyAlert = true
    }

    private func link(_ card: Card) {
        guard canLink(card) else { return }
        guard !isLinked(card) else { return }

        let link = BudgetCardLink(budget: budget, card: card)
        modelContext.insert(link)
    }

    private func unlink(_ card: Card) {
        let matches = (budget.cardLinks ?? []).filter { $0.card?.id == card.id }
        for link in matches {
            modelContext.delete(link)
        }
    }

    private func cleanupOrphanLinks() {
        let orphans = (budget.cardLinks ?? []).filter { $0.card == nil || $0.budget == nil }
        for link in orphans {
            modelContext.delete(link)
        }
    }

    // MARK: - Generated Planned Expense Checks

    private func hasAnyGeneratedPlannedExpenses(for card: Card) -> Bool {
        let budgetID: UUID? = budget.id
        let cardID = card.id

        var descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID
            }
        )
        descriptor.fetchLimit = 200

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.contains { $0.card?.id == cardID }
    }

    private func deleteUnspentGeneratedPlannedExpenses(for card: Card) -> Int {
        let budgetID: UUID? = budget.id
        let cardID = card.id

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID &&
                expense.actualAmount == 0
            }
        )

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        let scoped = matches.filter { $0.card?.id == cardID }

        for expense in scoped {
            PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        }

        return scoped.count
    }

    private func countRecordedGeneratedPlannedExpenses(for card: Card) -> Int {
        let budgetID: UUID? = budget.id
        let cardID = card.id

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID &&
                expense.actualAmount > 0
            }
        )

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return matches.filter { $0.card?.id == cardID }.count
    }

    private func presetIDsAffectingCard(for card: Card) -> Set<UUID> {
        let budgetID: UUID? = budget.id
        let cardID = card.id

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID
            }
        )

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        let scoped = matches.filter { $0.card?.id == cardID }

        return Set(scoped.compactMap { $0.sourcePresetID })
    }

    private func detachPresetLinksFromBudget(presetIDs: Set<UUID>) {
        guard !presetIDs.isEmpty else { return }

        // Keep this stable, same approach as cards, filter in-memory.
        let links = budget.presetLinks ?? []
        let matches = links.filter { link in
            guard let presetID = link.preset?.id else { return false }
            return presetIDs.contains(presetID)
        }

        for link in matches {
            modelContext.delete(link)
        }
    }

    private func unlinkAndDeleteBudgetPlannedExpenses(for card: Card) {
        let deletedUnspentCount = deleteUnspentGeneratedPlannedExpenses(for: card)
        let recordedCount = countRecordedGeneratedPlannedExpenses(for: card)

        // Unlink always happens as part of the user's action choice.
        unlink(card)

        // If there are recorded items, route to review instead of pretending "nothing happened".
        if recordedCount > 0 {
            reviewCard = card
            showingReviewRecordedExpenses = true
            return
        }

        // No recorded items exist.
        if deletedUnspentCount == 0 {
            showingNothingToDeleteAlert = true
        }
    }

    private func unlinkDeleteExpensesAndDetachPresets(for card: Card) {
        let presetIDs = presetIDsAffectingCard(for: card)

        let deletedUnspentCount = deleteUnspentGeneratedPlannedExpenses(for: card)
        let recordedCount = countRecordedGeneratedPlannedExpenses(for: card)

        unlink(card)

        // This is the key behavior: prevent re-materialization when the card is re-linked.
        detachPresetLinksFromBudget(presetIDs: presetIDs)

        if recordedCount > 0 {
            reviewCard = card
            showingReviewRecordedExpenses = true
            return
        }

        if deletedUnspentCount == 0 {
            showingNothingToDeleteAlert = true
        }
    }
}
