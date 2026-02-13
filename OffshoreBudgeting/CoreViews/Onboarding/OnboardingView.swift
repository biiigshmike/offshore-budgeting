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
        case 0:
            welcomeStep
            
        case 1:
            workspaceStep
            
        case 2:
            privacyAndSyncStep
            
        case 3:
            categoriesStep
            
        case 4:
            cardsStep

        case 5:
            presetsStep

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
    
    // MARK: - Step 4: Categories
    
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
    
    // MARK: - Step 5: Cards
    
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
    
    // MARK: - Step 6: Presets
    
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

    // MARK: - Step 7: Quick Actions

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
        onboardingStep >= 6 ? "Done" : "Next"
    }
    
    private func primaryActionTapped() {
        // Step-specific gating
        switch onboardingStep {
        case 1:
            guard !workspaces.isEmpty else {
                showingMissingWorkspaceAlert = true
                return
            }
            
            if selectedWorkspaceID.isEmpty {
                selectedWorkspaceID = (workspaces.first?.id.uuidString ?? "")
            }
            
        case 4:
            // Require at least one card before presets.
            if let ws = currentWorkspace {
                let hasCard = hasAtLeastOneCard(in: ws)
                guard hasCard else {
                    showingMissingCardAlert = true
                    return
                }
            }
            
        default:
            break
        }
        
        if onboardingStep >= 6 {
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
        onboardingStep = min(6, onboardingStep + 1)
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemBackground))
            .frame(minHeight: 220)

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
            
            List {
                if cards.isEmpty {
                    ContentUnavailableView(
                        "No Cards Yet",
                        systemImage: "creditcard",
                        description: Text("Create at least one card to continue.")
                    )
                } else {
                    ForEach(cards) { card in
                        HStack(spacing: 12) {
                            Image(systemName: "creditcard.fill")
                                .foregroundStyle(.secondary)
                            Text(card.name)
                        }
                        .padding(.vertical, 6)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                sheetRoute = .edit(card)
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color("AccentColor"))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteCardWithOptionalConfirm(card)
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
                modelContext.delete(expense)
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

#Preview("Onboarding") {
    let container = PreviewSeed.makeContainer()
    return NavigationStack {
        OnboardingView()
    }
    .modelContainer(container)
}
