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

    @AppStorage("icloud_useCloud") private var useICloud: Bool = false
    @AppStorage("app_rootResetToken") private var rootResetToken: String = UUID().uuidString

    /// Persist step so toggling iCloud (which rebuilds container) doesn't restart the flow.
    @AppStorage("onboarding_step") private var onboardingStep: Int = 0

    // MARK: - SwiftData

    @Query(sort: \Workspace.name, order: .forward)
    private var workspaces: [Workspace]

    @Environment(\.modelContext) private var modelContext

    // MARK: - Local Notifications

    @StateObject private var notificationService = LocalNotificationService()

    // MARK: - UI

    @State private var showingSkipPrompt: Bool = false
    @State private var skipPromptMessage: String = ""

    @State private var showingMissingWorkspaceAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false

    // MARK: - Derived

    private var currentWorkspace: Workspace? {
        if let uuid = UUID(uuidString: selectedWorkspaceID),
           let found = workspaces.first(where: { $0.id == uuid }) {
            return found
        }
        return workspaces.first
    }

    var body: some View {
        VStack(spacing: 0) {
            stepBody
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 18)
                .padding(.top, 18)

            if onboardingStep != 0 {
                Divider().opacity(0.35)

                bottomNavBar
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
            }

        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            Task { await maybeOfferSkipIfCloudAlreadyHasData() }
        }
        .alert("Workspace Required", isPresented: $showingMissingWorkspaceAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Create at least one workspace to continue.")
        }
        .alert("Card Required", isPresented: $showingMissingCardAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Create at least one card to continue, presets need a default card.")
        }
        .alert("Existing iCloud Data Detected", isPresented: $showingSkipPrompt) {
            Button("Continue Setup", role: .cancel) { }
            Button("Skip Onboarding", role: .destructive) { completeOnboarding() }
        } message: {
            Text(skipPromptMessage)
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

        default:
            presetsStep
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

            Button {
                goNext()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)

            Spacer(minLength: 18)
        }
        .frame(maxWidth: 560, alignment: .leading)
    }

    // MARK: - Step 2: Workspaces

    private var workspaceStep: some View {
        OnboardingWorkspaceStep(
            workspaces: workspaces,
            selectedWorkspaceID: $selectedWorkspaceID,
            onCreate: createWorkspace(name:hexColor:)
        )
        .frame(maxWidth: 680)
    }

    // MARK: - Step 3: Privacy + Sync + Notifications

    private var privacyAndSyncStep: some View {
        OnboardingPrivacySyncStep(
            requireBiometrics: $requireBiometrics,
            useICloud: $useICloud,
            rootResetToken: $rootResetToken,
            notificationService: notificationService
        )
        .frame(maxWidth: 680)
    }

    // MARK: - Step 4: Categories

    private var categoriesStep: some View {
        Group {
            if let ws = currentWorkspace {
                OnboardingCategoriesStep(workspace: ws)
            } else {
                ContentUnavailableView(
                    "No Workspace",
                    systemImage: "person.3",
                    description: Text("Create a workspace first.")
                )
            }
        }
        .frame(maxWidth: 760)
    }

    // MARK: - Step 5: Cards

    private var cardsStep: some View {
        Group {
            if let ws = currentWorkspace {
                OnboardingCardsStep(workspace: ws)
            } else {
                ContentUnavailableView(
                    "No Workspace",
                    systemImage: "person.3",
                    description: Text("Create a workspace first.")
                )
            }
        }
        .frame(maxWidth: 760)
    }

    // MARK: - Step 6: Presets

    private var presetsStep: some View {
        Group {
            if let ws = currentWorkspace {
                OnboardingPresetsStep(workspace: ws)
            } else {
                ContentUnavailableView(
                    "No Workspace",
                    systemImage: "person.3",
                    description: Text("Create a workspace first.")
                )
            }
        }
        .frame(maxWidth: 760)
    }

    // MARK: - Bottom Navigation

    private var bottomNavBar: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Text("Back")
                    .frame(minWidth: 110, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.gray)
            .disabled(onboardingStep == 0)

            Spacer(minLength: 0)

            Button {
                primaryActionTapped()
            } label: {
                Text(primaryButtonTitle)
                    .frame(minWidth: 140, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)
        }
    }

    private var primaryButtonTitle: String {
        onboardingStep >= 5 ? "Done" : "Next"
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

        if onboardingStep >= 5 {
            completeOnboarding()
        } else {
            goNext()
        }
    }

    private func goBack() {
        onboardingStep = max(0, onboardingStep - 1)
    }

    private func goNext() {
        onboardingStep = min(5, onboardingStep + 1)
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

    /// We can't reliably enumerate SwiftData-backed CloudKit records without plumbing.
    /// This is a pragmatic check:
    /// - If iCloud is enabled AND we already have workspaces, onboarding is likely redundant.
    /// - If iCloud account is available, we explain why enabling iCloud can pull data from other devices.
    private func maybeOfferSkipIfCloudAlreadyHasData() async {
        // Only offer the prompt on the welcome screen.
        guard onboardingStep == 0 else { return }

        // If the store already has data (often after enabling iCloud), offer to skip.
        if useICloud, !workspaces.isEmpty {
            skipPromptMessage = "It looks like iCloud Sync is enabled and data already exists on this Apple ID. You can skip onboarding to jump straight into your existing workspaces."
            showingSkipPrompt = true
            return
        }

        // If user is not using iCloud yet, we can still detect whether their iCloud account is available.
        // This helps us message the Step 3 toggle.
        let status = try? await CKContainer.default().accountStatus()
        if status == .available {
            // No-op for now, but this is where we'd enhance messaging later.
        }
    }
}

// MARK: - Step: Workspace Setup

private struct OnboardingWorkspaceStep: View {

    let workspaces: [Workspace]
    @Binding var selectedWorkspaceID: String
    let onCreate: (String, String) -> Void

    @State private var showingAddWorkspace: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            header(
                title: "Workspaces",
                subtitle: "Create your default workspace (like Personal), and add others if you want."
            )

            if workspaces.isEmpty {
                ContentUnavailableView(
                    "No Workspaces Yet",
                    systemImage: "person.3",
                    description: Text("Create at least one workspace to continue.")
                )
                .padding(.vertical, 8)
            } else {
                List {
                    ForEach(workspaces) { ws in
                        Button {
                            selectedWorkspaceID = ws.id.uuidString
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(Color(hex: ws.hexColor) ?? .secondary)
                                    .frame(width: 12, height: 12)

                                Text(ws.name)

                                Spacer(minLength: 0)

                                if selectedWorkspaceID == ws.id.uuidString {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listStyle(.insetGrouped)
                .frame(minHeight: 220)
            }

            Button {
                showingAddWorkspace = true
            } label: {
                Label("Add Workspace", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)

            Text("Tip: Most people start with a Personal workspace, then add a Work workspace later.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showingAddWorkspace) {
            NavigationStack {
                AddWorkspaceView(onCreate: onCreate)
            }
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

// MARK: - Step: Privacy + iCloud + Notifications

private struct OnboardingPrivacySyncStep: View {

    @Binding var requireBiometrics: Bool
    @Binding var useICloud: Bool
    @Binding var rootResetToken: String

    @ObservedObject var notificationService: LocalNotificationService

    @State private var biometricsInfo = LocalAuthenticationService.biometricAvailability()
    @State private var showingNotificationsDeniedInfo: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            header(
                title: "Privacy and Sync",
                subtitle: "Choose how you want Offshore to protect and sync your data."
            )

            Form {
                Section("App Lock") {
                    Toggle(biometricsInfo.kind.displayName, isOn: $requireBiometrics)
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

                Section("iCloud Sync") {
                    Toggle("Enable iCloud Sync", isOn: $useICloud)
                        .onChange(of: useICloud) { _, _ in
                            // Rebuild the SwiftData container (OffshoreBudgetingApp listens for this).
                            rootResetToken = UUID().uuidString
                        }

                    Text("Use iCloud to sync your workspaces and budgets across your devices signed into this Apple ID.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
        .alert("Notifications Disabled", isPresented: $showingNotificationsDeniedInfo) {
            Button("OK", role: .cancel) { }
            Button("Open Settings") {
                notificationService.openSystemSettings()
            }
        } message: {
            Text("Notifications are currently disabled for Offshore. You can enable them in Settings.")
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
                        } else {
                            // Quick happy-path ping
                            try? await notificationService.scheduleTestNotification()
                        }
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

    @Query private var categories: [Category]

    @State private var showingAddCategory: Bool = false

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
                if categories.isEmpty {
                    ContentUnavailableView(
                        "No Categories Yet",
                        systemImage: "tag",
                        description: Text("Add a few categories to get started. You can add more later.")
                    )
                } else {
                    ForEach(categories) { cat in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: cat.hexColor) ?? .secondary)
                                .frame(width: 10, height: 10)
                            Text(cat.name)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(minHeight: 260)

            Button {
                showingAddCategory = true
            } label: {
                Label("Add Category", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showingAddCategory) {
            NavigationStack {
                AddCategoryView(workspace: workspace)
            }
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

    @Query private var cards: [Card]
    @State private var showingAddCard: Bool = false

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
                        description: Text("Create at least one card. Presets need a default card.")
                    )
                } else {
                    ForEach(cards) { card in
                        HStack(spacing: 12) {
                            Image(systemName: "creditcard.fill")
                                .foregroundStyle(.secondary)
                            Text(card.name)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(minHeight: 260)

            Button {
                showingAddCard = true
            } label: {
                Label("Add Card", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showingAddCard) {
            NavigationStack {
                AddCardView(workspace: workspace)
            }
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

// MARK: - Step: Presets

private struct OnboardingPresetsStep: View {

    let workspace: Workspace

    @Query private var presets: [Preset]
    @State private var showingAddPreset: Bool = false

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id
        _presets = Query(
            filter: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Preset.title, order: .forward)]
        )
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
                            Text(preset.title)
                                .font(.subheadline.weight(.semibold))
                            Text(preset.frequency.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .frame(minHeight: 260)

            Button {
                showingAddPreset = true
            } label: {
                Label("Add Preset", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.glassProminent)
            .tint(.blue)

            Spacer(minLength: 0)
        }
        .sheet(isPresented: $showingAddPreset) {
            NavigationStack {
                AddPresetView(workspace: workspace)
            }
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
