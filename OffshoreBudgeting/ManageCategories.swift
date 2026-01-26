//
//  ManageCategoriesView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct ManageCategoriesView: View {

    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Query private var categories: [Category]

    @State private var showingAddSheet: Bool = false
    @State private var editingCategory: Category? = nil
    @State private var showingCategoryDeleteConfirm: Bool = false
    @State private var pendingCategoryDelete: (() -> Void)? = nil

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )
    }

    var body: some View {
        List {
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
                            if confirmBeforeDeleting {
                                pendingCategoryDelete = {
                                    delete(category)
                                }
                                showingCategoryDeleteConfirm = true
                            } else {
                                delete(category)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button {
                            editingCategory = category
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NavigationStack {
                AddCategoryView(workspace: workspace)
            }
        }
        .sheet(item: $editingCategory) { category in
            NavigationStack {
                EditCategoryView(workspace: workspace, category: category)
            }
        }
        .alert("Delete?", isPresented: $showingCategoryDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingCategoryDelete?()
                pendingCategoryDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCategoryDelete = nil
            }
        }
    }

    private func delete(_ category: Category) {
        modelContext.delete(category)
    }
}

#Preview("Manage Categories") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            ManageCategoriesView(workspace: ws)
        }
    }
}
