import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - ShoppingModeSuggestionService

final class ShoppingModeSuggestionService {
    static let shared = ShoppingModeSuggestionService()

    private enum Key {
        static let lastFiredByMerchant = "shoppingMode_lastFiredByMerchant"
        static let lastGlobalFireAt = "shoppingMode_lastGlobalFireAt"
        static let lastSessionID = "shoppingMode_lastSessionID"
        static let startupNudgedSessionID = "shoppingMode_startupNudgedSessionID"
    }

    private let defaults = UserDefaults.standard

    private init() {}

    func clearCooldownsIfSessionChanged(newSessionID: String?) {
        let previous = defaults.string(forKey: Key.lastSessionID)
        guard previous != newSessionID else { return }

        defaults.set([String: Double](), forKey: Key.lastFiredByMerchant)
        defaults.removeObject(forKey: Key.lastGlobalFireAt)
        defaults.set(newSessionID, forKey: Key.lastSessionID)
        defaults.removeObject(forKey: Key.startupNudgedSessionID)
    }

    func resetAllCooldowns() {
        defaults.set([String: Double](), forKey: Key.lastFiredByMerchant)
        defaults.removeObject(forKey: Key.lastGlobalFireAt)
        defaults.removeObject(forKey: Key.lastSessionID)
        defaults.removeObject(forKey: Key.startupNudgedSessionID)
    }

    func handleRegionEntry(merchant: ShoppingModeMerchant, now: Date = .now) {
        guard SpendingSessionStore.isActive(now: now) else { return }

        if let lastGlobalFireAt = lastGlobalFireDate(),
           now.timeIntervalSince(lastGlobalFireAt) < ShoppingModeTuning.globalNotificationCooldownSeconds {
            debugLog("Suggestion suppressed for \(merchant.name): global cooldown active")
            return
        }

        var map = (defaults.dictionary(forKey: Key.lastFiredByMerchant) as? [String: Double]) ?? [:]
        let lastMerchantFire = map[merchant.id].map(Date.init(timeIntervalSince1970:))

        if let lastMerchantFire,
           now.timeIntervalSince(lastMerchantFire) < ShoppingModeTuning.perMerchantNotificationCooldownSeconds {
            debugLog("Suggestion suppressed for \(merchant.name): merchant cooldown active")
            return
        }

        map[merchant.id] = now.timeIntervalSince1970
        defaults.set(map, forKey: Key.lastFiredByMerchant)
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastGlobalFireAt)

        Task { @MainActor in
            let service = LocalNotificationService()
            try? await service.scheduleShoppingModeSuggestionNotification(merchantName: merchant.name)
        }
    }

    #if canImport(CoreLocation)
    @discardableResult
    func sendStartupNudgeIfEligible(
        merchants: [ShoppingModeMerchant],
        userCoordinate: CLLocationCoordinate2D,
        sessionID: String?,
        now: Date = .now
    ) -> ShoppingModeMerchant? {
        guard ShoppingModeTuning.startupNudgeEnabled else {
            debugLog("Startup nudge suppressed: disabled by tuning")
            return nil
        }

        guard let sessionID else { return nil }
        guard SpendingSessionStore.isActive(now: now) else { return nil }

        if defaults.string(forKey: Key.startupNudgedSessionID) == sessionID {
            return nil
        }

        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let closestEligible = merchants
            .compactMap { merchant -> (ShoppingModeMerchant, CLLocationDistance)? in
                let merchantLocation = CLLocation(latitude: merchant.latitude, longitude: merchant.longitude)
                let distance = userLocation.distance(from: merchantLocation)
                let threshold = min(max(merchant.radiusMeters, 120), 220)
                guard distance <= threshold else { return nil }
                return (merchant, distance)
            }
            .min(by: { $0.1 < $1.1 })?
            .0

        guard let closestEligible else { return nil }

        defaults.set(sessionID, forKey: Key.startupNudgedSessionID)
        handleRegionEntry(merchant: closestEligible, now: now)
        return closestEligible
    }
    #endif

    private func lastGlobalFireDate() -> Date? {
        let raw = defaults.double(forKey: Key.lastGlobalFireAt)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ShoppingModeSuggestionService] \(message)")
        #endif
    }
}
