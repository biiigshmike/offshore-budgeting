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

    private enum SheetRoute: Identifiable {
        case add
        case edit(Category)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let category):
                return "edit-\(category.id.uuidString)"
            }
        }
    }

    @State private var sheetRoute: SheetRoute? = nil
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
            CategoryListRows(
                categories: categories,
                onEdit: { category in
                    sheetRoute = .edit(category)
                },
                onDelete: { category in
                    if confirmBeforeDeleting {
                        pendingCategoryDelete = {
                            delete(category)
                        }
                        showingCategoryDeleteConfirm = true
                    } else {
                        delete(category)
                    }
                }
            )
        }
        .postBoardingTip(
            key: "tip.categories.v1",
            title: "Categories Management",
            items: [
                PostBoardingTipItem(
                    systemImage: "tag",
                    title: "Categories",
                    detail: "Add categories to track and visualize spending. Swipe a row to the right to edit; swipe left to delete."
                )
            ]
        )
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sheetRoute = .add
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .add:
                NavigationStack {
                    AddCategoryView(workspace: workspace)
                }
            case .edit(let category):
                NavigationStack {
                    EditCategoryView(workspace: workspace, category: category)
                }
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
