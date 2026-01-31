//
//  SettingsGeneralView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI
import SwiftData

struct SettingsGeneralView: View {

    // Store "SYSTEM" when user wants the device default currency.
    @AppStorage("general_currencyCode") private var currencyCode: String = CurrencyPickerConstants.systemTag

    // Step 1.2
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @AppStorage("general_rememberTabSelection") private var rememberTabSelection: Bool = false

    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

    // Step 1.3
    @AppStorage("tips_resetToken") private var tipsResetToken: Int = 0
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

    @State private var searchText: String = ""

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        List {
            Section("Formatting") {
                NavigationLink {
                    CurrencyPickerView(
                        selectedCode: $currencyCode,
                        searchText: $searchText
                    )
                } label: {
                    LabeledContent("Currency") {
                        Text(selectedCurrencyLabel)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Behavior") {
                Toggle("Confirm Before Deleting", isOn: $confirmBeforeDeleting
                )
                .tint(Color("AccentColor"))

                Text("When enabled, you’ll always be asked to confirm before anything is deleted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Toggle("Remember Tab Selection", isOn: $rememberTabSelection
                )
                .tint(Color("AccentColor"))

                Text("When enabled, the app will always launch with the last view you were on instead of defaulting to Home.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Budgets") {
                Picker("Default Budgeting Period", selection: defaultBudgetingPeriodBinding) {
                    ForEach(BudgetingPeriod.allCases) { period in
                        Text(period.displayTitle)
                            .tag(period)
                    }
                }
                .pickerStyle(.menu)
            }

            Section("Maintenance") {
                HStack(spacing: 12) {
                    if #available(iOS 26.0, *) {
                        Button {
                            activeAlert = .tipsResetConfirm
                        } label: {
                            Text("Reset Tips & Hints")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.orange)
                        
                        Button {
                            activeAlert = .eraseConfirm
                        } label: {
                            Text("Reset & Erase Content")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.glassProminent)
                        .tint(.red)
                    } else {
                        Button {
                            activeAlert = .tipsResetConfirm
                        } label: {
                            Text("Reset Tips & Hints")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        
                        Button {
                            activeAlert = .eraseConfirm
                        } label: {
                            Text("Reset & Erase Content")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }

//                Text("Erase will remove all budgets, cards, categories, presets, transactions, and workspaces from this device.")
//                    .font(.footnote)
//                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("General")
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .tipsResetConfirm:
                Alert(
                    title: Text("Reset Tips & Hints?"),
                    message: Text("This will make tips and hints appear again."),
                    primaryButton: .destructive(Text("Reset")) {
                        tipsResetToken += 1
                        DispatchQueue.main.async {
                            activeAlert = .tipsResetResult
                        }
                    },
                    secondaryButton: .cancel()
                )
            case .tipsResetResult:
                Alert(
                    title: Text("Tips & Hints Reset"),
                    message: Text("Tips and hints will be shown again."),
                    dismissButton: .default(Text("OK"))
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
        .sheet(isPresented: $showingRestartRequired) {
            RestartRequiredView(
                title: "Restart Required",
                message: AppRestartService.restartRequiredMessage(
                    debugMessage: "Switching to On Device takes effect after you close and reopen Offshore.",
                    releaseExtraMessage: "After restarting, you can run Reset & Erase Content again."
                ),
                primaryButtonTitle: AppRestartService.closeAppButtonTitle,
                onPrimary: { AppRestartService.closeAppOrDismiss { showingRestartRequired = false } }
            )
            .presentationDetents([.medium])
        }
    }

    private var selectedCurrencyLabel: String {
        if currencyCode == CurrencyPickerConstants.systemTag {
            let systemCode = CurrencyPickerConstants.systemCurrencyCode
            let systemName = CurrencyPickerConstants.localizedCurrencyName(for: systemCode)
            return "System Default (\(systemName) • \(systemCode))"
        } else {
            let name = CurrencyPickerConstants.localizedCurrencyName(for: currencyCode)
            return "\(name) • \(currencyCode)"
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
            tipsResetToken = 0

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
    case tipsResetConfirm
    case tipsResetResult
    case eraseConfirm
    case eraseResult

    var id: Int {
        switch self {
        case .tipsResetConfirm: return 1
        case .tipsResetResult: return 2
        case .eraseConfirm: return 3
        case .eraseResult: return 4
        }
    }
}

// MARK: - Currency Picker

private struct CurrencyPickerView: View {

    @Binding var selectedCode: String
    @Binding var searchText: String

    @Environment(\.dismiss) private var dismiss

    private var filteredCurrencies: [String] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return CurrencyPickerConstants.allCurrencyCodes }

        let lower = query.lowercased()

        return CurrencyPickerConstants.allCurrencyCodes.filter { code in
            if code.lowercased().contains(lower) { return true }

            let name = CurrencyPickerConstants.localizedCurrencyName(for: code)
            if name.lowercased().contains(lower) { return true }

            let symbol = CurrencyPickerConstants.currencySymbol(for: code)
            if !symbol.isEmpty, symbol.lowercased().contains(lower) { return true }

            return false
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    selectedCode = CurrencyPickerConstants.systemTag
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("System Default")
                            Text("\(CurrencyPickerConstants.localizedCurrencyName(for: CurrencyPickerConstants.systemCurrencyCode)) • \(CurrencyPickerConstants.systemCurrencyCode)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if selectedCode == CurrencyPickerConstants.systemTag {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Section("Currencies") {
                ForEach(filteredCurrencies, id: \.self) { code in
                    Button {
                        selectedCode = code
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(CurrencyPickerConstants.localizedCurrencyName(for: code))
                                Text("\(CurrencyPickerConstants.currencySymbol(for: code)) • \(code)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if selectedCode == code {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Currency")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search currency or code"
        )
    }
}

// MARK: - Helpers

private enum CurrencyPickerConstants {
    static let systemTag: String = "SYSTEM"

    static var systemCurrencyCode: String {
        if let id = Locale.current.currency?.identifier, !id.isEmpty {
            return id
        }
        return "USD"
    }

    static var allCurrencyCodes: [String] = {
        let all = Set(Locale.Currency.isoCurrencies.map(\.identifier))
        let common = Set(Locale.commonISOCurrencyCodes)

        let uncommonSorted = all.subtracting(common).sorted()
        return Locale.commonISOCurrencyCodes + uncommonSorted
    }()

    static func localizedCurrencyName(for code: String) -> String {
        Locale.current.localizedString(forCurrencyCode: code) ?? code
    }

    static func currencySymbol(for code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = .current
        formatter.currencyCode = code
        return formatter.currencySymbol ?? ""
    }
}

#Preview("Settings General") {
    NavigationStack {
        SettingsGeneralView()
    }
}
