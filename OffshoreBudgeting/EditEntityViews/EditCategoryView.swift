//
//  EditCategoryView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct EditCategoryView: View {

    let workspace: Workspace
    let category: Category

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var color: Color

    init(workspace: Workspace, category: Category) {
        self.workspace = workspace
        self.category = category

        _name = State(initialValue: category.name)
        _color = State(initialValue: CategoryFormView.color(fromHex: category.hexColor))
    }

    private var trimmedName: String {
        CategoryFormView.trimmedName(name)
    }

    private var canSave: Bool {
        CategoryFormView.canSave(name: name)
    }

    var body: some View {
        CategoryFormView(name: $name, color: $color)
            .navigationTitle("Edit Category")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                            .tint(.accentColor)
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                            .tint(.accentColor)
                            .controlSize(.large)
                            .buttonStyle(.plain)
                    }
                }
            }
            .onAppear {
                guard DebugScreenshotFormDefaults.isEnabled else { return }
                if CategoryFormView.trimmedName(name).isEmpty {
                    name = DebugScreenshotFormDefaults.categoryName
                }
            }
    }

    private func save() {
        category.name = trimmedName
        category.hexColor = CategoryFormView.hexString(from: color)
        dismiss()
    }
}

#Preview("Edit Category") {
    let container = PreviewSeed.makeContainer()
    let context = container.mainContext

    // Seed expected data
    _ = PreviewSeed.seedBasicData(in: context)

    // Fetch a workspace + category from the seeded data
    let workspaceDescriptor = FetchDescriptor<Workspace>()
    let categoryDescriptor = FetchDescriptor<Category>()

    let ws = (try? context.fetch(workspaceDescriptor).first)
    let cat = (try? context.fetch(categoryDescriptor).first)

    return NavigationStack {
        if let ws, let cat {
            EditCategoryView(workspace: ws, category: cat)
        } else {
            ContentUnavailableView(
                "Missing Preview Data",
                systemImage: "tag",
                description: Text("PreviewSeed did not create a Workspace + Category.")
            )
        }
    }
    .modelContainer(container)
}
