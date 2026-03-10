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

#if canImport(PhotosUI)
import PhotosUI
#endif

#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

@MainActor
struct SettingsPrivacyView: View {

    @AppStorage("privacy_requireBiometrics") private var requireBiometrics: Bool = false
    @AppStorage("privacy_hideBalances") private var hideBalances: Bool = false

    // Handshake for avoiding double-auth when enabling App Lock.
    // Stored as a timestamp so AppLockGate can detect “just authenticated”.
    @AppStorage("privacy_lastSuccessfulAuthAt") private var lastSuccessfulAuthAt: Double = 0

    @Environment(\.scenePhase) private var scenePhase

    // Toggle UI state to authenticate before committing to AppStorage.
    @State private var requireBiometricsToggle: Bool = false

    #if canImport(CoreLocation)
    @State private var locationPermissionState: CLAuthorizationStatus = .notDetermined
    #endif

    #if canImport(Photos)
    @State private var photosPermissionState: PHAuthorizationStatus = .notDetermined
    #endif

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
                locationPermissionRow
                photosPermissionRow

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
                    description: "Allows Offshore to use mobile data during Excursion Mode when Wi-Fi may be unavailable.\nNote: Cellular Data is not needed to use the core functionalities of Offshore."
                )

                Button {
                    openSystemSettings()
                } label: {
                    Label("Open App Settings", systemImage: "gearshape")
                }
            } header: {
                Text("System Permissions")
            } footer: {
                Text("Offshore reflects Apple’s on-device permission system status. You can change any permission at any time in App Settings.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Privacy")
        .onAppear {
            requireBiometricsToggle = requireBiometrics
            refreshPermissionStates()
        }
        .onChange(of: scenePhase) { _, newValue in
            guard newValue == .active else { return }
            refreshPermissionStates()
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

    // MARK: - Permission Rows

    @ViewBuilder
    private var locationPermissionRow: some View {
        #if canImport(CoreLocation)
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Location", value: locationPermissionStatusText)

            Text("Allows Offshore to use Location Services during Excursion Mode to nudge you to log expenses before you forget.\nNote: Location Services are not needed to use the core functionalities of Offshore.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            switch locationPermissionState {
            case .notDetermined:
                Button("Enable for Excursion Mode") {
                    ShoppingModeLocationService.shared.requestAuthorizationForExcursionMode()
                }
            case .authorizedWhenInUse:
                Button("Upgrade in App Settings") {
                    openSystemSettings()
                }
            case .denied, .restricted:
                Button("Manage in App Settings") {
                    openSystemSettings()
                }
            case .authorizedAlways:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
        #else
        permissionRow(
            title: "Location",
            status: "Unavailable",
            description: "Allows Offshore to use Location Services during Excursion Mode to nudge you to log expenses before you forget.\nNote: Location Services are not needed to use the core functionalities of Offshore."
        )
        #endif
    }

    @ViewBuilder
    private var photosPermissionRow: some View {
        #if canImport(Photos)
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Photos", value: photosPermissionStatusText)

            Text("Allows importing screenshots from your Photos Library for quicker income and expense entry.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            switch photosPermissionState {
            case .notDetermined:
                Button("Allow Full Photo Access") {
                    Task {
                        _ = await PhotoLibraryAccessManager.shared.requestReadWriteAuthorization()
                        refreshPermissionStates()
                    }
                }
            case .limited:
                if PhotoLibraryAccessManager.shared.canManageLimitedLibrarySelection {
                    Button("Manage Selected Photos") {
                        if PhotoLibraryAccessManager.shared.presentLimitedLibraryPicker() == false {
                            openSystemSettings()
                        }
                    }
                }

                Button("Open App Settings") {
                    openSystemSettings()
                }
            case .denied, .restricted:
                Button("Manage in App Settings") {
                    openSystemSettings()
                }
            case .authorized:
                EmptyView()
            @unknown default:
                EmptyView()
            }
        }
        #else
        permissionRow(
            title: "Photos",
            status: "Unavailable",
            description: "Allows importing screenshots from your Photos Library for quicker income and expense entry."
        )
        #endif
    }

    // MARK: - Biometric Flow

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

    private func refreshPermissionStates() {
        #if canImport(CoreLocation)
        locationPermissionState = ShoppingModeLocationService.shared.currentAuthorizationStatus()
        #endif

        #if canImport(Photos)
        photosPermissionState = PhotoLibraryAccessManager.shared.authorizationStatus()
        #endif
    }

    private var locationPermissionStatusText: String {
        #if canImport(CoreLocation)
        switch locationPermissionState {
        case .authorizedAlways:
            return String(localized: "privacy.permissionStatus.alwaysAllow", defaultValue: "Always Allow", comment: "Permission status when location access is always allowed.")
        case .authorizedWhenInUse:
            return String(localized: "privacy.permissionStatus.whileUsingApp", defaultValue: "While Using App", comment: "Permission status when location access is only allowed while using the app.")
        case .denied:
            return String(localized: "privacy.permissionStatus.denied", defaultValue: "Denied", comment: "Permission status when access has been denied.")
        case .restricted:
            return String(localized: "privacy.permissionStatus.restricted", defaultValue: "Restricted", comment: "Permission status when access is restricted by the system.")
        case .notDetermined:
            return String(localized: "privacy.permissionStatus.notRequestedYet", defaultValue: "Not Requested Yet", comment: "Permission status when access has not been requested yet.")
        @unknown default:
            return String(localized: "privacy.permissionStatus.unknown", defaultValue: "Unknown", comment: "Fallback permission status when the system returns an unknown value.")
        }
        #else
        return String(localized: "privacy.permissionStatus.unavailable", defaultValue: "Unavailable", comment: "Permission status shown when a capability is unavailable on the current platform.")
        #endif
    }

    private var photosPermissionStatusText: String {
        #if canImport(Photos)
        switch photosPermissionState {
        case .authorized:
            return String(localized: "privacy.permissionStatus.fullAccess", defaultValue: "Full Access", comment: "Permission status when photo library access is fully allowed.")
        case .limited:
            return String(localized: "privacy.permissionStatus.limited", defaultValue: "Limited", comment: "Permission status when photo library access is limited.")
        case .denied:
            return String(localized: "privacy.permissionStatus.denied", defaultValue: "Denied", comment: "Permission status when access has been denied.")
        case .restricted:
            return String(localized: "privacy.permissionStatus.restricted", defaultValue: "Restricted", comment: "Permission status when access is restricted by the system.")
        case .notDetermined:
            return String(localized: "privacy.permissionStatus.pickerOnly", defaultValue: "Picker Only", comment: "Permission status when the user has only granted picker-based photo access.")
        @unknown default:
            return String(localized: "privacy.permissionStatus.unknown", defaultValue: "Unknown", comment: "Fallback permission status when the system returns an unknown value.")
        }
        #else
        return String(localized: "privacy.permissionStatus.unavailable", defaultValue: "Unavailable", comment: "Permission status shown when a capability is unavailable on the current platform.")
        #endif
    }

    private var liveActivitiesStatus: String {
        #if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
        if #available(iOS 16.1, *) {
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                return String(localized: "privacy.permissionStatus.allowed", defaultValue: "Allowed", comment: "Permission status when a capability is allowed.")
            } else {
                return String(localized: "privacy.permissionStatus.off", defaultValue: "Off", comment: "Permission status when a capability is turned off.")
            }
        } else {
            return String(localized: "privacy.permissionStatus.unavailable", defaultValue: "Unavailable", comment: "Permission status shown when a capability is unavailable on the current platform.")
        }
        #else
        return String(localized: "privacy.permissionStatus.unavailable", defaultValue: "Unavailable", comment: "Permission status shown when a capability is unavailable on the current platform.")
        #endif
    }

    private var backgroundAppRefreshStatus: String {
        #if canImport(UIKit)
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available:
            return String(localized: "privacy.permissionStatus.allowed", defaultValue: "Allowed", comment: "Permission status when a capability is allowed.")
        case .denied:
            return String(localized: "privacy.permissionStatus.off", defaultValue: "Off", comment: "Permission status when a capability is turned off.")
        case .restricted:
            return String(localized: "privacy.permissionStatus.restricted", defaultValue: "Restricted", comment: "Permission status when access is restricted by the system.")
        @unknown default:
            return String(localized: "privacy.permissionStatus.unknown", defaultValue: "Unknown", comment: "Fallback permission status when the system returns an unknown value.")
        }
        #else
        return String(localized: "privacy.permissionStatus.unavailable", defaultValue: "Unavailable", comment: "Permission status shown when a capability is unavailable on the current platform.")
        #endif
    }

    private var cellularDataStatus: String {
        String(localized: "Manage in App Settings", defaultValue: "Manage in App Settings", comment: "Button-like status text shown when the user must manage a permission in App Settings.")
    }

    @ViewBuilder
    private func permissionRow(title: LocalizedStringKey, status: String, description: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent {
                Text(status)
            } label: {
                Text(title)
            }

            Text(description)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - PhotoLibraryAccessManager

#if canImport(Photos)
@MainActor
final class PhotoLibraryAccessManager {
    static let shared = PhotoLibraryAccessManager()

    private init() {}

    func authorizationStatus() -> PHAuthorizationStatus {
        if #available(iOS 14.0, macCatalyst 14.0, *) {
            return PHPhotoLibrary.authorizationStatus(for: .readWrite)
        } else {
            return PHPhotoLibrary.authorizationStatus()
        }
    }

    func requestReadWriteAuthorization() async -> PHAuthorizationStatus {
        if #available(iOS 14.0, macCatalyst 14.0, *) {
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                    continuation.resume(returning: status)
                }
            }
        } else {
            return await withCheckedContinuation { continuation in
                PHPhotoLibrary.requestAuthorization { status in
                    continuation.resume(returning: status)
                }
            }
        }
    }

    var canManageLimitedLibrarySelection: Bool {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    @discardableResult
    func presentLimitedLibraryPicker() -> Bool {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        guard let presenter = topViewController() else { return false }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter)
        return true
        #else
        return false
        #endif
    }

    #if canImport(UIKit) && !targetEnvironment(macCatalyst)
    private func topViewController() -> UIViewController? {
        let connectedScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let foregroundScene = connectedScenes.first { $0.activationState == .foregroundActive }
        let rootViewController = foregroundScene?
            .windows
            .first(where: \.isKeyWindow)?
            .rootViewController

        return topViewController(from: rootViewController)
    }

    private func topViewController(from root: UIViewController?) -> UIViewController? {
        if let navigationController = root as? UINavigationController {
            return topViewController(from: navigationController.visibleViewController)
        }

        if let tabBarController = root as? UITabBarController {
            return topViewController(from: tabBarController.selectedViewController)
        }

        if let presentedViewController = root?.presentedViewController {
            return topViewController(from: presentedViewController)
        }

        return root
    }
    #endif
}
#endif

#Preview("Settings Privacy") {
    NavigationStack {
        SettingsPrivacyView()
    }
}
