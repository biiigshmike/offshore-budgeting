import SwiftUI
import SwiftData

/// Choices remain a draft until Continue; opening or dismissing setup never changes preferences.
struct ReminderSetupView: View {
    let workspaceID: UUID
    @ObservedObject var notificationService: LocalNotificationService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var preferences = ReminderPreferences.setupDraft()
    @State private var reminderTime = ReminderPreferences.setupDraft().time
    @State private var isSaving = false
    @State private var errorMessage = ""
    @State private var showingError = false
    @State private var showingBlockedInfo = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $preferences.daily) {
                        VStack(alignment: .leading) {
                            Text("Daily Expense Reminder")
                            Text("A daily nudge to log your expenses.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("reminderSetupDaily")
                    Toggle(isOn: $preferences.income) {
                        VStack(alignment: .leading) {
                            Text("Planned Income")
                            Text("On days you have planned income.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("reminderSetupIncome")
                    Toggle(isOn: $preferences.preset) {
                        VStack(alignment: .leading) {
                            Text("Preset Expense Due")
                            Text("On days preset expenses are due.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("reminderSetupPreset")
                } header: {
                    Text("Choose Your Reminders")
                } footer: {
                    Text("You can change these choices anytime in Settings.")
                }

                Section {
                    DatePicker("Reminder Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                } footer: {
                    Text("All reminders use this time. If needed, the next step asks for system permission to send notifications.")
                }
            }
            .tint(Color("AccentColor"))
            .disabled(isSaving)
            .navigationTitle("Set Up Reminders")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .disabled(isSaving)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text("Continue")
                    }
                    .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("reminderSetupContinue")
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isSaving)
                .padding()
                .background(.bar)
            }
        }
        .interactiveDismissDisabled(isSaving)
        .task { await notificationService.refreshAuthorizationStatus() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await notificationService.refreshAuthorizationStatus() }
            }
        }
        .alert("Reminder Setup Could Not Finish", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Reminders Are Off", isPresented: $showingBlockedInfo) {
            Button("Done", role: .cancel) { dismiss() }
            Button("Open Settings") {
                notificationService.openSystemSettings()
                dismiss()
            }
        } message: {
            Text("Your reminder choices are saved. Notifications are blocked in System Settings; you can allow them there, then turn on Send Scheduled Reminders in the app.")
        }
    }

    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        preferences.setTime(reminderTime)
        do {
            try await notificationService.configureReminders(
                preferences, modelContext: modelContext, workspaceID: workspaceID
            )
            if preferences.hasSelectedReminders && !notificationService.isAuthorized {
                showingBlockedInfo = true
            } else {
                dismiss()
            }
        } catch {
            errorMessage = String(localized: "Your reminder choices are saved, but setup could not finish.")
                + "\n" + error.localizedDescription
            showingError = true
        }
    }
}
