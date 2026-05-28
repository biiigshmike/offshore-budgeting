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
    @Environment(\.appCommandHub) private var commandHub

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("sort.categories.mode") private var sortModeRaw: String = CategorySortMode.az.rawValue

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
            if activeCategories.isEmpty && archivedCategories.isEmpty {
                ContentUnavailableView(
                    "No Categories Yet",
                    systemImage: "tag",
                    description: Text("Create categories to organize expenses and presets.")
                )
            } else {
                if activeCategories.isEmpty == false {
                    Section {
                        CategoryListRows(
                            categories: activeCategories,
                            onEdit: { category in
                                sheetRoute = .edit(category)
                            },
                            onArchive: { category in
                                archive(category)
                            },
                            onDelete: { category in
                                deleteCategoryWithOptionalConfirm(category)
                            }
                        )
                    }
                }

                if archivedCategories.isEmpty == false {
                    Section("Archived") {
                        CategoryListRows(
                            categories: archivedCategories,
                            onEdit: { category in
                                sheetRoute = .edit(category)
                            },
                            onUnarchive: { category in
                                unarchive(category)
                            },
                            onDelete: { category in
                                deleteCategoryWithOptionalConfirm(category)
                            }
                        )
                    }
                }
            }
        }
        .postBoardingTip(
            key: "tip.categories.v1",
            title: "Categories Management",
            items: [
                PostBoardingTipItem(
                    systemImage: "tag",
                    title: "Categories",
                    detail: "Add categories to track and visualize spending. Swipe a row to the right to edit or archive; swipe left to delete."
                )
            ]
        )
        .navigationTitle("Categories")
        .toolbar {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    sortToolbarButton
                }

                ToolbarSpacer(.flexible, placement: .primaryAction)

                ToolbarItemGroup(placement: .primaryAction) {
                    addToolbarButton
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    addToolbarButton
                }

                ToolbarItem(placement: .primaryAction) {
                    sortToolbarButton
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
        .onAppear {
            commandHub.activate(.categories)
        }
        .onDisappear {
            commandHub.deactivate(.categories)
        }
        .onReceive(commandHub.$sequence) { _ in
            guard commandHub.surface == .categories else { return }
            handleCommand(commandHub.latestCommandID)
        }
    }

    private var sortMode: CategorySortMode {
        CategorySortMode(rawValue: sortModeRaw) ?? .az
    }

    private func setSortMode(_ mode: CategorySortMode) {
        sortModeRaw = mode.rawValue
    }

    private var activeCategories: [Category] {
        sortedCategories(categories.filter { $0.isArchived == false })
    }

    private var archivedCategories: [Category] {
        sortedCategories(categories.filter { $0.isArchived })
    }

    private func sortedCategories(_ source: [Category]) -> [Category] {
        switch sortMode {
        case .az:
            return source.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .za:
            return source.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            }
        }
    }

    @ViewBuilder
    private var addToolbarButton: some View {
        Button {
            sheetRoute = .add
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add Category")
    }

    @ViewBuilder
    private var sortToolbarButton: some View {
        Menu {
            sortMenuButton(title: "A–Z", mode: .az)
            sortMenuButton(title: "Z–A", mode: .za)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
    }

    private func sortMenuButton(title: String, mode: CategorySortMode) -> some View {
        Button {
            setSortMode(mode)
        } label: {
            HStack {
                Text(title)
                if sortMode == mode {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func handleCommand(_ commandID: String) {
        switch commandID {
        case AppCommandID.Categories.sortAZ:
            setSortMode(.az)
        case AppCommandID.Categories.sortZA:
            setSortMode(.za)
        default:
            break
        }
    }

    private func delete(_ category: Category) {
        modelContext.delete(category)
    }

    private func deleteCategoryWithOptionalConfirm(_ category: Category) {
        if confirmBeforeDeleting {
            pendingCategoryDelete = {
                delete(category)
            }
            showingCategoryDeleteConfirm = true
        } else {
            delete(category)
        }
    }

    private func archive(_ category: Category) {
        category.isArchived = true
        category.archivedAt = Date()
    }

    private func unarchive(_ category: Category) {
        category.isArchived = false
        category.archivedAt = nil
    }
}

private enum CategorySortMode: String {
    case az
    case za
}

#Preview("Manage Categories") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            ManageCategoriesView(workspace: ws)
        }
    }
}
