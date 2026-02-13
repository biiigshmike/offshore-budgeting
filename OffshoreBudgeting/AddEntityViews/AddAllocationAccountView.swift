import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

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
            Section("Shared Balance") {
                TextField("Name", text: $name)
                ColorPicker("Color", selection: $color, supportsOpacity: false)
            }
        }
        .navigationTitle("New Shared Balance")
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
        guard !trimmedName.isEmpty else { return }

        let account = AllocationAccount(
            name: trimmedName,
            hexColor: hexString(from: color),
            workspace: workspace
        )

        modelContext.insert(account)
        dismiss()
    }

    private func hexString(from color: Color) -> String {
        #if canImport(UIKit)
        let ui = UIColor(color)

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else {
            return "#3B82F6"
        }

        return String(
            format: "#%02X%02X%02X",
            Int(round(r * 255)),
            Int(round(g * 255)),
            Int(round(b * 255))
        )
        #elseif canImport(AppKit)
        let ns = NSColor(color)
        let rgb = ns.usingColorSpace(.deviceRGB) ?? ns

        return String(
            format: "#%02X%02X%02X",
            Int(round(rgb.redComponent * 255)),
            Int(round(rgb.greenComponent * 255)),
            Int(round(rgb.blueComponent * 255))
        )
        #else
        return "#3B82F6"
        #endif
    }
}
