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
        static let lastDeliveredMerchantID = "shoppingMode_lastDeliveredMerchantID"
        static let lastDeliveredLatitude = "shoppingMode_lastDeliveredLatitude"
        static let lastDeliveredLongitude = "shoppingMode_lastDeliveredLongitude"
    }

    private let defaults = UserDefaults.standard
    private let policy = ExcursionDetectionPolicy()

    private init() {}

    func clearCooldownsIfSessionChanged(newSessionID: String?) {
        let previous = defaults.string(forKey: Key.lastSessionID)
        guard previous != newSessionID else { return }

        defaults.set([String: Double](), forKey: Key.lastFiredByMerchant)
        defaults.removeObject(forKey: Key.lastGlobalFireAt)
        defaults.set(newSessionID, forKey: Key.lastSessionID)
        defaults.removeObject(forKey: Key.startupNudgedSessionID)
        defaults.removeObject(forKey: Key.lastDeliveredMerchantID)
        defaults.removeObject(forKey: Key.lastDeliveredLatitude)
        defaults.removeObject(forKey: Key.lastDeliveredLongitude)
    }

    func resetAllCooldowns() {
        defaults.set([String: Double](), forKey: Key.lastFiredByMerchant)
        defaults.removeObject(forKey: Key.lastGlobalFireAt)
        defaults.removeObject(forKey: Key.lastSessionID)
        defaults.removeObject(forKey: Key.startupNudgedSessionID)
        defaults.removeObject(forKey: Key.lastDeliveredMerchantID)
        defaults.removeObject(forKey: Key.lastDeliveredLatitude)
        defaults.removeObject(forKey: Key.lastDeliveredLongitude)
    }

    func handleRegionEntry(
        merchant: ShoppingModeMerchant,
        currentLocation: CLLocation? = nil,
        now: Date = .now
    ) {
        guard SpendingSessionStore.isActive(now: now) else { return }
        let decision = notificationDecision(
            merchantID: merchant.id,
            currentLocation: currentLocation,
            now: now
        )
        guard decision.isAllowed else {
            if let reason = decision.reason {
                debugLog("Suggestion suppressed for \(merchant.name): \(reason)")
            }
            return
        }

        Task { @MainActor in
            let service = LocalNotificationService()
            do {
                try await service.scheduleShoppingModeSuggestionNotification(merchantName: merchant.name)
                self.recordSuccessfulFire(
                    merchantID: merchant.id,
                    currentLocation: currentLocation,
                    now: now
                )
            } catch {
                debugLog("Suggestion scheduling failed for \(merchant.name): \(error.localizedDescription)")
            }
        }
    }

    #if canImport(CoreLocation)
    @discardableResult
    func sendStartupNudge(
        merchant: ShoppingModeMerchant,
        sessionID: String?,
        currentLocation: CLLocation? = nil,
        now: Date = .now
    ) -> Bool {
        guard let sessionID else { return false }
        guard SpendingSessionStore.isActive(now: now) else { return false }

        if defaults.string(forKey: Key.startupNudgedSessionID) == sessionID {
            return false
        }

        defaults.set(sessionID, forKey: Key.startupNudgedSessionID)
        handleRegionEntry(merchant: merchant, currentLocation: currentLocation, now: now)
        return true
    }
    #endif

    func notificationDecision(
        merchantID: String,
        currentLocation: CLLocation?,
        now: Date = .now
    ) -> ExcursionDetectionPolicy.NotificationDecision {
        let map = (defaults.dictionary(forKey: Key.lastFiredByMerchant) as? [String: Double]) ?? [:]
        let lastMerchantFire = map[merchantID].map(Date.init(timeIntervalSince1970:))
        return policy.notificationDecision(
            merchantID: merchantID,
            currentLocation: currentLocation,
            lastGlobalFireAt: lastGlobalFireDate(),
            lastMerchantFireAt: lastMerchantFire,
            lastDeliveredMerchantID: defaults.string(forKey: Key.lastDeliveredMerchantID),
            lastDeliveredLocation: lastDeliveredLocation(),
            now: now
        )
    }

    private func lastGlobalFireDate() -> Date? {
        let raw = defaults.double(forKey: Key.lastGlobalFireAt)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    private func lastDeliveredLocation() -> CLLocation? {
        let latitude = defaults.double(forKey: Key.lastDeliveredLatitude)
        let longitude = defaults.double(forKey: Key.lastDeliveredLongitude)
        guard latitude != 0 || longitude != 0 else { return nil }
        return CLLocation(latitude: latitude, longitude: longitude)
    }

    private func recordSuccessfulFire(merchantID: String, currentLocation: CLLocation?, now: Date) {
        var map = (defaults.dictionary(forKey: Key.lastFiredByMerchant) as? [String: Double]) ?? [:]
        map[merchantID] = now.timeIntervalSince1970
        defaults.set(map, forKey: Key.lastFiredByMerchant)
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastGlobalFireAt)
        defaults.set(merchantID, forKey: Key.lastDeliveredMerchantID)
        if let currentLocation {
            defaults.set(currentLocation.coordinate.latitude, forKey: Key.lastDeliveredLatitude)
            defaults.set(currentLocation.coordinate.longitude, forKey: Key.lastDeliveredLongitude)
        } else {
            defaults.removeObject(forKey: Key.lastDeliveredLatitude)
            defaults.removeObject(forKey: Key.lastDeliveredLongitude)
        }
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ShoppingModeSuggestionService] \(message)")
        #endif
    }
}
