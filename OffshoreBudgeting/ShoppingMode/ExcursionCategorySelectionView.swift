import SwiftUI

struct ExcursionCategorySelectionView: View {
    @ObservedObject var store: ExcursionPreferencesStore
    @State private var searchText = ""

    private var filteredCategories: [ExcursionPOICategoryCatalog.Category] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExcursionPOICategoryCatalog.categories.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
        }
    }

    var body: some View {
        List {
            Section {
                Button("Select All") {
                    var next = store.value
                    next.categoryIDs.formUnion(ExcursionPOICategoryCatalog.supportedIDs)
                    store.update(next)
                }
                .accessibilityIdentifier("excursionSelectAllCategories")
                ForEach(filteredCategories) { category in
                    categoryButton(category)
                }
            } footer: {
                Text("Keep at least one category selected, or include uncategorized places. Categories are provided by Apple Maps and may vary with your OS version.")
            }
        }
        .navigationTitle("All Categories")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search Categories")
        .overlay {
            if filteredCategories.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
    }

    private func categoryButton(_ category: ExcursionPOICategoryCatalog.Category) -> some View {
        let selected = store.value.categoryIDs.contains(category.id)
        return Button {
            var next = store.value
            if next.toggleCategories([category.id]) { store.update(next) }
        } label: {
            HStack {
                Text(category.name)
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .accessibilityHidden(true)
            }
        }
        .disabled(selected && store.value.selectedSupportedCategoryIDs.count == 1 && !store.value.includeUncategorized)
        .accessibilityValue(selected ? String(localized: "Selected") : String(localized: "Not selected"))
        .accessibilityIdentifier("excursionCategory_\(category.id)")
    }
}
