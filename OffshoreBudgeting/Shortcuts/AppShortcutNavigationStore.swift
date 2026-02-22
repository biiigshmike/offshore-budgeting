import Foundation

// MARK: - AppShortcutNavigationStore

enum AppShortcutNavigationStore {
    static let pendingSectionKey = "shortcuts_pendingSection"
    static let pendingActionKey = "shortcuts_pendingAction"
    static let pendingExpenseDescriptionKey = "shortcuts_pendingExpenseDescription"

    enum PendingAction: String {
        case openQuickAddIncome = "open_quick_add_income"
        case openQuickAddExpense = "open_quick_add_expense"
        case openQuickAddExpenseFromShoppingMode = "open_quick_add_expense_from_shopping_mode"
    }
}
