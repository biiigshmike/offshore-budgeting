//
//  ContentView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {

    // MARK: - Selection

    @AppStorage("selectedWorkspaceID") private var selectedWorkspaceID: String = ""
    @AppStorage("didSeedDefaultWorkspaces") private var didSeedDefaultWorkspaces: Bool = false
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue
    @AppStorage("general_hideFuturePlannedExpenses")
    private var hideFuturePlannedExpenses: Bool = false
    @AppStorage("general_excludeFuturePlannedExpensesFromCalculations")
    private var excludeFuturePlannedExpensesFromCalculations: Bool = false
    @AppStorage("general_hideFutureVariableExpenses")
    private var hideFutureVariableExpenses: Bool = false
    @AppStorage("general_excludeFutureVariableExpensesFromCalculations")
    private var excludeFutureVariableExpensesFromCalculations: Bool = false

    // MARK: - Notifications

    @AppStorage("notifications_enabled") private var notificationsEnabled: Bool = false
    @AppStorage("notifications_reminderHour") private var reminderHour: Int = 20
    @AppStorage("notifications_reminderMinute") private var reminderMinute: Int = 0

    @AppStorage("notifications_dailyExpenseReminderEnabled") private var dailyExpenseReminderEnabled: Bool = false
    @AppStorage("notifications_plannedIncomeReminderEnabled") private var plannedIncomeReminderEnabled: Bool = false
    @AppStorage("notifications_presetDueReminderEnabled") private var presetDueReminderEnabled: Bool = false

    // MARK: - Onboarding

    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false

    // MARK: - Privacy

    @AppStorage("privacy_requireBiometrics") private var requireBiometrics: Bool = false

    // MARK: - iCloud

    @AppStorage("icloud_activeUseCloud") private var activeUseICloud: Bool = false
    @AppStorage("icloud_bootstrapStartedAt") private var iCloudBootstrapStartedAt: Double = 0

    // MARK: - Alerts

    @State private var showingCannotDeleteLastWorkspaceAlert: Bool = false
    @State private var showingWorkspaceDeleteConfirm: Bool = false
    @State private var pendingWorkspaceDelete: (() -> Void)? = nil
    @State private var repairedSavingsWorkspaceIDs: Set<UUID> = []

    // MARK: - SwiftData

    @Query(sort: \Workspace.name, order: .forward)
    private var workspaces: [Workspace]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notificationService = LocalNotificationService()

    // MARK: - Body

    var body: some View {
        AppLockGate(isEnabled: .constant(didCompleteOnboarding && requireBiometrics)) {
            Group {
                if didCompleteOnboarding == false {
                    OnboardingView()
                } else if let selected = selectedWorkspace {
                    AppRootView(
                        workspace: selected,
                        selectedWorkspaceID: $selectedWorkspaceID
                    )
                } else {
                    NavigationStack {
                        WorkspacePickerView(
                            workspaces: workspaces,
                            selectedWorkspaceID: $selectedWorkspaceID,
                            showsCloseButton: false,
                            onCreate: createWorkspace(name:hexColor:),
                            onDelete: deleteWorkspaces
                        )
                    }
                }
            }
            .task {
                let isBootstrapping = ICloudBootstrap.isBootstrapping(
                    useICloud: activeUseICloud,
                    startedAt: iCloudBootstrapStartedAt
                )

                if didCompleteOnboarding {
                    if !isBootstrapping {
                        if !activeUseICloud {
                            seedDefaultWorkspacesIfNeeded()
                        }
                    }
                } else {
                    didSeedDefaultWorkspaces = false
                    if workspaces.isEmpty {
                        selectedWorkspaceID = ""
                    }
                }

                if didCompleteOnboarding, !activeUseICloud, workspaces.isEmpty, !isBootstrapping {
                    didCompleteOnboarding = false
                    didSeedDefaultWorkspaces = false
                    selectedWorkspaceID = ""
                }
            }
            .onAppear {
                // Ensure the widget extension can see the active workspace immediately
                IncomeWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                CardWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                NextPlannedExpenseWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                SpendTrendsWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                syncGeneralSettingsToWidgets()

                refreshIncomeWidgetSnapshotsIfPossible()
                refreshCardWidgetSnapshotsIfPossible()
                refreshNextPlannedExpenseWidgetSnapshotsIfPossible()
                refreshSpendTrendsWidgetSnapshotsIfPossible()
                runSavingsAutoCaptureIfPossible()

                Task { await syncNotificationSchedulesIfPossible() }
            }
            .onChange(of: selectedWorkspaceID) { _, newValue in
                IncomeWidgetSnapshotStore.setSelectedWorkspaceID(newValue)
                CardWidgetSnapshotStore.setSelectedWorkspaceID(newValue)
                NextPlannedExpenseWidgetSnapshotStore.setSelectedWorkspaceID(newValue)
                SpendTrendsWidgetSnapshotStore.setSelectedWorkspaceID(newValue)

                refreshIncomeWidgetSnapshotsIfPossible()
                refreshCardWidgetSnapshotsIfPossible()
                refreshNextPlannedExpenseWidgetSnapshotsIfPossible()
                refreshSpendTrendsWidgetSnapshotsIfPossible()
                runSavingsAutoCaptureIfPossible()

                Task { await syncNotificationSchedulesIfPossible() }
            }
            .onChange(of: defaultBudgetingPeriodRaw) { _, _ in
                syncGeneralSettingsToWidgets()
                refreshIncomeWidgetSnapshotsIfPossible()
                refreshCardWidgetSnapshotsIfPossible()
                refreshNextPlannedExpenseWidgetSnapshotsIfPossible()
                refreshSpendTrendsWidgetSnapshotsIfPossible()
                runSavingsAutoCaptureIfPossible()
            }
            .onChange(of: hideFuturePlannedExpenses) { _, _ in
                syncGeneralSettingsToWidgets()
            }
            .onChange(of: excludeFuturePlannedExpensesFromCalculations) { _, _ in
                syncGeneralSettingsToWidgets()
                refreshCardWidgetSnapshotsIfPossible()
                refreshSpendTrendsWidgetSnapshotsIfPossible()
            }
            .onChange(of: hideFutureVariableExpenses) { _, _ in
                syncGeneralSettingsToWidgets()
            }
            .onChange(of: excludeFutureVariableExpensesFromCalculations) { _, _ in
                syncGeneralSettingsToWidgets()
                refreshCardWidgetSnapshotsIfPossible()
                refreshSpendTrendsWidgetSnapshotsIfPossible()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // fter SwiftData/iCloud finishes loading, the app often
                // becomes active with fresh data. Rebuild snapshots so the widget has options.
                guard newPhase == .active else { return }

                IncomeWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                CardWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                NextPlannedExpenseWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                SpendTrendsWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)

                refreshIncomeWidgetSnapshotsIfPossible()
                refreshCardWidgetSnapshotsIfPossible()
                refreshNextPlannedExpenseWidgetSnapshotsIfPossible()
                refreshSpendTrendsWidgetSnapshotsIfPossible()
                runSavingsAutoCaptureIfPossible()

                Task { await syncNotificationSchedulesIfPossible() }
            }
            .onChange(of: workspaces.count) { _, newCount in
                if activeUseICloud, newCount > 0 {
                    iCloudBootstrapStartedAt = 0
                }

                if didCompleteOnboarding, newCount > 0, selectedWorkspace == nil {
                    selectedWorkspaceID = workspaces.first?.id.uuidString ?? ""
                }

                // when the store populates (especially iCloud), rebuild widget caches.
                IncomeWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                CardWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                NextPlannedExpenseWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)
                SpendTrendsWidgetSnapshotStore.setSelectedWorkspaceID(selectedWorkspaceID)

                refreshIncomeWidgetSnapshotsIfPossible()
                refreshCardWidgetSnapshotsIfPossible()
                refreshNextPlannedExpenseWidgetSnapshotsIfPossible()
                refreshSpendTrendsWidgetSnapshotsIfPossible()
                runSavingsAutoCaptureIfPossible()

                Task { await syncNotificationSchedulesIfPossible() }
            }
            .alert("You must keep at least one workspace.", isPresented: $showingCannotDeleteLastWorkspaceAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Create another workspace first, then you can delete this one.")
            }
            .alert("Delete?", isPresented: $showingWorkspaceDeleteConfirm) {
                Button("Delete", role: .destructive) {
                    pendingWorkspaceDelete?()
                    pendingWorkspaceDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingWorkspaceDelete = nil
                }
            }
        }
    }

    // MARK: - Widget Refresh

    private func refreshIncomeWidgetSnapshotsIfPossible() {
        guard let id = UUID(uuidString: selectedWorkspaceID) else { return }
        IncomeWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: modelContext,
            workspaceID: id
        )
    }

    private func refreshCardWidgetSnapshotsIfPossible() {
        guard let id = UUID(uuidString: selectedWorkspaceID) else { return }
        CardWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: modelContext,
            workspaceID: id
        )
    }

    private func refreshNextPlannedExpenseWidgetSnapshotsIfPossible() {
        guard let id = UUID(uuidString: selectedWorkspaceID) else { return }
        NextPlannedExpenseWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: modelContext,
            workspaceID: id
        )
    }

    private func refreshSpendTrendsWidgetSnapshotsIfPossible() {
        guard let id = UUID(uuidString: selectedWorkspaceID) else { return }
        SpendTrendsWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: modelContext,
            workspaceID: id
        )
    }

    private func syncGeneralSettingsToWidgets() {
        guard let defaults = UserDefaults(suiteName: IncomeWidgetSnapshotStore.appGroupID) else { return }
        defaults.set(defaultBudgetingPeriodRaw, forKey: "general_defaultBudgetingPeriod")
        defaults.set(hideFuturePlannedExpenses, forKey: "general_hideFuturePlannedExpenses")
        defaults.set(
            excludeFuturePlannedExpensesFromCalculations,
            forKey: "general_excludeFuturePlannedExpensesFromCalculations"
        )
        defaults.set(hideFutureVariableExpenses, forKey: "general_hideFutureVariableExpenses")
        defaults.set(
            excludeFutureVariableExpensesFromCalculations,
            forKey: "general_excludeFutureVariableExpensesFromCalculations"
        )
    }

    private func runSavingsAutoCaptureIfPossible() {
        if DebugScreenshotFormDefaults.isEnabled {
            return
        }

        guard let workspace = selectedWorkspace else { return }
        let workspaceID = workspace.id

        if !repairedSavingsWorkspaceIDs.contains(workspaceID) {
            _ = SavingsAccountService.normalizeSavingsData(for: workspace, modelContext: modelContext)
            repairedSavingsWorkspaceIDs.insert(workspaceID)
        }

        let incomeDescriptor = FetchDescriptor<Income>(
            predicate: #Predicate<Income> { $0.workspace?.id == workspaceID }
        )
        let plannedDescriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { $0.workspace?.id == workspaceID }
        )
        let variableDescriptor = FetchDescriptor<VariableExpense>(
            predicate: #Predicate<VariableExpense> { $0.workspace?.id == workspaceID }
        )

        let incomes = (try? modelContext.fetch(incomeDescriptor)) ?? []
        let plannedExpenses = (try? modelContext.fetch(plannedDescriptor)) ?? []
        let variableExpenses = (try? modelContext.fetch(variableDescriptor)) ?? []

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: workspace,
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            modelContext: modelContext
        )
    }

    // MARK: - Notification Sync

    private func syncNotificationSchedulesIfPossible() async {
        guard didCompleteOnboarding else { return }
        guard let workspaceID = UUID(uuidString: selectedWorkspaceID) else { return }

        await notificationService.refreshAuthorizationStatus()
        guard notificationService.isAuthorized else { return }

        do {
            try await notificationService.syncReminders(
                modelContext: modelContext,
                workspaceID: workspaceID,
                notificationsEnabled: notificationsEnabled,
                dailyExpenseEnabled: dailyExpenseReminderEnabled,
                plannedIncomeEnabled: plannedIncomeReminderEnabled,
                presetDueEnabled: presetDueReminderEnabled,
                hour: reminderHour,
                minute: reminderMinute
            )
        } catch {
            // intentionally ignoring errors here so notifications never block app startup.
        }
    }

    // MARK: - Derived

    private var selectedWorkspace: Workspace? {
        guard let uuid = UUID(uuidString: selectedWorkspaceID) else { return nil }
        return workspaces.first(where: { $0.id == uuid })
    }

    // MARK: - Seeding

    private func seedDefaultWorkspacesIfNeeded() {
        if !workspaces.isEmpty {
            didSeedDefaultWorkspaces = true

            if selectedWorkspace == nil {
                selectedWorkspaceID = workspaces.first?.id.uuidString ?? ""
            }
            return
        }

        if didSeedDefaultWorkspaces == false || workspaces.isEmpty {
            let personal = Workspace(name: "Personal", hexColor: "#3B82F6")
            let work = Workspace(name: "Work", hexColor: "#10B981")

            modelContext.insert(personal)
            modelContext.insert(work)

            selectedWorkspaceID = personal.id.uuidString
            didSeedDefaultWorkspaces = true
        }
    }

    // MARK: - Actions

    private func createWorkspace(name: String, hexColor: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHex = hexColor.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else { return }

        let workspace = Workspace(
            name: trimmedName,
            hexColor: trimmedHex.isEmpty ? "#3B82F6" : trimmedHex
        )

        modelContext.insert(workspace)
        selectedWorkspaceID = workspace.id.uuidString
    }

    private func deleteWorkspaces(at offsets: IndexSet) {
        let remainingIndices = workspaces.indices.filter { !offsets.contains($0) }
        guard !remainingIndices.isEmpty else {
            showingCannotDeleteLastWorkspaceAlert = true
            return
        }

        let workspacesToDelete = offsets.compactMap { index in
            workspaces.indices.contains(index) ? workspaces[index] : nil
        }

        let deletedIDs = workspacesToDelete.map { $0.id.uuidString }
        let willDeleteSelected = deletedIDs.contains(selectedWorkspaceID)
        let fallbackSelectedID = workspaces[remainingIndices[0]].id.uuidString

        if confirmBeforeDeleting {
            pendingWorkspaceDelete = {
                for workspace in workspacesToDelete {
                    modelContext.delete(workspace)
                }

                if willDeleteSelected {
                    selectedWorkspaceID = fallbackSelectedID
                }
            }
            showingWorkspaceDeleteConfirm = true
        } else {
            for workspace in workspacesToDelete {
                modelContext.delete(workspace)
            }

            if willDeleteSelected {
                selectedWorkspaceID = fallbackSelectedID
            }
        }
    }
}
