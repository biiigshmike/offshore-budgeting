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

    // Step 1.3
    @AppStorage("tips_resetToken") private var tipsResetToken: Int = 0
    @State private var showingTipsResetAlert: Bool = false

    // Step 1.4
    @State private var showingEraseConfirm: Bool = false
    @State private var showingEraseResultAlert: Bool = false
    @State private var eraseResultMessage: String = ""

    // Reset-to-first-run flags
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding: Bool = false
    @AppStorage("selectedWorkspaceID") private var selectedWorkspaceID: String = ""
    @AppStorage("didSeedDefaultWorkspaces") private var didSeedDefaultWorkspaces: Bool = false
    @AppStorage("privacy_requireBiometrics") private var requireBiometrics: Bool = false

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
                Toggle("Confirm Before Deleting", isOn: $confirmBeforeDeleting)

                Text("When enabled, you’ll always be asked to confirm before anything is deleted.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Maintenance") {
                HStack(spacing: 12) {
                    Button {
                        tipsResetToken += 1
                        showingTipsResetAlert = true
                    } label: {
                        Text("Reset Tips & Hints")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.orange)

                    Button {
                        showingEraseConfirm = true
                    } label: {
                        Text("Reset & Erase Content")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                }

//                Text("Erase will remove all budgets, cards, categories, presets, transactions, and workspaces from this device.")
//                    .font(.footnote)
//                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("General")
        .alert("Tips & Hints Reset", isPresented: $showingTipsResetAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Tips and hints will be shown again.")
        }
        .alert("Reset & Erase Content?", isPresented: $showingEraseConfirm) {
            Button("Erase", role: .destructive) {
                performLocalErase()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently remove your data from this device and return you to onboarding.")
        }
        .alert("Reset Complete", isPresented: $showingEraseResultAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(eraseResultMessage)
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

    // MARK: - Erase

    private func performLocalErase() {
        do {
            try AppResetService.eraseAllLocalData(modelContext: modelContext)

            // Reset app flags to feel like first-run
            selectedWorkspaceID = ""
            didSeedDefaultWorkspaces = false
            didCompleteOnboarding = false

            // Safety: if app lock was enabled, disable it so onboarding isn’t blocked
            requireBiometrics = false

            // Optional: bring tips back to a clean baseline
            tipsResetToken = 0

            eraseResultMessage = "All content has been erased. You’ll be returned to onboarding."
            showingEraseResultAlert = true
        } catch {
            eraseResultMessage = "Something went wrong while erasing data: \(error.localizedDescription)"
            showingEraseResultAlert = true
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
