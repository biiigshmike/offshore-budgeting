//
//  HomeEditPinnedCardsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

struct HomeEditPinnedCardsView: View {

    let cards: [Card]
    let workspaceID: UUID
    @Binding var pinnedIDs: [UUID]

    // ✅ New: widget ordering + visibility (presence in array = shown)
    @Binding var pinnedWidgets: [HomeWidgetID]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Widgets

                Section("Pinned Widgets") {
                    if pinnedWidgets.isEmpty {
                        Text("No pinned widgets yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pinnedWidgets) { widget in
                            HStack {
                                Text(widget.title)
                                Spacer()
                                Image(systemName: "line.3.horizontal")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onMove(perform: movePinnedWidgets)
                        .onDelete(perform: deletePinnedWidgets)
                    }
                }

                Section("Available Widgets") {
                    let available = HomeWidgetID.allCases.filter { !pinnedWidgets.contains($0) }

                    if available.isEmpty {
                        Text("All widgets are pinned.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(available) { widget in
                            Button {
                                pinnedWidgets.append(widget)
                            } label: {
                                HStack {
                                    Text(widget.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // MARK: - Cards (existing behavior)

                Section("Pinned Cards") {
                    if pinnedIDs.isEmpty {
                        Text("No pinned cards yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pinnedIDs, id: \.self) { id in
                            if let card = cards.first(where: { $0.id == id }) {
                                HStack {
                                    Text(card.name)
                                    Spacer()
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onMove(perform: movePinnedCards)
                        .onDelete(perform: deletePinnedCards)
                    }
                }

                Section("Available Cards") {
                    ForEach(cards) { card in
                        Button {
                            togglePinnedCard(card.id)
                        } label: {
                            HStack {
                                Text(card.name)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if pinnedIDs.contains(card.id) {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Widgets")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
    }

    // MARK: - Widgets helpers

    private func movePinnedWidgets(from source: IndexSet, to destination: Int) {
        pinnedWidgets.move(fromOffsets: source, toOffset: destination)
    }

    private func deletePinnedWidgets(at offsets: IndexSet) {
        pinnedWidgets.remove(atOffsets: offsets)
    }

    // MARK: - Card helpers

    private func togglePinnedCard(_ id: UUID) {
        if let index = pinnedIDs.firstIndex(of: id) {
            pinnedIDs.remove(at: index)
        } else {
            pinnedIDs.append(id)
        }
    }

    private func movePinnedCards(from source: IndexSet, to destination: Int) {
        pinnedIDs.move(fromOffsets: source, toOffset: destination)
    }

    private func deletePinnedCards(at offsets: IndexSet) {
        pinnedIDs.remove(atOffsets: offsets)
    }
}
