import SwiftUI

struct ExcursionCategorySelectionView: View {
    @ObservedObject var store: ExcursionPreferencesStore
    @State private var searchText = ""
    @State private var editMode: EditMode = .inactive
    @State private var draftCategoryIDs: Set<String> = []

    private var isEditing: Bool { editMode.isEditing }

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
        List(selection: isEditing ? $draftCategoryIDs : nil) {
            Section {
                ForEach(filteredCategories) { category in
                    if isEditing {
                        Text(category.name)
                            .tag(category.id)
                            .accessibilityValue(draftCategoryIDs.contains(category.id)
                                                ? String(localized: "Selected") : String(localized: "Not selected"))
                            .accessibilityIdentifier("excursionCategory_\(category.id)")
                    } else {
                        HStack {
                            Text(category.name)
                            Spacer()
                            if store.value.categoryIDs.contains(category.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .foregroundStyle(.primary)
                        .accessibilityElement(children: .combine)
                        .accessibilityValue(store.value.categoryIDs.contains(category.id)
                                            ? String(localized: "Selected") : String(localized: "Not selected"))
                        .accessibilityIdentifier("excursionCategory_\(category.id)")
                    }
                }
            } footer: {
                Text("Keep at least one category selected, or include uncategorized places. Categories are provided by Apple Maps and may vary with your OS version.")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .offshoreAccentTint()
        .navigationTitle("Categories")
        .navigationBarBackButtonHidden(isEditing)
        .toolbar(isEditing ? .hidden : .visible, for: .tabBar)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        draftCategoryIDs = []
                        editMode = .inactive
                    }
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
                        if store.update(next) { editMode = .inactive }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(!canSave)
                    .glassProminentButtonStyleCompat()
                    .offshoreAccentTint()
                    .accessibilityIdentifier("excursionSaveCategories")
                } else {
                    Button("Edit") {
                        draftCategoryIDs = store.value.categoryIDs
                        editMode = .active
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
