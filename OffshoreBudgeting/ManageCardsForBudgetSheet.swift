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

    @State private var showingUnlinkDeleteConfirm: Bool = false
    @State private var pendingUnlinkDelete: (() -> Void)? = nil

    @Query private var cards: [Card]

    init(workspace: Workspace, budget: Budget) {
        self.workspace = workspace
        self.budget = budget

        let workspaceID = workspace.id
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
                    .disabled(!canLink(card))
                }
            }
        }
        .navigationTitle("Linked Cards")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            cleanupOrphanLinks()
        }
        .alert("Delete?", isPresented: $showingUnlinkDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingUnlinkDelete?()
                pendingUnlinkDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingUnlinkDelete = nil
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
                    if confirmBeforeDeleting {
                        pendingUnlinkDelete = {
                            unlink(card)
                        }
                        showingUnlinkDeleteConfirm = true
                    } else {
                        unlink(card)
                    }
                }
            }
        )
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
}
