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
        AppShortcut(
            intent: EnableSpendingSessionIntent(),
            phrases: [
                "Start excursion mode in \(.applicationName)",
                "Enable excursion mode in \(.applicationName)",
                "Start shopping mode in \(.applicationName)",
                "Enable shopping mode in \(.applicationName)",
                "Enable spending session in \(.applicationName)",
                "Start spending mode in \(.applicationName)"
            ],
            shortTitle: "Excursion Mode",
            systemImageName: "cart.badge.plus"
        )
        AppShortcut(
            intent: ReviewTodaysSpendingIntent(),
            phrases: [
                "Review today's spending in \(.applicationName)",
                "Check today's spending in \(.applicationName)"
            ],
            shortTitle: "Review Today",
            systemImageName: "list.bullet.clipboard"
        )
        AppShortcut(
            intent: WhatCanISpendTodayIntent(),
            phrases: [
                "What can I spend today in \(.applicationName)",
                "Check safe spending in \(.applicationName)"
            ],
            shortTitle: "Safe Spend Today",
            systemImageName: "dollarsign.circle"
        )
        AppShortcut(
            intent: ForecastSavingsIntent(),
            phrases: [
                "Forecast savings in \(.applicationName)",
                "Check projected savings in \(.applicationName)"
            ],
            shortTitle: "Forecast Savings",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
    }
}
