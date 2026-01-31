//
//  SettingsNotificationsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI

struct SettingsNotificationsView: View {

    // MARK: - Persisted Settings

    @AppStorage("notifications_enabled") private var notificationsEnabled: Bool = false
    @AppStorage("notifications_reminderHour") private var reminderHour: Int = 20
    @AppStorage("notifications_reminderMinute") private var reminderMinute: Int = 0

    @AppStorage("notifications_dailyExpenseReminderEnabled") private var dailyExpenseReminderEnabled: Bool = false
    @AppStorage("notifications_plannedIncomeReminderEnabled") private var plannedIncomeReminderEnabled: Bool = false
    @AppStorage("notifications_presetDueReminderEnabled") private var presetDueReminderEnabled: Bool = false

    // MARK: - Local UI State

    @State private var notificationsToggle: Bool = false
    @State private var reminderTime: Date = Date()

    @StateObject private var notificationService = LocalNotificationService()

    @State private var showingErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        List {
            // MARK: - Permission

            Section("Permission") {
                Toggle("Enable Notifications", isOn: $notificationsToggle)
                    .tint(Color("AccentColor"))
                    .onChange(of: notificationsToggle) { _, newValue in
                        Task { await handleToggleChange(newValue) }
                    }

                statusRow
            }

            // MARK: - Reminder Time

            Section("Reminder Time") {
                HStack {
                    Text("Time")
                    Spacer()
                    PillTimePickerField(title: "Time", time: $reminderTime)
                }
                .disabled(!canEditReminderTime)
                .onChange(of: reminderTime) { _, newValue in
                    persistReminderTime(newValue)
                    Task { await syncSchedulesIfPossible() }
                }

                Text("This time is shared by all reminders below.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Expenses

            Section("Expenses") {
                Toggle("Daily Expense Reminder", isOn: $dailyExpenseReminderEnabled)
                    .tint(Color("AccentColor"))
                    .disabled(!canEditReminderToggles)
                    .onChange(of: dailyExpenseReminderEnabled) { _, _ in
                        Task { await syncSchedulesIfPossible() }
                    }

                Text("A daily reminder to open the app and log variable expenses.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Income

            Section("Income") {
                Toggle("Planned Income Reminder", isOn: $plannedIncomeReminderEnabled)
                    .tint(Color("AccentColor"))

                    .disabled(!canEditReminderToggles)
                    .onChange(of: plannedIncomeReminderEnabled) { _, _ in
                        Task { await syncSchedulesIfPossible() }
                    }

                Text("A reminder to review income and confirm anything planned for today.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Presets

            Section("Presets") {
                Toggle("Preset Expense Due Reminder", isOn: $presetDueReminderEnabled)
                    .tint(Color("AccentColor"))

                    .disabled(!canEditReminderToggles)
                    .onChange(of: presetDueReminderEnabled) { _, _ in
                        Task { await syncSchedulesIfPossible() }
                    }

                Text("A reminder to review presets that may be due today.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Denied

            if notificationService.authorizationState == .denied {
                Section {
                    Button {
                        notificationService.openSystemSettings()
                    } label: {
                        Label("Open System Settings", systemImage: "gearshape")
                    }

                    Text("Notifications are currently off at the system level. Turn them on in Settings, then come back here.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            /*
            if notificationService.authorizationState == .authorized {
                Section("Testing") {
                    Button("Send Test Notification") {
                        Task { await sendTestNotification() }
                    }
                }
            }
            */
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notifications")
        .task {
            await notificationService.refreshAuthorizationStatus()
            syncUIFromCurrentState()

            reminderTime = makeDate(hour: reminderHour, minute: reminderMinute)

            // If authorized and enabled, make sure schedules match current toggles/time.
            await syncSchedulesIfPossible()
        }
        .alert("Notification Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Computed

    private var canEditReminderTime: Bool {
        notificationService.authorizationState == .authorized && notificationsEnabled
    }

    private var canEditReminderToggles: Bool {
        canEditReminderTime
    }

    // MARK: - UI

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIconName)
                .foregroundStyle(statusIconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))

                Text(statusSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }

    private var statusIconName: String {
        switch notificationService.authorizationState {
        case .authorized: return "checkmark.circle.fill"
        case .denied: return "xmark.octagon.fill"
        case .notDetermined: return "questionmark.circle.fill"
        }
    }

    private var statusIconColor: Color {
        switch notificationService.authorizationState {
        case .authorized: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        }
    }

    private var statusTitle: String {
        switch notificationService.authorizationState {
        case .authorized: return "Allowed"
        case .denied: return "Denied"
        case .notDetermined: return "Not Asked Yet"
        }
    }

    private var statusSubtitle: String {
        switch notificationService.authorizationState {
        case .authorized:
            return notificationsEnabled
            ? "App will send notifications."
            : "Permission is allowed. Use the toggle to turn notifications on."

        case .denied:
            return "Allow notifications in System Settings."

        case .notDetermined:
            return "Turn on the toggle to request permission."
        }
    }

    // MARK: - Actions

    private func syncUIFromCurrentState() {
        if notificationService.authorizationState == .denied {
            notificationsEnabled = false
            notificationsToggle = false
            return
        }

        notificationsToggle = notificationsEnabled
    }

    private func handleToggleChange(_ wantsEnabled: Bool) async {
        if wantsEnabled == false {
            notificationsEnabled = false

            // Cancel our reminder notifications when the app-level toggle is off.
            notificationService.removeScheduledNotifications(identifiers: [
                LocalNotificationService.NotificationID.dailyExpenseReminder,
                LocalNotificationService.NotificationID.plannedIncomeReminder,
                LocalNotificationService.NotificationID.presetDueReminder
            ])

            return
        }

        await notificationService.refreshAuthorizationStatus()

        switch notificationService.authorizationState {
        case .authorized:
            notificationsEnabled = true
            notificationsToggle = true
            await syncSchedulesIfPossible()

        case .notDetermined:
            do {
                let granted = try await notificationService.requestAuthorization()
                if granted {
                    notificationsEnabled = true
                    notificationsToggle = true
                    await syncSchedulesIfPossible()
                } else {
                    notificationsEnabled = false
                    notificationsToggle = false
                }
            } catch {
                notificationsEnabled = false
                notificationsToggle = false
                errorMessage = error.localizedDescription
                showingErrorAlert = true
            }

        case .denied:
            notificationsEnabled = false
            notificationsToggle = false
            errorMessage = "Notifications are denied at the system level. Please enable them in System Settings."
            showingErrorAlert = true
        }
    }

    private func persistReminderTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        reminderHour = components.hour ?? reminderHour
        reminderMinute = components.minute ?? reminderMinute
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(
            bySettingHour: hour,
            minute: minute,
            second: 0,
            of: Date()
        ) ?? Date()
    }

    private func syncSchedulesIfPossible() async {
        await notificationService.refreshAuthorizationStatus()

        guard notificationService.authorizationState == .authorized else { return }

        do {
            try await notificationService.syncDailyReminders(
                notificationsEnabled: notificationsEnabled,
                dailyExpenseEnabled: dailyExpenseReminderEnabled,
                plannedIncomeEnabled: plannedIncomeReminderEnabled,
                presetDueEnabled: presetDueReminderEnabled,
                hour: reminderHour,
                minute: reminderMinute
            )
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    // Keeping your helper intact for later use/testing
    private func sendTestNotification() async {
        do {
            await notificationService.refreshAuthorizationStatus()

            guard notificationService.isAuthorized else {
                errorMessage = "Notifications are not authorized yet."
                showingErrorAlert = true
                return
            }

            guard notificationsEnabled else {
                errorMessage = "Your in-app notifications toggle is off."
                showingErrorAlert = true
                return
            }
        }
    }
}

#Preview("Notifications") {
    NavigationStack { SettingsNotificationsView() }
}
