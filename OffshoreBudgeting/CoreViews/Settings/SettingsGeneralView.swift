//
//  SettingsGeneralView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI
import SwiftData

struct SettingsGeneralView: View {

    let workspace: Workspace

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

    @AppStorage("general_reviewUncategorizedExpensesOnOpen")
    private var reviewUncategorizedExpensesOnOpen = false

    @State private var eraseResultMessage: String = ""

    @State private var activeAlert: ActiveAlert? = nil

    // Reset-to-first-run flags
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @AppStorage("selectedWorkspaceID") private var selectedWorkspaceID: String = ""
    @AppStorage("didSeedDefaultWorkspaces") private var didSeedDefaultWorkspaces: Bool = false
    @AppStorage("privacy_requireBiometrics") private var requireBiometrics: Bool = false
    @AppStorage("onboarding_step") private var onboardingStep: Int = 0
    @AppStorage("onboarding_didPressGetStarted") private var didPressGetStarted: Bool = false
    @AppStorage("onboarding_didChooseDataSource") private var didChooseDataSource: Bool = false
    @AppStorage("icloud_useCloud") private var desiredUseICloud: Bool = false
    @AppStorage("icloud_activeUseCloud") private var activeUseICloud: Bool = false
    @AppStorage("app_rootResetToken") private var rootResetToken: String = UUID().uuidString
    @State private var showingRestartRequired: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(PostBoardingTipsStore.self) private var postBoardingTipsStore

    var body: some View {
        List {
            Section("Behavior") {
                Toggle("Confirm Before Deleting", isOn: $confirmBeforeDeleting
                )
                .offshoreAccentTint()

                Text("When enabled, you’ll always be asked to confirm before anything is deleted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Review Uncategorized Expenses on App Open", isOn: $reviewUncategorizedExpensesOnOpen)
                    .offshoreAccentTint()
                    .accessibilityIdentifier("reviewUncategorizedExpensesOnOpen")

                Text("When enabled, review uncategorized expenses in your selected workspace when you next open or return to the app. You can choose Later to skip a review.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                NavigationLink {
                    SettingsExpenseDisplayView(
                        hideFuturePlannedExpenses: $hideFuturePlannedExpenses,
                        excludeFuturePlannedExpensesFromCalculations: $excludeFuturePlannedExpensesFromCalculations,
                        hideFutureVariableExpenses: $hideFutureVariableExpenses,
                        excludeFutureVariableExpensesFromCalculations: $excludeFutureVariableExpensesFromCalculations
                    )
                } label: {
                    Text("Expense Display")
                }
            }

            Section {
                Picker("Default Budgeting Period", selection: defaultBudgetingPeriodBinding) {
                    ForEach(BudgetingPeriod.allCases) { period in
                        Text(period.displayTitle)
                            .tag(period)
                    }
                }
                .pickerStyle(.menu)
            } header: {
                Text("Budgets")
            } footer: {
                Text("Sets the default date range for Home, account views, and widgets, and the starting dates for new budgets. Monthly, for example, starts with the current month. This period also determines when completed periods are recorded in Offshore Savings. You can choose other date ranges when needed.")
            }

            Section("Maintenance") {
                NavigationLink {
                    SettingsMaintenanceView(
                        workspace: workspace,
                        onResetTipsConfirmed: { postBoardingTipsStore.resetTips() },
                        onRepeatOnboarding: { activeAlert = .repeatOnboardingConfirm },
                        onEraseContent: { activeAlert = .eraseConfirm }
                    )
                } label: {
                    Text("Maintenance")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("General")
        .blocksAutomaticExpenseReview(while: activeAlert != nil)
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .repeatOnboardingConfirm:
                Alert(
                    title: Text("Repeat Onboarding?"),
                    message: Text("You can restart onboarding at any time. Your current data source and saved data will stay in place."),
                    primaryButton: .destructive(Text("Go")) {
                        OnboardingResetService.repeatOnboarding()
                        onboardingStep = 0
                        didPressGetStarted = false
                        didCompleteOnboarding = false
                    },
                    secondaryButton: .cancel()
                )
            case .eraseConfirm:
                if activeUseICloud {
                    Alert(
                        title: Text("Switch to On Device?"),
                        message: Text("Reset & Erase Content applies to on-device data. You’re currently using iCloud, so you’ll need to switch to On Device and restart first."),
                        primaryButton: .destructive(Text("Switch")) {
                            performLocalErase()
                        },
                        secondaryButton: .cancel()
                    )
                } else {
                    Alert(
                        title: Text("Reset & Erase Content?"),
                        message: Text("This will permanently remove your data from this device and return you to onboarding."),
                        primaryButton: .destructive(Text("Erase")) {
                            performLocalErase()
                        },
                        secondaryButton: .cancel()
                    )
                }
            case .eraseResult:
                Alert(
                    title: Text("Reset Complete"),
                    message: Text(eraseResultMessage),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .appSheet(isPresented: $showingRestartRequired) {
            RestartRequiredView(
                title: "Restart Required",
                message: AppRestartService.restartRequiredMessage(
                    debugMessage: "Will take effect the next time you quit and relaunch the app.",
                    releaseExtraMessage: "After restarting, you can run Reset & Erase Content again."
                ),
                primaryButtonTitle: AppRestartService.closeAppButtonTitle,
                onPrimary: { AppRestartService.closeAppOrDismiss { showingRestartRequired = false } }
            )
            .presentationDetents([.large])
        }
    }

    private var defaultBudgetingPeriodBinding: Binding<BudgetingPeriod> {
        Binding(
            get: { BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly },
            set: { defaultBudgetingPeriodRaw = $0.rawValue }
        )
    }

    // MARK: - Erase

    private func performLocalErase() {
        do {
            if activeUseICloud {
                desiredUseICloud = false
                showingRestartRequired = (desiredUseICloud != activeUseICloud)
                return
            }

            try AppResetService.eraseAllLocalData(modelContext: modelContext)

            // Reset app flags to feel like first-run
            selectedWorkspaceID = ""
            didSeedDefaultWorkspaces = false
            didCompleteOnboarding = false
            onboardingStep = 0
            didPressGetStarted = false
            didChooseDataSource = false

            // Safety: if app lock was enabled, disable it so onboarding isn’t blocked
            requireBiometrics = false

            // Optional: bring tips back to a clean baseline
            postBoardingTipsStore.resetToBaselineForErase()

            let newToken = UUID().uuidString
            DispatchQueue.main.async {
                rootResetToken = newToken
            }

            eraseResultMessage = "All content has been erased. You’ll be returned to onboarding."
            DispatchQueue.main.async {
                activeAlert = .eraseResult
            }
        } catch {
            eraseResultMessage = "Something went wrong while erasing data: \(error.localizedDescription)"
            DispatchQueue.main.async {
                activeAlert = .eraseResult
            }
        }
    }
}

private enum ActiveAlert: Identifiable {
    case repeatOnboardingConfirm
    case eraseConfirm
    case eraseResult

    var id: Int {
        switch self {
        case .repeatOnboardingConfirm: return 1
        case .eraseConfirm: return 2
        case .eraseResult: return 3
        }
    }
}

// MARK: - Maintenance Screen

private struct SettingsMaintenanceView: View {
    @Environment(\.appearanceTheme) private var theme
    @Environment(\.modelContext) private var modelContext


    let workspace: Workspace
    let onResetTipsConfirmed: () -> Void
    let onRepeatOnboarding: () -> Void
    let onEraseContent: () -> Void
    @State private var activeMaintenanceAlert: MaintenanceAlert? = nil

    init(
        workspace: Workspace,
        onResetTipsConfirmed: @escaping () -> Void,
        onRepeatOnboarding: @escaping () -> Void,
        onEraseContent: @escaping () -> Void
    ) {
        self.workspace = workspace
        self.onResetTipsConfirmed = onResetTipsConfirmed
        self.onRepeatOnboarding = onRepeatOnboarding
        self.onEraseContent = onEraseContent
    }

    private var hideWorkspaceProgress: Binding<Bool> {
        Binding(
            get: { WorkspaceProgressPreferences.savedChoice(for: workspace) ?? false },
            set: { isHidden in
                do {
                    try WorkspaceProgressPreferences.saveChoice(isHidden, for: workspace) {
                        try modelContext.save()
                    }
                } catch {
                    activeMaintenanceAlert = .saveProgressPreferenceFailed
                }
            }
        )
    }

    var body: some View {
        List {
            if WorkspaceProgressService.canHideProgress(in: workspace) {
                Section {
                    Toggle("Hide Workspace Progress", isOn: hideWorkspaceProgress)
                        .offshoreAccentTint()
                        .accessibilityIdentifier("hideWorkspaceProgress")
                } footer: {
                    Text("This setting is saved with \(workspace.name). Turn it off to show the Workspace Progress row again.")
                }
            }

            Section {
                maintenanceButton(
                    title: "Reset Tips & Hints",
                    tint: .orange,
                    action: { activeMaintenanceAlert = .resetConfirm }
                )
                .listRowSeparator(.hidden)

                maintenanceButton(
                    title: "Repeat Onboarding",
                    tint: theme.accent,
                    action: onRepeatOnboarding
                )
                .listRowSeparator(.hidden)

                maintenanceButton(
                    title: "Reset & Erase Content",
                    tint: .red,
                    action: onEraseContent
                )
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Maintenance")
        .blocksAutomaticExpenseReview(while: activeMaintenanceAlert != nil)
        .alert(item: $activeMaintenanceAlert) { alert in
            switch alert {
            case .resetConfirm:
                Alert(
                    title: Text("Reset Tips & Hints?"),
                    message: Text("This will make tips and hints appear again."),
                    primaryButton: .destructive(Text("Reset")) {
                        onResetTipsConfirmed()
                        DispatchQueue.main.async {
                            activeMaintenanceAlert = .resetResult
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .resetResult:
                Alert(
                    title: Text("Tips & Hints Reset"),
                    message: Text("Tips and hints will be shown again."),
                    dismissButton: .default(Text("OK"))
                )
            case .saveProgressPreferenceFailed:
                Alert(
                    title: Text("Couldn’t Save Settings"),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    @ViewBuilder
    private func maintenanceButton(title: LocalizedStringKey, tint: Color, action: @escaping () -> Void) -> some View {
        if #available(iOS 26.0, *) {
            Button(action: action) {
                Text(title)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .glassProminentButtonStyleCompat()
            .tint(tint)
            #if targetEnvironment(macCatalyst)
            .padding(.vertical, 8)
            #endif
        } else {
            Button(action: action) {
                Text(title)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
        }
    }

    private enum MaintenanceAlert: Identifiable {
        case resetConfirm
        case resetResult
        case saveProgressPreferenceFailed

        var id: Int {
            switch self {
            case .resetConfirm: return 1
            case .resetResult: return 2
            case .saveProgressPreferenceFailed: return 3
            }
        }
    }
}

// MARK: - Expense Display Screen

private struct SettingsExpenseDisplayView: View {

    @Binding var hideFuturePlannedExpenses: Bool
    @Binding var excludeFuturePlannedExpensesFromCalculations: Bool
    @Binding var hideFutureVariableExpenses: Bool
    @Binding var excludeFutureVariableExpensesFromCalculations: Bool

    var body: some View {
        List {
            Section("Planned Expenses") {
                Toggle("Hide Future Planned Expenses", isOn: $hideFuturePlannedExpenses)
                    .offshoreAccentTint()

                Text("When enabled, planned expenses scheduled after today are hidden from expense lists.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Exclude Future Planned Expenses from Totals",
                    isOn: $excludeFuturePlannedExpensesFromCalculations
                )
                .offshoreAccentTint()

                Text("When enabled, planned expenses scheduled after today are excluded from totals and savings calculations.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Variable Expenses") {
                Toggle("Hide Future Variable Expenses", isOn: $hideFutureVariableExpenses)
                    .offshoreAccentTint()

                Text("When enabled, variable expenses dated after today are hidden from expense lists.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Exclude Future Variable Expenses from Totals",
                    isOn: $excludeFutureVariableExpensesFromCalculations
                )
                .offshoreAccentTint()

                Text("When enabled, variable expenses dated after today are excluded from totals and savings calculations.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Expense Display")
    }
}

#Preview("Settings General") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { workspace in
        NavigationStack {
            SettingsGeneralView(workspace: workspace)
        }
        .environment(PostBoardingTipsStore())
    }
}
