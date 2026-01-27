//
//  AddCategoryView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct AddCategoryView: View {

    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var color: Color = CategoryFormView.color(fromHex: "#3B82F6")

    private var trimmedName: String {
        CategoryFormView.trimmedName(name)
    }

    private var canSave: Bool {
        CategoryFormView.canSave(name: name)
    }

    var body: some View {
        CategoryFormView(name: $name, color: $color)
            .navigationTitle("Add Category")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                if #available(iOS 26.0, *) {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { save() }
                            .disabled(!canSave)
                            .tint(.accentColor)
                            .controlSize(.large)
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
    }

    private func save() {
        let hex = CategoryFormView.hexString(from: color)

        let category = Category(
            name: trimmedName,
            hexColor: hex,
            workspace: workspace
        )

        modelContext.insert(category)
        dismiss()
    }
}

#Preview("Add Category") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            AddCategoryView(workspace: ws)
        }
    }
}
