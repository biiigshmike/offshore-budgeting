//
//  SettingsPrivacyView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

#if canImport(CoreLocation)
import CoreLocation
#endif

#if canImport(Photos)
import Photos
#endif

#if canImport(ActivityKit)
import ActivityKit
#endif

struct SettingsPrivacyView: View {

    @AppStorage("privacy_requireBiometrics") private var requireBiometrics: Bool = false
    @AppStorage("privacy_hideBalances") private var hideBalances: Bool = false

    // Handshake for avoiding double-auth when enabling App Lock.
    // Stored as a timestamp so AppLockGate can detect “just authenticated”.
    @AppStorage("privacy_lastSuccessfulAuthAt") private var lastSuccessfulAuthAt: Double = 0

    // Toggle UI state to authenticate before committing to AppStorage.
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

            // MARK: - System Permissions

            Section {
                permissionRow(
                    title: "Location",
                    status: locationPermissionStatus,
                    description: "Excursion Mode uses location for a short period to monitor store entry and nudge you to log expenses before you forget."
                )

                permissionRow(
                    title: "Photos",
                    status: photosPermissionStatus,
                    description: "Allows importing screenshots from your Photos Library for quicker income and expense entry."
                )

                permissionRow(
                    title: "Live Activities",
                    status: liveActivitiesStatus,
                    description: "Shows Excursion Mode status and timing on your Lock Screen while the session is active."
                )

                permissionRow(
                    title: "Background App Refresh",
                    status: backgroundAppRefreshStatus,
                    description: "Helps Excursion Mode continue monitoring reliably when Offshore is not in the foreground."
                )

                permissionRow(
                    title: "Cellular Data",
                    status: cellularDataStatus,
                    description: "Allows Offshore to use mobile data. Offshore can run offline, but cellular helps Excursion Mode when Wi-Fi is unavailable."
                )

                Button {
                    openSystemSettings()
                } label: {
                    Label("Open App Settings", systemImage: "gearshape")
                }
            } header: {
                Text("System Permissions")
            } footer: {
                Text("These controls use Apple’s on-device permission system. Offshore reflects your current status here, and you can change any permission anytime in App Settings.")
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

    // MARK: - System Settings

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    // MARK: - Permission Status

    private var locationPermissionStatus: String {
        #if canImport(CoreLocation)
        let status: CLAuthorizationStatus
        if #available(iOS 14.0, macCatalyst 14.0, *) {
            status = CLLocationManager().authorizationStatus
        } else {
            status = CLLocationManager.authorizationStatus()
        }

        switch status {
        case .authorizedAlways:
            return "Always Allow"
        case .authorizedWhenInUse:
            return "While Using App"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
        #else
        return "Unavailable"
        #endif
    }

    private var photosPermissionStatus: String {
        #if canImport(Photos)
        let status: PHAuthorizationStatus
        if #available(iOS 14.0, macCatalyst 14.0, *) {
            status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            status = PHPhotoLibrary.authorizationStatus()
        }

        switch status {
        case .authorized:
            return "Allowed"
        case .limited:
            return "Limited"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        case .notDetermined:
            return "Not Determined"
        @unknown default:
            return "Unknown"
        }
        #else
        return "Unavailable"
        #endif
    }

    private var liveActivitiesStatus: String {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled ? "Allowed" : "Off"
        } else {
            return "Unavailable"
        }
        #else
        return "Unavailable"
        #endif
    }

    private var backgroundAppRefreshStatus: String {
        #if canImport(UIKit)
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            return "Allowed"
        case .denied:
            return "Off"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
        #else
        return "Unavailable"
        #endif
    }

    private var cellularDataStatus: String {
        "Managed in iOS Settings"
    }

    @ViewBuilder
    private func permissionRow(title: String, status: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(title, value: status)

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Settings Privacy") {
    NavigationStack {
        SettingsPrivacyView()
    }
}
