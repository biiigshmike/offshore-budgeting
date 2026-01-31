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
    // pull links broadly and filter in-memory for the current workspace.
    @Query private var presetLinks: [BudgetPresetLink]

    private enum SheetRoute: Identifiable {
        case add
        case edit(Preset)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let preset):
                return "edit-\(preset.id.uuidString)"
            }
        }
    }

    @State private var sheetRoute: SheetRoute? = nil

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

    private var presetIDsMissingLinkedCards: Set<UUID> {
        var ids = Set<UUID>()

        for link in presetLinks {
            guard link.budget?.workspace?.id == workspace.id else { continue }
            guard let presetID = link.preset?.id else { continue }

            let budgetHasCards = ((link.budget?.cardLinks ?? []).isEmpty == false)
            if !budgetHasCards {
                ids.insert(presetID)
            }
        }

        return ids
    }

    private var presetRequiresCardFootnoteText: String {
        let hasAnyCardsInSystem = (workspace.cards ?? []).isEmpty == false
        return hasAnyCardsInSystem ? "Card Unassigned" : "No Cards Available"
    }

    // MARK: - Active vs archived

    private var activePresets: [Preset] {
        presets.filter { $0.isArchived == false }
    }

    private var archivedPresets: [Preset] {
        presets.filter { $0.isArchived }
    }

    private var highlightedPreset: Preset? {
        guard let id = highlightedPresetID else { return nil }
        return activePresets.first(where: { $0.id == id })
    }

    private var activePresetsWithoutHighlighted: [Preset] {
        guard let highlightedPresetID else { return activePresets }
        return activePresets.filter { $0.id != highlightedPresetID }
    }

    // MARK: - View

    var body: some View {
        List {
            if activePresets.isEmpty && archivedPresets.isEmpty {
                ContentUnavailableView(
                    "No Presets Yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create presets to generate planned expenses when you assign them to budgets.")
                )
            } else {

                if let pinned = highlightedPreset {
                    Section("Next Planned Expense") {
                        let assignedCount = assignedBudgetCountsByPresetID[pinned.id, default: 0]

                        VStack(alignment: .leading, spacing: 6) {
                            PresetRowView(
                                preset: pinned,
                                assignedBudgetsCount: assignedCount
                            )

                            if presetIDsMissingLinkedCards.contains(pinned.id) {
                                Text(presetRequiresCardFootnoteText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(pinnedPresetBackground(for: pinned))
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                sheetRoute = .edit(pinned)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color("AccentColor"))

                            Button {
                                archive(pinned)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(Color("OffshoreSand"))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deletePresetWithOptionalConfirm(pinned)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(Color("OffshoreDepth"))
                        }
                    }
                }

                // MARK: - Active presets

                Section {
                    ForEach(activePresetsWithoutHighlighted) { preset in
                        let assignedCount = assignedBudgetCountsByPresetID[preset.id, default: 0]

                        VStack(alignment: .leading, spacing: 6) {
                            PresetRowView(
                                preset: preset,
                                assignedBudgetsCount: assignedCount
                            )

                            if presetIDsMissingLinkedCards.contains(preset.id) {
                                Text(presetRequiresCardFootnoteText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                sheetRoute = .edit(preset)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color("AccentColor"))

                            Button {
                                archive(preset)
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                            .tint(Color("OffshoreSand"))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deletePresetWithOptionalConfirm(preset)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(Color("OffshoreDepth"))
                        }
                    }
                    .onDelete(perform: deleteActiveViaListSwipe)
                }

                // MARK: - Archived presets

                if archivedPresets.isEmpty == false {
                    Section("Archived") {
                        ForEach(archivedPresets) { preset in
                            let assignedCount = assignedBudgetCountsByPresetID[preset.id, default: 0]

                            VStack(alignment: .leading, spacing: 6) {
                                PresetRowView(
                                    preset: preset,
                                    assignedBudgetsCount: assignedCount
                                )

                                if presetIDsMissingLinkedCards.contains(preset.id) {
                                    Text(presetRequiresCardFootnoteText)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    unarchive(preset)
                                } label: {
                                    Label("Unarchive", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)

                                Button {
                                    sheetRoute = .edit(preset)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color("AccentColor"))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deletePresetWithOptionalConfirm(preset)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(Color("OffshoreDepth"))
                            }
                        }
                        .onDelete(perform: deleteArchivedViaListSwipe)
                    }
                }
            }
        }
        .postBoardingTip(
            key: "tip.preset.v1",
            title: "Preset Management",
            items: [
                PostBoardingTipItem(
                    systemImage: "list.bullet.badge.ellipsis",
                    title: "Presets",
                    detail: "Save planned expenses you expect to reuse in future budgets."
                ),
                PostBoardingTipItem(
                    systemImage: "text.line.first.and.arrowtriangle.forward",
                    title: "Planned Amount",
                    detail: "Enter the minimum or antipated amount that you anticipate this expense debiting."
                ),
                PostBoardingTipItem(
                    systemImage: "calendar",
                    title: "Recurrences",
                    detail: "Use the Schedule section, choosing from a wide array of recurrence options, and setup a recurrence for your Preset. This makes it easy to plan for regular, fixed expenses, whenver you expect them to debit."
                )
            ]
        )
        .navigationTitle("Presets")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheetRoute = .add
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Preset")
            }
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .add:
                NavigationStack {
                    AddPresetView(workspace: workspace)
                }
            case .edit(let preset):
                NavigationStack {
                    EditPresetView(workspace: workspace, preset: preset)
                }
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

    // MARK: - Actions

    private func archive(_ preset: Preset) {
        preset.isArchived = true
        preset.archivedAt = Date()
    }

    private func unarchive(_ preset: Preset) {
        preset.isArchived = false
        preset.archivedAt = nil
    }

    private func deletePresetWithOptionalConfirm(_ preset: Preset) {
        if confirmBeforeDeleting {
            pendingPresetDelete = {
                modelContext.delete(preset)
            }
            showingPresetDeleteConfirm = true
        } else {
            modelContext.delete(preset)
        }
    }

    private func deletePresetsWithOptionalConfirm(_ presetsToDelete: [Preset]) {
        if presetsToDelete.isEmpty { return }

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

    private func deleteActiveViaListSwipe(at offsets: IndexSet) {
        let presetsToDelete = offsets.compactMap { index in
            activePresetsWithoutHighlighted.indices.contains(index) ? activePresetsWithoutHighlighted[index] : nil
        }

        deletePresetsWithOptionalConfirm(presetsToDelete)
    }

    private func deleteArchivedViaListSwipe(at offsets: IndexSet) {
        let presetsToDelete = offsets.compactMap { index in
            archivedPresets.indices.contains(index) ? archivedPresets[index] : nil
        }

        deletePresetsWithOptionalConfirm(presetsToDelete)
    }

    // MARK: - Styling

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
