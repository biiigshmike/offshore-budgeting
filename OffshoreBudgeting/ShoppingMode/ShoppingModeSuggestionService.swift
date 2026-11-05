import Foundation
import UserNotifications

#if canImport(CoreLocation)
import CoreLocation
#endif

// MARK: - ShoppingModeSuggestionService

@MainActor
final class ShoppingModeSuggestionService {
    static let shared = ShoppingModeSuggestionService()

    private enum Key {
        static let lastFiredByMerchant = "shoppingMode_lastFiredByMerchant"
        static let lastGlobalFireAt = "shoppingMode_lastGlobalFireAt"
        static let lastSessionID = "shoppingMode_lastSessionID"
        static let lastDeliveredMerchantID = "shoppingMode_lastDeliveredMerchantID"
        static let lastDeliveredLatitude = "shoppingMode_lastDeliveredLatitude"
        static let lastDeliveredLongitude = "shoppingMode_lastDeliveredLongitude"
        static let lastDeliveredStopLatitude = "shoppingMode_lastDeliveredStopLatitude"
        static let lastDeliveredStopLongitude = "shoppingMode_lastDeliveredStopLongitude"
    }

    enum DeliveryResult: Equatable {
        case scheduled(identifier: String)
        case suppressed
        case failed
    }

    private let defaults: UserDefaults
    private let sessionIDProvider: () -> String?
    private let schedule: (ExcursionSuggestion, @escaping @MainActor @Sendable () -> Bool) async throws -> String?
    private let cancel: (String) -> Void
    private let policy = ExcursionDetectionPolicy()
    private var deliveryInFlight = false
    private var latestSuggestionID: String?

    init(
        defaults: UserDefaults = .standard,
        sessionIDProvider: (() -> String?)? = nil,
        schedule: @escaping (ExcursionSuggestion, @escaping @MainActor @Sendable () -> Bool) async throws -> String? = {
            try await LocalNotificationService().scheduleShoppingModeSuggestionNotification(suggestion: $0, isStillValid: $1)
        },
        cancel: @escaping (String) -> Void = {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [$0])
        }
    ) {
        self.defaults = defaults
        self.sessionIDProvider = sessionIDProvider ?? { SpendingSessionStore.sessionID() }
        self.schedule = schedule
        self.cancel = cancel
    }

    func clearCooldownsIfSessionChanged(newSessionID: String?) {
        let previous = defaults.string(forKey: Key.lastSessionID)
        guard previous != newSessionID else { return }

        defaults.set([String: Double](), forKey: Key.lastFiredByMerchant)
        defaults.removeObject(forKey: Key.lastGlobalFireAt)
        defaults.set(newSessionID, forKey: Key.lastSessionID)
        defaults.removeObject(forKey: Key.lastDeliveredMerchantID)
        defaults.removeObject(forKey: Key.lastDeliveredLatitude)
        defaults.removeObject(forKey: Key.lastDeliveredLongitude)
        defaults.removeObject(forKey: Key.lastDeliveredStopLatitude)
        defaults.removeObject(forKey: Key.lastDeliveredStopLongitude)
    }

    func resetAllCooldowns() {
        defaults.set([String: Double](), forKey: Key.lastFiredByMerchant)
        defaults.removeObject(forKey: Key.lastGlobalFireAt)
        defaults.removeObject(forKey: Key.lastSessionID)
        defaults.removeObject(forKey: Key.lastDeliveredMerchantID)
        defaults.removeObject(forKey: Key.lastDeliveredLatitude)
        defaults.removeObject(forKey: Key.lastDeliveredLongitude)
        defaults.removeObject(forKey: Key.lastDeliveredStopLatitude)
        defaults.removeObject(forKey: Key.lastDeliveredStopLongitude)
    }

    func cancelPendingSuggestion() {
        guard let latestSuggestionID else { return }
        cancel(latestSuggestionID)
        self.latestSuggestionID = nil
    }

    func send(
        suggestion: ExcursionSuggestion,
        currentLocation: CLLocation?,
        now: Date = .now,
        isStillValid: @escaping @MainActor @Sendable () -> Bool
    ) async -> DeliveryResult {
        let canDeliver: @MainActor @Sendable () -> Bool = { [self] in
            isStillValid() && sessionIDProvider() == suggestion.sessionID
        }
        guard canDeliver(), !deliveryInFlight, let merchant = suggestion.candidates.first else { return .suppressed }
        clearCooldownsIfSessionChanged(newSessionID: suggestion.sessionID)
        let decision = notificationDecision(merchantID: merchant.id, currentLocation: currentLocation, now: now)
        guard decision.isAllowed else {
            debugLogSuppressedSuggestion(for: merchant.name, decision: decision)
            return .suppressed
        }
        deliveryInFlight = true
        defer { deliveryInFlight = false }
        do {
            guard let identifier = try await schedule(suggestion, canDeliver) else { return .suppressed }
            guard canDeliver() else {
                cancel(identifier)
                return .suppressed
            }
            latestSuggestionID = identifier
            recordSuccessfulFire(merchantID: merchant.id, currentLocation: currentLocation, now: now)
            return .scheduled(identifier: identifier)
        } catch is CancellationError {
            return .suppressed
        } catch {
            debugLog("Suggestion scheduling failed: \(error.localizedDescription)")
            return .failed
        }
    }

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
            lastDeliveredStopLocation: lastDeliveredStopLocation(),
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

    private func lastDeliveredStopLocation() -> CLLocation? {
        let latitude = defaults.double(forKey: Key.lastDeliveredStopLatitude)
        let longitude = defaults.double(forKey: Key.lastDeliveredStopLongitude)
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
            defaults.set(currentLocation.coordinate.latitude, forKey: Key.lastDeliveredStopLatitude)
            defaults.set(currentLocation.coordinate.longitude, forKey: Key.lastDeliveredStopLongitude)
        } else {
            defaults.removeObject(forKey: Key.lastDeliveredLatitude)
            defaults.removeObject(forKey: Key.lastDeliveredLongitude)
            defaults.removeObject(forKey: Key.lastDeliveredStopLatitude)
            defaults.removeObject(forKey: Key.lastDeliveredStopLongitude)
        }
    }

    private func debugLogSuppressedSuggestion(
        for merchantName: String,
        decision: ExcursionDetectionPolicy.NotificationDecision
    ) {
        guard let reason = decision.reason else { return }

        let globalSeconds = decision.secondsSinceLastGlobalFire.map { String(Int($0)) } ?? "n/a"
        let merchantSeconds = decision.secondsSinceLastMerchantFire.map { String(Int($0)) } ?? "n/a"
        let movementMeters = decision.distanceFromLastDeliveredLocation.map { String(Int($0)) } ?? "n/a"
        let stopMeters = decision.distanceFromLastStopLocation.map { String(Int($0)) } ?? "n/a"
        debugLog(
            "Suggestion suppressed for \(merchantName): \(reason) " +
            "[global=\(globalSeconds)s merchant=\(merchantSeconds)s moved=\(movementMeters)m stop=\(stopMeters)m sameStop=\(decision.isSameStopCluster)]"
        )
    }

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[ShoppingModeSuggestionService] \(message)")
        #endif
    }
}
