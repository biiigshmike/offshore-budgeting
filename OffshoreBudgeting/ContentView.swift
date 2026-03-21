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
    let resumeState: ContentViewResumeState
    private let widgetRefreshExecutor: ContentViewWidgetRefreshExecutor

    init(
        initialSectionOverride: AppSection? = nil,
        resumeState: ContentViewResumeState,
        modelContainer: ModelContainer
    ) {
        self.initialSectionOverride = initialSectionOverride
        self.resumeState = resumeState
        self.widgetRefreshExecutor = ContentViewWidgetRefreshExecutor(modelContainer: modelContainer)
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
    @Query private var allIncomes: [Income]
    @Query private var allPlannedExpenses: [PlannedExpense]
    @Query private var allVariableExpenses: [VariableExpense]

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
                        selectedWorkspaceID: $selectedWorkspaceID,
                        initialSectionOverride: initialSectionOverride,
                        onTabInteraction: handleTabInteraction
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
                traceResume("contentView onAppear")
                TabFlickerDiagnostics.beginWatch(
                    reason: "coldLaunch",
                    metadata: ["selectedWorkspaceID": selectedWorkspaceID],
                    duration: 2.5
                )
                TabFlickerDiagnostics.markEvent(
                    "contentViewOnAppear",
                    metadata: ["selectedWorkspaceID": selectedWorkspaceID]
                )
                performImmediateResumeWiring()
                scheduleDeferredResumeRefresh(
                    trigger: .initialAppear,
                    includesWidgets: true,
                    includesSavings: true,
                    includesNotifications: true
                )
            }
            .onChange(of: selectedWorkspaceID) { _, newValue in
                syncSelectedWorkspaceToWidgetStores(newValue)
                TabFlickerDiagnostics.markEvent(
                    "selectedWorkspaceChanged",
                    metadata: ["selectedWorkspaceID": newValue]
                )
                scheduleDeferredResumeRefresh(
                    trigger: .workspaceSelectionChanged,
                    includesWidgets: true,
                    includesSavings: true,
                    includesNotifications: true
                )
            }
            .onChange(of: defaultBudgetingPeriodRaw) { _, _ in
                syncGeneralSettingsToWidgets()
                scheduleDeferredResumeRefresh(
                    trigger: .settingsChanged,
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
                    trigger: .settingsChanged,
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
                    trigger: .settingsChanged,
                    includesWidgets: true,
                    includesSavings: false,
                    includesNotifications: false
                )
            }
            .onChange(of: savingsRefreshSignature) { oldValue, newValue in
                guard oldValue != newValue else { return }
                scheduleDeferredResumeRefresh(
                    trigger: .savingsDataChanged,
                    includesWidgets: false,
                    includesSavings: true,
                    includesNotifications: false
                )
            }
            .onChange(of: scenePhase) { _, newPhase in
                traceResume("scenePhase changed=\(debugScenePhase(newPhase))")
                TabFlickerDiagnostics.markEvent(
                    "scenePhaseChanged",
                    metadata: ["phase": debugScenePhase(newPhase)]
                )
                if newPhase == .active {
                    TabFlickerDiagnostics.beginWatch(
                        reason: "sceneResume",
                        metadata: [
                            "phase": "active",
                            "selectedWorkspaceID": selectedWorkspaceID
                        ],
                        duration: 2.0
                    )
                    performImmediateResumeWiring()
                    scheduleDeferredResumeRefresh(
                        trigger: .sceneBecameActive,
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
                    trigger: .workspaceCountChanged,
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
        static let coldLaunchDelayNanos: UInt64 = 1_200_000_000
        static let standardDelayNanos: UInt64 = 450_000_000
        static let savingsDelayNanos: UInt64 = 1_500_000_000
    }

    @MainActor
    private func performImmediateResumeWiring() {
        let start = DispatchTime.now().uptimeNanoseconds
        TabFlickerDiagnostics.markEvent("resumeImmediatePhaseStarted")
        syncSelectedWorkspaceToWidgetStores(selectedWorkspaceID)
        syncGeneralSettingsToWidgets()
        let elapsedMillis = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        TabFlickerDiagnostics.markEvent(
            "resumeImmediatePhaseFinished",
            metadata: ["elapsedMs": String(format: "%.1f", elapsedMillis)]
        )
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
        trigger: ContentViewResumeTrigger,
        includesWidgets: Bool,
        includesSavings: Bool,
        includesNotifications: Bool
    ) {
        let shouldRefreshWidgetsOnForeground = shouldRefreshWidgetsOnForeground()
        let shouldRefreshSavingsOnForeground = shouldRefreshSavingsOnForeground()

        let plan = ContentViewDeferredRefreshPlanner.plan(
            trigger: trigger,
            widgetSignature: includesWidgets ? widgetRefreshSignature : nil,
            savingsSignature: includesSavings ? savingsRefreshSignature : nil,
            notificationSignature: includesNotifications ? notificationRefreshSignature : nil,
            shouldRefreshWidgetsOnForeground: shouldRefreshWidgetsOnForeground,
            shouldRefreshSavingsOnForeground: shouldRefreshSavingsOnForeground
        )

        traceResume(
            "schedule trigger=\(trigger.rawValue) " +
            "widgets=\(plan.widgetSignature != nil) forceWidgets=\(plan.forceWidgetRefresh) " +
            "savings=\(plan.savingsSignature != nil) forceSavings=\(plan.forceSavingsRefresh) " +
            "notifications=\(plan.notificationSignature != nil)"
        )
        TabFlickerDiagnostics.markEvent(
            "resumeRefreshScheduled",
            metadata: [
                "trigger": trigger.rawValue,
                "widgets": plan.widgetSignature != nil ? "true" : "false",
                "forceWidgets": plan.forceWidgetRefresh ? "true" : "false",
                "savings": plan.savingsSignature != nil ? "true" : "false",
                "forceSavings": plan.forceSavingsRefresh ? "true" : "false",
                "notifications": plan.notificationSignature != nil ? "true" : "false"
            ]
        )

        let request = resumeState.schedule(plan: plan)
        guard let request else { return }
        let initialDelayNanos = initialDelayNanos(for: trigger)

        resumeState.replaceDeferredResumeTask(Task {
            try? await Task.sleep(nanoseconds: initialDelayNanos)
            guard Task.isCancelled == false else { return }

            let shouldContinue = await MainActor.run { resumeState.coordinator.isCurrent(request) }
            guard shouldContinue else { return }

            if let widgetSignature = request.widgetSignature {
                let shouldRunWidgets = await waitForNavigationQuietPeriod(
                    trigger: trigger,
                    request: request,
                    stage: "widgets"
                )
                guard shouldRunWidgets else { return }

                await MainActor.run {
                    traceResume(
                        "starting widgets trigger=\(trigger.rawValue) workspaceID=\(widgetSignature.workspaceID.uuidString)"
                    )
                    TabFlickerDiagnostics.markEvent(
                        "widgetsRefreshStarted",
                        metadata: [
                            "trigger": trigger.rawValue,
                            "workspaceID": widgetSignature.workspaceID.uuidString
                        ]
                    )
                }

                let widgetReport = await widgetRefreshExecutor.refreshAll(
                    workspaceID: widgetSignature.workspaceID
                )

                await MainActor.run {
                    resumeState.markWidgetRefreshCompleted(request)
                    traceResume(
                        "completed widgets trigger=\(trigger.rawValue) \(widgetReport.traceSummary)"
                    )
                    TabFlickerDiagnostics.markEvent(
                        "widgetsRefreshCompleted",
                        metadata: [
                            "trigger": trigger.rawValue,
                            "summary": widgetReport.traceSummary
                        ]
                    )
                }
            }

            if request.notificationSignature != nil {
                let shouldRunNotifications = await waitForNavigationQuietPeriod(
                    trigger: trigger,
                    request: request,
                    stage: "notifications"
                )
                guard shouldRunNotifications else { return }

                await syncNotificationSchedulesIfPossible()
                await MainActor.run {
                    resumeState.markNotificationRefreshCompleted(request)
                    traceResume("completed notifications trigger=\(trigger.rawValue)")
                    TabFlickerDiagnostics.markEvent(
                        "notificationsRefreshCompleted",
                        metadata: ["trigger": trigger.rawValue]
                    )
                }
            }

            guard request.savingsSignature != nil else { return }

            try? await Task.sleep(nanoseconds: ResumeScheduling.savingsDelayNanos)
            guard Task.isCancelled == false else { return }

            let shouldRunSavings = await MainActor.run { resumeState.coordinator.isCurrent(request) }
            guard shouldRunSavings else { return }

            let shouldContinueSavings = await waitForNavigationQuietPeriod(
                trigger: trigger,
                request: request,
                stage: "savings"
            )
            guard shouldContinueSavings else { return }

            await MainActor.run {
                runSavingsAutoCaptureIfPossible()
                resumeState.markSavingsRefreshCompleted(request)
                traceResume("completed savings trigger=\(trigger.rawValue)")
                TabFlickerDiagnostics.markEvent(
                    "savingsRefreshCompleted",
                    metadata: ["trigger": trigger.rawValue]
                )
            }
        })
    }

    @MainActor
    private func cancelDeferredResumeRefresh() {
        traceResume("cancel deferred refresh")
        TabFlickerDiagnostics.markEvent("resumeRefreshCancelled")
        TabFlickerDiagnostics.endWatch(reason: "coldLaunch")
        TabFlickerDiagnostics.endWatch(reason: "sceneResume")
        resumeState.cancelPending()
    }

    @MainActor
    private func shouldRefreshWidgetsOnForeground(now: Date = .now) -> Bool {
        guard resumeState.lastWidgetRefreshDayStart != nil else { return true }
        let todayStart = Calendar.current.startOfDay(for: now)
        return resumeState.lastWidgetRefreshDayStart != todayStart
    }

    @MainActor
    private func shouldRefreshSavingsOnForeground(now: Date = .now) -> Bool {
        guard let workspace = selectedWorkspace else { return false }
        return SavingsAccountService.shouldRunForegroundAutoCapture(
            for: workspace,
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            modelContext: modelContext,
            now: now
        )
    }

    private func initialDelayNanos(for trigger: ContentViewResumeTrigger) -> UInt64 {
        switch trigger {
        case .initialAppear, .workspaceCountChanged:
            return ResumeScheduling.coldLaunchDelayNanos
        case .sceneBecameActive, .workspaceSelectionChanged, .settingsChanged, .savingsDataChanged:
            return ResumeScheduling.standardDelayNanos
        }
    }

    private func navigationQuietPeriodNanos(for trigger: ContentViewResumeTrigger) -> UInt64 {
        switch trigger {
        case .initialAppear, .sceneBecameActive:
            return 900_000_000
        case .workspaceSelectionChanged, .workspaceCountChanged, .settingsChanged, .savingsDataChanged:
            return 0
        }
    }

    private func waitForNavigationQuietPeriod(
        trigger: ContentViewResumeTrigger,
        request: ContentViewDeferredRefreshRequest,
        stage: String
    ) async -> Bool {
        let quietPeriodNanos = navigationQuietPeriodNanos(for: trigger)
        guard quietPeriodNanos > 0 else { return true }

        while true {
            let shouldContinue = await MainActor.run { resumeState.coordinator.isCurrent(request) }
            guard shouldContinue else { return false }

            let hasRecentInteraction = await MainActor.run {
                resumeState.hasRecentUserInteraction(within: quietPeriodNanos)
            }
            guard hasRecentInteraction == false else {
                await MainActor.run {
                    TabFlickerDiagnostics.markEvent(
                        "resumeRefreshPostponedForInteraction",
                        metadata: [
                            "trigger": trigger.rawValue,
                            "stage": stage
                        ]
                    )
                }
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard Task.isCancelled == false else { return false }
                continue
            }

            return true
        }
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
        guard let dataSignature = savingsDataSignature(workspaceID: workspaceID) else { return nil }
        return ContentViewSavingsRefreshSignature(
            workspaceID: workspaceID,
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            dataSignature: dataSignature
        )
    }

    private func savingsDataSignature(workspaceID: UUID) -> ContentViewSavingsDataSignature? {
        let incomes = allIncomes.filter { $0.workspace?.id == workspaceID }
        let plannedExpenses = allPlannedExpenses.filter { $0.workspace?.id == workspaceID }
        let variableExpenses = allVariableExpenses.filter { $0.workspace?.id == workspaceID }

        guard !(incomes.isEmpty && plannedExpenses.isEmpty && variableExpenses.isEmpty) else {
            return ContentViewSavingsDataSignature(
                incomeCount: 0,
                incomeLatestUpdateStamp: 0,
                incomeTotalCents: 0,
                plannedExpenseCount: 0,
                plannedExpenseLatestUpdateStamp: 0,
                plannedExpenseTotalCents: 0,
                variableExpenseCount: 0,
                variableExpenseLatestUpdateStamp: 0,
                variableExpenseTotalCents: 0
            )
        }

        return ContentViewSavingsDataSignature(
            incomeCount: incomes.count,
            incomeLatestUpdateStamp: latestDateStamp(for: incomes.map(\.date)),
            incomeTotalCents: totalCents(for: incomes.map(\.amount)),
            plannedExpenseCount: plannedExpenses.count,
            plannedExpenseLatestUpdateStamp: latestDateStamp(for: plannedExpenses.map(\.expenseDate)),
            plannedExpenseTotalCents: totalCents(for: plannedExpenses.map { $0.plannedAmount + $0.actualAmount }),
            variableExpenseCount: variableExpenses.count,
            variableExpenseLatestUpdateStamp: latestDateStamp(for: variableExpenses.map(\.transactionDate)),
            variableExpenseTotalCents: totalCents(for: variableExpenses.map(\.amount))
        )
    }

    private func latestDateStamp(for dates: [Date]) -> Int64 {
        Int64(dates.map(\.timeIntervalSinceReferenceDate).max() ?? 0)
    }

    private func totalCents(for amounts: [Double]) -> Int64 {
        Int64(amounts.reduce(0, +) * 100)
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

    private func traceResume(_ message: String) {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "debug_resumeTraceEnabled") else { return }
        print("[ResumeTrace] \(message)")
        #endif
    }

    private func debugScenePhase(_ phase: ScenePhase) -> String {
        switch phase {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
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
    private func handleTabInteraction(_ section: AppSection) {
        resumeState.recordUserInteraction()
        TabFlickerDiagnostics.markEvent(
            "tabInteractionObserved",
            metadata: ["tab": section.rawValue]
        )
    }

    @MainActor
    private func runSavingsAutoCaptureIfPossible() {
        if DebugScreenshotFormDefaults.isEnabled {
            return
        }

        guard let workspace = selectedWorkspace else { return }
        let start = DispatchTime.now().uptimeNanoseconds
        TabFlickerDiagnostics.markEvent(
            "savingsAutoCaptureStarted",
            metadata: ["workspaceID": workspace.id.uuidString]
        )
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

        let elapsedMillis = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        TabFlickerDiagnostics.markEvent(
            "savingsAutoCaptureFinished",
            metadata: [
                "workspaceID": workspaceID.uuidString,
                "elapsedMs": String(format: "%.1f", elapsedMillis)
            ]
        )
    }

    // MARK: - Notification Sync

    @MainActor
    private func syncNotificationSchedulesIfPossible() async {
        guard didCompleteOnboarding else { return }
        guard let workspaceID = UUID(uuidString: selectedWorkspaceID) else { return }

        let start = DispatchTime.now().uptimeNanoseconds
        TabFlickerDiagnostics.markEvent(
            "notificationsRefreshStarted",
            metadata: ["workspaceID": workspaceID.uuidString]
        )
        await notificationService.refreshAuthorizationStatus()
        guard notificationService.isAuthorized else {
            TabFlickerDiagnostics.markEvent(
                "notificationsRefreshSkipped",
                metadata: [
                    "workspaceID": workspaceID.uuidString,
                    "reason": "notAuthorized"
                ]
            )
            return
        }

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

        let elapsedMillis = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        TabFlickerDiagnostics.markEvent(
            "notificationsRefreshFinished",
            metadata: [
                "workspaceID": workspaceID.uuidString,
                "elapsedMs": String(format: "%.1f", elapsedMillis)
            ]
        )
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
