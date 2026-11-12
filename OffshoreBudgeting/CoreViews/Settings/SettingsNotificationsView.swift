//
//  SettingsNotificationsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI
import SwiftData

struct SettingsNotificationsView: View {

    let workspaceID: UUID

    // MARK: - Persisted Settings

    @AppStorage(ReminderPreferences.Key.enabled) private var notificationsEnabled: Bool = false
    @AppStorage(ReminderPreferences.Key.hour) private var reminderHour: Int = 20
    @AppStorage(ReminderPreferences.Key.minute) private var reminderMinute: Int = 0

    @AppStorage(ReminderPreferences.Key.daily) private var dailyExpenseReminderEnabled: Bool = false
    @AppStorage(ReminderPreferences.Key.income) private var plannedIncomeReminderEnabled: Bool = false
    @AppStorage(ReminderPreferences.Key.preset) private var presetDueReminderEnabled: Bool = false

    // MARK: - Local UI State

    @State private var reminderTime = ReminderPreferences.load().time
    @State private var showingReminderSetup = false
    @State private var isRequestingPermission = false
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var notificationService = LocalNotificationService()

    @Environment(\.modelContext) private var modelContext

    @State private var showingErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        List {
            // MARK: - Permission

            Section("Scheduled Reminders") {
                Toggle("Send Scheduled Reminders", isOn: $notificationsEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("scheduledRemindersEnabled")
                    .tint(Color("AccentColor"))
                    .disabled(isRequestingPermission)
                    .onChange(of: notificationsEnabled) { _, newValue in
                        Task { await handleToggleChange(newValue) }
                    }

                Text("Controls Daily Expense, Planned Income, and Preset Expense Due reminders. Excursion Mode is managed separately.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ReminderPermissionView(
                    notificationService: notificationService,
                    remindersEnabled: notificationsEnabled,
                    hasSelectedReminders: hasSelectedReminders
                )

                if !hasSelectedReminders {
                    Button("Set Up Reminders", systemImage: "bell.badge") {
                        showingReminderSetup = true
                    }
                }
            }

            // MARK: - Reminder Time

            Section("Reminder Time") {
                HStack {
                    Text("Time")
                    Spacer()
                    PillTimePickerField(title: "Time", time: $reminderTime)
                }
                .disabled(isRequestingPermission)
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
                    .toggleStyle(.switch)
                    .tint(Color("AccentColor"))
                    .disabled(isRequestingPermission)
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
                    .toggleStyle(.switch)
                    .tint(Color("AccentColor"))

                    .disabled(isRequestingPermission)
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
                    .toggleStyle(.switch)
                    .tint(Color("AccentColor"))

                    .disabled(isRequestingPermission)
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
                        Label("Open Settings", systemImage: "gearshape")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Notifications")
        .task {
            await notificationService.refreshAuthorizationStatus()
            reminderTime = ReminderPreferences.load().time
            await syncSchedulesIfPossible()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await syncSchedulesIfPossible() }
            }
        }
        .appSheet(isPresented: $showingReminderSetup, onDismiss: {
            reminderTime = ReminderPreferences.load().time
        }) {
            ReminderSetupView(workspaceID: workspaceID, notificationService: notificationService)
                .presentationDetents([.large])
        }
        .blocksAutomaticExpenseReview(while: showingErrorAlert)
        .alert("Notification Error", isPresented: $showingErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Computed

    private var hasSelectedReminders: Bool {
        dailyExpenseReminderEnabled || plannedIncomeReminderEnabled || presetDueReminderEnabled
    }

    // MARK: - Actions

    private func handleToggleChange(_ wantsEnabled: Bool) async {
        // Initialization and permission refresh never write this preference.
        guard wantsEnabled else {
            await syncSchedulesIfPossible()
            return
        }
        guard hasSelectedReminders else {
            notificationsEnabled = false
            showingReminderSetup = true
            return
        }
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        do {
            await notificationService.refreshAuthorizationStatus()
            if notificationService.authorizationState == .notDetermined {
                _ = try await notificationService.requestAuthorization()
            }
            if !notificationService.isAuthorized {
                notificationsEnabled = false
                errorMessage = String(localized: "Notifications are not allowed. Your reminder choices are saved. You can allow notifications in System Settings.")
                showingErrorAlert = true
            }
            await syncSchedulesIfPossible()
        } catch {
            notificationsEnabled = false
            await syncSchedulesIfPossible()
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }

    private func persistReminderTime(_ date: Date) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        reminderHour = components.hour ?? reminderHour
        reminderMinute = components.minute ?? reminderMinute
    }

    private func syncSchedulesIfPossible() async {
        do {
            try await notificationService.syncReminders(
                modelContext: modelContext, workspaceID: workspaceID,
                preferences: ReminderPreferences.load()
            )
        } catch {
            errorMessage = error.localizedDescription
            showingErrorAlert = true
        }
    }
}

#Preview("Notifications") {
    NavigationStack { SettingsNotificationsView(workspaceID: UUID()) }
}
