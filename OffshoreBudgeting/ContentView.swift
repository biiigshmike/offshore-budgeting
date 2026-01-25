//
//  ContentView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {

    // MARK: - Selection

    @AppStorage("selectedWorkspaceID") private var selectedWorkspaceID: String = ""
    @AppStorage("didSeedDefaultWorkspaces") private var didSeedDefaultWorkspaces: Bool = false
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    // MARK: - Privacy

    @AppStorage("privacy_requireBiometrics") private var requireBiometrics: Bool = false

    // MARK: - Alerts

    @State private var showingCannotDeleteLastWorkspaceAlert: Bool = false
    @State private var showingWorkspaceDeleteConfirm: Bool = false
    @State private var pendingWorkspaceDelete: (() -> Void)? = nil

    // MARK: - SwiftData

    @Query(sort: \Workspace.name, order: .forward)
    private var workspaces: [Workspace]

    @Environment(\.modelContext) private var modelContext

    // MARK: - Body

    var body: some View {
        AppLockGate(isEnabled: $requireBiometrics) {
            Group {
                if let selected = selectedWorkspace {
                    AppRootView(
                        workspace: selected,
                        selectedWorkspaceID: $selectedWorkspaceID
                    )
                } else {
                    WorkspacePickerView(
                        workspaces: workspaces,
                        selectedWorkspaceID: $selectedWorkspaceID,
                        onCreate: createWorkspace(name:hexColor:),
                        onDelete: deleteWorkspaces
                    )
                }
            }
            .task {
                seedDefaultWorkspacesIfNeeded()
            }
            .alert("You must keep at least one workspace.", isPresented: $showingCannotDeleteLastWorkspaceAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Create another workspace first, then you can delete this one.")
            }
            .alert("Delete?", isPresented: $showingWorkspaceDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    pendingWorkspaceDelete?()
                    pendingWorkspaceDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingWorkspaceDelete = nil
                }
            }
        }
    }

    // MARK: - Derived

    private var selectedWorkspace: Workspace? {
        guard let uuid = UUID(uuidString: selectedWorkspaceID) else { return nil }
        return workspaces.first(where: { $0.id == uuid })
    }

    // MARK: - Seeding

    private func seedDefaultWorkspacesIfNeeded() {
        if !workspaces.isEmpty {
            didSeedDefaultWorkspaces = true

            if selectedWorkspace == nil {
                selectedWorkspaceID = workspaces.first?.id.uuidString ?? ""
            }
            return
        }

        // Store is empty. Seed defaults.
        if didSeedDefaultWorkspaces == false || workspaces.isEmpty {
            let personal = Workspace(name: "Personal", hexColor: "#3B82F6")
            let work = Workspace(name: "Work", hexColor: "#10B981")

            modelContext.insert(personal)
            modelContext.insert(work)

            selectedWorkspaceID = personal.id.uuidString
            didSeedDefaultWorkspaces = true
        }
    }

    // MARK: - Actions

    private func createWorkspace(name: String, hexColor: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHex = hexColor.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { return }

        let workspace = Workspace(
            name: trimmedName,
            hexColor: trimmedHex.isEmpty ? "#3B82F6" : trimmedHex
        )

        modelContext.insert(workspace)
        selectedWorkspaceID = workspace.id.uuidString
    }

    private func deleteWorkspaces(at offsets: IndexSet) {
        // Enforce: must keep at least 1 workspace
        let remainingIndices = workspaces.indices.filter { !offsets.contains($0) }
        guard !remainingIndices.isEmpty else {
            showingCannotDeleteLastWorkspaceAlert = true
            return
        }

        let workspacesToDelete = offsets.compactMap { index in
            workspaces.indices.contains(index) ? workspaces[index] : nil
        }

        // If the selected workspace is being deleted, choose a safe fallback.
        let deletedIDs = workspacesToDelete.map { $0.id.uuidString }
        let willDeleteSelected = deletedIDs.contains(selectedWorkspaceID)
        let fallbackSelectedID = workspaces[remainingIndices[0]].id.uuidString

        if confirmBeforeDeleting {
            pendingWorkspaceDelete = {
                for workspace in workspacesToDelete {
                    modelContext.delete(workspace)
                }

                // Apply fallback selection after delete if needed.
                if willDeleteSelected {
                    selectedWorkspaceID = fallbackSelectedID
                }
            }
            showingWorkspaceDeleteConfirm = true
        } else {
            for workspace in workspacesToDelete {
                modelContext.delete(workspace)
            }

            // Apply fallback selection after delete if needed.
            if willDeleteSelected {
                selectedWorkspaceID = fallbackSelectedID
            }
        }
    }
}
