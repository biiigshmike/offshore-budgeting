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

    // ✅ Unified ordering + visibility (presence in array = shown)
    @Binding var pinnedItems: [HomePinnedItem]

    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive

    private var isEditing: Bool { editMode == .active }

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Pinned on Home (combined)

                Section("Pinned on Home") {
                    if pinnedItems.isEmpty {
                        Text("Nothing is pinned yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(pinnedItems) { item in
                            row(for: item)
                                .moveDisabled(!isEditing)
                                .deleteDisabled(!isEditing)
                        }
                        .onMove(perform: movePinnedItems)
                        .onDelete(perform: deletePinnedItems)
                    }
                }

                // MARK: - Available Widgets

                Section("Available Widgets") {
                    let pinnedWidgetSet = Set(pinnedItems.compactMap { item -> HomeWidgetID? in
                        if case .widget(let w) = item { return w }
                        return nil
                    })

                    let availableWidgets = HomeWidgetID.allCases.filter { !pinnedWidgetSet.contains($0) }

                    if availableWidgets.isEmpty {
                        Text("All widgets are pinned.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableWidgets) { widget in
                            Button {
                                pinnedItems.append(.widget(widget))
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

                // MARK: - Available Cards

                Section("Available Cards") {
                    let pinnedCardSet = Set(pinnedItems.compactMap { item -> UUID? in
                        if case .card(let id) = item { return id }
                        return nil
                    })

                    let availableCards = cards.filter { !pinnedCardSet.contains($0.id) }

                    if availableCards.isEmpty {
                        Text("All cards are pinned.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableCards) { card in
                            Button {
                                pinnedItems.append(.card(card.id))
                            } label: {
                                HStack {
                                    Text(card.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Home")
            .environment(\.editMode, $editMode)
            .onDisappear {
                editMode = .inactive
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            editMode = isEditing ? .inactive : .active
                        }
                    } label: {
                        if isEditing {
                            Label("Done", systemImage: "checkmark")
                        } else {
                            Text("Edit")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Row UI

    @ViewBuilder
    private func row(for item: HomePinnedItem) -> some View {
        switch item {
        case .widget(let widget):
            HStack(spacing: 10) {
                Text(widget.title)
                Spacer()
                Text("Widget")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

        case .card(let id):
            if let card = cards.first(where: { $0.id == id }) {
                HStack(spacing: 10) {
                    Text(card.name)
                    Spacer()
                    Text("Card")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack(spacing: 10) {
                    Text("Missing Card")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Card")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func movePinnedItems(from source: IndexSet, to destination: Int) {
        pinnedItems.move(fromOffsets: source, toOffset: destination)
    }

    private func deletePinnedItems(at offsets: IndexSet) {
        pinnedItems.remove(atOffsets: offsets)
    }
}
