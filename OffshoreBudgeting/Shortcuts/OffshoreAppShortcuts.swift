import AppIntents

// MARK: - OffshoreAppShortcuts

struct OffshoreAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AddExpenseIntent(),
            phrases: [
                "Add expense in \(.applicationName)",
                "Log expense in \(.applicationName)"
            ],
            shortTitle: "Add Expense",
            systemImageName: "creditcard"
        )
        AppShortcut(
            intent: AddIncomeIntent(),
            phrases: [
                "Add income in \(.applicationName)",
                "Log income in \(.applicationName)"
            ],
            shortTitle: "Add Income",
            systemImageName: "banknote"
        )
    }
}
