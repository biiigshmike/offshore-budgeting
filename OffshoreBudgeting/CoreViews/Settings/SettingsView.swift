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
    @State private var showingWorkspaceManager: Bool = false

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
            aboutSection
            systemSection
            managementCategoriesSection
            managementPresetsSection
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                workspaceTrailingNavBarItem
            }
        }
        .sheet(isPresented: $showingWorkspaceManager) {
            workspaceManagerSheet
        }
    }

    // MARK: - Sections

    private var aboutSection: some View {
        Section {
            NavigationLink {
                SettingsAboutView()
            } label: {
                aboutRow
            }

            NavigationLink {
                SettingsHelpView()
            } label: {
                SettingsRow(
                    title: "Help",
                    systemImage: "questionmark.circle",
                    tint: Color(.systemGray)
                )
            }
        } header: {
            EmptyView()
        } footer: {
            EmptyView()
        }
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

                Text("About")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }

    private var systemSection: some View {
        Section {
            NavigationLink {
                SettingsGeneralView()
            } label: {
                SettingsRow(
                    title: "General",
                    systemImage: "gear",
                    tint: Color(.systemGray)
                )
            }

            NavigationLink {
                SettingsPrivacyView()
            } label: {
                SettingsRow(
                    title: "Privacy",
                    systemImage: "faceid",
                    tint: Color(.systemBlue)
                )
            }

            NavigationLink {
                SettingsNotificationsView(workspaceID: workspace.id)
            } label: {
                SettingsRow(
                    title: "Notifications",
                    systemImage: "bell.badge",
                    tint: Color(.systemRed)
                )
            }

            NavigationLink {
                SettingsiCloudView()
            } label: {
                SettingsRow(
                    title: "iCloud",
                    systemImage: "icloud",
                    tint: Color(.systemBlue)
                )
            }
        } header: {
            EmptyView()
        } footer: {
            EmptyView()
        }
    }

    private var managementCategoriesSection: some View {
        Section {
            NavigationLink {
                ManageCategoriesView(workspace: workspace)
            } label: {
                SettingsRow(
                    title: "Manage Categories",
                    systemImage: "tag",
                    tint: .purple
                )
            }
        } header: {
            EmptyView()
        } footer: {
            EmptyView()
        }
    }

    private var managementPresetsSection: some View {
        Section {
            NavigationLink {
                ManagePresetsView(workspace: workspace)
            } label: {
                SettingsRow(
                    title: "Manage Presets",
                    systemImage: "list.bullet.rectangle",
                    tint: .orange
                )
            }
        } header: {
            EmptyView()
        } footer: {
            EmptyView()
        }
    }

    // MARK: - Toolbar Workspace Item (Single Source of Truth)

    // MARK: - Toolbar Workspace Item (Single Source of Truth)

    @ViewBuilder
    private var workspaceTrailingNavBarItem: some View {
        let baseMenu = Menu {
            workspaceSwitcherMenuContent

            Button {
                showingWorkspaceManager = true
            } label: {
                Label("Manage Workspaces", systemImage: "person.fill")
            }
        } label: {
            WorkspaceToolbarMenuLabel(
                tint: selectedWorkspaceColor,
                systemImage: "person.fill"
            )
        }
        .accessibilityLabel("Workspaces")
        .accessibilityHint("Switch workspaces or manage them")
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
        if !workspaces.isEmpty {
            Section("Switch Workspace") {
                ForEach(workspaces) { ws in
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

    private func workspaceMenuRow(for ws: Workspace) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: ws.hexColor) ?? .secondary)
                .frame(width: 10, height: 10)

            Text(ws.name)

            Spacer()

            if selectedWorkspaceID == ws.id.uuidString {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
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
