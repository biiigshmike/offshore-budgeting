import SwiftUI
import SwiftData

struct EditAllocationAccountView: View {

    @Bindable var account: AllocationAccount

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var color: Color

    init(account: AllocationAccount) {
        self.account = account
        _name = State(initialValue: account.name)
        _color = State(initialValue: Color(hex: account.hexColor) ?? .blue)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !trimmedName.isEmpty
    }

    // MARK: - Body

    var body: some View {
        Form {
            Section("Reconciliation") {
                TextField("Name", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
        }
        .navigationTitle("Edit Reconciliation")
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

    // MARK: - Actions

    private func save() {
        guard !trimmedName.isEmpty else { return }
        account.name = trimmedName
        account.hexColor = color.hexRGBString()
        dismiss()
    }
}
