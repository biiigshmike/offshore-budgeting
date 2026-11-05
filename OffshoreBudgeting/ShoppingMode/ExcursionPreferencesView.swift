import SwiftUI

struct ExcursionPreferencesView: View {
    @ObservedObject private var store: ExcursionPreferencesStore
    @State private var includeUncategorized: Bool
    @State private var dwellSeconds: Int

    init(store: ExcursionPreferencesStore? = nil) {
        let store = store ?? .shared
        self.store = store
        _includeUncategorized = State(initialValue: store.value.includeUncategorized)
        _dwellSeconds = State(initialValue: store.value.dwellSeconds)
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ExcursionCategorySelectionView(store: store)
                } label: {
                    LabeledContent {
                        Text("\(store.value.selectedSupportedCategoryIDs.count) selected")
                    } label: {
                        Text("Categories")
                    }
                }
                .accessibilityIdentifier("excursionAllCategories")
                Toggle("Include uncategorized places", isOn: $includeUncategorized)
                    .offshoreAccentTint()
                    .disabled(store.value.selectedSupportedCategoryIDs.isEmpty)
                    .accessibilityIdentifier("excursionIncludeUncategorized")
            } header: {
                Text("Places to Include")
            } footer: {
                Text("Use Edit in Categories to select or deselect all categories. Include uncategorized places also allows places without a recognized Apple Maps category.")
            }

            Section {
                Picker("Remind After", selection: $dwellSeconds) {
                    Text("45 seconds").tag(45)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                }
                .accessibilityIdentifier("excursionDwellTime")
            } header: {
                Text("Reminder Timing")
            } footer: {
                Text("The default is about 45 seconds nearby. Short pauses may trigger a reminder. Location accuracy and background delivery can make reminders take longer.")
            }

            Section {
                Button("Restore Defaults") { store.restoreDefaults() }
                    .accessibilityIdentifier("excursionRestoreDefaults")
            } footer: {
                Text("Preferences apply immediately to Excursion Mode on this device, across all workspaces.")
            }
        }
        .offshoreAccentTint()
        .navigationTitle("Excursion Preferences")
        .onChange(of: includeUncategorized) { _, value in
            var next = store.value
            next.includeUncategorized = value
            store.update(next)
        }
        .onChange(of: dwellSeconds) { _, value in
            var next = store.value
            next.dwellSeconds = value
            store.update(next)
        }
        .onChange(of: store.value) { _, value in
            includeUncategorized = value.includeUncategorized
            dwellSeconds = value.dwellSeconds
        }
    }

}
