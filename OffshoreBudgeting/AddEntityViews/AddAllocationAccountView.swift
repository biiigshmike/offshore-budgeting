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
            if trimmedName.isEmpty {
                name = DebugScreenshotFormDefaults.accountName
            }
        }
    }

    private func save() {
        guard persistAccount() else { return }
        dismiss()
    }

    private func saveAndAdd() {
        guard persistAccount() else { return }
        resetForm()
    }

    @discardableResult
    private func persistAccount() -> Bool {
        guard !trimmedName.isEmpty else { return false }

        let account = AllocationAccount(
            name: trimmedName,
            hexColor: color.hexRGBString(),
            workspace: workspace
        )

        modelContext.insert(account)
        return true
    }

    private func resetForm() {
        name = ""
        color = .blue

        guard DebugScreenshotFormDefaults.isEnabled else { return }
        name = DebugScreenshotFormDefaults.accountName
    }
}
