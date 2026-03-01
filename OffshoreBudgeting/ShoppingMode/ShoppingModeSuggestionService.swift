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

        let map = (defaults.dictionary(forKey: Key.lastFiredByMerchant) as? [String: Double]) ?? [:]
        let lastMerchantFire = map[merchant.id].map(Date.init(timeIntervalSince1970:))

        if let lastMerchantFire,
           now.timeIntervalSince(lastMerchantFire) < ShoppingModeTuning.perMerchantNotificationCooldownSeconds {
            debugLog("Suggestion suppressed for \(merchant.name): merchant cooldown active")
            return
        }

        Task { @MainActor in
            let service = LocalNotificationService()
            do {
                try await service.scheduleShoppingModeSuggestionNotification(merchantName: merchant.name)
                self.recordSuccessfulFire(merchantID: merchant.id, now: now)
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
        now: Date = .now
    ) -> Bool {
        guard let sessionID else { return false }
        guard SpendingSessionStore.isActive(now: now) else { return false }

        if defaults.string(forKey: Key.startupNudgedSessionID) == sessionID {
            return false
        }

        defaults.set(sessionID, forKey: Key.startupNudgedSessionID)
        handleRegionEntry(merchant: merchant, now: now)
        return true
    }
    #endif

    private func lastGlobalFireDate() -> Date? {
        let raw = defaults.double(forKey: Key.lastGlobalFireAt)
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw)
    }

    private func recordSuccessfulFire(merchantID: String, now: Date) {
        var map = (defaults.dictionary(forKey: Key.lastFiredByMerchant) as? [String: Double]) ?? [:]
        map[merchantID] = now.timeIntervalSince1970
        defaults.set(map, forKey: Key.lastFiredByMerchant)
        defaults.set(now.timeIntervalSince1970, forKey: Key.lastGlobalFireAt)
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ShoppingModeSuggestionService] \(message)")
        #endif
    }
}
