import Foundation
import UserNotifications
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

/// Compatibility cleanup for installations that previously used Excursion Mode.
/// This never requests permissions, starts a session, or changes financial records.
/// Location/background and Live Activity declarations remain temporarily until
/// upgrades with existing monitoring and Activities have been verified on a device.
@MainActor
enum ExcursionRetirementService {
    static let defaultsKeys = [
        "spendingSession_expiresAt", "spendingSession_startedAt", "spendingSession_sessionID",
        "shoppingMode_monitoredMerchantPayloads", "shoppingMode_lastFiredByMerchant",
        "shoppingMode_lastGlobalFireAt", "shoppingMode_lastSessionID",
        "shoppingMode_startupNudgedSessionID", "shoppingMode_lastDeliveredMerchantID",
        "shoppingMode_lastDeliveredLatitude", "shoppingMode_lastDeliveredLongitude",
        "shoppingMode_lastDeliveredStopLatitude", "shoppingMode_lastDeliveredStopLongitude",
        "debug_shoppingModeForegroundTraceEnabled"
    ]

    static func retireLegacyState() async {
        clearDefaults(in: .standard)
        if let shared = UserDefaults(suiteName: "group.com.mb.offshore-budgeting") {
            clearDefaults(in: shared)
        }

        #if canImport(CoreLocation)
        let manager = CLLocationManager()
        for region in manager.monitoredRegions where isLegacyRegion(region.identifier) {
            manager.stopMonitoring(for: region)
        }
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopUpdatingLocation()
        #endif

        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        for activity in Activity<ShoppingModeActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter(isLegacyNotification))
        let delivered = await center.deliveredNotifications()
        center.removeDeliveredNotifications(withIdentifiers: delivered.map { $0.request.identifier }.filter(isLegacyNotification))
    }

    static func clearDefaults(in defaults: UserDefaults) {
        for key in defaultsKeys { defaults.removeObject(forKey: key) }
        if defaults.string(forKey: AppShortcutNavigationStore.pendingActionKey) == "open_quick_add_expense_from_shopping_mode" {
            defaults.removeObject(forKey: AppShortcutNavigationStore.pendingActionKey)
            defaults.removeObject(forKey: AppShortcutNavigationStore.pendingExpenseDescriptionKey)
        }
    }

    static func isLegacyRegion(_ identifier: String) -> Bool {
        identifier.hasPrefix("shopping_mode.")
    }

    static func isLegacyNotification(_ identifier: String) -> Bool {
        identifier.hasPrefix("shopping_mode_suggestion_")
    }
}
