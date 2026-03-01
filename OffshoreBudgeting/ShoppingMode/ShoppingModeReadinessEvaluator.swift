import Foundation
import UserNotifications

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

// MARK: - ShoppingModeStartBlocker

enum ShoppingModeStartBlocker: String, Equatable, CaseIterable {
    case notificationsNotAuthorized
    case locationAlwaysNotGranted
    case liveActivitiesDisabled
    case backgroundRefreshUnavailable

    nonisolated var message: String {
        switch self {
        case .notificationsNotAuthorized:
            return "Enable Notifications for Offshore in System Settings."
        case .locationAlwaysNotGranted:
            return "Set Location access to Always Allow for Excursion Mode."
        case .liveActivitiesDisabled:
            return "Enable Live Activities for Offshore in System Settings."
        case .backgroundRefreshUnavailable:
            return "Enable Background App Refresh for Offshore in System Settings."
        }
    }
}

// MARK: - ShoppingModeStartResult

enum ShoppingModeStartResult: Equatable {
    case started(expiresAt: Date)
    case blocked([ShoppingModeStartBlocker])
}

// MARK: - ShoppingModeReadinessEvaluator

@MainActor
final class ShoppingModeReadinessEvaluator {
    static let shared = ShoppingModeReadinessEvaluator()

    private init() {}

    func evaluate() async -> [ShoppingModeStartBlocker] {
        var blockers: [ShoppingModeStartBlocker] = []

        let notificationSettings = await fetchNotificationSettings()
        if Self.isNotificationAuthorized(notificationSettings.authorizationStatus) == false {
            blockers.append(.notificationsNotAuthorized)
        }

        #if canImport(CoreLocation)
        let locationStatus = CLLocationManager().authorizationStatus
        if locationStatus != .authorizedAlways {
            blockers.append(.locationAlwaysNotGranted)
        }
        #endif

        #if canImport(UIKit)
        if UIApplication.shared.backgroundRefreshStatus != .available {
            blockers.append(.backgroundRefreshUnavailable)
        }
        #endif

        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        if UIDevice.current.userInterfaceIdiom == .phone,
           ActivityAuthorizationInfo().areActivitiesEnabled == false {
            blockers.append(.liveActivitiesDisabled)
        }
        #endif

        return blockers
    }

    private func fetchNotificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private static func isNotificationAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined, .denied:
            return false
        @unknown default:
            return false
        }
    }
}
