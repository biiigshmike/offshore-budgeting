//
//  EditWorkspaceView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/24/26.
//

import SwiftUI
import SwiftData

struct EditWorkspaceView: View {

    let workspace: Workspace

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var color: Color

    init(workspace: Workspace) {
        self.workspace = workspace
        _name = State(initialValue: workspace.name)
        _color = State(initialValue: WorkspaceFormView.color(fromHex: workspace.hexColor))
    }

    private var trimmedName: String {
        WorkspaceFormView.trimmedName(name)
    }

    private var canSave: Bool {
        WorkspaceFormView.canSave(name: name)
    }

    var body: some View {
        WorkspaceFormView(name: $name, color: $color)
            .navigationTitle("Edit Workspace")
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
                if WorkspaceFormView.trimmedName(name).isEmpty {
                    name = DebugScreenshotFormDefaults.workspaceName
                }
            }
    }

    private func save() {
        workspace.name = trimmedName
        workspace.hexColor = WorkspaceFormView.hexString(from: color)
        dismiss()
    }
}
