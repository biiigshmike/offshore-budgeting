import Foundation

enum CategoryArchivePolicy {
    static func activeCategories(from categories: [Category]) -> [Category] {
        categories.filter { $0.isArchived == false }
    }

    static func selectableCategories(from categories: [Category], selectedCategoryID: UUID?) -> [Category] {
        categories.filter { category in
            category.isArchived == false || category.id == selectedCategoryID
        }
    }
}
