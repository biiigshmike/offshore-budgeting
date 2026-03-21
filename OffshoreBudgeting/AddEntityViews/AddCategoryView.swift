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
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Cancel")
                }

                if #available(iOS 26.0, macCatalyst 26.0, *) {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { saveAndAdd() } label: {
                            Image(systemName: "checkmark.arrow.trianglehead.clockwise")
                        }
                        .accessibilityLabel("Save & Add")
                            .disabled(!canSave)
                            .tint(.accentColor)
                            .buttonStyle(.plain)
                    }

                    ToolbarSpacer(.flexible, placement: .primaryAction)

                    ToolbarItemGroup(placement: .primaryAction) {
                        Button { save() } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Save")
                            .disabled(!canSave)
                            .tint(.accentColor)
                            .buttonStyle(.glassProminent)
                    }
                } else {
                    ToolbarItem(placement: .primaryAction) {
                        Button { saveAndAdd() } label: {
                            Image(systemName: "checkmark.arrow.trianglehead.clockwise")
                        }
                        .accessibilityLabel("Save & Add")
                            .disabled(!canSave)
                            .tint(.accentColor)
                            .controlSize(.large)
                            .buttonStyle(.plain)
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button { save() } label: {
                            Image(systemName: "checkmark")
                        }
                        .accessibilityLabel("Save")
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
        guard persistCategory() else { return }
        dismiss()
    }

    private func saveAndAdd() {
        guard persistCategory() else { return }
        resetForm()
    }

    @discardableResult
    private func persistCategory() -> Bool {
        guard !trimmedName.isEmpty else { return false }
        let hex = CategoryFormView.hexString(from: color)

        let category = Category(
            name: trimmedName,
            hexColor: hex,
            workspace: workspace
        )

        modelContext.insert(category)
        return true
    }

    private func resetForm() {
        name = ""
        color = CategoryFormView.color(fromHex: "#3B82F6")

        guard DebugScreenshotFormDefaults.isEnabled else { return }
        name = DebugScreenshotFormDefaults.categoryName
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
