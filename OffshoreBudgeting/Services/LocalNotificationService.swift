//
//  LocalNotificationService.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import Foundation
import Combine
import SwiftData
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

    // MARK: - Constants

    private enum Scheduling {
        static let maxScheduledDays: Int = 30
        static let maxNotificationBodyCharacters: Int = 95
        static let maxNamesInPresetDueBody: Int = 2
    }

    // MARK: - AppStorage Keys

    private enum SettingsKey {
        static let notificationsEnabled = "notifications_enabled"
        static let reminderHour = "notifications_reminderHour"
        static let reminderMinute = "notifications_reminderMinute"
        static let dailyExpenseReminderEnabled = "notifications_dailyExpenseReminderEnabled"
        static let plannedIncomeReminderEnabled = "notifications_plannedIncomeReminderEnabled"
        static let presetDueReminderEnabled = "notifications_presetDueReminderEnabled"
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

    // MARK: - Convenience Sync

    static func syncFromUserDefaultsIfPossible(modelContext: ModelContext, workspaceID: UUID) async {
        let defaults = UserDefaults.standard

        let notificationsEnabled = defaults.bool(forKey: SettingsKey.notificationsEnabled)
        let reminderHour = defaults.object(forKey: SettingsKey.reminderHour) as? Int ?? 20
        let reminderMinute = defaults.object(forKey: SettingsKey.reminderMinute) as? Int ?? 0

        let dailyExpenseEnabled = defaults.bool(forKey: SettingsKey.dailyExpenseReminderEnabled)
        let plannedIncomeEnabled = defaults.bool(forKey: SettingsKey.plannedIncomeReminderEnabled)
        let presetDueEnabled = defaults.bool(forKey: SettingsKey.presetDueReminderEnabled)

        let service = LocalNotificationService()
        await service.refreshAuthorizationStatus()
        guard service.isAuthorized else { return }

        do {
            try await service.syncReminders(
                modelContext: modelContext,
                workspaceID: workspaceID,
                notificationsEnabled: notificationsEnabled,
                dailyExpenseEnabled: dailyExpenseEnabled,
                plannedIncomeEnabled: plannedIncomeEnabled,
                presetDueEnabled: presetDueEnabled,
                hour: reminderHour,
                minute: reminderMinute
            )
        } catch {
            // intentionally ignoring errors so scheduling never blocks UI flows.
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

    /// Syncs the three reminder types based on toggles + reminder time + SwiftData.
    /// - Daily Expense: repeating daily at the chosen time.
    /// - Planned Income: one-off notifications only on days with planned income.
    /// - Preset Due: one-off notifications only on days with preset-derived planned expenses.
    ///
    /// This is deterministic and safe to call anytime (toggle changes, time changes, app launch).
    func syncReminders(
        modelContext: ModelContext,
        workspaceID: UUID,
        notificationsEnabled: Bool,
        dailyExpenseEnabled: Bool,
        plannedIncomeEnabled: Bool,
        presetDueEnabled: Bool,
        hour: Int,
        minute: Int
    ) async throws {

        // If app-level notifications are off, cancel app’s reminder IDs.
        guard notificationsEnabled else {
            cancelNotification(identifier: NotificationID.dailyExpenseReminder)
            await removeScheduledNotifications(matchingPrefix: NotificationID.plannedIncomeReminder)
            await removeScheduledNotifications(matchingPrefix: NotificationID.presetDueReminder)
            return
        }

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

        await removeScheduledNotifications(matchingPrefix: NotificationID.plannedIncomeReminder)
        if plannedIncomeEnabled {
            let days = try plannedIncomeDays(
                modelContext: modelContext,
                workspaceID: workspaceID,
                startDay: Calendar.current.startOfDay(for: Date()),
                horizonDays: Scheduling.maxScheduledDays
            )

            try await scheduleOneOffNotifications(
                days: days,
                identifierPrefix: NotificationID.plannedIncomeReminder,
                title: "Offshore Budgeting",
                body: "Income is planned to arrive offshore today. Verify any deposits and log actual income.",
                hour: hour,
                minute: minute
            )
        }

        await removeScheduledNotifications(matchingPrefix: NotificationID.presetDueReminder)
        if presetDueEnabled {
            let presetNamesByDay = try presetDuePresetNamesByDay(
                modelContext: modelContext,
                workspaceID: workspaceID,
                startDay: Calendar.current.startOfDay(for: Date()),
                horizonDays: Scheduling.maxScheduledDays
            )

            let days = Set(presetNamesByDay.keys)
            try await scheduleOneOffNotifications(
                days: days,
                identifierPrefix: NotificationID.presetDueReminder,
                title: "Offshore Budgeting",
                bodyForDay: { day in
                    Self.presetDueBody(
                        presetNames: presetNamesByDay[day] ?? [],
                        maxNamesShown: Scheduling.maxNamesInPresetDueBody,
                        maxCharacters: Scheduling.maxNotificationBodyCharacters
                    )
                },
                hour: hour,
                minute: minute
            )
        }
    }

    // MARK: - Helpers

    private func scheduleOneOffNotifications(
        days: Set<Date>,
        identifierPrefix: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int
    ) async throws {
        try await scheduleOneOffNotifications(
            days: days,
            identifierPrefix: identifierPrefix,
            title: title,
            bodyForDay: { _ in body },
            hour: hour,
            minute: minute
        )
    }

    private func scheduleOneOffNotifications(
        days: Set<Date>,
        identifierPrefix: String,
        title: String,
        bodyForDay: (Date) -> String,
        hour: Int,
        minute: Int
    ) async throws {

        for day in days.sorted() {
            guard let fireDate = Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: day) else {
                continue
            }

            guard fireDate > Date() else { continue }

            let identifier = "\(identifierPrefix)_\(Self.dayToken(for: day))"
            try await scheduleOneOffNotification(
                identifier: identifier,
                title: title,
                body: bodyForDay(day),
                fireDate: fireDate
            )
        }
    }

    private func scheduleOneOffNotification(
        identifier: String,
        title: String,
        body: String,
        fireDate: Date
    ) async throws {

        removeScheduledNotifications(identifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        components.second = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: trigger
        )

        try await addNotificationRequest(request)
    }

    private func plannedIncomeDays(
        modelContext: ModelContext,
        workspaceID: UUID,
        startDay: Date,
        horizonDays: Int
    ) throws -> Set<Date> {

        let clampedDays = max(1, min(Scheduling.maxScheduledDays, horizonDays))
        guard let endExclusive = Calendar.current.date(byAdding: .day, value: clampedDays, to: startDay) else {
            return []
        }

        let descriptor = FetchDescriptor<Income>(
            predicate: #Predicate { income in
                income.workspace?.id == workspaceID &&
                income.isPlanned == true &&
                income.date >= startDay &&
                income.date < endExclusive
            }
        )

        let matches = try modelContext.fetch(descriptor)
        return Set(matches.map { Calendar.current.startOfDay(for: $0.date) })
    }

    private func presetDuePresetNamesByDay(
        modelContext: ModelContext,
        workspaceID: UUID,
        startDay: Date,
        horizonDays: Int
    ) throws -> [Date: [String]] {

        let clampedDays = max(1, min(Scheduling.maxScheduledDays, horizonDays))
        guard let endExclusive = Calendar.current.date(byAdding: .day, value: clampedDays, to: startDay) else {
            return [:]
        }

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.workspace?.id == workspaceID &&
                expense.sourcePresetID != nil &&
                expense.expenseDate >= startDay &&
                expense.expenseDate < endExclusive
            }
        )

        let matches = try modelContext.fetch(descriptor)

        var byDay: [Date: [String]] = [:]

        for expense in matches {
            let day = Calendar.current.startOfDay(for: expense.expenseDate)
            let title = expense.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { continue }
            byDay[day, default: []].append(title)
        }

        for (day, titles) in byDay {
            let unique = Array(Set(titles)).sorted()
            byDay[day] = unique
        }

        return byDay
    }

    private func fetchPendingNotificationRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getPendingNotificationRequests { requests in
                continuation.resume(returning: requests)
            }
        }
    }

    func debugPendingRequestLines() async -> [String] {
        let requests = await fetchPendingNotificationRequests()

        let lines: [String] = requests
            .sorted(by: { $0.identifier < $1.identifier })
            .map { request in
                if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                    let next = trigger.nextTriggerDate()?.formatted(date: .abbreviated, time: .shortened) ?? "unknown"
                    let title = request.content.title.isEmpty ? "Untitled" : request.content.title
                    let body = request.content.body.isEmpty ? "(no body)" : request.content.body
                    return "\(next) — \(title): \(body) • id=\(request.identifier) • repeats=\(trigger.repeats)"
                }

                let triggerType = request.trigger.map { String(describing: type(of: $0)) } ?? "nil"
                let title = request.content.title.isEmpty ? "Untitled" : request.content.title
                let body = request.content.body.isEmpty ? "(no body)" : request.content.body
                return "\(title): \(body) • id=\(request.identifier) • trigger=\(triggerType)"
            }

        return lines
    }

    func removeScheduledNotifications(matchingPrefix prefix: String) async {
        let requests = await fetchPendingNotificationRequests()
        let ids = requests
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) }

        removeScheduledNotifications(identifiers: ids)
    }

    private static func dayToken(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func presetDueBody(
        presetNames: [String],
        maxNamesShown: Int,
        maxCharacters: Int
    ) -> String {

        let cleaned = presetNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let uniqueSorted = Array(Set(cleaned)).sorted()
        let total = uniqueSorted.count

        guard total > 0 else {
            return "Preset expenses due."
        }

        let clampedMaxNames = max(0, min(2, maxNamesShown))

        func makeBody(shownCount: Int) -> String {
            let shown = Array(uniqueSorted.prefix(shownCount))
            let remaining = max(0, total - shownCount)

            if total == 1 {
                return "Preset expected to set sail: \(uniqueSorted[0])"
            }

            if shown.isEmpty {
                return "\(localizedInt(total)) presets due"
            }

            var body = "Presets docking from your account today: \(shown.joined(separator: ", "))"
            if remaining > 0 {
                body += " +\(localizedInt(remaining)) more"
            }
            return body
        }

        for shownCount in stride(from: clampedMaxNames, through: 0, by: -1) {
            let body = makeBody(shownCount: shownCount)
            if body.count <= maxCharacters {
                return body
            }
        }

        return total == 1 ? "Preset due" : "\(localizedInt(total)) presets due"
    }

    private static func localizedInt(_ value: Int) -> String {
        value.formatted(.number)
    }

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
