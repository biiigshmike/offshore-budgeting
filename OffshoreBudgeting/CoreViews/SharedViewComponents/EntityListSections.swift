//
//  EntityListSections.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/13/26.
//

import SwiftUI

// MARK: - Workspace Rows

struct WorkspaceListRows: View {

    let workspaces: [Workspace]
    let selectedWorkspaceID: String
    let usesICloud: Bool
    let isICloudBootstrapping: Bool
    let showsSelectionHint: Bool
    let onSelect: (Workspace) -> Void
    let onEdit: (Workspace) -> Void
    let onDelete: (Workspace) -> Void

    var body: some View {
        if workspaces.isEmpty {
            if isICloudBootstrapping {
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
                    usesICloud ? "No iCloud Workspaces Found" : "No Workspaces Yet",
                    systemImage: usesICloud ? "icloud.slash" : "person.fill",
                    description: Text(usesICloud ? "Nothing was found in iCloud. Create a workspace to begin." : "Create a workspace to begin.")
                )
            }
        } else {
            ForEach(workspaces) { workspace in
                Button {
                    onSelect(workspace)
                } label: {
                    row(workspace)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        onEdit(workspace)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(Color("AccentColor"))
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDelete(workspace)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(Color("OffshoreDepth"))
                }
            }

            if showsSelectionHint {
                Text("Choose a Workspace to switch contexts.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

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

// MARK: - Category Rows

struct CategoryListRows: View {

    let categories: [Category]
    let onEdit: (Category) -> Void
    let onDelete: (Category) -> Void

    var body: some View {
        if categories.isEmpty {
            ContentUnavailableView(
                "No Categories Yet",
                systemImage: "tag",
                description: Text("Create categories to organize transactions and presets.")
            )
        } else {
            ForEach(categories) { category in
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color(hex: category.hexColor) ?? .secondary)
                        .frame(width: 10, height: 10)

                    Text(category.name)
                }
                .padding(.vertical, 6)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDelete(category)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(Color("OffshoreDepth"))
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button {
                        onEdit(category)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(Color("AccentColor"))
                }
            }
        }
    }
}
