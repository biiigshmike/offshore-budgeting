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
                        ForEach($pinnedItems) { $item in
                            row(item: $item)
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
                        if case .widget(let w, _) = item { return w }
                        return nil
                    })

                    let availableWidgets = HomeWidgetID.allCases.filter { !pinnedWidgetSet.contains($0) }

                    if availableWidgets.isEmpty {
                        Text("All widgets are pinned.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableWidgets) { widget in
                            Button {
                                pinnedItems.append(.widget(widget, .small))
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
                        .disabled(!isEditing)
                    }
                }

                // MARK: - Available Cards

                Section("Available Cards") {
                    let pinnedCardSet = Set(pinnedItems.compactMap { item -> UUID? in
                        if case .card(let id, _) = item { return id }
                        return nil
                    })

                    let availableCards = cards.filter { !pinnedCardSet.contains($0.id) }

                    if availableCards.isEmpty {
                        Text("All cards are pinned.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(availableCards) { card in
                            Button {
                                pinnedItems.append(.card(card.id, .small))
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
                        .disabled(!isEditing)
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
    private func row(item: Binding<HomePinnedItem>) -> some View {
        let sizeBinding = Binding<HomeTileSize>(
            get: { item.wrappedValue.tileSize },
            set: { item.wrappedValue = item.wrappedValue.withTileSize($0) }
        )

        HStack(spacing: 10) {
            Text(title(for: item.wrappedValue))
                .foregroundStyle(Color("AccentColor"))

            Spacer()

            Picker("Size", selection: sizeBinding) {
                ForEach(HomeTileSize.allCases, id: \.self) { size in
                    Text(size.title).tag(size)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 160)
            .disabled(!isEditing)
        }
    }

    // MARK: - Helpers

    private func title(for item: HomePinnedItem) -> String {
        switch item {
        case .widget(let widget, _):
            return widget.title
        case .card(let id, _):
            return cards.first(where: { $0.id == id })?.name ?? "Missing Card"
        }
    }

    private func movePinnedItems(from source: IndexSet, to destination: Int) {
        pinnedItems.move(fromOffsets: source, toOffset: destination)
    }

    private func deletePinnedItems(at offsets: IndexSet) {
        pinnedItems.remove(atOffsets: offsets)
    }
}
