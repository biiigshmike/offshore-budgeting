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
        let hex = WorkspaceFormView.hexString(from: color)
        onCreate(trimmedName, hex)
        dismiss()
    }
}
