//
//  SettingsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {

    let workspace: Workspace
    @Binding var selectedWorkspaceID: String

    @Query(sort: \Workspace.name, order: .forward)
    private var workspaces: [Workspace]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTabActivationContext) private var tabActivationContext
    @State private var showingWorkspaceManager: Bool = false
    @State private var sectionModels: [SettingsSectionModel] = []
    @State private var workspaceMenuItems: [WorkspaceMenuItemModel] = []
    @State private var activationEnrichmentTask: Task<Void, Never>? = nil

    private enum SettingsDestination: Hashable {
        case about
        case help
        case general
        case privacy
        case notifications
        case iCloud
        case quickActions
        case manageCategories
        case managePresets
    }

    private struct SettingsRowModel: Identifiable {
        let id: SettingsDestination
        let title: String
        let systemImage: String
        let tint: Color
    }

    private struct SettingsSectionModel: Identifiable {
        let id: String
        let rows: [SettingsRowModel]
    }

    private struct WorkspaceMenuItemModel: Identifiable {
        let id: UUID
        let name: String
        let hexColor: String
        let isSelected: Bool
    }

    // MARK: - Derived

    private var appDisplayName: String {
        let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        return displayName ?? bundleName ?? "App"
    }

    private var selectedWorkspaceColor: Color {
        Color(hex: workspace.hexColor) ?? Color(.systemBlue)
    }

    // MARK: - Body

    var body: some View {
        List {
            ForEach(displayedSectionModels) { section in
                Section {
                    ForEach(section.rows) { row in
                        settingsRow(for: row)
                    }
                } header: {
                    EmptyView()
                } footer: {
                    EmptyView()
                }
            }
        }
        .navigationTitle(String(localized: "app.section.settings", defaultValue: "Settings", comment: "Main tab title for the Settings section."))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                workspaceTrailingNavBarItem
            }
        }
        .sheet(isPresented: $showingWorkspaceManager) {
            workspaceManagerSheet
        }
        .onAppear {
            rebuildDisplayModels()
            scheduleActivationEnrichment(reason: "onAppear")
        }
        .onDisappear {
            cancelActivationEnrichment()
        }
        .onChange(of: workspace.id) { _, _ in
            rebuildDisplayModels()
        }
        .onChange(of: selectedWorkspaceID) { _, _ in
            rebuildWorkspaceMenuItems()
        }
        .onChange(of: workspaces.count) { _, _ in
            rebuildDisplayModels()
        }
        .onChange(of: tabActivationContext) { _, newValue in
            guard newValue.sectionRawValue == AppSection.settings.rawValue else { return }
            if newValue.phase == .active {
                scheduleActivationEnrichment(reason: "tabActivationSettled")
            } else {
                cancelActivationEnrichment()
            }
        }
    }

    private var displayedSectionModels: [SettingsSectionModel] {
        sectionModels.isEmpty ? buildSectionModels() : sectionModels
    }

    private var aboutRow: some View {
        HStack(spacing: 14) {
            Image("SettingsIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 46, height: 46)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(appDisplayName)
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text(String(localized: "settings.about", defaultValue: "About", comment: "Title for about screen."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Toolbar Workspace Item (Single Source of Truth)

    @ViewBuilder
    private var workspaceTrailingNavBarItem: some View {
        let baseMenu = Menu {
            workspaceSwitcherMenuContent

            Button {
                showingWorkspaceManager = true
            } label: {
                Label(String(localized: "settings.manageWorkspaces", defaultValue: "Manage Workspaces", comment: "Menu action to open workspace manager."), systemImage: "person.fill")
            }
        } label: {
            WorkspaceToolbarMenuLabel(
                tint: selectedWorkspaceColor,
                systemImage: "person.fill"
            )
        }
        .accessibilityLabel(String(localized: "settings.workspaces", defaultValue: "Workspaces", comment: "Accessibility label for workspace menu."))
        .accessibilityHint(String(localized: "settings.workspaces.hint", defaultValue: "Switch workspaces or manage them", comment: "Accessibility hint for workspace menu."))
        .tint(.primary)
        .controlSize(.large)

        if #available(iOS 26.0, *) {
            baseMenu.buttonStyle(.glassProminent)
        } else {
            baseMenu.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var workspaceSwitcherMenuContent: some View {
        if !displayedWorkspaceMenuItems.isEmpty {
            Section(String(localized: "settings.switchWorkspace", defaultValue: "Switch Workspace", comment: "Section title for switching workspace.")) {
                ForEach(displayedWorkspaceMenuItems) { ws in
                    Button {
                        selectedWorkspaceID = ws.id.uuidString
                    } label: {
                        workspaceMenuRow(for: ws)
                    }
                }
            }

            Divider()
        }
    }

    private var displayedWorkspaceMenuItems: [WorkspaceMenuItemModel] {
        workspaceMenuItems.isEmpty ? buildWorkspaceMenuItems() : workspaceMenuItems
    }

    private func workspaceMenuRow(for ws: WorkspaceMenuItemModel) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: ws.hexColor) ?? .secondary)
                .frame(width: 10, height: 10)

            Text(ws.name)

            Spacer()

            if ws.isSelected {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
    }

    @ViewBuilder
    private func settingsRow(for row: SettingsRowModel) -> some View {
        NavigationLink {
            settingsDestination(for: row.id)
        } label: {
            if row.id == .about {
                aboutRow
            } else {
                SettingsRow(
                    title: row.title,
                    systemImage: row.systemImage,
                    tint: row.tint
                )
            }
        }
    }

    @ViewBuilder
    private func settingsDestination(for destination: SettingsDestination) -> some View {
        switch destination {
        case .about:
            SettingsAboutView()
        case .help:
            SettingsHelpView()
        case .general:
            SettingsGeneralView()
        case .privacy:
            SettingsPrivacyView()
        case .notifications:
            SettingsNotificationsView(workspaceID: workspace.id)
        case .iCloud:
            SettingsiCloudView()
        case .quickActions:
            QuickActionsInstallView()
        case .manageCategories:
            ManageCategoriesView(workspace: workspace)
        case .managePresets:
            ManagePresetsView(workspace: workspace)
        }
    }

    private func rebuildDisplayModels() {
        sectionModels = buildSectionModels()
        workspaceMenuItems = buildWorkspaceMenuItems()
    }

    private func rebuildWorkspaceMenuItems() {
        workspaceMenuItems = buildWorkspaceMenuItems()
    }

    private func buildSectionModels() -> [SettingsSectionModel] {
        [
            SettingsSectionModel(
                id: "about",
                rows: [
                    SettingsRowModel(id: .about, title: appDisplayName, systemImage: "", tint: .clear),
                    SettingsRowModel(
                        id: .help,
                        title: String(localized: "help.title", defaultValue: "Help", comment: "Title for help screen."),
                        systemImage: "questionmark.circle",
                        tint: Color(.systemGray)
                    )
                ]
            ),
            SettingsSectionModel(
                id: "system",
                rows: [
                    SettingsRowModel(id: .general, title: String(localized: "settings.general", defaultValue: "General", comment: "Title for general settings."), systemImage: "gear", tint: Color(.systemGray)),
                    SettingsRowModel(id: .privacy, title: String(localized: "settings.privacy", defaultValue: "Privacy", comment: "Title for privacy settings."), systemImage: "faceid", tint: Color(.systemBlue)),
                    SettingsRowModel(id: .notifications, title: String(localized: "settings.notifications", defaultValue: "Notifications", comment: "Title for notifications settings."), systemImage: "bell.badge", tint: Color(.systemRed)),
                    SettingsRowModel(id: .iCloud, title: String(localized: "settings.icloud", defaultValue: "iCloud", comment: "Title for iCloud settings."), systemImage: "icloud", tint: Color(.systemBlue))
                ]
            ),
            SettingsSectionModel(
                id: "quick-actions",
                rows: [
                    SettingsRowModel(id: .quickActions, title: String(localized: "settings.quickActions", defaultValue: "Quick Actions", comment: "Title for quick actions settings."), systemImage: "bolt.circle", tint: .green)
                ]
            ),
            SettingsSectionModel(
                id: "categories",
                rows: [
                    SettingsRowModel(id: .manageCategories, title: String(localized: "settings.manageCategories", defaultValue: "Manage Categories", comment: "Title for manage categories row."), systemImage: "tag", tint: .purple)
                ]
            ),
            SettingsSectionModel(
                id: "presets",
                rows: [
                    SettingsRowModel(id: .managePresets, title: String(localized: "settings.managePresets", defaultValue: "Manage Presets", comment: "Title for manage presets row."), systemImage: "list.bullet.rectangle", tint: .orange)
                ]
            )
        ]
    }

    private func buildWorkspaceMenuItems() -> [WorkspaceMenuItemModel] {
        workspaces.map { ws in
            WorkspaceMenuItemModel(
                id: ws.id,
                name: ws.name,
                hexColor: ws.hexColor,
                isSelected: selectedWorkspaceID == ws.id.uuidString
            )
        }
    }

    private func scheduleActivationEnrichment(reason: String) {
        cancelActivationEnrichment()
        let activationToken = tabActivationContext.token

        activationEnrichmentTask = Task {
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                guard tabActivationContext.sectionRawValue == AppSection.settings.rawValue,
                      tabActivationContext.phase == .active,
                      tabActivationContext.token == activationToken else {
                    return
                }

                rebuildDisplayModels()
                TabFlickerDiagnostics.markEvent(
                    "settingsActivationEnrichmentFinished",
                    metadata: ["reason": reason]
                )
            }
        }
    }

    private func cancelActivationEnrichment() {
        activationEnrichmentTask?.cancel()
        activationEnrichmentTask = nil
    }

    private var workspaceManagerSheet: some View {
        NavigationStack {
            WorkspacePickerView(
                workspaces: workspaces,
                selectedWorkspaceID: $selectedWorkspaceID,
                showsCloseButton: true,
                onCreate: createWorkspace(name:hexColor:),
                onDelete: deleteWorkspaces
            )
        }
    }

    // MARK: - Actions

    private func createWorkspace(name: String, hexColor: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHex = hexColor.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { return }

        let newWorkspace = Workspace(
            name: trimmedName,
            hexColor: trimmedHex.isEmpty ? "#3B82F6" : trimmedHex
        )

        modelContext.insert(newWorkspace)
    }

    private func deleteWorkspaces(at offsets: IndexSet) {
        let workspacesToDelete = offsets.compactMap { index in
            workspaces.indices.contains(index) ? workspaces[index] : nil
        }

        let deletedIDs = workspacesToDelete.map { $0.id.uuidString }
        let willDeleteSelected = deletedIDs.contains(selectedWorkspaceID)

        for ws in workspacesToDelete {
            modelContext.delete(ws)
        }

        if willDeleteSelected {
            selectedWorkspaceID = ""
        }
    }

}

// MARK: - Workspace Toolbar Menu Label

private struct WorkspaceToolbarMenuLabel: View {

    let tint: Color
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(
                Circle()
                    .fill(tint)
            )
            .background(.thinMaterial, in: Circle())
            .opacity(0.95)
            .contentShape(Circle())
    }
}

// MARK: - Settings Row

private struct SettingsRow: View {

    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint)

                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)

            Text(title)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)
        }
        .padding(.vertical, 2)
    }
}

#Preview("Settings") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            SettingsView(workspace: ws, selectedWorkspaceID: .constant(ws.id.uuidString))
        }
    }
}
