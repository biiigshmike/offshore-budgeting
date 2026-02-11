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
                "Enable spending session in \(.applicationName)",
                "Start spending mode in \(.applicationName)"
            ],
            shortTitle: "Spending Session",
            systemImageName: "timer"
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
            intent: ImportFromClipboardIntent(),
            phrases: [
                "Import from clipboard in \(.applicationName)",
                "Parse clipboard transactions in \(.applicationName)"
            ],
            shortTitle: "Import Clipboard",
            systemImageName: "doc.on.clipboard"
        )
        AppShortcut(
            intent: ImportScreenshotIntent(),
            phrases: [
                "Import screenshot in \(.applicationName)",
                "Parse screenshot transactions in \(.applicationName)"
            ],
            shortTitle: "Import Screenshot",
            systemImageName: "photo.on.rectangle"
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
