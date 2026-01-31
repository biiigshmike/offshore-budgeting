//
//  SettingsPrivacyView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI

struct SettingsPrivacyView: View {

    @AppStorage("privacy_requireBiometrics") private var requireBiometrics: Bool = false
    @AppStorage("privacy_hideBalances") private var hideBalances: Bool = false

    // Handshake for avoiding double-auth when enabling App Lock.
    // Stored as a timestamp so AppLockGate can detect “just authenticated”.
    @AppStorage("privacy_lastSuccessfulAuthAt") private var lastSuccessfulAuthAt: Double = 0

    // Toggle UI state, so we can authenticate before committing to AppStorage.
    @State private var requireBiometricsToggle: Bool = false

    @State private var showingEnableError: Bool = false
    @State private var enableErrorMessage: String = ""

    private var biometricAvailability: LocalAuthenticationService.BiometricAvailability {
        LocalAuthenticationService.biometricAvailability()
    }

    private var biometricToggleTitle: String {
        switch biometricAvailability.kind {
        case .faceID:
            return "Use Face ID"
        case .touchID:
            return "Use Touch ID"
        case .none:
            return "Use Face ID / Touch ID"
        }
    }

    private var biometricsToggleIsEnabled: Bool {
        biometricAvailability.isAvailable && biometricAvailability.kind != .none
    }

    var body: some View {
        List {

            // MARK: - Security

            Section {
                Toggle(biometricToggleTitle, isOn: $requireBiometricsToggle)
                    .tint(Color("AccentColor"))

                    .disabled(!biometricsToggleIsEnabled)

                if !biometricsToggleIsEnabled {
                    Text(biometricAvailability.errorMessage ?? "Face ID or Touch ID isn’t available on this device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Security")
            } footer: {
                Text("")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy")
        .onAppear {
            requireBiometricsToggle = requireBiometrics
        }
        .onChange(of: requireBiometrics) { _, newValue in
            // Keep UI toggle in sync if changed elsewhere.
            if requireBiometricsToggle != newValue {
                requireBiometricsToggle = newValue
            }
        }
        .onChange(of: requireBiometricsToggle) { _, newValue in
            guard newValue != requireBiometrics else { return }

            if newValue == false {
                requireBiometrics = false
                return
            }

            // Turning ON: authenticate first, then commit.
            Task {
                await attemptEnableBiometricLock()
            }
        }
        .alert("Unable to Enable App Lock", isPresented: $showingEnableError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(enableErrorMessage)
        }
    }

    @MainActor
    private func attemptEnableBiometricLock() async {
        let availability = biometricAvailability
        guard availability.isAvailable, availability.kind != .none else {
            requireBiometrics = false
            requireBiometricsToggle = false
            enableErrorMessage = availability.errorMessage ?? "Face ID or Touch ID is not available on this device."
            showingEnableError = true
            return
        }

        do {
            let reason = "Enable \(availability.kind.displayName) to unlock the app."
            let success = try await LocalAuthenticationService.authenticateForUnlock(localizedReason: reason)

            if success {
                // Mark “just authenticated” so AppLockGate doesn’t prompt again immediately.
                lastSuccessfulAuthAt = Date().timeIntervalSince1970

                requireBiometrics = true
                requireBiometricsToggle = true
            } else {
                // User canceled, keep it off quietly.
                requireBiometrics = false
                requireBiometricsToggle = false
            }
        } catch {
            requireBiometrics = false
            requireBiometricsToggle = false
            enableErrorMessage = LocalAuthenticationService.userFriendlyMessage(for: error)
            showingEnableError = true
        }
    }
}

#Preview("Settings Privacy") {
    NavigationStack {
        SettingsPrivacyView()
    }
}
