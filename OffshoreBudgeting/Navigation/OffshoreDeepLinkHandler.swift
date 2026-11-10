import Foundation
import Observation

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

enum QuickLinkSheet: String, Identifiable {
    case expense
    case income
    case reviewToday

    var id: String { rawValue }
}

@MainActor
@Observable
final class OffshoreControlPresentation {
    static let shared = OffshoreControlPresentation()

    var pendingSheet: QuickLinkSheet?
    var pendingExcursionBlockers: [ShoppingModeStartBlocker]?

    private init() {}
}

// MARK: - OffshoreDeepLinkHandler

@MainActor
enum OffshoreDeepLinkHandler {
    static func handleControl(_ destination: OffshoreControlDestination) async {
        switch destination {
        case .addExpense:
            handle(OffshoreDeepLink.openAddExpenseURL)
        case .addIncome:
            handle(OffshoreDeepLink.openAddIncomeURL)
        case .reviewToday:
            handle(OffshoreDeepLink.openReviewTodayURL)
        case .excursionMode:
            await startExcursion(hours: 2)
        }
    }

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
            OffshoreControlPresentation.shared.pendingSheet = .expense
            return true

        case ("open", "/add-income"):
            OffshoreControlPresentation.shared.pendingSheet = .income
            return true

        case ("open", "/review-today"):
            OffshoreControlPresentation.shared.pendingSheet = .reviewToday
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
                await startExcursion(hours: hours)
            }
            return true

        default:
            return false
        }
    }

    private static func startExcursion(hours: Int) async {
        let result = await ShoppingModeManager.shared.start(hours: hours)
        switch result {
        case .started:
            OffshoreControlPresentation.shared.pendingExcursionBlockers = nil
        case .blocked(let blockers):
            OffshoreControlPresentation.shared.pendingExcursionBlockers = blockers
        }
    }
}
