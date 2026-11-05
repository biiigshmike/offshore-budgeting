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
                Button("Select All") {
                    var next = store.value
                    next.categoryIDs.formUnion(ExcursionPOICategoryCatalog.supportedIDs)
                    store.update(next)
                }
                .accessibilityIdentifier("excursionSelectAll")
                ForEach(ExcursionPOICategoryCatalog.groups) { group in
                    categoryGroupButton(group)
                }
                NavigationLink {
                    ExcursionCategorySelectionView(store: store)
                } label: {
                    LabeledContent {
                        Text("\(store.value.selectedSupportedCategoryIDs.count) selected")
                    } label: {
                        Text("All Categories")
                    }
                }
                .accessibilityIdentifier("excursionAllCategories")
                Toggle("Include uncategorized places", isOn: $includeUncategorized)
                    .disabled(store.value.selectedSupportedCategoryIDs.isEmpty)
                    .accessibilityIdentifier("excursionIncludeUncategorized")
            } header: {
                Text("Places to Include")
            } footer: {
                Text("Select All selects every category. Include uncategorized places also allows places without a recognized Apple Maps category. A dash means part of a group is selected.")
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

    private func categoryGroupButton(_ group: ExcursionPOICategoryCatalog.Group) -> some View {
        let selected = store.value.categoryIDs.intersection(group.categoryIDs).count
        let symbol = selected == group.categoryIDs.count ? "checkmark.circle.fill" : (selected == 0 ? "circle" : "minus.circle.fill")
        let removingLastSelection = selected == group.categoryIDs.count
            && store.value.selectedSupportedCategoryIDs.subtracting(group.categoryIDs).isEmpty
            && !store.value.includeUncategorized
        return Button {
            var next = store.value
            if next.toggleCategories(group.categoryIDs) { store.update(next) }
        } label: {
            HStack {
                Text(group.name)
                Spacer()
                Image(systemName: symbol).accessibilityHidden(true)
            }
        }
        .disabled(removingLastSelection)
        .accessibilityValue(selected == group.categoryIDs.count ? String(localized: "Selected")
                            : (selected == 0 ? String(localized: "Not selected") : String(localized: "Partially selected")))
        .accessibilityIdentifier("excursionGroup_\(group.id)")
    }
}
