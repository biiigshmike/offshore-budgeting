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

    var body: some View {
        List {
            Section("Workspaces") {
                if workspaces.isEmpty {
                    ContentUnavailableView(
                        "No Workspaces Yet",
                        systemImage: "person.3",
                        description: Text("Create a workspace to begin.")
                    )
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
