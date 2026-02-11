import Foundation

// MARK: - AppShortcutNavigationStore

enum AppShortcutNavigationStore {
    static let pendingSectionKey = "shortcuts_pendingSection"
    static let pendingActionKey = "shortcuts_pendingAction"
    static let pendingImportClipboardTextKey = "shortcuts_pendingImportClipboardText"
    static let pendingImportCardIDKey = "shortcuts_pendingImportCardID"

    enum PendingAction: String {
        case openIncomeImportReview = "open_income_import_review"
        case openCardImportReview = "open_card_import_review"
        case openQuickAddIncome = "open_quick_add_income"
        case openQuickAddExpense = "open_quick_add_expense"
    }
}
