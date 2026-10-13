import Foundation
import Testing
@testable import Offshore

@MainActor
struct ExcursionRetirementServiceTests {
    @Test func clearsLegacyStateWithoutTouchingUnrelatedDefaults() {
        let suite = "ExcursionRetirementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for key in ExcursionRetirementService.defaultsKeys { defaults.set("legacy", forKey: key) }
        defaults.set("open_quick_add_expense_from_shopping_mode", forKey: AppShortcutNavigationStore.pendingActionKey)
        defaults.set("Old merchant", forKey: AppShortcutNavigationStore.pendingExpenseDescriptionKey)
        defaults.set(true, forKey: "notifications_enabled")
        defaults.set("workspace", forKey: "selectedWorkspaceID")
        ExcursionRetirementService.clearDefaults(in: defaults)
        ExcursionRetirementService.clearDefaults(in: defaults)
        for key in ExcursionRetirementService.defaultsKeys { #expect(defaults.object(forKey: key) == nil) }
        #expect(defaults.object(forKey: AppShortcutNavigationStore.pendingActionKey) == nil)
        #expect(defaults.object(forKey: AppShortcutNavigationStore.pendingExpenseDescriptionKey) == nil)
        #expect(defaults.bool(forKey: "notifications_enabled"))
        #expect(defaults.string(forKey: "selectedWorkspaceID") == "workspace")
    }

    @Test func preservesOrdinaryQuickAddNavigation() {
        let suite = "ExcursionRetirementTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(AppShortcutNavigationStore.PendingAction.openQuickAddExpense.rawValue, forKey: AppShortcutNavigationStore.pendingActionKey)
        defaults.set("Lunch", forKey: AppShortcutNavigationStore.pendingExpenseDescriptionKey)
        ExcursionRetirementService.clearDefaults(in: defaults)
        #expect(defaults.string(forKey: AppShortcutNavigationStore.pendingActionKey) == AppShortcutNavigationStore.PendingAction.openQuickAddExpense.rawValue)
        #expect(defaults.string(forKey: AppShortcutNavigationStore.pendingExpenseDescriptionKey) == "Lunch")
    }

    @Test func selectsOnlyLegacySystemResources() {
        #expect(ExcursionRetirementService.isLegacyRegion("shopping_mode.merchant"))
        #expect(!ExcursionRetirementService.isLegacyRegion("another_feature.region"))
        #expect(ExcursionRetirementService.isLegacyNotification("shopping_mode_suggestion_123"))
        #expect(!ExcursionRetirementService.isLegacyNotification("planned_income_reminder_123"))
    }
}
