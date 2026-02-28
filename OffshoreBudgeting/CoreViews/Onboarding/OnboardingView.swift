//
//  OnboardingView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/25/26.
//

import SwiftUI
import SwiftData
import CloudKit

/// First-run onboarding flow.
///
/// Triggers:
/// - Fresh install: `didCompleteOnboarding == false`
/// - SettingsHelpView -> "Repeat Onboarding" sets didCompleteOnboarding = false
/// - SettingsGeneralView -> "Reset & Erase Content" sets didCompleteOnboarding = false
struct OnboardingView: View {

    private enum Step: Int {
        case welcome = 0
        case workspaces = 1
        case privacy = 2
        case gestures = 3
        case categories = 4
        case cards = 5
        case presets = 6
        case income = 7
        case budgets = 8
        case quickActions = 9
    }
    
    // MARK: - Persisted State
    
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @AppStorage("selectedWorkspaceID") private var selectedWorkspaceID: String = ""
    
    @AppStorage("privacy_requireBiometrics") private var requireBiometrics: Bool = false
    
    @AppStorage("icloud_useCloud") private var desiredUseICloud: Bool = false
    @AppStorage("icloud_activeUseCloud") private var activeUseICloud: Bool = false
    @AppStorage("icloud_bootstrapStartedAt") private var iCloudBootstrapStartedAt: Double = 0
    
    /// Persist step so relaunches and resets don't restart the flow.
    @AppStorage("onboarding_step") private var onboardingStep: Int = 0
    
    @AppStorage("onboarding_didChooseDataSource") private var didChooseDataSource: Bool = false
    @AppStorage("onboarding_didPressGetStarted") private var didPressGetStarted: Bool = false
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue
    
    // MARK: - SwiftData
    
    @Query(sort: \Workspace.name, order: .forward)
    private var workspaces: [Workspace]
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    // MARK: - Local Notifications
    
    @StateObject private var notificationService = LocalNotificationService()
    
    // MARK: - UI
    
    @State private var showingSkipPrompt: Bool = false
    @State private var skipPromptMessage: String = ""
    
    @State private var showingMissingWorkspaceAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false
    @State private var showingGetStartedICloudChoice: Bool = false
    @State private var isCheckingICloudForGetStarted: Bool = false
    @State private var showingRestartRequired: Bool = false
    @State private var didChooseICloudFromGetStarted: Bool = false
    @State private var showingStarterBudgetPrompt: Bool = false
    
    // Drives the “wake up” background motion on the welcome step.
    @State private var isExitingWelcome: Bool = false
    
    // MARK: - Derived
    
    private var currentWorkspace: Workspace? {
        if let uuid = UUID(uuidString: selectedWorkspaceID),
           let found = workspaces.first(where: { $0.id == uuid }) {
            return found
        }
        return workspaces.first
    }
    
    private var isICloudBootstrapping: Bool {
        ICloudBootstrap.isBootstrapping(useICloud: activeUseICloud, startedAt: iCloudBootstrapStartedAt)
    }

    private var finalStepValue: Int {
        Step.quickActions.rawValue
    }
    
    var body: some View {
        GeometryReader { proxy in
            let layout = OnboardingLayoutProfile.resolve(
                containerWidth: proxy.size.width,
                horizontalSizeClass: horizontalSizeClass,
                dynamicTypeSize: dynamicTypeSize
            )

            ZStack {
                if onboardingStep == 0 {
                    WaveBackdrop(isExiting: isExitingWelcome)
                        .ignoresSafeArea()
                }

                VStack(spacing: 0) {
                    stepBody
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, layout.horizontalPadding)
                    .padding(.top, 18)

                    if onboardingStep != 0 {
                        bottomNavBar
                            .padding(.horizontal, layout.horizontalPadding)
                            .padding(.vertical, 14)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            Task { await maybeOfferSkipIfCloudAlreadyHasData() }
        }
        .task(id: iCloudBootstrapStartedAt) {
            await enforceICloudBootstrapTimeoutIfNeeded()
        }
        .onChange(of: workspaces.count) { _, newCount in
            if activeUseICloud, newCount > 0 {
                iCloudBootstrapStartedAt = 0
            }
        }
        .alert("Workspace Required", isPresented: $showingMissingWorkspaceAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Create at least one workspace to continue.")
        }
        .alert("Card Required", isPresented: $showingMissingCardAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Create at least one card to continue.")
        }
        .alert("Existing iCloud Data Detected", isPresented: $showingSkipPrompt) {
            Button("Continue Setup", role: .cancel) { }
            Button("Skip Onboarding", role: .destructive) { completeOnboarding() }
        } message: {
            Text(skipPromptMessage)
        }
        .alert("Use iCloud or Continue Locally?", isPresented: $showingGetStartedICloudChoice) {
            Button("Use iCloud") { startUsingICloudFromGetStarted() }
            Button("Continue Locally", role: .cancel) { startLocalFromGetStarted() }
        } message: {
            Text("This Apple ID can sync existing Offshore data from iCloud. You can always switch later from Manage Workspaces.")
        }
        .alert("Create a Starter Budget?", isPresented: $showingStarterBudgetPrompt) {
            Button("Create Budget") {
                if let workspace = currentWorkspace {
                    _ = createStarterBudgetIfNeeded(in: workspace)
                }
                completeOnboarding()
            }
            Button("Skip", role: .cancel) {
                completeOnboarding()
            }
        } message: {
            Text("You can finish now, or create a starter budget so Home has planning context right away.")
        }
        .sheet(isPresented: $showingRestartRequired) {
            RestartRequiredView(
                title: "Restart Required",
                message: AppRestartService.restartRequiredMessage(
                    debugMessage: "Will take effect the next time you quit and relaunch the app."
                ),
                primaryButtonTitle: AppRestartService.nextButtonTitle,
                onPrimary: {
                    AppRestartService.closeAppOrDismiss {
                        showingRestartRequired = false
                        if didChooseICloudFromGetStarted {
                            didChooseICloudFromGetStarted = false
                            goNext()
                        }
                    }
                },
                secondaryButtonTitle: "Not Now",
                onSecondary: {
                    showingRestartRequired = false
                    if didChooseICloudFromGetStarted {
                        didChooseICloudFromGetStarted = false
                        desiredUseICloud = false
                        goNext()
                    }
                }
            )
            .presentationDetents([.large])
        }
    }
    
    // MARK: - Step Body
    
    @ViewBuilder
    private var stepBody: some View {
        switch onboardingStep {
        case Step.welcome.rawValue:
            welcomeStep

        case Step.workspaces.rawValue:
            workspaceStep

        case Step.privacy.rawValue:
            privacyAndSyncStep

        case Step.gestures.rawValue:
            gesturesStep

        case Step.categories.rawValue:
            categoriesStep

        case Step.cards.rawValue:
            cardsStep

        case Step.presets.rawValue:
            presetsStep

        case Step.income.rawValue:
            incomeStep

        case Step.budgets.rawValue:
            budgetsStep

        default:
            quickActionsStep
        }
    }
    
    // MARK: - Step 1: Welcome
    
    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 8)

            Image(systemName: "sailboat.fill")
                .font(.system(size: 46, weight: .semibold))
                .foregroundStyle(.tint)

            Text("Welcome to Offshore Budgeting!")
                .font(.largeTitle.weight(.bold))

            Text("Press the button below to get started setting up your budgeting workspace.")
                .font(.body)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            if #available(iOS 26.0, *) {
                Button {
                    getStartedTapped()
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
                .disabled(isCheckingICloudForGetStarted)

                Spacer(minLength: 18)
            } else {
                Button {
                    getStartedTapped()
                } label: {
                    Text("Get Started")
                        .frame(maxWidth: .infinity, minHeight: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
                .disabled(isCheckingICloudForGetStarted)

                Spacer(minLength: 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    // MARK: - Step 2: Workspaces
    
    private var workspaceStep: some View {
        OnboardingWorkspaceStep(
            workspaces: workspaces,
            selectedWorkspaceID: $selectedWorkspaceID,
            usesICloud: activeUseICloud,
            isICloudBootstrapping: isICloudBootstrapping,
            onCreate: createWorkspace(name:hexColor:)
        )
    }
    
    // MARK: - Step 3: Privacy + Sync + Notifications
    
    private var privacyAndSyncStep: some View {
        OnboardingPrivacySyncStep(
            requireBiometrics: $requireBiometrics,
            hasExistingDataInCurrentStore: !workspaces.isEmpty,
            notificationService: notificationService
        )
    }
    
    // MARK: - Step 4: Gestures & Editing

    private var gesturesStep: some View {
        Group {
            if let ws = currentWorkspace {
                OnboardingGestureTrainingStep(workspace: ws)
            } else {
                if isICloudBootstrapping {
                    iCloudRestorePlaceholder
                } else {
                    ContentUnavailableView(
                        "No Workspace",
                        systemImage: "person.fill",
                        description: Text("Create a workspace first.")
                    )
                }
            }
        }
    }

    // MARK: - Step 5: Categories

    private var categoriesStep: some View {
        Group {
            if let ws = currentWorkspace {
                OnboardingCategoriesStep(workspace: ws)
            } else {
                if isICloudBootstrapping {
                    iCloudRestorePlaceholder
                } else {
                    ContentUnavailableView(
                        "No Workspace",
                        systemImage: "person.fill",
                        description: Text("Create a workspace first.")
                    )
                }
            }
        }
    }
    
    // MARK: - Step 6: Cards
    
    private var cardsStep: some View {
        Group {
            if let ws = currentWorkspace {
                OnboardingCardsStep(workspace: ws)
            } else {
                if isICloudBootstrapping {
                    iCloudRestorePlaceholder
                } else {
                    ContentUnavailableView(
                        "No Workspace",
                        systemImage: "person.fill",
                        description: Text("Create a workspace first.")
                    )
                }
            }
        }
    }

    // MARK: - Step 7: Presets

    private var presetsStep: some View {
        Group {
            if let ws = currentWorkspace {
                OnboardingPresetsStep(workspace: ws)
            } else {
                if isICloudBootstrapping {
                    iCloudRestorePlaceholder
                } else {
                    ContentUnavailableView(
                        "No Workspace",
                        systemImage: "person.fill",
                        description: Text("Create a workspace first.")
                    )
                }
            }
        }
    }

    // MARK: - Step 8: Income

    private var incomeStep: some View {
        Group {
            if let ws = currentWorkspace {
                OnboardingIncomeStep(workspace: ws)
            } else {
                if isICloudBootstrapping {
                    iCloudRestorePlaceholder
                } else {
                    ContentUnavailableView(
                        "No Workspace",
                        systemImage: "person.fill",
                        description: Text("Create a workspace first.")
                    )
                }
            }
        }
    }

    // MARK: - Step 9: Budgets

    private var budgetsStep: some View {
        Group {
            if let ws = currentWorkspace {
                OnboardingBudgetsStep(workspace: ws)
            } else {
                if isICloudBootstrapping {
                    iCloudRestorePlaceholder
                } else {
                    ContentUnavailableView(
                        "No Workspace",
                        systemImage: "person.fill",
                        description: Text("Create a workspace first.")
                    )
                }
            }
        }
    }

    // MARK: - Step 10: Quick Actions

    private var quickActionsStep: some View {
        QuickActionsInstallView(isOnboarding: true)
    }
    
    private var iCloudRestorePlaceholder: some View {
        VStack(spacing: 12) {
            ContentUnavailableView(
                "Setting Up iCloud Sync",
                systemImage: "icloud.and.arrow.down",
                description: Text("Looking for existing workspaces on this Apple ID.")
            )
            ProgressView()
        }
        .padding(.vertical, 10)
    }
    
    // MARK: - Bottom Navigation
    
    private var bottomNavBar: some View {
        HStack(spacing: 12) {
            
            if #available(iOS 26.0, *) {
                Button {
                    goBack()
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.gray)
                .disabled(onboardingStep == 0)
            } else {
                Button {
                    goBack()
                } label: {
                    Text("Back")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
                .disabled(onboardingStep == 0)
            }
            
            if #available(iOS 26.0, *) {
                Button {
                    primaryActionTapped()
                } label: {
                    Text(primaryButtonTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else {
                Button {
                    primaryActionTapped()
                } label: {
                    Text(primaryButtonTitle)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
        }
    }
    
    
    private var primaryButtonTitle: String {
        onboardingStep >= finalStepValue ? "Done" : "Next"
    }
    
    private func primaryActionTapped() {
        // Step-specific gating
        switch onboardingStep {
        case Step.workspaces.rawValue:
            guard !workspaces.isEmpty else {
                showingMissingWorkspaceAlert = true
                return
            }
            
            if selectedWorkspaceID.isEmpty {
                selectedWorkspaceID = (workspaces.first?.id.uuidString ?? "")
            }
            
        case Step.cards.rawValue:
            // Require at least one card before presets.
            if let ws = currentWorkspace {
                let hasCard = hasAtLeastOneCard(in: ws)
                guard hasCard else {
                    showingMissingCardAlert = true
                    return
                }
            }

        case Step.income.rawValue:
            if let ws = currentWorkspace {
                let hasIncome = hasAtLeastOneIncome(in: ws)
                let hasBudget = hasAtLeastOneBudget(in: ws)
                if hasIncome && !hasBudget {
                    _ = createStarterBudgetIfNeeded(in: ws)
                }
            }

        default:
            break
        }

        if onboardingStep >= finalStepValue {
            if let ws = currentWorkspace {
                let hasIncome = hasAtLeastOneIncome(in: ws)
                let hasBudget = hasAtLeastOneBudget(in: ws)
                if !hasIncome && !hasBudget {
                    showingStarterBudgetPrompt = true
                    return
                }
            }
            completeOnboarding()
        } else {
            goNext()
        }
    }
    
    private func returnToDataSource() {
        // Ensure the gate opens directly on the data source screen.
        didPressGetStarted = true
        
        // This flips AppBootstrapRootView back to OnboardingStartGateView.
        didChooseDataSource = false
        
        // Reset onboarding to welcome for when the user comes back through.
        onboardingStep = 0
    }
    
    private func goBack() {
        if onboardingStep == 1 {
            returnToDataSource()
            return
        }
        
        onboardingStep = max(0, onboardingStep - 1)
    }
    
    private func goNext() {
        onboardingStep = min(finalStepValue, onboardingStep + 1)
    }
    
    // MARK: - Get Started
    
    private func getStartedTapped() {
        withAnimation(.easeInOut(duration: 0.55)) {
            isExitingWelcome = true
        }
        
        isCheckingICloudForGetStarted = true
        Task {
            let status = (try? await CKContainer.default().accountStatus()) ?? .couldNotDetermine
            
            await MainActor.run {
                isCheckingICloudForGetStarted = false
                
                let delay: Double = 0.28
                
                if status == .available {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        showingGetStartedICloudChoice = true
                    }
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        goNext()
                    }
                }
            }
        }
    }
    
    private func startLocalFromGetStarted() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            goNext()
        }
    }
    
    
    private func startUsingICloudFromGetStarted() {
        desiredUseICloud = true
        didChooseICloudFromGetStarted = true
        
        if desiredUseICloud == activeUseICloud {
            didChooseICloudFromGetStarted = false
            goNext()
            return
        }
        showingRestartRequired = (desiredUseICloud != activeUseICloud)
    }
    
    // MARK: - Completion
    
    private func completeOnboarding() {
        if selectedWorkspaceID.isEmpty {
            selectedWorkspaceID = workspaces.first?.id.uuidString ?? ""
        }
        
        didCompleteOnboarding = true
        onboardingStep = 0
    }
    
    // MARK: - Workspace Create
    
    private func createWorkspace(name: String, hexColor: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHex = hexColor.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        let workspace = Workspace(
            name: trimmedName,
            hexColor: trimmedHex.isEmpty ? "#3B82F6" : trimmedHex
        )
        
        modelContext.insert(workspace)
        
        // Keep this in sync for downstream onboarding steps.
        selectedWorkspaceID = workspace.id.uuidString
    }
    
    // MARK: - Cards check
    
    private func hasAtLeastOneCard(in workspace: Workspace) -> Bool {
        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { $0.workspace?.id == workspaceID }
        )
        let cards = (try? modelContext.fetch(descriptor)) ?? []
        return !cards.isEmpty
    }

    private func hasAtLeastOneIncome(in workspace: Workspace) -> Bool {
        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<Income>(
            predicate: #Predicate<Income> { $0.workspace?.id == workspaceID }
        )
        let incomes = (try? modelContext.fetch(descriptor)) ?? []
        return !incomes.isEmpty
    }

    private func hasAtLeastOneBudget(in workspace: Workspace) -> Bool {
        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<Budget>(
            predicate: #Predicate<Budget> { $0.workspace?.id == workspaceID }
        )
        let budgets = (try? modelContext.fetch(descriptor)) ?? []
        return !budgets.isEmpty
    }

    @discardableResult
    private func createStarterBudgetIfNeeded(in workspace: Workspace) -> Budget? {
        if hasAtLeastOneBudget(in: workspace) {
            return nil
        }

        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let range = period.defaultRange(containing: .now, calendar: .current)
        let budgetName = BudgetNameSuggestion.suggestedName(
            start: range.start,
            end: range.end,
            calendar: .current
        )

        let budget = Budget(
            name: budgetName,
            startDate: range.start,
            endDate: range.end,
            workspace: workspace
        )
        modelContext.insert(budget)

        let workspaceID = workspace.id
        let cardsDescriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sortBy: [SortDescriptor(\Card.name, order: .forward)]
        )
        let presetsDescriptor = FetchDescriptor<Preset>(
            predicate: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sortBy: [SortDescriptor(\Preset.title, order: .forward)]
        )

        let cards = (try? modelContext.fetch(cardsDescriptor)) ?? []
        let presets = ((try? modelContext.fetch(presetsDescriptor)) ?? []).filter { !$0.isArchived }

        for card in cards {
            modelContext.insert(BudgetCardLink(budget: budget, card: card))
        }

        for preset in presets {
            modelContext.insert(BudgetPresetLink(budget: budget, preset: preset))
            let dates = PresetScheduleEngine.occurrences(for: preset, in: budget)

            for date in dates {
                let plannedExpense = PlannedExpense(
                    title: preset.title,
                    plannedAmount: preset.plannedAmount,
                    actualAmount: 0,
                    expenseDate: date,
                    workspace: workspace,
                    card: preset.defaultCard,
                    category: preset.defaultCategory,
                    sourcePresetID: preset.id,
                    sourceBudgetID: budget.id
                )
                modelContext.insert(plannedExpense)
            }
        }

        return budget
    }
    
    // MARK: - Skip prompt
    
    /// This is a pragmatic check:
    /// - If iCloud is enabled AND we already have workspaces, onboarding is likely redundant.
    /// - If iCloud account is available, we explain why enabling iCloud can pull data from other devices.
    private func maybeOfferSkipIfCloudAlreadyHasData() async {
        // Only offer the prompt on the welcome screen.
        guard onboardingStep == 0 else { return }
        
        // If the store already has data (often after enabling iCloud), offer to skip.
        if activeUseICloud, !workspaces.isEmpty {
            skipPromptMessage = "It looks like iCloud Sync is enabled and data already exists on this Apple ID. You can skip onboarding to jump straight into your existing workspaces."
            showingSkipPrompt = true
            return
        }
        
        // If user is not using iCloud yet, still detect whether their iCloud account is available.
        // This helps message the Step 3 toggle.
        let status = try? await CKContainer.default().accountStatus()
        if status == .available {
            // No-op for now, but this is where enhanced messaging would be handy for later.
        }
    }

    @MainActor
    private func enforceICloudBootstrapTimeoutIfNeeded() async {
        guard onboardingStep == 1 else { return }
        guard activeUseICloud, iCloudBootstrapStartedAt > 0 else { return }
        guard workspaces.isEmpty else { return }

        let startedAtSnapshot = iCloudBootstrapStartedAt
        let nanoseconds = UInt64(ICloudBootstrap.maxWaitSeconds * 1_000_000_000)

        do {
            try await Task.sleep(nanoseconds: nanoseconds)
        } catch {
            return
        }

        guard onboardingStep == 1 else { return }
        guard activeUseICloud else { return }
        guard workspaces.isEmpty else { return }
        guard iCloudBootstrapStartedAt == startedAtSnapshot else { return }

        #if DEBUG
        print("[iCloudBootstrap] Timed out on onboarding workspace step after \(ICloudBootstrap.maxWaitSeconds)s with 0 workspaces.")
        #endif

        iCloudBootstrapStartedAt = 0
    }
}

// MARK: - Step: Workspace Setup

private struct OnboardingWorkspaceStep: View {

    let workspaces: [Workspace]
    @Binding var selectedWorkspaceID: String
    let usesICloud: Bool
    let isICloudBootstrapping: Bool
    let onCreate: (String, String) -> Void

    @Environment(\.modelContext) private var modelContext

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

    private enum SheetRoute: Identifiable {
        case add
        case edit(Workspace)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let workspace):
                return "edit-\(workspace.id.uuidString)"
            }
        }
    }

    @State private var sheetRoute: SheetRoute? = nil
    @State private var showingWorkspaceDeleteConfirm: Bool = false
    @State private var pendingWorkspaceDeleteName: String = ""
    @State private var pendingWorkspaceDelete: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            header(
                title: "Workspaces",
                subtitle: "A Workspace is where your all of your budgeting data lives. You can create multiple workspaces for different budgeting purposes."
            )

            List {
                Section("Workspaces") {
                    WorkspaceListRows(
                        workspaces: workspaces,
                        selectedWorkspaceID: selectedWorkspaceID,
                        usesICloud: usesICloud,
                        isICloudBootstrapping: isICloudBootstrapping,
                        showsSelectionHint: false,
                        onSelect: { workspace in
                            selectedWorkspaceID = workspace.id.uuidString
                        },
                        onEdit: { workspace in
                            sheetRoute = .edit(workspace)
                        },
                        onDelete: { workspace in
                            requestDelete(workspace)
                        }
                    )
                }

                Section {
                    Picker("Default Budgeting Period", selection: defaultBudgetingPeriodBinding) {
                        ForEach(BudgetingPeriod.allCases) { period in
                            Text(period.displayTitle)
                                .tag(period)
                        }
                    }
                    .pickerStyle(.menu)

                    Toggle("Confirm Before Deleting", isOn: $confirmBeforeDeleting)
                    .tint(Color("AccentColor"))
                } header: {
                    Text("Workspace Behaviors")
                } footer: {
                    Text("You can change these later in Settings.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .frame(minHeight: 340)

            if #available(iOS 26.0, *) {
                Button {
                    sheetRoute = .add
                } label: {
                    Label("Add Workspace", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else {
                Button {
                    sheetRoute = .add
                } label: {
                    Label("Add Workspace", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }

            Text("Tip: Try starting with a workspace called Personal. You can always add more later.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .onAppear {
            ensureInitialSelection()
        }
        .onChange(of: workspaces.count) { _, _ in
            ensureInitialSelection()
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .add:
                NavigationStack {
                    AddWorkspaceView(onCreate: onCreate)
                }
            case .edit(let workspace):
                NavigationStack {
                    EditWorkspaceView(workspace: workspace)
                }
            }
        }
        .alert("Delete Workspace?", isPresented: $showingWorkspaceDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingWorkspaceDelete?()
                pendingWorkspaceDelete = nil
                pendingWorkspaceDeleteName = ""
            }
            Button("Cancel", role: .cancel) {
                pendingWorkspaceDelete = nil
                pendingWorkspaceDeleteName = ""
            }
        } message: {
            if pendingWorkspaceDeleteName.isEmpty {
                Text("This workspace will be deleted.")
            } else {
                Text("“\(pendingWorkspaceDeleteName)” will be deleted.")
            }
        }
    }

    private func requestDelete(_ workspace: Workspace) {
        if confirmBeforeDeleting {
            pendingWorkspaceDeleteName = workspace.name
            pendingWorkspaceDelete = {
                delete(workspace)
            }
            showingWorkspaceDeleteConfirm = true
        } else {
            delete(workspace)
        }
    }

    private func delete(_ workspace: Workspace) {
        let fallbackWorkspaceID = workspaces.first(where: { $0.id != workspace.id })?.id.uuidString ?? ""
        let willDeleteSelected = selectedWorkspaceID == workspace.id.uuidString

        modelContext.delete(workspace)

        if willDeleteSelected {
            selectedWorkspaceID = fallbackWorkspaceID
        }
    }

    private func ensureInitialSelection() {
        guard selectedWorkspaceID.isEmpty else { return }
        selectedWorkspaceID = workspaces.first?.id.uuidString ?? ""
    }

    private var defaultBudgetingPeriodBinding: Binding<BudgetingPeriod> {
        Binding(
            get: { BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly },
            set: { defaultBudgetingPeriodRaw = $0.rawValue }
        )
    }

    @ViewBuilder
    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Step: Privacy + iCloud + Notifications

private struct OnboardingPrivacySyncStep: View {
    
    @Binding var requireBiometrics: Bool
    let hasExistingDataInCurrentStore: Bool
    @AppStorage("icloud_useCloud") private var desiredUseICloud: Bool = false
    @AppStorage("icloud_activeUseCloud") private var activeUseICloud: Bool = false
    
    @ObservedObject var notificationService: LocalNotificationService
    
    @State private var biometricsInfo = LocalAuthenticationService.biometricAvailability()
    @State private var showingNotificationsDeniedInfo: Bool = false
    @State private var showingICloudSwitchConfirm: Bool = false
    @State private var showingICloudUnavailable: Bool = false
    @State private var showingRestartRequired: Bool = false
    
    private var shouldShowICloudSyncSection: Bool {
        // If the user chose "On Device" as the data source at the start gate,
        // keep onboarding focused and hide iCloud here. They can switch later
        // from Manage Workspaces.
        activeUseICloud
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            header(
                title: shouldShowICloudSyncSection
                    ? "Privacy, iCloud, and Notifications"
                    : "Privacy and Notifications",
                subtitle: shouldShowICloudSyncSection
                    ? "Enable App Lock, iCloud sync, and setup Notifications."
                    : "Enable App Lock and setup Notifications."
            )
            
            Form {
                Section("App Lock") {
                    Toggle(biometricsInfo.kind.displayName, isOn: $requireBiometrics)
                        .tint(Color("AccentColor"))
                        .disabled(!biometricsInfo.isAvailable)
                    
                    
                    if !biometricsInfo.isAvailable {
                        Text(biometricsInfo.errorMessage ?? "Biometrics are not available on this device.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("When enabled, you’ll be asked to authenticate whenever the app opens.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                
                if shouldShowICloudSyncSection {
                    Section("iCloud Sync") {
                        Toggle("Enable iCloud Sync", isOn: Binding(
                            get: { desiredUseICloud },
                            set: { wantsEnabled in
                                handleICloudToggleChanged(wantsEnabled: wantsEnabled)
                            }
                        )).tint(Color("AccentColor"))

                        
                        Text("Use iCloud to sync your workspaces and budgets across your devices signed into this Apple ID.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Notifications") {
                    notificationRow
                }
            }
            .scrollContentBackground(.hidden)
            
            Spacer(minLength: 0)
        }
        .onAppear {
            biometricsInfo = LocalAuthenticationService.biometricAvailability()
        }
        .alert("iCloud Unavailable", isPresented: $showingICloudUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("To use iCloud sync, sign in to iCloud in the Settings app, then return here and try again.")
        }
        .alert("Switch to iCloud?", isPresented: $showingICloudSwitchConfirm) {
            Button("Switch") {
                desiredUseICloud = true
                if desiredUseICloud != activeUseICloud {
                    showingRestartRequired = true
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Switching to iCloud will show your iCloud data. Your on-device data will remain on this device if you switch back later.")
        }
        .sheet(isPresented: $showingRestartRequired) {
            RestartRequiredView(
                title: "Restart Required",
                message: AppRestartService.restartRequiredMessage(
                    debugMessage: "Will take effect the next time you quit and relaunch the app."
                ),
                primaryButtonTitle: AppRestartService.closeAppButtonTitle,
                onPrimary: { AppRestartService.closeAppOrDismiss { showingRestartRequired = false } },
                secondaryButtonTitle: "Not Now",
                onSecondary: { showingRestartRequired = false }
            )
            .presentationDetents([.large])
        }
        .alert("Notifications Disabled", isPresented: $showingNotificationsDeniedInfo) {
            Button("OK", role: .cancel) { }
            Button("Open Settings") {
                notificationService.openSystemSettings()
            }
        } message: {
            Text("Notifications are currently disabled for Offshore. You can enable them in Settings.")
        }
    }
    
    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }
    
    private func handleICloudToggleChanged(wantsEnabled: Bool) {
        if wantsEnabled {
            guard isICloudAvailable else {
                desiredUseICloud = false
                showingICloudUnavailable = true
                return
            }
            
            if hasExistingDataInCurrentStore {
                desiredUseICloud = false
                showingICloudSwitchConfirm = true
                return
            }
            
            desiredUseICloud = true
            if desiredUseICloud != activeUseICloud {
                showingRestartRequired = true
            }
        } else {
            desiredUseICloud = false
            if desiredUseICloud != activeUseICloud {
                showingRestartRequired = true
            }
        }
    }
    
    @ViewBuilder
    private var notificationRow: some View {
        switch notificationService.authorizationState {
        case .notDetermined:
            Button {
                Task {
                    do {
                        _ = try await notificationService.requestAuthorization()
                        if notificationService.authorizationState == .denied {
                            showingNotificationsDeniedInfo = true
                        } else {}
                    } catch {
                        showingNotificationsDeniedInfo = true
                    }
                }
            } label: {
                Label("Enable Notifications", systemImage: "bell.badge")
            }
            
            Text("Enable reminders for logging expenses and reviewing presets.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            
        case .denied:
            Button {
                showingNotificationsDeniedInfo = true
            } label: {
                Label("Notifications Disabled", systemImage: "bell.slash")
            }
            .foregroundStyle(.secondary)
            
        case .authorized:
            Label("Notifications Enabled", systemImage: "bell.fill")
                .foregroundStyle(.secondary)
        }
    }
    
    @ViewBuilder
    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Step: Categories

private struct OnboardingCategoriesStep: View {
    
    let workspace: Workspace
    
    @Environment(\.modelContext) private var modelContext
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Query private var categories: [Category]
    
    private enum SheetRoute: Identifiable {
        case add
        case edit(Category)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let category):
                return "edit-\(category.id.uuidString)"
            }
        }
    }

    @State private var sheetRoute: SheetRoute? = nil
    @State private var showingCategoryDeleteConfirm: Bool = false
    @State private var pendingCategoryDelete: (() -> Void)? = nil
    
    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id
        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            header(
                title: "Categories",
                subtitle: "Categories help you understand where money goes, groceries, rent, fuel, and more."
            )
            
            List {
                CategoryListRows(
                    categories: categories,
                    onEdit: { category in
                        sheetRoute = .edit(category)
                    },
                    onDelete: { category in
                        deleteCategoryWithOptionalConfirm(category)
                    }
                )
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .frame(minHeight: 260)
            if #available(iOS 26.0, *) {
                Button {
                    sheetRoute = .add
                } label: {
                    Label("Add Category", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else {
                Button {
                    sheetRoute = .add
                } label: {
                    Label("Add Category", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
            Spacer(minLength: 0)
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .add:
                NavigationStack {
                    AddCategoryView(workspace: workspace)
                }
            case .edit(let category):
                NavigationStack {
                    EditCategoryView(workspace: workspace, category: category)
                }
            }
        }
        .alert("Delete?", isPresented: $showingCategoryDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingCategoryDelete?()
                pendingCategoryDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCategoryDelete = nil
            }
        }
    }

    private func deleteCategoryWithOptionalConfirm(_ category: Category) {
        if confirmBeforeDeleting {
            pendingCategoryDelete = {
                modelContext.delete(category)
            }
            showingCategoryDeleteConfirm = true
        } else {
            modelContext.delete(category)
        }
    }
    
    @ViewBuilder
    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Step: Cards

private struct OnboardingCardsStep: View {
    
    let workspace: Workspace
    
    @Environment(\.modelContext) private var modelContext
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Query private var cards: [Card]

    private enum SheetRoute: Identifiable {
        case add
        case edit(Card)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let card):
                return "edit-\(card.id.uuidString)"
            }
        }
    }

    @State private var sheetRoute: SheetRoute? = nil
    @State private var showingCardDeleteConfirm: Bool = false
    @State private var pendingCardDelete: (() -> Void)? = nil
    
    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id
        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            header(
                title: "Cards",
                subtitle: "Cards represent where spending happens, debit, credit, cash, or any account you track."
            )

            cardsGrid
                .frame(minHeight: 260)

            if #available(iOS 26.0, *) {
                Button {
                    sheetRoute = .add
                } label: {
                    Label("Add Card", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else {
                Button {
                    sheetRoute = .add
                } label: {
                    Label("Add Card", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }

            Spacer(minLength: 0)
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .add:
                NavigationStack {
                    AddCardView(workspace: workspace)
                }
            case .edit(let card):
                NavigationStack {
                    EditCardView(workspace: workspace, card: card)
                }
            }
        }
        .alert("Delete Card?", isPresented: $showingCardDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingCardDelete?()
                pendingCardDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCardDelete = nil
            }
        } message: {
            Text("This deletes the card and all of its expenses.")
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 16)]
    }

    private var cardsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 14) {
                if cards.isEmpty {
                    ContentUnavailableView(
                        "No Cards Yet",
                        systemImage: "creditcard",
                        description: Text("Create at least one card to continue.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    ForEach(cards) { card in
                        cardTile(card)
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.top, 4)
            .padding(.bottom, 10)
        }
    }

    private func cardTile(_ card: Card) -> some View {
        CardVisualView(
            title: card.name,
            theme: CardThemeOption(rawValue: card.theme) ?? .ruby,
            effect: CardEffectOption(rawValue: card.effect) ?? .plastic,
            showsShadow: false
        )
        .contextMenu {
            Button {
                sheetRoute = .edit(card)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Color("AccentColor"))

            Button(role: .destructive) {
                deleteCardWithOptionalConfirm(card)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color("OffshoreDepth"))
        }
    }

    private func deleteCardWithOptionalConfirm(_ card: Card) {
        if confirmBeforeDeleting {
            pendingCardDelete = {
                delete(card)
            }
            showingCardDeleteConfirm = true
        } else {
            delete(card)
        }
    }

    private func delete(_ card: Card) {
        let cardID = card.id
        let workspaceID = workspace.id

        HomePinnedItemsStore(workspaceID: workspaceID).removePinnedCard(id: cardID)
        HomePinnedCardsStore(workspaceID: workspaceID).removePinnedCardID(cardID)

        // I prefer being explicit here even though SwiftData delete rules are set to cascade.
        // This keeps behavior predictable if those rules ever change.
        if let planned = card.plannedExpenses {
            for expense in planned {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        }

        if let variable = card.variableExpenses {
            for expense in variable {
                modelContext.delete(expense)
            }
        }

        if let incomes = card.incomes {
            for income in incomes {
                modelContext.delete(income)
            }
        }

        if let links = card.budgetLinks {
            for link in links {
                modelContext.delete(link)
            }
        }

        modelContext.delete(card)
    }

    @ViewBuilder
    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Step: Presets

private struct OnboardingPresetsStep: View {
    
    let workspace: Workspace
    
    @Environment(\.modelContext) private var modelContext
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Query private var presets: [Preset]
    @Query private var presetLinks: [BudgetPresetLink]

    private enum SheetRoute: Identifiable {
        case add
        case edit(Preset)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let preset):
                return "edit-\(preset.id.uuidString)"
            }
        }
    }

    @State private var sheetRoute: SheetRoute? = nil
    @State private var showingPresetDeleteConfirm: Bool = false
    @State private var pendingPresetDelete: (() -> Void)? = nil
    
    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id
        _presets = Query(
            filter: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Preset.title, order: .forward)]
        )

        // Avoid deep relationship chains in the predicate.
        _presetLinks = Query()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            
            header(
                title: "Presets",
                subtitle: "Presets are reusable templates for recurring bills, rent, subscriptions, and more."
            )
            
            List {
                if presets.isEmpty {
                    ContentUnavailableView(
                        "No Presets Yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Add presets now, or skip and add them later from the Presets screen.")
                    )
                } else {
                    ForEach(presets) { preset in
                        VStack(alignment: .leading, spacing: 4) {
                            PresetRowView(
                                preset: preset,
                                assignedBudgetsCount: assignedBudgetCountsByPresetID[preset.id, default: 0]
                            )

                            if presetIDsMissingLinkedCards.contains(preset.id) {
                                Text(presetRequiresCardFootnoteText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                sheetRoute = .edit(preset)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color("AccentColor"))

                            if preset.isArchived {
                                Button {
                                    preset.isArchived = false
                                    preset.archivedAt = nil
                                } label: {
                                    Label("Unarchive", systemImage: "arrow.uturn.backward")
                                }
                                .tint(.green)
                            } else {
                                Button {
                                    preset.isArchived = true
                                    preset.archivedAt = .now
                                } label: {
                                    Label("Archive", systemImage: "archivebox")
                                }
                                .tint(Color("OffshoreSand"))
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deletePresetWithOptionalConfirm(preset)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(Color("OffshoreDepth"))
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .frame(minHeight: 260)
            if #available(iOS 26.0, *) {
                Button {
                    sheetRoute = .add
                } label: {
                    Label("Add Preset", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else {
                Button {
                    sheetRoute = .add
                } label: {
                    Label("Add Preset", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
            
            Spacer(minLength: 0)
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .add:
                NavigationStack {
                    AddPresetView(workspace: workspace)
                }
            case .edit(let preset):
                NavigationStack {
                    EditPresetView(workspace: workspace, preset: preset)
                }
            }
        }
        .alert("Delete?", isPresented: $showingPresetDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingPresetDelete?()
                pendingPresetDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingPresetDelete = nil
            }
        }
    }

    private var assignedBudgetCountsByPresetID: [UUID: Int] {
        var counts: [UUID: Int] = [:]

        for link in presetLinks {
            guard link.budget?.workspace?.id == workspace.id else { continue }
            guard let presetID = link.preset?.id else { continue }
            counts[presetID, default: 0] += 1
        }

        return counts
    }

    private var presetIDsMissingLinkedCards: Set<UUID> {
        var ids = Set<UUID>()

        for link in presetLinks {
            guard link.budget?.workspace?.id == workspace.id else { continue }
            guard let presetID = link.preset?.id else { continue }

            let budgetHasCards = ((link.budget?.cardLinks ?? []).isEmpty == false)
            if !budgetHasCards {
                ids.insert(presetID)
            }
        }

        return ids
    }

    private var presetRequiresCardFootnoteText: String {
        let hasAnyCardsInSystem = (workspace.cards ?? []).isEmpty == false
        return hasAnyCardsInSystem ? "Card Unassigned" : "No Cards Available"
    }

    private func deletePresetWithOptionalConfirm(_ preset: Preset) {
        if confirmBeforeDeleting {
            pendingPresetDelete = {
                modelContext.delete(preset)
            }
            showingPresetDeleteConfirm = true
        } else {
            modelContext.delete(preset)
        }
    }
    
    @ViewBuilder
    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Step: Gestures & Editing

private struct OnboardingGestureTrainingStep: View {

    let workspace: Workspace

    @Query private var cards: [Card]
    @Query private var presets: [Preset]
    @Query private var variableExpenses: [VariableExpense]

    @State private var cardInstruction: String = "Long press the card to open contextual actions."
    @State private var expenseInstruction: String = "Swipe either direction to edit or delete."
    @State private var presetInstruction: String = "Swipe either direction to edit, archive, or delete."

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id
        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )
        _presets = Query(
            filter: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Preset.title, order: .forward)]
        )
        _variableExpenses = Query(
            filter: #Predicate<VariableExpense> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\VariableExpense.transactionDate, order: .reverse)]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            header(
                title: "Gestures & Editing",
                subtitle: "Take a moment and familiarize yourself with the edit and delete gestures inside Offshore."
            )

            List {
                Section {
                    CardVisualView(
                        title: demoCard.name,
                        theme: CardThemeOption(rawValue: demoCard.theme) ?? .ruby,
                        effect: CardEffectOption(rawValue: demoCard.effect) ?? .plastic
                    )
                    .contentShape(Rectangle())
                    .onLongPressGesture {
                        cardInstruction = "Long press detected. Open actions from the card context menu."
                    }
                    .contextMenu {
                        Button {
                            cardInstruction = "Card Edit action selected."
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button(role: .destructive) {
                            cardInstruction = "Card Delete action selected."
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } header: {
                    Text("Card")
                } footer: {
                    Text(cardInstruction)
                }

                Section {
                    expenseDemoRow
                } header: {
                    Text("Expense")
                } footer: {
                    Text(expenseInstruction)
                }

                Section {
                    presetDemoRow
                } header: {
                    Text("Preset")
                } footer: {
                    Text(presetInstruction)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .frame(minHeight: 320)

            Spacer(minLength: 0)
        }
    }

    private var demoCard: Card {
        cards.first ?? Card(name: "Everyday Card", theme: CardThemeOption.ruby.rawValue, effect: CardEffectOption.plastic.rawValue, workspace: workspace)
    }

    private var demoExpense: VariableExpense {
        if let existing = variableExpenses.first {
            return existing
        }
        let category = Category(name: "Groceries", hexColor: "#22C55E", workspace: workspace)
        return VariableExpense(
            descriptionText: "Local Market",
            amount: 48.90,
            transactionDate: .now,
            workspace: workspace,
            card: demoCard,
            category: category
        )
    }

    private var demoPreset: Preset {
        presets.first ?? Preset(
            title: "Rent",
            plannedAmount: 1400,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            workspace: workspace,
            defaultCard: demoCard,
            defaultCategory: nil
        )
    }

    private var expenseDemoRow: some View {
        SharedVariableExpenseRow(expense: demoExpense)
            .contentShape(Rectangle())
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    expenseInstruction = "Leading swipe opened Edit."
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(Color("AccentColor"))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    expenseInstruction = "Trailing swipe opened Delete."
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Color("OffshoreDepth"))
            }
    }

    private var presetDemoRow: some View {
        PresetRowView(preset: demoPreset, assignedBudgetsCount: 1)
            .contentShape(Rectangle())
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    presetInstruction = "Leading swipe opened Edit."
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(Color("AccentColor"))

                Button {
                    presetInstruction = "Leading swipe opened Archive."
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .tint(Color("OffshoreSand"))
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    presetInstruction = "Trailing swipe opened Delete."
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .tint(Color("OffshoreDepth"))
            }
    }

    @ViewBuilder
    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Step: Income

private struct OnboardingIncomeStep: View {

    private enum IncomeKind: String, CaseIterable, Identifiable {
        case planned = "Planned"
        case actual = "Actual"

        var id: String { rawValue }

        var isPlanned: Bool {
            self == .planned
        }
    }

    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Query private var incomes: [Income]

    private enum SheetRoute: Identifiable {
        case edit(Income)

        var id: String {
            switch self {
            case .edit(let income):
                return "edit-\(income.id.uuidString)"
            }
        }
    }

    @State private var incomeKind: IncomeKind = .planned
    @State private var source: String = ""
    @State private var amountText: String = ""
    @State private var date: Date = .now

    @State private var sheetRoute: SheetRoute? = nil
    @State private var showingIncomeDeleteConfirm: Bool = false
    @State private var pendingIncomeDelete: (() -> Void)? = nil
    @State private var showingInvalidAmountAlert: Bool = false

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _incomes = Query(
            filter: #Predicate<Income> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Income.date, order: .reverse)]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            header(
                title: "Income",
                subtitle: "Capture planned or actual income before first launch."
            )

            List {
                Section {
                    Picker("Income Type", selection: $incomeKind) {
                        ForEach(IncomeKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField("Source", text: $source)
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)

                    DatePicker("Date", selection: $date, displayedComponents: .date)
                        .datePickerStyle(.compact)
                } header: {
                    Text("Quick Income Capture")
                } footer: {
                    Text("You can change this later in Income.")
                }

                Section("Income Added") {
                    if incomes.isEmpty {
                        Text("No income added during onboarding.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(incomes) { income in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(income.source)
                                    Text(income.isPlanned ? "Planned" : "Actual")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(income.amount, format: CurrencyFormatter.currencyStyle())
                                    .fontWeight(.semibold)
                            }
                            .contentShape(Rectangle())
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    sheetRoute = .edit(income)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color("AccentColor"))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteIncomeWithOptionalConfirm(income)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(Color("OffshoreDepth"))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .frame(minHeight: 340)

            if #available(iOS 26.0, *) {
                Button {
                    addIncome()
                } label: {
                    Label("Add Income", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else {
                Button {
                    addIncome()
                } label: {
                    Label("Add Income", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }

            Spacer(minLength: 0)
        }
        .alert("Invalid Amount", isPresented: $showingInvalidAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enter an amount greater than 0 to add income.")
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .edit(let income):
                NavigationStack {
                    EditIncomeView(workspace: workspace, income: income)
                }
            }
        }
        .alert("Delete?", isPresented: $showingIncomeDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingIncomeDelete?()
                pendingIncomeDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingIncomeDelete = nil
            }
        }
    }

    private var trimmedSource: String {
        source.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addIncome() {
        guard let amount = CurrencyFormatter.parseAmount(amountText), amount > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        let finalSource = trimmedSource.isEmpty ? "Income" : trimmedSource
        let income = Income(
            source: finalSource,
            amount: amount,
            date: Calendar.current.startOfDay(for: date),
            isPlanned: incomeKind.isPlanned,
            isException: false,
            workspace: workspace,
            series: nil
        )
        modelContext.insert(income)

        source = ""
        amountText = ""
    }

    private func deleteIncomeWithOptionalConfirm(_ income: Income) {
        if confirmBeforeDeleting {
            pendingIncomeDelete = {
                deleteIncome(income)
            }
            showingIncomeDeleteConfirm = true
        } else {
            deleteIncome(income)
        }
    }

    private func deleteIncome(_ income: Income) {
        modelContext.delete(income)

        if case .edit(let editingIncome) = sheetRoute, editingIncome.id == income.id {
            sheetRoute = nil
        }
    }

    @ViewBuilder
    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Step: Budgets

private struct OnboardingBudgetsStep: View {

    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

    @Query private var budgets: [Budget]

    private enum SheetRoute: Identifiable {
        case add
        case edit(Budget)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let budget):
                return "edit-\(budget.id.uuidString)"
            }
        }
    }

    @State private var sheetRoute: SheetRoute? = nil
    @State private var showingDeleteConfirm: Bool = false
    @State private var pendingDelete: (() -> Void)? = nil

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _budgets = Query(
            filter: #Predicate<Budget> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Budget.startDate, order: .reverse)]
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(
                title: "Budgets",
                subtitle: "Create a budget now, or continue and add one later."
            )

            List {
                Section("Budgets") {
                    if budgets.isEmpty {
                        Text("No budgets yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(budgets) { budget in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(budget.name)
                                    .font(.body.weight(.semibold))
                                Text(budgetRangeLabel(for: budget))
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    sheetRoute = .edit(budget)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(Color("AccentColor"))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    deleteBudgetWithOptionalConfirm(budget)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(Color("OffshoreDepth"))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .frame(minHeight: 320)

            Text("Default period: \((BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly).displayTitle)")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if #available(iOS 26.0, *) {
                Button {
                    sheetRoute = .add
                } label: {
                    Label("Create Budget", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.glassProminent)
                .tint(.accentColor)
            } else {
                Button {
                    sheetRoute = .add
                } label: {
                    Label("Create Budget", systemImage: "plus")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }

            Spacer(minLength: 0)
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .add:
                NavigationStack {
                    AddBudgetView(workspace: workspace)
                }
            case .edit(let budget):
                NavigationStack {
                    EditBudgetView(workspace: workspace, budget: budget)
                }
            }
        }
        .alert("Delete Budget?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingDelete?()
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        }
    }

    private func deleteBudgetWithOptionalConfirm(_ budget: Budget) {
        if confirmBeforeDeleting {
            pendingDelete = {
                deleteBudgetAndGeneratedPlannedExpenses(budget)
            }
            showingDeleteConfirm = true
        } else {
            deleteBudgetAndGeneratedPlannedExpenses(budget)
        }
    }

    private func deleteBudgetAndGeneratedPlannedExpenses(_ budget: Budget) {
        let budgetID: UUID? = budget.id
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID
            }
        )

        if let expenses = try? modelContext.fetch(descriptor) {
            for expense in expenses {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        }

        modelContext.delete(budget)
    }

    private func budgetRangeLabel(for budget: Budget) -> String {
        let start = budget.startDate.formatted(date: .abbreviated, time: .omitted)
        let end = budget.endDate.formatted(date: .abbreviated, time: .omitted)
        return "\(start) - \(end)"
    }

    @ViewBuilder
    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Onboarding") {
    let container = PreviewSeed.makeContainer()
    return NavigationStack {
        OnboardingView()
    }
    .modelContainer(container)
}
