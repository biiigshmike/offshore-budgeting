//
//  LocalNotificationService.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import Foundation
import Combine
import UserNotifications

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class LocalNotificationService: ObservableObject {

    // MARK: - Identifiers

    enum NotificationID {
        static let dailyExpenseReminder = "daily_expense_reminder"
        static let plannedIncomeReminder = "planned_income_reminder"
        static let presetDueReminder = "preset_due_reminder"
        static let testNotification = "local_test_notification"
    }

    // MARK: - Authorization State

    enum AuthorizationState: Equatable {
        case notDetermined
        case denied
        case authorized
    }

    @Published private(set) var authorizationState: AuthorizationState = .notDetermined

    var isAuthorized: Bool {
        authorizationState == .authorized
    }

    // MARK: - Init

    init() {
        Task {
            await refreshAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    func refreshAuthorizationStatus() async {
        let settings = await fetchNotificationSettings()
        authorizationState = Self.mapAuthorizationStatus(settings.authorizationStatus)
    }

    func requestAuthorization() async throws -> Bool {
        let granted = try await requestAuthorizationInternal(options: [.alert, .sound, .badge])
        await refreshAuthorizationStatus()
        return granted
    }

    func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    // MARK: - Removal

    func removeAllScheduledNotifications() {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        center.removeAllDeliveredNotifications()
    }

    func removeScheduledNotifications(identifiers: [String]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    // MARK: - Scheduling (Daily)

    /// Schedule or replace a repeating daily notification at the specified hour/minute.
    func scheduleDailyNotification(
        identifier: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int
    ) async throws {

        // Replace any existing pending request with the same identifier.
        removeScheduledNotifications(identifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        try await addNotificationRequest(request)
    }

    /// Cancels a scheduled daily reminder by identifier.
    func cancelNotification(identifier: String) {
        removeScheduledNotifications(identifiers: [identifier])
    }

    /// Syncs the three reminder types based on toggles + reminder time.
    /// This is deterministic and safe to call anytime (toggle changes, time changes, app launch).
    func syncDailyReminders(
        notificationsEnabled: Bool,
        dailyExpenseEnabled: Bool,
        plannedIncomeEnabled: Bool,
        presetDueEnabled: Bool,
        hour: Int,
        minute: Int
    ) async throws {

        // If app-level notifications are off, cancel our app’s reminder IDs.
        guard notificationsEnabled else {
            removeScheduledNotifications(identifiers: [
                NotificationID.dailyExpenseReminder,
                NotificationID.plannedIncomeReminder,
                NotificationID.presetDueReminder
            ])
            return
        }

        // These titles/bodies are intentionally “safe” for now.
        // Once we add real detection logic, we can change messaging and scheduling behavior.
        if dailyExpenseEnabled {
            try await scheduleDailyNotification(
                identifier: NotificationID.dailyExpenseReminder,
                title: "Offshore Budgeting",
                body: "Keep the books tidy and balanced. Log any variable expenses today.",
                hour: hour,
                minute: minute
            )
        } else {
            cancelNotification(identifier: NotificationID.dailyExpenseReminder)
        }

        if plannedIncomeEnabled {
            try await scheduleDailyNotification(
                identifier: NotificationID.plannedIncomeReminder,
                title: "Offshore Budgeting",
                body: "Income is planned to arrive offshore today. Verify any deposits and log actual income.",
                hour: hour,
                minute: minute
            )
        } else {
            cancelNotification(identifier: NotificationID.plannedIncomeReminder)
        }

        if presetDueEnabled {
            try await scheduleDailyNotification(
                identifier: NotificationID.presetDueReminder,
                title: "Offshore Budgeting",
                body: "Presets are scheduled to set sail today. Make sure the planned amount matches what was debited.",
                hour: hour,
                minute: minute
            )
        } else {
            cancelNotification(identifier: NotificationID.presetDueReminder)
        }
    }

    // MARK: - Testing

    func scheduleTestNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Offshore Budgeting"
        content.body = "Notifications are enabled ✅"
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        let request = UNNotificationRequest(
            identifier: NotificationID.testNotification,
            content: content,
            trigger: trigger
        )

        try await addNotificationRequest(request)
    }

    // MARK: - Helpers

    private func fetchNotificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func requestAuthorizationInternal(options: UNAuthorizationOptions) async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: options) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: granted)
            }
        }
    }

    private func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            UNUserNotificationCenter.current().add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }

    private static func mapAuthorizationStatus(_ status: UNAuthorizationStatus) -> AuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized, .provisional, .ephemeral:
            return .authorized
        @unknown default:
            return .notDetermined
        }
    }
}
