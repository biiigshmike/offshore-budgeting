import Foundation
import Testing
@testable import Offshore

struct CategoryArchiveBehaviorTests {
    @Test func importCategoryMatching_ignoresArchivedLearnedCategory() {
        let archivedCategory = Category(
            name: "Groceries",
            hexColor: "#00AA00",
            isArchived: true,
            archivedAt: Date()
        )
        let activeCategory = Category(name: "Dining", hexColor: "#FFAA00")
        let learnedRule = ImportMerchantRule(
            merchantKey: MerchantNormalizer.normalizeKey("Whole Foods"),
            preferredName: "Whole Foods",
            preferredCategory: archivedCategory
        )

        let suggestion = CategoryMatchingEngine.suggest(
            csvCategory: nil,
            merchant: "Whole Foods",
            availableCategories: [activeCategory],
            learnedRule: learnedRule
        )

        #expect(suggestion.category == nil)
    }
}
