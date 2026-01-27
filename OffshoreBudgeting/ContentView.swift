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

    // MARK: - Onboarding

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false

    // MARK: - Privacy

    @AppStorage("privacy_requireBiometrics") private var requireBiometrics: Bool = false

    // MARK: - iCloud

    @AppStorage("icloud_activeUseCloud") private var activeUseICloud: Bool = false
    @AppStorage("icloud_bootstrapStartedAt") private var iCloudBootstrapStartedAt: Double = 0

    // MARK: - Alerts

    @State private var showingCannotDeleteLastWorkspaceAlert: Bool = false

    // MARK: - SwiftData

    @Query(sort: \Workspace.name, order: .forward)
    private var workspaces: [Workspace]

    @Environment(\.modelContext) private var modelContext

    // MARK: - Body

    var body: some View {
        AppLockGate(isEnabled: .constant(didCompleteOnboarding && requireBiometrics)) {
            Group {
                if didCompleteOnboarding == false {
                    OnboardingView()
                } else if let selected = selectedWorkspace {
                    AppRootView(
                        workspace: selected,
                        selectedWorkspaceID: $selectedWorkspaceID
                    )
                } else {
                    NavigationStack {
                        WorkspacePickerView(
                            workspaces: workspaces,
                            selectedWorkspaceID: $selectedWorkspaceID,
                            showsCloseButton: false,
                            onCreate: createWorkspace(name:hexColor:),
                            onDelete: deleteWorkspaces
                        )
                    }
                }
            }
            .task {
                let isBootstrapping = ICloudBootstrap.isBootstrapping(
                    useICloud: activeUseICloud,
                    startedAt: iCloudBootstrapStartedAt
                )

                // If onboarding is complete, we can safely seed defaults only when empty.
                // If onboarding is NOT complete, do not seed anything.
                if didCompleteOnboarding {
                    if !isBootstrapping {
                        if !activeUseICloud {
                            seedDefaultWorkspacesIfNeeded()
                        }
                    }
                } else {
                    // Keep state clean for true first-run.
                    didSeedDefaultWorkspaces = false
                    if workspaces.isEmpty {
                        selectedWorkspaceID = ""
                    }
                }

                // If the user previously completed onboarding, then enabled iCloud and the
                // store comes back empty, re-run onboarding instead of dumping them into
                // a picker with nothing configured.
                if didCompleteOnboarding, !activeUseICloud, workspaces.isEmpty, !isBootstrapping {
                    didCompleteOnboarding = false
                    didSeedDefaultWorkspaces = false
                    selectedWorkspaceID = ""
                }
            }
            .onAppear {
                IncomeWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                refreshIncomeWidgetSnapshotsIfPossible()
            }
            .onChange(of: selectedWorkspaceID) { _, newValue in
                IncomeWidgetSnapshotStore.setSelectedWorkspaceID(newValue)
                refreshIncomeWidgetSnapshotsIfPossible()
            }
            .onChange(of: workspaces.count) { _, newCount in
                if activeUseICloud, newCount > 0 {
                    iCloudBootstrapStartedAt = 0
                }

                if didCompleteOnboarding, newCount > 0, selectedWorkspace == nil {
                    selectedWorkspaceID = workspaces.first?.id.uuidString ?? ""
                }
            }
            .alert("You must keep at least one workspace.", isPresented: $showingCannotDeleteLastWorkspaceAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Create another workspace first, then you can delete this one.")
            }
        }
    }
    
    private func refreshIncomeWidgetSnapshotsIfPossible() {
        guard let id = UUID(uuidString: selectedWorkspaceID) else { return }
        IncomeWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: modelContext,
            workspaceID: id
        )
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

        for workspace in workspacesToDelete {
            modelContext.delete(workspace)
        }

        // Apply fallback selection after delete if needed.
        if willDeleteSelected {
            selectedWorkspaceID = fallbackSelectedID
        }
    }
}
