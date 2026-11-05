import Foundation
import MapKit
import Testing
@testable import Offshore

@MainActor
struct ExcursionPreferencesTests {
    @Test func defaultsAreCommonSpendingGroupsAndFortyFiveSeconds() {
        let preferences = ExcursionPreferences.default
        #expect(preferences.mode == .custom)
        #expect(preferences.dwellSeconds == 45)
        #expect(preferences.categoryIDs == ExcursionPOICategoryCatalog.recommendedIDs)
        #expect(preferences.categoryIDs.count == 12)
        #expect(preferences.allows(categoryID: MKPointOfInterestCategory.restaurant.rawValue))
        #expect(!preferences.allows(categoryID: MKPointOfInterestCategory.school.rawValue))
        #expect(!preferences.allows(categoryID: nil))
    }

    @Test func groupsAndIndividualCategoriesShareSelection() throws {
        let food = try #require(ExcursionPOICategoryCatalog.groups.first { $0.id == "food-drink" })
        var preferences = ExcursionPreferences.default
        let removedRestaurant = preferences.toggleCategories([MKPointOfInterestCategory.restaurant.rawValue])
        #expect(removedRestaurant)
        #expect(preferences.categoryIDs.intersection(food.categoryIDs).count == food.categoryIDs.count - 1)
        let selectedFoodGroup = preferences.toggleCategories(food.categoryIDs)
        #expect(selectedFoodGroup)
        #expect(food.categoryIDs.isSubset(of: preferences.categoryIDs))
        let removedFoodGroup = preferences.toggleCategories(food.categoryIDs)
        #expect(removedFoodGroup)
        #expect(preferences.categoryIDs.isDisjoint(with: food.categoryIDs))
    }

    @Test func customCannotLoseLastSupportedSelectionAndUnknownDoesNotCount() {
        let restaurant = MKPointOfInterestCategory.restaurant.rawValue
        var preferences = ExcursionPreferences(mode: .custom, categoryIDs: [restaurant, "future.category"], dwellSeconds: 45)
        let removedLastCategory = preferences.toggleCategories([restaurant])
        #expect(!removedLastCategory)
        #expect(preferences.allows(categoryID: restaurant))
        #expect(!preferences.allows(categoryID: "future.category"))
        preferences.setMode(.all)
        #expect(preferences.allows(categoryID: nil))
        #expect(preferences.allows(categoryID: "future.category"))
        preferences.setMode(.custom)
        #expect(preferences.categoryIDs.contains("future.category"))
    }

    @Test func persistenceRestoreAndInvalidDataFallback() throws {
        let suite = "ExcursionPreferencesTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExcursionPreferencesStore(defaults: defaults)
        #expect(store.value == .default)
        let chosen = ExcursionPreferences(mode: .custom, categoryIDs: [MKPointOfInterestCategory.pharmacy.rawValue, "future.category"], dwellSeconds: 120)
        #expect(store.update(chosen))
        #expect(ExcursionPreferencesStore(defaults: defaults).value == chosen)
        #expect(!store.update(ExcursionPreferences(mode: .custom, categoryIDs: [], dwellSeconds: 45)))
        #expect(store.value == chosen)
        store.restoreDefaults()
        #expect(ExcursionPreferencesStore(defaults: defaults).value == .default)

        for invalid in [
            ExcursionPreferences(mode: .custom, categoryIDs: ["future.only"], dwellSeconds: 45),
            ExcursionPreferences(mode: .all, categoryIDs: [], dwellSeconds: 10)
        ] {
            defaults.set(try JSONEncoder().encode(invalid), forKey: ExcursionPreferencesStore.storageKey)
            #expect(ExcursionPreferencesStore(defaults: defaults).value == .default)
        }
        defaults.set(Data("not JSON".utf8), forKey: ExcursionPreferencesStore.storageKey)
        #expect(ExcursionPreferencesStore(defaults: defaults).value == .default)
    }

    @Test func allModeAndEachDwellOptionPersist() {
        let suite = "ExcursionPreferencesTests.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ExcursionPreferencesStore(defaults: defaults)
        for seconds in ExcursionPreferences.dwellOptions {
            let value = ExcursionPreferences(mode: .all, categoryIDs: [], dwellSeconds: seconds)
            #expect(store.update(value))
            #expect(ExcursionPreferencesStore(defaults: defaults).value == value)
        }
    }

    @Test func catalogueHasUniqueLocalizedNamesAndRuntimeCategories() {
        let categories = ExcursionPOICategoryCatalog.categories
        #expect(categories.count == Set(categories.map(\.id)).count)
        #expect(categories.allSatisfy { !$0.name.isEmpty && !$0.id.isEmpty })
        #expect(ExcursionPOICategoryCatalog.recommendedIDs.isSubset(of: ExcursionPOICategoryCatalog.supportedIDs))
        #expect(ExcursionPOICategoryCatalog.supportedIDs.contains(MKPointOfInterestCategory.animalService.rawValue))
        #expect(ExcursionPOICategoryCatalog.supportedIDs.contains(MKPointOfInterestCategory.school.rawValue))
        if #available(iOS 27.0, macCatalyst 27.0, macOS 27.0, *) {
            #expect(ExcursionPOICategoryCatalog.supportedIDs.contains(MKPointOfInterestCategory.airportTerminal.rawValue))
            #expect(categories.count == 84)
        } else {
            #expect(categories.count == 73)
        }
    }
    @Test func legacyAllPlacesMigratesToAllCategoriesAndUncategorized() throws {
        let data = Data(#"{"mode":"all","categoryIDs":[],"dwellSeconds":60}"#.utf8)
        let value = try JSONDecoder().decode(ExcursionPreferences.self, from: data)
        #expect(value.selectedSupportedCategoryIDs == ExcursionPOICategoryCatalog.supportedIDs)
        #expect(value.includeUncategorized)
        #expect(value.dwellSeconds == 60)
        #expect(try JSONDecoder().decode(ExcursionPreferences.self, from: JSONEncoder().encode(value)) == value)
    }

    @Test func uncategorizedDoesNotAdmitExcludedKnownCategories() {
        var value = ExcursionPreferences(mode: .custom,
            categoryIDs: [MKPointOfInterestCategory.restaurant.rawValue], dwellSeconds: 45,
            includeUncategorized: true)
        #expect(value.allows(categoryID: nil))
        #expect(value.allows(categoryID: MKPointOfInterestCategory.restaurant.rawValue))
        #expect(!value.allows(categoryID: MKPointOfInterestCategory.gasStation.rawValue))
        value.categoryIDs.formUnion(ExcursionPOICategoryCatalog.supportedIDs)
        value.includeUncategorized = false
        #expect(!value.allows(categoryID: nil))
        #expect(value.allows(categoryID: MKPointOfInterestCategory.gasStation.rawValue))
    }

}
