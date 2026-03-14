//
//  ContentView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    let initialSectionOverride: AppSection?

    init(initialSectionOverride: AppSection? = nil) {
        self.initialSectionOverride = initialSectionOverride
    }

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

    // MARK: - SwiftData

    @Query(sort: \Workspace.name, order: .forward)
    private var workspaces: [Workspace]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var notificationService = LocalNotificationService()
    @State private var resumeCoordinator = ContentViewResumeCoordinator()
    @State private var deferredResumeTask: Task<Void, Never>? = nil

    // MARK: - Body

    var body: some View {
        AppLockGate(isEnabled: .constant(didCompleteOnboarding && requireBiometrics)) {
            Group {
                if didCompleteOnboarding == false {
                    OnboardingView()
                } else if let selected = selectedWorkspace {
                    AppRootView(
                        workspace: selected,
                        selectedWorkspaceID: $selectedWorkspaceID,
                        initialSectionOverride: initialSectionOverride
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
                let discoveryPhase = ICloudBootstrap.workspaceDiscoveryPhase(
                    useICloud: activeUseICloud,
                    startedAt: iCloudBootstrapStartedAt,
                    workspaceCount: workspaces.count
                )
                let isBootstrapping = discoveryPhase == .loading || discoveryPhase == .loadingSlow

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
                performImmediateResumeWiring()
                scheduleDeferredResumeRefresh(
                    includesWidgets: true,
                    includesSavings: true,
                    includesNotifications: true
                )
            }
            .onChange(of: selectedWorkspaceID) { _, newValue in
                syncSelectedWorkspaceToWidgetStores(newValue)
                scheduleDeferredResumeRefresh(
                    includesWidgets: true,
                    includesSavings: true,
                    includesNotifications: true
                )
            }
            .onChange(of: defaultBudgetingPeriodRaw) { _, _ in
                syncGeneralSettingsToWidgets()
                scheduleDeferredResumeRefresh(
                    includesWidgets: true,
                    includesSavings: true,
                    includesNotifications: false
                )
            }
            .onChange(of: hideFuturePlannedExpenses) { _, _ in
                syncGeneralSettingsToWidgets()
            }
            .onChange(of: excludeFuturePlannedExpensesFromCalculations) { _, _ in
                syncGeneralSettingsToWidgets()
                scheduleDeferredResumeRefresh(
                    includesWidgets: true,
                    includesSavings: false,
                    includesNotifications: false
                )
            }
            .onChange(of: hideFutureVariableExpenses) { _, _ in
                syncGeneralSettingsToWidgets()
            }
            .onChange(of: excludeFutureVariableExpensesFromCalculations) { _, _ in
                syncGeneralSettingsToWidgets()
                scheduleDeferredResumeRefresh(
                    includesWidgets: true,
                    includesSavings: false,
                    includesNotifications: false
                )
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    performImmediateResumeWiring()
                    scheduleDeferredResumeRefresh(
                        includesWidgets: true,
                        includesSavings: true,
                        includesNotifications: true
                    )
                } else {
                    cancelDeferredResumeRefresh()
                }
            }
            .onChange(of: workspaces.count) { _, newCount in
                if activeUseICloud, newCount > 0 {
                    ICloudBootstrap.logFirstWorkspaceAppearance(
                        startedAt: iCloudBootstrapStartedAt,
                        workspaceCount: newCount
                    )
                    iCloudBootstrapStartedAt = 0
                }

                if didCompleteOnboarding, newCount > 0, selectedWorkspace == nil {
                    selectedWorkspaceID = workspaces.first?.id.uuidString ?? ""
                }

                performImmediateResumeWiring()
                scheduleDeferredResumeRefresh(
                    includesWidgets: true,
                    includesSavings: true,
                    includesNotifications: true
                )
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

    private enum ResumeScheduling {
        static let initialDelayNanos: UInt64 = 250_000_000
        static let savingsDelayNanos: UInt64 = 700_000_000
    }

    @MainActor
    private func performImmediateResumeWiring() {
        syncSelectedWorkspaceToWidgetStores(selectedWorkspaceID)
        syncGeneralSettingsToWidgets()
    }

    @MainActor
    private func syncSelectedWorkspaceToWidgetStores(_ workspaceID: String) {
        IncomeWidgetSnapshotStore.setSelectedWorkspaceID(workspaceID)
        CardWidgetSnapshotStore.setSelectedWorkspaceID(workspaceID)
        NextPlannedExpenseWidgetSnapshotStore.setSelectedWorkspaceID(workspaceID)
        SpendTrendsWidgetSnapshotStore.setSelectedWorkspaceID(workspaceID)
    }

    @MainActor
    private func scheduleDeferredResumeRefresh(
        includesWidgets: Bool,
        includesSavings: Bool,
        includesNotifications: Bool
    ) {
        let request = resumeCoordinator.schedule(
            widgetSignature: includesWidgets ? widgetRefreshSignature : nil,
            savingsSignature: includesSavings ? savingsRefreshSignature : nil,
            notificationSignature: includesNotifications ? notificationRefreshSignature : nil
        )

        guard let request else { return }

        deferredResumeTask?.cancel()
        deferredResumeTask = Task {
            try? await Task.sleep(nanoseconds: ResumeScheduling.initialDelayNanos)
            guard Task.isCancelled == false else { return }

            let shouldContinue = await MainActor.run { resumeCoordinator.isCurrent(request) }
            guard shouldContinue else { return }

            if request.widgetSignature != nil {
                await MainActor.run {
                    refreshAllWidgetSnapshotsIfPossible()
                    resumeCoordinator.markWidgetRefreshCompleted(request)
                }
            }

            if request.notificationSignature != nil {
                await syncNotificationSchedulesIfPossible()
                await MainActor.run {
                    resumeCoordinator.markNotificationRefreshCompleted(request)
                }
            }

            guard request.savingsSignature != nil else { return }

            try? await Task.sleep(nanoseconds: ResumeScheduling.savingsDelayNanos)
            guard Task.isCancelled == false else { return }

            let shouldRunSavings = await MainActor.run { resumeCoordinator.isCurrent(request) }
            guard shouldRunSavings else { return }

            await MainActor.run {
                runSavingsAutoCaptureIfPossible()
                resumeCoordinator.markSavingsRefreshCompleted(request)
            }
        }
    }

    @MainActor
    private func cancelDeferredResumeRefresh() {
        deferredResumeTask?.cancel()
        deferredResumeTask = nil
        resumeCoordinator.cancelPending()
    }

    private var widgetRefreshSignature: ContentViewWidgetRefreshSignature? {
        guard let workspaceID = UUID(uuidString: selectedWorkspaceID) else { return nil }
        return ContentViewWidgetRefreshSignature(
            workspaceID: workspaceID,
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            excludeFuturePlannedExpensesFromCalculations: excludeFuturePlannedExpensesFromCalculations,
            excludeFutureVariableExpensesFromCalculations: excludeFutureVariableExpensesFromCalculations
        )
    }

    private var savingsRefreshSignature: ContentViewSavingsRefreshSignature? {
        guard let workspaceID = UUID(uuidString: selectedWorkspaceID) else { return nil }
        return ContentViewSavingsRefreshSignature(
            workspaceID: workspaceID,
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw
        )
    }

    private var notificationRefreshSignature: ContentViewNotificationRefreshSignature? {
        guard didCompleteOnboarding else { return nil }
        guard let workspaceID = UUID(uuidString: selectedWorkspaceID) else { return nil }
        return ContentViewNotificationRefreshSignature(
            workspaceID: workspaceID,
            notificationsEnabled: notificationsEnabled,
            dailyExpenseReminderEnabled: dailyExpenseReminderEnabled,
            plannedIncomeReminderEnabled: plannedIncomeReminderEnabled,
            presetDueReminderEnabled: presetDueReminderEnabled,
            reminderHour: reminderHour,
            reminderMinute: reminderMinute
        )
    }

    @MainActor
    private func refreshAllWidgetSnapshotsIfPossible() {
        refreshIncomeWidgetSnapshotsIfPossible()
        refreshCardWidgetSnapshotsIfPossible()
        refreshNextPlannedExpenseWidgetSnapshotsIfPossible()
        refreshSpendTrendsWidgetSnapshotsIfPossible()
    }

    @MainActor
    private func refreshIncomeWidgetSnapshotsIfPossible() {
        guard let id = UUID(uuidString: selectedWorkspaceID) else { return }
        IncomeWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: modelContext,
            workspaceID: id
        )
    }

    @MainActor
    private func refreshCardWidgetSnapshotsIfPossible() {
        guard let id = UUID(uuidString: selectedWorkspaceID) else { return }
        CardWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: modelContext,
            workspaceID: id
        )
    }

    @MainActor
    private func refreshNextPlannedExpenseWidgetSnapshotsIfPossible() {
        guard let id = UUID(uuidString: selectedWorkspaceID) else { return }
        NextPlannedExpenseWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: modelContext,
            workspaceID: id
        )
    }

    @MainActor
    private func refreshSpendTrendsWidgetSnapshotsIfPossible() {
        guard let id = UUID(uuidString: selectedWorkspaceID) else { return }
        SpendTrendsWidgetSnapshotBuilder.buildAndSaveAllPeriods(
            modelContext: modelContext,
            workspaceID: id
        )
    }

    @MainActor
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

    @MainActor
    private func runSavingsAutoCaptureIfPossible() {
        if DebugScreenshotFormDefaults.isEnabled {
            return
        }

        guard let workspace = selectedWorkspace else { return }
        let workspaceID = workspace.id
        _ = SavingsAccountService.normalizeSavingsData(for: workspace, modelContext: modelContext)

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

    @MainActor
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
