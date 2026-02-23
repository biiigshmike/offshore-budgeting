import SwiftUI
import SwiftData

struct AddAllocationAccountView: View {

    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var color: Color = .blue

    private var canSave: Bool {
        !trimmedName.isEmpty
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section("Reconciliation") {
                TextField("Name", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
        }
        .navigationTitle("New Reconciliation")
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
            if trimmedName.isEmpty {
                name = DebugScreenshotFormDefaults.accountName
            }
        }
    }

    private func save() {
        guard !trimmedName.isEmpty else { return }

        let account = AllocationAccount(
            name: trimmedName,
            hexColor: color.hexRGBString(),
            workspace: workspace
        )

        modelContext.insert(account)
        dismiss()
    }
}
