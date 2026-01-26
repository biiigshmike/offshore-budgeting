//
//  WorkspacePickerView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct WorkspacePickerView: View {

    let workspaces: [Workspace]
    @Binding var selectedWorkspaceID: String

    let onCreate: (String, String) -> Void
    let onDelete: (IndexSet) -> Void

    @State private var showingAddWorkspace: Bool = false
    @State private var editingWorkspace: Workspace? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage("icloud_useCloud") private var useICloud: Bool = false
    @AppStorage("icloud_bootstrapStartedAt") private var iCloudBootstrapStartedAt: Double = 0
    @AppStorage("app_rootResetToken") private var rootResetToken: String = UUID().uuidString
    @AppStorage("profiles_activeLocalID") private var activeLocalProfileID: String = ""

    @State private var localProfiles: [LocalProfile] = []
    @State private var newProfileName: String = ""
    @State private var renameProfileID: String = ""
    @State private var renameProfileName: String = ""
    @State private var pendingDeleteProfileID: String = ""

    @State private var showingNewProfilePrompt: Bool = false
    @State private var showingRenameProfilePrompt: Bool = false
    @State private var showingDeleteProfileConfirm: Bool = false
    @State private var showingICloudUnavailable: Bool = false
    @State private var showingICloudSwitchConfirm: Bool = false

    var body: some View {
        List {
            profilesSection

            Section("Workspaces") {
                if workspaces.isEmpty {
                    if ICloudBootstrap.isBootstrapping(useICloud: useICloud, startedAt: iCloudBootstrapStartedAt) {
                        VStack(spacing: 12) {
                            ContentUnavailableView(
                                "Setting Up iCloud Sync",
                                systemImage: "icloud.and.arrow.down",
                                description: Text("Looking for existing workspaces on this Apple ID.")
                            )

                            ProgressView()
                                .padding(.bottom, 6)
                        }
                        .padding(.vertical, 10)
                    } else {
                        ContentUnavailableView(
                            "No Workspaces Yet",
                            systemImage: "person.3",
                            description: Text("Create a workspace to begin.")
                        )
                    }
                } else {
                    ForEach(workspaces) { workspace in
                        Button {
                            selectedWorkspaceID = workspace.id.uuidString
                        } label: {
                            row(workspace)
                        }
                        .buttonStyle(.plain)

                        // Swipe right (leading) -> Edit
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingWorkspace = workspace
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }

                        // Swipe left (trailing) -> Delete
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                delete(workspace)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Workspaces")
        .task {
            LocalProfilesStore.ensureDefaultProfileExists()
            refreshProfiles()
        }
        .onChange(of: workspaces.count) { _, newCount in
            if useICloud, newCount > 0 {
                iCloudBootstrapStartedAt = 0
            }
        }
        .alert("New Profile", isPresented: $showingNewProfilePrompt) {
            TextField("Name", text: $newProfileName)
            Button("Create") { createProfileAndSwitch() }
            Button("Cancel", role: .cancel) { newProfileName = "" }
        } message: {
            Text("Create a separate on-device profile with its own workspaces and budgets.")
        }
        .alert("Rename Profile", isPresented: $showingRenameProfilePrompt) {
            TextField("Name", text: $renameProfileName)
            Button("Save") { renameProfile() }
            Button("Cancel", role: .cancel) { renameProfileID = ""; renameProfileName = "" }
        }
        .alert("Delete Profile?", isPresented: $showingDeleteProfileConfirm) {
            Button("Delete", role: .destructive) { deleteProfile() }
            Button("Cancel", role: .cancel) { pendingDeleteProfileID = "" }
        } message: {
            Text("This will delete the on-device data for this profile. This cannot be undone.")
        }
        .alert("iCloud Unavailable", isPresented: $showingICloudUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To use iCloud sync, sign in to iCloud in the Settings app, then try again.")
        }
        .alert("Switch to iCloud?", isPresented: $showingICloudSwitchConfirm) {
            Button("Switch", role: .destructive) { switchToICloud() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your current on-device profile will remain available. iCloud data may take a moment to restore.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .accessibilityLabel("Close")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddWorkspace = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddWorkspace) {
            NavigationStack {
                AddWorkspaceView(onCreate: onCreate)
            }
        }
        .sheet(item: $editingWorkspace) { workspace in
            NavigationStack {
                EditWorkspaceView(workspace: workspace)
            }
        }
    }

    // MARK: - Actions

    private func delete(_ workspace: Workspace) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        onDelete(IndexSet(integer: index))
    }

    // MARK: - Row

    @ViewBuilder
    private func row(_ workspace: Workspace) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: workspace.hexColor) ?? .secondary)
                .frame(width: 14, height: 14)

            Text(workspace.name)

            Spacer()

            if selectedWorkspaceID == workspace.id.uuidString {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Profiles

extension WorkspacePickerView {

    private var profilesSection: some View {
        Section("Profiles") {
            Button {
                handleICloudRowTapped()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "icloud")
                        .foregroundStyle(.blue)

                    Text("iCloud")

                    Spacer()

                    if useICloud {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(localProfiles) { profile in
                Button {
                    switchToLocal(profileID: profile.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "iphone")
                            .foregroundStyle(.secondary)

                        Text(profile.name)

                        Spacer()

                        if !useICloud, activeLocalProfileID == profile.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if profile.id != "default" {
                        Button {
                            renameProfileID = profile.id
                            renameProfileName = profile.name
                            showingRenameProfilePrompt = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if profile.id != "default" {
                        Button(role: .destructive) {
                            pendingDeleteProfileID = profile.id
                            showingDeleteProfileConfirm = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }

            Button {
                newProfileName = ""
                showingNewProfilePrompt = true
            } label: {
                Label("New On-Device Profile", systemImage: "plus")
            }
        }
    }

    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func refreshProfiles() {
        localProfiles = LocalProfilesStore.loadProfiles()
        if activeLocalProfileID.isEmpty {
            activeLocalProfileID = LocalProfilesStore.activeProfileID()
        }
    }

    private func handleICloudRowTapped() {
        guard isICloudAvailable else {
            showingICloudUnavailable = true
            return
        }

        guard !useICloud else { return }

        if !workspaces.isEmpty {
            showingICloudSwitchConfirm = true
        } else {
            switchToICloud()
        }
    }

    private func switchToICloud() {
        useICloud = true
        iCloudBootstrapStartedAt = Date().timeIntervalSince1970
        selectedWorkspaceID = ""
        dismiss()
        let newToken = UUID().uuidString
        DispatchQueue.main.async {
            rootResetToken = newToken
        }
    }

    private func switchToLocal(profileID: String) {
        guard !(useICloud == false && activeLocalProfileID == profileID) else { return }

        useICloud = false
        iCloudBootstrapStartedAt = 0
        activeLocalProfileID = profileID
        LocalProfilesStore.setActiveProfileID(profileID)
        selectedWorkspaceID = ""
        dismiss()
        let newToken = UUID().uuidString
        DispatchQueue.main.async {
            rootResetToken = newToken
        }
    }

    private func createProfileAndSwitch() {
        let profile = LocalProfilesStore.makeNewProfile(name: newProfileName)
        refreshProfiles()
        switchToLocal(profileID: profile.id)
        newProfileName = ""
    }

    private func renameProfile() {
        let id = renameProfileID
        guard !id.isEmpty else { return }
        LocalProfilesStore.renameProfile(id: id, newName: renameProfileName)
        renameProfileID = ""
        renameProfileName = ""
        refreshProfiles()
    }

    private func deleteProfile() {
        let id = pendingDeleteProfileID
        guard !id.isEmpty else { return }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        LocalProfilesStore.deleteLocalStoreFileIfPresent(applicationSupportDirectory: appSupport, profileID: id)
        LocalProfilesStore.deleteProfile(id: id)
        pendingDeleteProfileID = ""
        refreshProfiles()

        if !useICloud, activeLocalProfileID == id {
            switchToLocal(profileID: LocalProfilesStore.activeProfileID())
        }
    }
}

#Preview("Workspace Picker") {
    let container = PreviewSeed.makeContainer()

    NavigationStack {
        WorkspacePickerView(
            workspaces: [
                Workspace(name: "Personal", hexColor: "#3B82F6"),
                Workspace(name: "Work", hexColor: "#10B981")
            ],
            selectedWorkspaceID: .constant(""),
            onCreate: { _, _ in },
            onDelete: { _ in }
        )
    }
    .modelContainer(container)
}
