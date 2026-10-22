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
    let showsTileSizePicker: Bool

    @Binding var pinnedItems: [HomePinnedItem]

    @Environment(\.dismiss) private var dismiss

    @State private var editMode: EditMode = .inactive

    private var isEditing: Bool { editMode == .active }

    var body: some View {
        NavigationStack {
            List {

                // MARK: - Pinned on Home (combined)

                Section(
                    String(
                        localized: "homeEdit.section.pinnedOnDashboard",
                        defaultValue: "Pinned on Dashboard",
                        comment: "Section title for items currently pinned to the Home dashboard."
                    )
                ) {
                    if pinnedItems.isEmpty {
                        Text(
                            String(
                                localized: "homeEdit.empty.pinned",
                                defaultValue: "Nothing is pinned yet.",
                                comment: "Empty-state message when no cards or widgets are pinned on Home."
                            )
                        )
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

                Section(
                    String(
                        localized: "homeEdit.section.availableWidgets",
                        defaultValue: "Available Panels",
                        comment: "Section title for widgets available to pin to Home."
                    )
                ) {
                    let pinnedWidgetSet = Set(pinnedItems.compactMap { item -> HomeWidgetID? in
                        if case .widget(let w, _) = item { return w }
                        return nil
                    })

                    let availableWidgets = HomeWidgetID.allCases.filter { !pinnedWidgetSet.contains($0) }

                    if availableWidgets.isEmpty {
                        Text(
                            String(
                                localized: "homeEdit.empty.availableWidgets",
                                defaultValue: "All panels are pinned.",
                                comment: "Message shown when there are no additional widgets available to pin."
                            )
                        )
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

                Section(
                    String(
                        localized: "homeEdit.section.availableCards",
                        defaultValue: "Available Cards",
                        comment: "Section title for cards available to pin to Home."
                    )
                ) {
                    let pinnedCardSet = Set(pinnedItems.compactMap { item -> UUID? in
                        if case .card(let id, _) = item { return id }
                        return nil
                    })

                    let availableCards = cards.filter { !pinnedCardSet.contains($0.id) }

                    if availableCards.isEmpty {
                        Text(
                            String(
                                localized: "homeEdit.empty.availableCards",
                                defaultValue: "All cards are pinned.",
                                comment: "Message shown when there are no additional cards available to pin."
                            )
                        )
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
            .navigationTitle(
                String(
                    localized: "homeEdit.navigationTitle",
                    defaultValue: "Edit Dashboard",
                    comment: "Navigation title for editing Home pinned items."
                )
            )
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
                            Label(
                                String(
                                    localized: "common.done",
                                    defaultValue: "Done",
                                    comment: "Generic action label to finish editing."
                                ),
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(
                                String(
                                    localized: "common.edit",
                                    defaultValue: "Edit",
                                    comment: "Generic action label to start editing."
                                )
                            )
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

            if showsTileSizePicker {
                Spacer()

                Picker(
                    String(
                        localized: "homeEdit.picker.size",
                        defaultValue: "Size",
                        comment: "Label for the home tile size picker."
                    ),
                    selection: sizeBinding
                ) {
                    ForEach(HomeTileSize.allCases, id: \.self) { size in
                        Text(size.title).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .disabled(!isEditing)
            }
        }
    }

    // MARK: - Helpers

    private func title(for item: HomePinnedItem) -> String {
        switch item {
        case .widget(let widget, _):
            return widget.title
        case .card(let id, _):
            return cards.first(where: { $0.id == id })?.name
                ?? String(
                    localized: "homeEdit.missingCard",
                    defaultValue: "Missing Card",
                    comment: "Fallback title when a pinned card can no longer be found."
                )
        }
    }

    private func movePinnedItems(from source: IndexSet, to destination: Int) {
        pinnedItems.move(fromOffsets: source, toOffset: destination)
    }

    private func deletePinnedItems(at offsets: IndexSet) {
        pinnedItems.remove(atOffsets: offsets)
    }
}
