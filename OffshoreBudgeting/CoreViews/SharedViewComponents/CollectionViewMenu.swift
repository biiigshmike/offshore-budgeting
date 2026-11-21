import SwiftUI

struct CollectionViewMenu: View {
    @Binding var selection: CollectionViewMode

    var body: some View {
        Menu {
            Picker("View", selection: $selection) {
                ForEach(CollectionViewMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .tag(mode)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("View", systemImage: selection.systemImage)
        }
        .accessibilityLabel(Text("View, \(selection.title)"))
        .accessibilityIdentifier("collection.viewMenu")
        #if targetEnvironment(macCatalyst) || os(macOS)
        // Rebuild the native Mac menu so its Picker checkmark follows the binding.
        .id(selection)
        #endif
    }
}
