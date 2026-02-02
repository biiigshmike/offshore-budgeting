//
//  CardsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct CardsView: View {

    @Environment(\.modelContext) private var modelContext

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @State private var showingAddCard: Bool = false
    @State private var showingEditCard: Bool = false
    @State private var editingCard: Card? = nil

    @State private var showingCardDeleteConfirm: Bool = false
    @State private var pendingCardDelete: (() -> Void)? = nil

    let workspace: Workspace
    @Query private var cards: [Card]

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 16)]
    }

    var body: some View {
        Group {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No Cards Yet",
                    systemImage: "creditcard",
                    description: Text("Create a card to start tracking expenses.")
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(cards) { card in
                            NavigationLink {
                                CardDetailView(workspace: workspace, card: card)
                            } label: {
                                CardVisualView(
                                    title: card.name,
                                    theme: CardThemeOption(rawValue: card.theme) ?? .ruby,
                                    effect: CardEffectOption(rawValue: card.effect) ?? .plastic
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    editingCard = card
                                    showingEditCard = true
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color("AccentColor"))

                                Button(role: .destructive) {
                                    if confirmBeforeDeleting {
                                        pendingCardDelete = {
                                            delete(card)
                                        }
                                        showingCardDeleteConfirm = true
                                    } else {
                                        delete(card)
                                    }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(Color("OffshoreDepth"))
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .postBoardingTip(
            key: "tip.cards.v1",
            title: "Cards",
            items: [
                PostBoardingTipItem(
                    systemImage: "creditcard.fill",
                    title: "Cards",
                    detail: "Browse stored cards. Single press to open a card to add expense and to view and filter spending. Long press a card to edit or delete it."
                )
            ]
        )
        .navigationTitle("Cards")
        .toolbar {
            Button {
                showingAddCard = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Card")
        }
        .alert("Delete Card?", isPresented: $showingCardDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingCardDelete?()
                pendingCardDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCardDelete = nil
            }
        } message: {
            Text("This deletes the card and all of its expenses.")
        }
        .sheet(isPresented: $showingAddCard) {
            NavigationStack {
                AddCardView(workspace: workspace)
            }
        }
        .sheet(isPresented: $showingEditCard, onDismiss: { editingCard = nil }) {
            NavigationStack {
                if let editingCard {
                    EditCardView(workspace: workspace, card: editingCard)
                } else {
                    EmptyView()
                }
            }
        }
    }

    // MARK: - Delete

    private func delete(_ card: Card) {
        let cardID = card.id
        let workspaceID = workspace.id

        HomePinnedItemsStore(workspaceID: workspaceID).removePinnedCard(id: cardID)
        HomePinnedCardsStore(workspaceID: workspaceID).removePinnedCardID(cardID)

        // I prefer being explicit here even though SwiftData delete rules are set to cascade.
        // This keeps behavior predictable if those rules ever change.
        if let planned = card.plannedExpenses {
            for expense in planned {
                modelContext.delete(expense)
            }
        }

        if let variable = card.variableExpenses {
            for expense in variable {
                modelContext.delete(expense)
            }
        }

        if let incomes = card.incomes {
            for income in incomes {
                modelContext.delete(income)
            }
        }

        if let links = card.budgetLinks {
            for link in links {
                modelContext.delete(link)
            }
        }

        modelContext.delete(card)
    }
}

#Preview("Cards") {
    let container = PreviewSeed.makeContainer()
    let context = container.mainContext

    _ = PreviewSeed.seedBasicData(in: context)

    let workspace = (try? context.fetch(FetchDescriptor<Workspace>()).first)

    return NavigationStack {
        if let workspace {
            CardsView(workspace: workspace)
        } else {
            ContentUnavailableView(
                "Missing Preview Data",
                systemImage: "creditcard",
                description: Text("PreviewSeed did not create a Workspace.")
            )
        }
    }
    .modelContainer(container)
}
