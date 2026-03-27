import AppIntents
import Foundation

// MARK: - OffshoreWidgetDeepLink

enum OffshoreWidgetDeepLink {
    static let openAddExpenseURL = URL(string: "offshore://open/add-expense")!
    static let openAddIncomeURL = URL(string: "offshore://open/add-income")!
    static let openReviewTodayURL = URL(string: "offshore://open/review-today")!
    static let openSafeSpendTodayURL = URL(string: "offshore://open/safe-spend-today")!
    static let openForecastSavingsURL = URL(string: "offshore://open/forecast-savings")!

    static func startExcursionModeURL(hours: Int = 2) -> URL {
        URL(string: "offshore://action/excursion-mode/start?hours=\(hours)")!
    }
}

// MARK: - Widget Launch Intents

struct WidgetOpenAddExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Expense"
    static var description = IntentDescription("Open Offshore directly to quick add expense.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetActionLaunchStore.queue(OffshoreWidgetDeepLink.openAddExpenseURL)
        return .result()
    }
}

struct WidgetOpenAddIncomeIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Income"
    static var description = IntentDescription("Open Offshore directly to quick add income.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetActionLaunchStore.queue(OffshoreWidgetDeepLink.openAddIncomeURL)
        return .result()
    }
}

struct WidgetReviewTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Review Today"
    static var description = IntentDescription("Open Offshore for a review of today's spending.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetActionLaunchStore.queue(OffshoreWidgetDeepLink.openReviewTodayURL)
        return .result()
    }
}

struct WidgetOpenSafeSpendTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Safe Spend Today"
    static var description = IntentDescription("Open Offshore to review safe spending guidance for today.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetActionLaunchStore.queue(OffshoreWidgetDeepLink.openSafeSpendTodayURL)
        return .result()
    }
}

struct WidgetOpenForecastSavingsIntent: AppIntent {
    static var title: LocalizedStringResource = "Forecast Savings"
    static var description = IntentDescription("Open Offshore to review your savings outlook.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetActionLaunchStore.queue(OffshoreWidgetDeepLink.openForecastSavingsURL)
        return .result()
    }
}

struct WidgetStartExcursionModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Excursion Mode"
    static var description = IntentDescription("Start a 2-hour Excursion Mode session in Offshore.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        WidgetActionLaunchStore.queue(OffshoreWidgetDeepLink.startExcursionModeURL(hours: 2))
        return .result()
    }
}
