import SwiftUI

struct ExcursionCategorySelectionView: View {
    @ObservedObject var store: ExcursionPreferencesStore
    @State private var searchText = ""
    @State private var isEditing = false
    @State private var draftCategoryIDs: Set<String> = []

    private var categorySelection: Binding<Set<String>> {
        Binding {
            isEditing ? draftCategoryIDs : store.value.categoryIDs
        } set: { ids in
            guard isEditing else { return }
            draftCategoryIDs = ids
        }
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
        List(selection: categorySelection) {
            Section {
                ForEach(filteredCategories) { category in
                    Text(category.name)
                        .tag(category.id)
                        .disabled(!isEditing)
                        .accessibilityValue(categorySelection.wrappedValue.contains(category.id)
                                            ? String(localized: "Selected") : String(localized: "Not selected"))
                        .accessibilityIdentifier("excursionCategory_\(category.id)")
                }
            } footer: {
                Text("Keep at least one category selected, or include uncategorized places. Categories are provided by Apple Maps and may vary with your OS version.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
        .offshoreAccentTint()
        .navigationTitle("Categories")
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
                    .offshoreAccentTint()
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

}
