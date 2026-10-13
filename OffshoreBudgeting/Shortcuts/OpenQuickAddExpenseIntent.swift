import AppIntents
import Foundation

// MARK: - OpenQuickAddExpenseIntent

struct OpenQuickAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Open Offshore to the expense entry form in your selected workspace.")
    static var isDiscoverable: Bool = false
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
        await MainActor.run {
            UserDefaults.standard.set(
                AppSection.cards.rawValue,
                forKey: AppShortcutNavigationStore.pendingSectionKey
            )
            UserDefaults.standard.set(
                AppShortcutNavigationStore.PendingAction.openQuickAddExpense.rawValue,
                forKey: AppShortcutNavigationStore.pendingActionKey
            )
        }

        return .result(
            opensIntent: OpenOffshoreForImportIntent(),
            dialog: IntentDialog(stringLiteral: "Opening Offshore quick add.")
        )
    }
}
