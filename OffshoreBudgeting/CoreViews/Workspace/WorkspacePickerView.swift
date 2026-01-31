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
    let showsCloseButton: Bool

    let onCreate: (String, String) -> Void
    let onDelete: (IndexSet) -> Void

    private enum SheetRoute: Identifiable {
        case restartRequired
        case addWorkspace
        case editWorkspace(Workspace)

        var id: String {
            switch self {
            case .restartRequired:
                return "restartRequired"
            case .addWorkspace:
                return "addWorkspace"
            case .editWorkspace(let workspace):
                return "editWorkspace-\(workspace.id.uuidString)"
            }
        }
    }

    @State private var sheetRoute: SheetRoute? = nil

    @Environment(\.dismiss) private var dismiss
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("icloud_useCloud") private var desiredUseICloud: Bool = false
    @AppStorage("icloud_activeUseCloud") private var activeUseICloud: Bool = false
    @AppStorage("icloud_bootstrapStartedAt") private var iCloudBootstrapStartedAt: Double = 0

    @State private var showingICloudUnavailable: Bool = false
    @State private var showingWorkspaceDeleteConfirm: Bool = false
    @State private var pendingWorkspaceDeleteName: String = ""
    @State private var pendingWorkspaceDeleteOffsets: IndexSet? = nil

    var body: some View {
        List {
            dataSourceSection

            Section("Workspaces") {
                if workspaces.isEmpty {
                    if ICloudBootstrap.isBootstrapping(useICloud: activeUseICloud, startedAt: iCloudBootstrapStartedAt) {
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
                            systemImage: "person.fill",
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
                                sheetRoute = .editWorkspace(workspace)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color("AccentColor"))
                        }

                        // Swipe left (trailing) -> Delete
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                requestDelete(workspace)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(Color("OffshoreDepth"))
                        }
                    }
                }
            }
        }
        .navigationTitle("Workspaces")
        .onChange(of: workspaces.count) { _, newCount in
            if activeUseICloud, newCount > 0 {
                iCloudBootstrapStartedAt = 0
            }
        }
        .alert("iCloud Unavailable", isPresented: $showingICloudUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To use iCloud sync, sign in to iCloud in the Settings app, then try again.")
        }
        .alert("Delete Workspace?", isPresented: $showingWorkspaceDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let offsets = pendingWorkspaceDeleteOffsets {
                    onDelete(offsets)
                }
                pendingWorkspaceDeleteOffsets = nil
                pendingWorkspaceDeleteName = ""
            }
            Button("Cancel", role: .cancel) {
                pendingWorkspaceDeleteOffsets = nil
                pendingWorkspaceDeleteName = ""
            }
        } message: {
            if pendingWorkspaceDeleteName.isEmpty {
                Text("This workspace will be deleted.")
            } else {
                Text("“\(pendingWorkspaceDeleteName)” will be deleted.")
            }
        }
        .toolbar {
            if showsCloseButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheetRoute = .addWorkspace
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .restartRequired:
                RestartRequiredView(
                    title: "Restart Required",
                    message: AppRestartService.restartRequiredMessage(
                        debugMessage: "Switching between On Device and iCloud takes effect after you close and reopen Offshore."
                    ),
                    primaryButtonTitle: AppRestartService.closeAppButtonTitle,
                    onPrimary: { AppRestartService.closeAppOrDismiss { sheetRoute = nil } }
                )
                .presentationDetents([.medium])

            case .addWorkspace:
                NavigationStack {
                    AddWorkspaceView(onCreate: onCreate)
                }

            case .editWorkspace(let workspace):
                NavigationStack {
                    EditWorkspaceView(workspace: workspace)
                }
            }
        }
    }

    // MARK: - Actions

    private func requestDelete(_ workspace: Workspace) {
        guard let index = workspaces.firstIndex(where: { $0.id == workspace.id }) else { return }
        let offsets = IndexSet(integer: index)

        if confirmBeforeDeleting {
            pendingWorkspaceDeleteName = workspace.name
            pendingWorkspaceDeleteOffsets = offsets
            showingWorkspaceDeleteConfirm = true
        } else {
            onDelete(offsets)
        }
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
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Data Source

extension WorkspacePickerView {

    private var dataSourceSection: some View {
        Section("Data Source") {
            Button {
                handleOnDeviceRowTapped()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "iphone")
                        .foregroundStyle(.secondary)
                    Text("On Device")
                    Spacer()
                    dataSourceTrailingIcon(isActive: !activeUseICloud, isDesired: !desiredUseICloud)
                }
            }

            Button {
                handleICloudRowTapped()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "icloud")
                        .foregroundStyle(.tint)
                    Text("iCloud")
                    Spacer()
                    dataSourceTrailingIcon(isActive: activeUseICloud, isDesired: desiredUseICloud)
                }
            }
        }
    }

    @ViewBuilder
    private func dataSourceTrailingIcon(isActive: Bool, isDesired: Bool) -> some View {
        if isActive {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.tint)
        } else if isDesired != isActive {
            Image(systemName: "arrow.clockwise.circle")
                .foregroundStyle(.tint)
                .accessibilityLabel("Restart required")
        }
    }

    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private func handleICloudRowTapped() {
        guard isICloudAvailable else {
            showingICloudUnavailable = true
            return
        }

        guard !activeUseICloud else { return }
        requestSwitchToICloud()
    }

    private func handleOnDeviceRowTapped() {
        guard activeUseICloud else { return }
        requestSwitchToOnDevice()
    }

    private func requestSwitchToICloud() {
        desiredUseICloud = true
        if desiredUseICloud != activeUseICloud {
            sheetRoute = .restartRequired
        }
    }

    private func requestSwitchToOnDevice() {
        desiredUseICloud = false
        if desiredUseICloud != activeUseICloud {
            sheetRoute = .restartRequired
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
            showsCloseButton: true,
            onCreate: { _, _ in },
            onDelete: { _ in }
        )
    }
    .modelContainer(container)
}
