//
//  SettingsNotificationsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI
import UIKit
import CoreLocation

#if canImport(CoreLocation)
import CoreLocation
import SwiftData
#endif

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
    @State private var showingExcursionSetup = false
    @ObservedObject private var excursionLocation = ShoppingModeLocationService.shared
    @State private var showingExcursionStartAlert = false
    @State private var showingExcursionLocationUnavailable = false
    @State private var selectedExcursionMinutes = 0
    @State private var pendingExcursionMinutes: Int?
    @State private var isRequestingPermission = false
    @Environment(\.scenePhase) private var scenePhase

    @StateObject private var notificationService = LocalNotificationService()
    @StateObject private var shoppingModeManager = ShoppingModeManager.shared

    @Environment(\.modelContext) private var modelContext

    @State private var showingErrorAlert: Bool = false
    @State private var errorMessage: String = ""

    var body: some View {
        List {
            // MARK: - Permission

            Section("Scheduled Reminders") {
                Toggle("Send Scheduled Reminders", isOn: $notificationsEnabled)
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
                    .tint(Color("AccentColor"))

                    .disabled(isRequestingPermission)
                    .onChange(of: presetDueReminderEnabled) { _, _ in
                        Task { await syncSchedulesIfPossible() }
                    }

                Text("A reminder to review presets that may be due today.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // MARK: - Excursion Mode

            if isExcursionControlsAvailable {
                Section("Excursion Mode") {
                    if shoppingModeManager.status.isActive, let expiresAt = shoppingModeManager.status.expiresAt {
                        LabeledContent("Status") {
                            Text(shoppingModeManager.locationCapability.canMonitor ? "Active" : "Paused")
                                .foregroundStyle(shoppingModeManager.locationCapability.canMonitor ? .green : .secondary)
                        }

                        LabeledContent("Ends") {
                            Text(expiresAt, format: .dateTime.hour().minute())
                        }

                        Button("Stop Excursion Mode", role: .destructive) {
                            shoppingModeManager.end()
                        }
                    } else {
                        LabeledContent("Status") {
                            Text("Inactive")
                                .foregroundStyle(.secondary)
                        }

                        Menu("Start Excursion Mode") {
                            #if DEBUG
                            Button("1 minute") {
                                Task { await startDebugExcursionMode(minutes: 1) }
                            }
                            #endif
                            Button("1 hour") {
                                Task { await startExcursionMode(hours: 1) }
                            }
                            Button("2 hours") {
                                Task { await startExcursionMode(hours: 2) }
                            }
                            Button("4 hours") {
                                Task { await startExcursionMode(hours: 4) }
                            }
                        }
                    }

                    Text(locationStatusText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if shoppingModeManager.status.isActive {
                        switch shoppingModeManager.locationCapability {
                        case .foregroundOnly, .paused:
                            Button("Allow background reminders") { showLocationSetup() }
                        case .needsPermission, .denied:
                            Button("Set Up Location") { showLocationSetup() }
                        case .background, .restricted:
                            EmptyView()
                        }
                    }
                }
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
            shoppingModeManager.refreshIfExpired()
            await notificationService.refreshAuthorizationStatus()
            reminderTime = ReminderPreferences.load().time
            await syncSchedulesIfPossible()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                advanceExcursionStart()
                Task { await syncSchedulesIfPossible() }
            }
        }
        .appSheet(isPresented: $showingReminderSetup, onDismiss: {
            reminderTime = ReminderPreferences.load().time
        }) {
            ReminderSetupView(workspaceID: workspaceID, notificationService: notificationService)
                .presentationDetents([.large])
        }
        .appSheet(isPresented: $showingExcursionSetup) {
            ExcursionLocationSetupView()
                .presentationDetents([.large])
        }
        .onChange(of: excursionLocation.authorizationStatus) { _, _ in
            advanceExcursionStart()
        }
        .alert("Get nearby reminders while you’re out", isPresented: $showingExcursionStartAlert) {
            Button("Continue") { beginExcursionLocationRequest() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("For reminders when Offshore is closed, choose Allow While Using App first, then Change to Always Allow. If you choose Allow Once, reminders work only while Offshore is open.")
        }
        .alert("Location access is off", isPresented: $showingExcursionLocationUnavailable) {
            if excursionLocation.authorizationStatus == .denied {
                Button("Open Settings") { notificationService.openSystemSettings() }
            }
            Button("Dismiss", role: .cancel) { }
        } message: {
            Text(excursionLocation.capability.statusText)
        }
        .blocksAutomaticExpenseReview(
            while: showingErrorAlert || showingExcursionStartAlert || showingExcursionLocationUnavailable
        )
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

    private var isExcursionControlsAvailable: Bool {
        #if targetEnvironment(macCatalyst)
        return false
        #else
        return true
        #endif
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

    private func startExcursionMode(hours: Int) async {
        await prepareExcursion(minutes: hours * 60)
    }

    #if DEBUG
    private func startDebugExcursionMode(minutes: Int) async {
        await prepareExcursion(minutes: minutes)
    }
    #endif

    private func showLocationSetup() {
        pendingExcursionMinutes = nil
        showingExcursionSetup = true
    }

    private func prepareExcursion(minutes: Int) async {
        guard pendingExcursionMinutes == nil else { return }
        switch excursionLocation.currentAuthorizationStatus() {
        case .authorizedAlways:
            await activateExcursion(minutes: minutes)
        case .notDetermined, .authorizedWhenInUse:
            selectedExcursionMinutes = minutes
            showingExcursionStartAlert = true
        default:
            showingExcursionLocationUnavailable = true
        }
    }

    private func beginExcursionLocationRequest() {
        pendingExcursionMinutes = selectedExcursionMinutes
        if excursionLocation.currentAuthorizationStatus() == .notDetermined {
            excursionLocation.requestAuthorizationForExcursionMode()
        } else {
            advanceExcursionStart()
        }
    }

    private func advanceExcursionStart() {
        guard let minutes = pendingExcursionMinutes, scenePhase == .active,
              UIApplication.shared.applicationState == .active else { return }

        let status = excursionLocation.currentAuthorizationStatus()
        guard status != .notDetermined else { return }
        pendingExcursionMinutes = nil
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            if status == .authorizedWhenInUse {
                excursionLocation.requestAuthorizationForExcursionMode()
            }
            // A declined or suppressed upgrade may leave authorization unchanged.
            Task { await activateExcursion(minutes: minutes) }
        default:
            showingExcursionLocationUnavailable = true
        }
    }

    private func activateExcursion(minutes: Int) async {
        let result: ShoppingModeStartResult
        #if DEBUG
        if minutes < 60 {
            result = await shoppingModeManager.start(minutes: minutes)
        } else {
            result = await shoppingModeManager.start(hours: minutes / 60)
        }
        #else
        result = await shoppingModeManager.start(hours: minutes / 60)
        #endif
        if case .blocked(let blockers) = result {
            errorMessage = blockers.map(\.message).joined(separator: "\n")
            showingErrorAlert = true
        }
    }

    private var locationStatusText: String {
        shoppingModeManager.locationCapability.statusText
    }
}

#Preview("Notifications") {
    NavigationStack { SettingsNotificationsView(workspaceID: UUID()) }
}
