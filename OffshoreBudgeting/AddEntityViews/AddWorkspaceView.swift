//
//  AddWorkspaceView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI

struct AddWorkspaceView: View {

    let onCreate: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var color: Color = WorkspaceFormView.color(fromHex: "#3B82F6")

    private var trimmedName: String {
        WorkspaceFormView.trimmedName(name)
    }

    private var canSave: Bool {
        WorkspaceFormView.canSave(name: name)
    }

    var body: some View {
        WorkspaceFormView(name: $name, color: $color)
            .navigationTitle("Add Workspace")
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
                if WorkspaceFormView.trimmedName(name).isEmpty {
                    name = DebugScreenshotFormDefaults.workspaceName
                }
            }
    }

    private func save() {
        guard persistWorkspace() else { return }
        dismiss()
    }

    private func saveAndAdd() {
        guard persistWorkspace() else { return }
        resetForm()
    }

    @discardableResult
    private func persistWorkspace() -> Bool {
        guard !trimmedName.isEmpty else { return false }
        let hex = WorkspaceFormView.hexString(from: color)
        onCreate(trimmedName, hex)
        return true
    }

    private func resetForm() {
        name = ""
        color = WorkspaceFormView.color(fromHex: "#3B82F6")

        guard DebugScreenshotFormDefaults.isEnabled else { return }
        name = DebugScreenshotFormDefaults.workspaceName
    }
}
