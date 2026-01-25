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

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []

    var body: some View {
        NavigationStack {
            List {
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
                        .onMove(perform: movePinned)
                        .onDelete(perform: deletePinned)
                    }
                }

                Section("Available Cards") {
                    ForEach(cards) { card in
                        Button {
                            togglePinned(card.id)
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

    private func togglePinned(_ id: UUID) {
        if let index = pinnedIDs.firstIndex(of: id) {
            pinnedIDs.remove(at: index)
        } else {
            pinnedIDs.append(id)
        }
    }

    private func movePinned(from source: IndexSet, to destination: Int) {
        pinnedIDs.move(fromOffsets: source, toOffset: destination)
    }

    private func deletePinned(at offsets: IndexSet) {
        pinnedIDs.remove(atOffsets: offsets)
    }
}
