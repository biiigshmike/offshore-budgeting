import Foundation

#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - ShoppingModeSuggestionService

final class ShoppingModeSuggestionService {
    static let shared = ShoppingModeSuggestionService()

    private enum Key {
        static let lastFiredByMerchant = "shoppingMode_lastFiredByMerchant"
        static let lastSessionID = "shoppingMode_lastSessionID"
        static let startupNudgedSessionID = "shoppingMode_startupNudgedSessionID"
    }

    private let defaults = UserDefaults.standard
    private let cooldownSeconds: TimeInterval = 15 * 60

    private init() {}

    func clearCooldownsIfSessionChanged(newSessionID: String?) {
        let previous = defaults.string(forKey: Key.lastSessionID)
        guard previous != newSessionID else { return }

        defaults.set([String: Double](), forKey: Key.lastFiredByMerchant)
        defaults.set(newSessionID, forKey: Key.lastSessionID)
        defaults.removeObject(forKey: Key.startupNudgedSessionID)
    }

    func resetAllCooldowns() {
        defaults.set([String: Double](), forKey: Key.lastFiredByMerchant)
        defaults.removeObject(forKey: Key.lastSessionID)
        defaults.removeObject(forKey: Key.startupNudgedSessionID)
    }

    func handleRegionEntry(merchant: ShoppingModeMerchant, now: Date = .now) {
        guard SpendingSessionStore.isActive(now: now) else { return }

        var map = (defaults.dictionary(forKey: Key.lastFiredByMerchant) as? [String: Double]) ?? [:]
        let lastFire = map[merchant.id].map(Date.init(timeIntervalSince1970:))

        if let lastFire, now.timeIntervalSince(lastFire) < cooldownSeconds {
            return
        }

        map[merchant.id] = now.timeIntervalSince1970
        defaults.set(map, forKey: Key.lastFiredByMerchant)

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
}
