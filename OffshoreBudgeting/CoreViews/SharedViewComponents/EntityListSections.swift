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
    let discoveryPhase: ICloudBootstrap.WorkspaceDiscoveryPhase
    let showsSelectionHint: Bool
    let onSelect: (Workspace) -> Void
    let onEdit: (Workspace) -> Void
    let onDelete: (Workspace) -> Void

    var body: some View {
        if workspaces.isEmpty {
            switch discoveryPhase {
            case .loading:
                iCloudLoadingState(
                    title: "Setting Up iCloud Sync",
                    description: "Looking for existing workspaces on this Apple ID."
                )

            case .loadingSlow:
                iCloudLoadingState(
                    title: "Still Checking iCloud",
                    description: "This can take a moment..."
                )

            case .loaded(hasWorkspaces: false):
                ContentUnavailableView(
                    usesICloud ? "No iCloud Workspaces Found" : "No Workspaces Yet",
                    systemImage: usesICloud ? "icloud.slash" : "person.fill",
                    description: Text(usesICloud ? "Nothing was found in iCloud. Create a workspace to begin." : "Create a workspace to begin.")
                )
                .frame(maxWidth: .infinity, alignment: .center)

            case .loaded(hasWorkspaces: true):
                EmptyView()
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

    private func iCloudLoadingState(title: String, description: String) -> some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                title,
                systemImage: "icloud.and.arrow.down",
                description: Text(description)
            )

            ProgressView()
                .padding(.bottom, 6)
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .center)
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

struct CategoryListRows<Destination: View>: View {

    let categories: [Category]
    let onEdit: (Category) -> Void
    let onArchive: ((Category) -> Void)?
    let onUnarchive: ((Category) -> Void)?
    let onDelete: (Category) -> Void
    private let destination: ((Category) -> Destination)?

    init(
        categories: [Category],
        onEdit: @escaping (Category) -> Void,
        onArchive: ((Category) -> Void)? = nil,
        onUnarchive: ((Category) -> Void)? = nil,
        onDelete: @escaping (Category) -> Void
    ) where Destination == EmptyView {
        self.categories = categories
        self.onEdit = onEdit
        self.onArchive = onArchive
        self.onUnarchive = onUnarchive
        self.onDelete = onDelete
        self.destination = nil
    }

    init(
        categories: [Category],
        onEdit: @escaping (Category) -> Void,
        onArchive: ((Category) -> Void)? = nil,
        onUnarchive: ((Category) -> Void)? = nil,
        onDelete: @escaping (Category) -> Void,
        @ViewBuilder destination: @escaping (Category) -> Destination
    ) {
        self.categories = categories
        self.onEdit = onEdit
        self.onArchive = onArchive
        self.onUnarchive = onUnarchive
        self.onDelete = onDelete
        self.destination = destination
    }

    var body: some View {
        if categories.isEmpty {
            ContentUnavailableView(
                "No Categories Yet",
                systemImage: "tag",
                description: Text("Create categories to organize expenses and presets.")
            )
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            ForEach(categories) { category in
                Group {
                    if let destination {
                        NavigationLink {
                            destination(category)
                        } label: {
                            categoryLabel(category)
                        }
                        .accessibilityIdentifier("categories.row.\(category.id.uuidString)")
                    } else {
                        categoryLabel(category)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        onDelete(category)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(Color("OffshoreDepth"))
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if let onUnarchive {
                        Button {
                            onUnarchive(category)
                        } label: {
                            Label("Unarchive", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }

                    Button {
                        onEdit(category)
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(Color("AccentColor"))

                    if let onArchive {
                        Button {
                            onArchive(category)
                        } label: {
                            Label("Archive", systemImage: "archivebox")
                        }
                        .tint(Color("OffshoreSand"))
                    }
                }
            }
        }
    }

    private func categoryLabel(_ category: Category) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color(hex: category.hexColor) ?? .secondary)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(category.name)
        }
        .frame(minHeight: 32)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
