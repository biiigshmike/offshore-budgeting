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
        static let shoppingModeSuggestion = "shopping_mode_suggestion"
        static let testNotification = "local_test_notification"
    }

    enum NotificationAction: String {
        case openCards = "open_cards"
        case openBudgets = "open_budgets"
        case openQuickAddIncome = "open_quick_add_income"
        case openQuickAddExpenseFromShoppingMode = "open_quick_add_expense_from_shopping_mode"
    }

    enum NotificationCategory {
        static let dailyExpenseReminder = "daily_expense_reminder_category"
        static let plannedIncomeReminder = "planned_income_reminder_category"
        static let presetDueReminder = "preset_due_reminder_category"
        static let shoppingModeSuggestion = "shopping_mode_suggestion_category"
    }

    enum NotificationKind: String {
        case dailyExpenseReminder = "daily_expense_reminder"
        case plannedIncomeReminder = "planned_income_reminder"
        case presetDueReminder = "preset_due_reminder"
        case shoppingModeSuggestion = "shopping_mode_suggestion"
    }

    enum UserInfoKey {
        static let action = "offshore_action"
        static let notificationKind = "offshore_notification_kind"
        static let merchantName = "offshore_merchant_name"
        static let excursionSuggestion = "offshore_excursion_suggestion"
    }

    // MARK: - Constants

    private enum Scheduling {
        static let maxScheduledDays: Int = 30
        static let maxNotificationBodyCharacters: Int = 95
        static let maxNamesInPresetDueBody: Int = 2
    }

    // MARK: - Authorization State

    enum AuthorizationState: Equatable {
        case unknown
        case notDetermined
        case denied
        case authorized
        case provisional
        case ephemeral
    }

    @Published private(set) var settings: NotificationSettingsSnapshot?
    private let center: any LocalNotificationCenter

    // All service instances share this queue because the system owns one set of reminder IDs.
    private static var reminderSyncTail: Task<Void, Never>?

    var authorizationState: AuthorizationState {
        guard let settings else { return .unknown }
        switch settings.authorization {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    var isAuthorized: Bool {
        switch authorizationState {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    var deliveryDescription: String {
        guard isAuthorized, let settings else {
            return String(localized: "Allow notifications to receive your reminders.")
        }
        if authorizationState == .provisional {
            return String(localized: "Notifications are delivered quietly to Notification Center.")
        }
        if authorizationState == .ephemeral {
            return String(localized: "Your device has allowed notifications for a limited time.")
        }
        if settings.alerts != .enabled {
            return String(localized: "Notification alerts are off. You can change this in your device’s Settings.")
        }
        if settings.sounds != .enabled {
            return String(localized: "Notification sounds are off. You can change this in your device’s Settings.")
        }
        return String(localized: "Your device’s settings control when reminders appear.")
    }

    init(center: (any LocalNotificationCenter)? = nil) {
        self.center = center ?? SystemLocalNotificationCenter()
    }

    // MARK: - Convenience Sync

    static func syncFromUserDefaultsIfPossible(modelContext: ModelContext, workspaceID: UUID) async {
        do {
            try await LocalNotificationService().syncReminders(
                modelContext: modelContext, workspaceID: workspaceID,
                preferences: ReminderPreferences.load()
            )
        } catch {
            // Background refresh must not block the financial editing flow.
        }
    }

    /// Saves an explicit setup choice. Denial keeps the categories/time but leaves reminders off.
    func configureReminders(
        _ draft: ReminderPreferences,
        defaults: UserDefaults = .standard,
        modelContext: ModelContext,
        workspaceID: UUID
    ) async throws {
        var preferences = draft
        preferences.enabled = false
        preferences.save(to: defaults)
        do {
            if preferences.hasSelectedReminders {
                await refreshAuthorizationStatus()
                if authorizationState == .notDetermined {
                    _ = try await requestAuthorization()
                }
                preferences.enabled = isAuthorized
            }
            preferences.save(to: defaults)
            try await syncReminders(
                modelContext: modelContext, workspaceID: workspaceID, preferences: preferences
            )
        } catch {
            // A failed authorization request must also remove previously scheduled reminders.
            if !preferences.enabled {
                try? await syncReminders(
                    modelContext: modelContext, workspaceID: workspaceID, preferences: preferences
                )
            }
            throw error
        }
    }

    // MARK: - Authorization

    func refreshAuthorizationStatus() async {
        settings = await center.settings()
    }

    func requestAuthorization() async throws -> Bool {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
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
        center.removeAll()
    }

    func removeScheduledNotifications(identifiers: [String]) {
        center.remove(identifiers: identifiers)
    }

    // MARK: - Scheduling (Daily)

    /// Schedule or replace a repeating daily notification at the specified hour/minute.
    func scheduleDailyNotification(
        identifier: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        categoryIdentifier: String? = nil,
        userInfo: [AnyHashable: Any] = [:]
    ) async throws {

        // Replace any existing pending request with the same identifier.
        removeScheduledNotifications(identifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }
        content.userInfo = userInfo

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

    @discardableResult
    func scheduleShoppingModeSuggestionNotification(
        suggestion: ExcursionSuggestion,
        isStillValid: @escaping @MainActor @Sendable () -> Bool = { true }
    ) async throws -> String? {
        guard !suggestion.candidates.isEmpty, let encoded = suggestion.encoded else { return nil }
        let merchantName = suggestion.candidates.count == 1 ? suggestion.candidates.first?.name : nil
        return try await scheduleExcursionNotification(merchantName: merchantName, encodedSuggestion: encoded, isStillValid: isStillValid)
    }

    // Kept for older callers and single-merchant notification compatibility.
    func scheduleShoppingModeSuggestionNotification(
        merchantName: String,
        isStillValid: @escaping @MainActor @Sendable () -> Bool = { true }
    ) async throws -> String? {
        guard !merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return try await scheduleExcursionNotification(merchantName: merchantName, encodedSuggestion: nil, isStillValid: isStillValid)
    }

    private func scheduleExcursionNotification(
        merchantName: String?,
        encodedSuggestion: String?,
        isStillValid: @escaping @MainActor @Sendable () -> Bool
    ) async throws -> String? {
        guard isStillValid() else { throw CancellationError() }
        let content = UNMutableNotificationContent()
        content.title = Self.localizedAppName
        if let merchantName {
            content.body = String(format: String(localized: "Near %@? Record an expense if you made a purchase."), locale: .current, merchantName)
        } else {
            content.body = String(localized: "Near a few places? Record an expense if you made a purchase.")
        }
        content.sound = .default
        content.interruptionLevel = .active
        content.categoryIdentifier = NotificationCategory.shoppingModeSuggestion
        content.userInfo = [
            UserInfoKey.notificationKind: NotificationKind.shoppingModeSuggestion.rawValue,
            UserInfoKey.action: NotificationAction.openQuickAddExpenseFromShoppingMode.rawValue
        ]
        if let merchantName { content.userInfo[UserInfoKey.merchantName] = merchantName }
        if let encodedSuggestion { content.userInfo[UserInfoKey.excursionSuggestion] = encodedSuggestion }
        let identifier = "\(NotificationID.shoppingModeSuggestion)_\(UUID().uuidString)"
        let request = UNNotificationRequest(identifier: identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
        guard isStillValid() else { throw CancellationError() }
        try await addNotificationRequest(request)
        guard isStillValid() else {
            removeScheduledNotifications(identifiers: [identifier])
            throw CancellationError()
        }
        return identifier
    }

    /// Syncs the three reminder types based on toggles + reminder time + SwiftData.
    /// - Daily Expense: repeating daily at the chosen time.
    /// - Planned Income: one-off notifications only on days with planned income.
    /// - Preset Due: one-off notifications only on days with preset-derived planned expenses.
    ///
    /// This is deterministic and safe to call anytime (toggle changes, time changes, app launch).
    func syncReminders(
        modelContext: ModelContext, workspaceID: UUID, preferences: ReminderPreferences
    ) async throws {
        let predecessor = Self.reminderSyncTail
        let operation = Task { @MainActor in
            await predecessor?.value
            try await self.performReminderSync(
                modelContext: modelContext, workspaceID: workspaceID, preferences: preferences
            )
        }
        Self.reminderSyncTail = Task { _ = try? await operation.value }
        try await operation.value
    }

    private func performReminderSync(
        modelContext: ModelContext, workspaceID: UUID, preferences: ReminderPreferences
    ) async throws {
        await refreshAuthorizationStatus()
        let dailyExpenseEnabled = preferences.daily
        let plannedIncomeEnabled = preferences.income
        let presetDueEnabled = preferences.preset
        let hour = preferences.hour
        let minute = preferences.minute

        // A blocked system permission never overwrites the person's app preferences.
        // If app-level notifications are off, cancel app’s reminder IDs.
        guard preferences.enabled && isAuthorized else {
            cancelNotification(identifier: NotificationID.dailyExpenseReminder)
            await removeScheduledNotifications(matchingPrefix: NotificationID.plannedIncomeReminder)
            await removeScheduledNotifications(matchingPrefix: NotificationID.presetDueReminder)
            return
        }

        if dailyExpenseEnabled {
            try await scheduleDailyNotification(
                identifier: NotificationID.dailyExpenseReminder,
                title: Self.localizedAppName,
                body: String(
                    localized: "notification.dailyExpense.body",
                    defaultValue: "Keep the books tidy and balanced. Log any variable expenses today.",
                    comment: "Daily reminder notification body for logging expenses."
                ),
                hour: hour,
                minute: minute,
                categoryIdentifier: NotificationCategory.dailyExpenseReminder,
                userInfo: [UserInfoKey.notificationKind: NotificationKind.dailyExpenseReminder.rawValue]
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
                title: Self.localizedAppName,
                body: String(
                    localized: "notification.plannedIncome.body",
                    defaultValue: "Income is planned to arrive offshore today. Verify any deposits and log actual income.",
                    comment: "Notification body for planned income reminder."
                ),
                categoryIdentifier: NotificationCategory.plannedIncomeReminder,
                userInfo: [UserInfoKey.notificationKind: NotificationKind.plannedIncomeReminder.rawValue],
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
                title: Self.localizedAppName,
                bodyForDay: { day in
                    Self.presetDueBody(
                        presetNames: presetNamesByDay[day] ?? [],
                        maxNamesShown: Scheduling.maxNamesInPresetDueBody,
                        maxCharacters: Scheduling.maxNotificationBodyCharacters
                    )
                },
                categoryIdentifier: NotificationCategory.presetDueReminder,
                userInfo: [UserInfoKey.notificationKind: NotificationKind.presetDueReminder.rawValue],
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
        categoryIdentifier: String? = nil,
        userInfo: [AnyHashable: Any] = [:],
        hour: Int,
        minute: Int
    ) async throws {
        try await scheduleOneOffNotifications(
            days: days,
            identifierPrefix: identifierPrefix,
            title: title,
            bodyForDay: { _ in body },
            categoryIdentifier: categoryIdentifier,
            userInfo: userInfo,
            hour: hour,
            minute: minute
        )
    }

    private func scheduleOneOffNotifications(
        days: Set<Date>,
        identifierPrefix: String,
        title: String,
        bodyForDay: (Date) -> String,
        categoryIdentifier: String? = nil,
        userInfo: [AnyHashable: Any] = [:],
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
                categoryIdentifier: categoryIdentifier,
                userInfo: userInfo,
                fireDate: fireDate
            )
        }
    }

    private func scheduleOneOffNotification(
        identifier: String,
        title: String,
        body: String,
        categoryIdentifier: String? = nil,
        userInfo: [AnyHashable: Any] = [:],
        fireDate: Date
    ) async throws {

        removeScheduledNotifications(identifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let categoryIdentifier {
            content.categoryIdentifier = categoryIdentifier
        }
        content.userInfo = userInfo

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
        await center.pendingRequests()
    }

    func debugPendingRequestLines() async -> [String] {
        let requests = await fetchPendingNotificationRequests()

        let lines: [String] = requests
            .sorted(by: { $0.identifier < $1.identifier })
            .map { request in
                if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                    let next = trigger.nextTriggerDate().map(AppDateFormat.abbreviatedDateTime) ?? "unknown"
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
            return String(
                localized: "notification.presetDue.empty",
                defaultValue: "Preset expenses due.",
                comment: "Fallback preset due notification body when no specific preset names are available."
            )
        }

        let clampedMaxNames = max(0, min(2, maxNamesShown))

        func makeBody(shownCount: Int) -> String {
            let shown = Array(uniqueSorted.prefix(shownCount))
            let remaining = max(0, total - shownCount)

            if total == 1 {
                let singleTemplate = String(
                    localized: "notification.presetDue.single",
                    defaultValue: "Preset expected to set sail: %@",
                    comment: "Preset due notification body when exactly one preset name is due."
                )
                return String(format: singleTemplate, locale: .current, uniqueSorted[0])
            }

            if shown.isEmpty {
                return String(
                    format: String(
                        localized: "notification.presetDue.count",
                        defaultValue: "%@ presets due",
                        comment: "Preset due notification body with only a count. Placeholder is localized number."
                    ),
                    locale: .current,
                    localizedInt(total)
                )
            }

            var body = String(
                format: String(
                    localized: "notification.presetDue.list",
                    defaultValue: "Presets docking from your account today: %@",
                    comment: "Preset due notification body listing due preset names."
                ),
                locale: .current,
                shown.joined(separator: ", ")
            )
            if remaining > 0 {
                body += String(
                    format: String(
                        localized: "notification.presetDue.more",
                        defaultValue: " +%@ more",
                        comment: "Suffix for additional preset count in notification body. Placeholder is localized number."
                    ),
                    locale: .current,
                    localizedInt(remaining)
                )
            }
            return body
        }

        for shownCount in stride(from: clampedMaxNames, through: 0, by: -1) {
            let body = makeBody(shownCount: shownCount)
            if body.count <= maxCharacters {
                return body
            }
        }

        if total == 1 {
            return String(
                localized: "notification.presetDue.shortSingle",
                defaultValue: "Preset due",
                comment: "Short fallback preset due body when content must be brief."
            )
        }

        return String(
            format: String(
                localized: "notification.presetDue.count",
                defaultValue: "%@ presets due",
                comment: "Preset due notification body with only a count. Placeholder is localized number."
            ),
            locale: .current,
            localizedInt(total)
        )
    }

    private static var localizedAppName: String {
        String(
            localized: "notification.appName",
            defaultValue: "Offshore Budgeting",
            comment: "App name used as notification title."
        )
    }

    private static func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }

    private func addNotificationRequest(_ request: UNNotificationRequest) async throws {
        try await center.add(request)
    }
}
