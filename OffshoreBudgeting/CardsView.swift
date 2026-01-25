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

    @State private var showingAddCardSheet = false
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
                                    theme: CardThemeOption(rawValue: card.theme) ?? .rose,
                                    effect: CardEffectOption(rawValue: card.effect) ?? .plastic
                                )
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    editingCard = card
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }

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
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Cards")
        .toolbar {
            Button {
                showingAddCardSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("Add Card")
        }
        .sheet(isPresented: $showingAddCardSheet) {
            NavigationStack {
                AddCardView(workspace: workspace)
            }
        }
        .sheet(item: $editingCard) { card in
            NavigationStack {
                EditCardView(workspace: workspace, card: card)
            }
        }
        .alert("Delete?", isPresented: $showingCardDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingCardDelete?()
                pendingCardDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCardDelete = nil
            }
        }
    }

    private func delete(_ card: Card) {
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
