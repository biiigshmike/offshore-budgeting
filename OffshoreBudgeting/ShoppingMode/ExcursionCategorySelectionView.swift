import SwiftUI

struct ExcursionCategorySelectionView: View {
    @ObservedObject var store: ExcursionPreferencesStore
    @State private var searchText = ""
    @State private var isEditing = false
    @State private var draftCategoryIDs: Set<String> = []

    private var selectedIDs: Set<String> {
        isEditing ? draftCategoryIDs : store.value.categoryIDs
    }

    private var canSave: Bool {
        store.value.includeUncategorized || !draftCategoryIDs.isDisjoint(with: ExcursionPOICategoryCatalog.supportedIDs)
    }

    private var filteredCategories: [ExcursionPOICategoryCatalog.Category] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExcursionPOICategoryCatalog.categories.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(filteredCategories) { category in
                    categoryButton(category)
                }
            } footer: {
                Text("Keep at least one category selected, or include uncategorized places. Categories are provided by Apple Maps and may vary with your OS version.")
            }
        }
        .navigationTitle("All Categories")
        .navigationBarBackButtonHidden(isEditing)
        .toolbar(isEditing ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isEditing = false }
                        .accessibilityIdentifier("excursionCancelCategories")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Select All") {
                        draftCategoryIDs.formUnion(ExcursionPOICategoryCatalog.supportedIDs)
                    }
                    .accessibilityIdentifier("excursionSelectAllCategories")
                    Spacer()
                    Button("Deselect All") { draftCategoryIDs.removeAll() }
                        .accessibilityIdentifier("excursionDeselectAllCategories")
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if isEditing {
                    Button("Done", systemImage: "checkmark") {
                        var next = store.value
                        next.categoryIDs = draftCategoryIDs
                        if store.update(next) { isEditing = false }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!canSave)
                    .glassProminentButtonStyleCompat()
                    .offshoreAccentTint()
                    .accessibilityIdentifier("excursionSaveCategories")
                } else {
                    Button("Edit") {
                        draftCategoryIDs = store.value.categoryIDs
                        isEditing = true
                    }
                    .tint(.primary)
                    .accessibilityIdentifier("excursionEditCategories")
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Categories")
        .overlay {
            if filteredCategories.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func categoryButton(_ category: ExcursionPOICategoryCatalog.Category) -> some View {
        let selected = selectedIDs.contains(category.id)
        return Button {
            if isEditing {
                if selected { draftCategoryIDs.remove(category.id) }
                else { draftCategoryIDs.insert(category.id) }
            } else {
                var next = store.value
                if next.toggleCategories([category.id]) { store.update(next) }
            }
        } label: {
            HStack {
                Text(category.name)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
            }
        }
        .disabled(!isEditing && selected && store.value.selectedSupportedCategoryIDs.count == 1 && !store.value.includeUncategorized)
        .accessibilityValue(selected ? String(localized: "Selected") : String(localized: "Not selected"))
        .accessibilityIdentifier("excursionCategory_\(category.id)")
    }
}
