import Foundation

// MARK: - OffshoreDeepLink

enum OffshoreDeepLink {
    static let scheme = "offshore"

    static let openAddExpenseURL = URL(string: "offshore://open/add-expense")!
    static let openAddIncomeURL = URL(string: "offshore://open/add-income")!
    static let openReviewTodayURL = URL(string: "offshore://open/review-today")!
    static let openSafeSpendTodayURL = URL(string: "offshore://open/safe-spend-today")!
    static let openForecastSavingsURL = URL(string: "offshore://open/forecast-savings")!

    static func startExcursionModeURL(hours: Int = 2) -> URL {
        URL(string: "offshore://action/excursion-mode/start?hours=\(hours)")!
    }
}

// MARK: - OffshoreDeepLinkHandler

@MainActor
enum OffshoreDeepLinkHandler {
    @discardableResult
    static func handle(_ url: URL) -> Bool {
        if ShoppingModeManager.shared.handleDeepLink(url) {
            return true
        }

        guard url.scheme == OffshoreDeepLink.scheme else { return false }

        let path: String
        if url.host == "open" || url.host == "action" {
            path = url.path
        } else {
            path = url.host.map { "/\($0)\(url.path)" } ?? url.path
        }

        switch (url.host, path) {
        case ("open", "/add-expense"):
            UserDefaults.standard.set(AppSection.cards.rawValue, forKey: AppShortcutNavigationStore.pendingSectionKey)
            UserDefaults.standard.set(
                AppShortcutNavigationStore.PendingAction.openQuickAddExpense.rawValue,
                forKey: AppShortcutNavigationStore.pendingActionKey
            )
            return true

        case ("open", "/add-income"):
            UserDefaults.standard.set(AppSection.income.rawValue, forKey: AppShortcutNavigationStore.pendingSectionKey)
            UserDefaults.standard.set(
                AppShortcutNavigationStore.PendingAction.openQuickAddIncome.rawValue,
                forKey: AppShortcutNavigationStore.pendingActionKey
            )
            return true

        case ("open", "/review-today"):
            UserDefaults.standard.set(AppSection.cards.rawValue, forKey: AppShortcutNavigationStore.pendingSectionKey)
            return true

        case ("open", "/safe-spend-today"):
            UserDefaults.standard.set(AppSection.home.rawValue, forKey: AppShortcutNavigationStore.pendingSectionKey)
            return true

        case ("open", "/forecast-savings"):
            UserDefaults.standard.set(AppSection.home.rawValue, forKey: AppShortcutNavigationStore.pendingSectionKey)
            return true

        case ("action", "/excursion-mode/start"):
            let requestedHours = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "hours" })?
                .value
                .flatMap(Int.init) ?? 2

            let hours = min(max(1, requestedHours), 4)
            Task {
                _ = await ShoppingModeManager.shared.start(hours: hours)
            }
            return true

        default:
            return false
        }
    }
}
