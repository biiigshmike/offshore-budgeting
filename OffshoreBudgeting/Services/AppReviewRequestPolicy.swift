import Foundation

/// A review request is eligible only after sustained, successful use.
/// StoreKit still decides whether to display its native prompt.
enum AppReviewRequestPolicy {
    private static let firstUseKey = "reviews_firstExpenseAddedAt"
    private static let countKey = "reviews_expensesAdded"
    private static let lastRequestKey = "reviews_lastRequestedAt"

    static func recordExpenseAdded(defaults: UserDefaults = .standard, now: Date = .now) -> Bool {
        let count = defaults.integer(forKey: countKey) + 1
        defaults.set(count, forKey: countKey)
        if defaults.object(forKey: firstUseKey) == nil {
            defaults.set(now.timeIntervalSince1970, forKey: firstUseKey)
        }

        let firstUse = defaults.double(forKey: firstUseKey)
        guard count >= 10, now.timeIntervalSince1970 - firstUse >= 7 * 24 * 60 * 60 else { return false }

        if defaults.object(forKey: lastRequestKey) != nil {
            let lastRequest = defaults.double(forKey: lastRequestKey)
            guard now.timeIntervalSince1970 - lastRequest >= 180 * 24 * 60 * 60 else { return false }
        }

        defaults.set(now.timeIntervalSince1970, forKey: lastRequestKey)
        return true
    }
}
