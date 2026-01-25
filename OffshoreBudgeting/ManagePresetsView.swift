//
//  ManagePresetsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct ManagePresetsView: View {

    let workspace: Workspace
    let highlightedPresetID: UUID?

    @Environment(\.modelContext) private var modelContext

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Query private var presets: [Preset]

    // IMPORTANT:
    // Avoid deep relationship chains in SwiftData predicates, they can crash in previews (and sometimes runtime).
    // We'll pull links broadly and filter in-memory for the current workspace.
    @Query private var presetLinks: [BudgetPresetLink]

    @State private var showingAddPresetSheet: Bool = false

    @State private var presetPendingEdit: Preset? = nil

    @State private var showingPresetDeleteConfirm: Bool = false
    @State private var pendingPresetDelete: (() -> Void)? = nil

    init(workspace: Workspace, highlightedPresetID: UUID? = nil) {
        self.workspace = workspace
        self.highlightedPresetID = highlightedPresetID
        let workspaceID = workspace.id

        _presets = Query(
            filter: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Preset.title, order: .forward)]
        )

        // No filter here on purpose (see note above).
        _presetLinks = Query()
    }

    private var assignedBudgetCountsByPresetID: [UUID: Int] {
        var counts: [UUID: Int] = [:]

        for link in presetLinks {
            // Filter to only links whose budget belongs to this workspace.
            guard link.budget?.workspace?.id == workspace.id else { continue }
            guard let presetID = link.preset?.id else { continue }

            counts[presetID, default: 0] += 1
        }

        return counts
    }

    private var highlightedPreset: Preset? {
        guard let id = highlightedPresetID else { return nil }
        return presets.first(where: { $0.id == id })
    }

    private var presetsWithoutHighlighted: [Preset] {
        guard let highlightedPresetID else { return presets }
        return presets.filter { $0.id != highlightedPresetID }
    }

    var body: some View {
        List {
            if presets.isEmpty {
                ContentUnavailableView(
                    "No Presets Yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create presets to generate planned expenses when you assign them to budgets.")
                )
            } else {

                if let pinned = highlightedPreset {
                    Section("Pinned: Next Planned Expense") {
                        let assignedCount = assignedBudgetCountsByPresetID[pinned.id, default: 0]

                        PresetRowView(
                            preset: pinned,
                            assignedBudgetsCount: assignedCount
                        )
                        .padding(.vertical, 4)
                        .listRowBackground(pinnedPresetBackground(for: pinned))
                        .listRowSeparator(.hidden)
                        // Removed the overlay strokes entirely.
                        // SwiftUI can still render a hairline even when lineWidth is 0,
                        // so removing the overlay is the reliable fix.
                    }
                }

                ForEach(presetsWithoutHighlighted) { preset in
                    let assignedCount = assignedBudgetCountsByPresetID[preset.id, default: 0]

                    PresetRowView(
                        preset: preset,
                        assignedBudgetsCount: assignedCount
                    )
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            presetPendingEdit = preset
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            if confirmBeforeDeleting {
                                pendingPresetDelete = {
                                    modelContext.delete(preset)
                                }
                                showingPresetDeleteConfirm = true
                            } else {
                                modelContext.delete(preset)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteViaListSwipe)
            }
        }
        .navigationTitle("Presets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddPresetSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Preset")
            }
        }
        .sheet(isPresented: $showingAddPresetSheet) {
            NavigationStack {
                AddPresetView(workspace: workspace)
            }
        }
        .sheet(item: $presetPendingEdit) { preset in
            NavigationStack {
                EditPresetView(workspace: workspace, preset: preset)
            }
        }
        .alert("Delete?", isPresented: $showingPresetDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingPresetDelete?()
                pendingPresetDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingPresetDelete = nil
            }
        }
    }

    private func deleteViaListSwipe(at offsets: IndexSet) {
        let presetsToDelete = offsets.compactMap { index in
            presets.indices.contains(index) ? presets[index] : nil
        }

        if confirmBeforeDeleting {
            pendingPresetDelete = {
                for preset in presetsToDelete {
                    modelContext.delete(preset)
                }
            }
            showingPresetDeleteConfirm = true
        } else {
            for preset in presetsToDelete {
                modelContext.delete(preset)
            }
        }
    }

    private func pinnedPresetBackground(for preset: Preset) -> some View {
        let categoryTint = preset.defaultCategory.flatMap { Color(hex: $0.hexColor) } ?? Color.secondary.opacity(0.22)
        let palette = preset.defaultCard.map { cardThemePalette(raw: $0.theme) } ?? [.blue]
        let primary = palette.first ?? .blue
        let secondary = palette.dropFirst().first ?? primary

        return LinearGradient(
            colors: [
                primary.opacity(0.22),
                secondary.opacity(0.18),
                categoryTint.opacity(0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func pinnedPresetStroke(for preset: Preset) -> Color {
        let palette = preset.defaultCard.map { cardThemePalette(raw: $0.theme) } ?? [.blue]
        return (palette.first ?? .blue)
    }

    private func cardThemePalette(raw: String) -> [Color] {
        let theme = CardThemeOption(rawValue: raw) ?? .graphite
        return CardThemePalette.colors(for: theme)
    }
}

#Preview("Manage Presets") {
    let container = PreviewSeed.makeContainer()

    return PreviewHost(container: container) { workspace in
        NavigationStack {
            ManagePresetsView(workspace: workspace)
        }
    }
}
