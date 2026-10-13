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


#if canImport(Photos)
import Photos
#endif

#if canImport(PhotosUI)
import PhotosUI
#endif


@MainActor
struct SettingsPrivacyView: View {
    private enum SystemPermissionKind {
        case photos
    }

    @AppStorage("privacy_requireBiometrics") private var requireBiometrics: Bool = false
    @AppStorage("privacy_hideBalances") private var hideBalances: Bool = false

    // Handshake for avoiding double-auth when enabling App Lock.
    // Stored as a timestamp so AppLockGate can detect “just authenticated”.
    @AppStorage("privacy_lastSuccessfulAuthAt") private var lastSuccessfulAuthAt: Double = 0

    @Environment(\.scenePhase) private var scenePhase

    // Toggle UI state to authenticate before committing to AppStorage.
    @State private var requireBiometricsToggle: Bool = false


    #if canImport(Photos)
    @State private var photosPermissionState: PHAuthorizationStatus = .notDetermined
    #endif

    @State private var showingEnableError: Bool = false
    @State private var enableErrorMessage: String = ""

    private var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        true
        #else
        false
        #endif
    }

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
                photosPermissionRow

                Button {
                    openAppOrSystemSettings()
                } label: {
                    Label(isMacCatalyst ? "Open System Settings" : "Open App Settings", systemImage: "gearshape")
                }
            } header: {
                Text("System Permissions")
            } footer: {
                Text(
                    isMacCatalyst
                    ? "Offshore reflects Apple’s on-device permission system status. On Mac, the button opens the relevant area in System Settings, and you can enable Offshore there if needed."
                    : "Offshore reflects Apple’s on-device permission system status. You can change any permission at any time in App Settings."
                )
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
    private var photosPermissionRow: some View {
        #if canImport(Photos)
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Photos", value: photosPermissionStatusText)

            Text("Allows importing screenshots from your Photos Library for quicker income and expense entry.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            switch photosPermissionState {
            case .notDetermined:
                if !isMacCatalyst {
                    Button("Allow Full Photo Access") {
                        Task {
                            _ = await PhotoLibraryAccessManager.shared.requestReadWriteAuthorization()
                            refreshPermissionStates()
                        }
                    }
                }
            case .limited:
                if PhotoLibraryAccessManager.shared.canManageLimitedLibrarySelection {
                    Button("Manage Selected Photos") {
                        if PhotoLibraryAccessManager.shared.presentLimitedLibraryPicker() == false {
                            openSystemSettings(for: .photos)
                        }
                    }
                }

                if !isMacCatalyst {
                    Button("Open App Settings") {
                        openAppOrSystemSettings()
                    }
                }
            case .denied, .restricted:
                if isMacCatalyst {
                    Button("Open Photos Settings") {
                        openSystemSettings(for: .photos)
                    }
                } else {
                    Button("Manage in App Settings") {
                        openSystemSettings(for: .photos)
                    }
                }
            case .authorized:
                EmptyView()
            @unknown default:
                EmptyView()
            }

            if isMacCatalyst {
                Text("On Mac, Offshore imports screenshots through the system photo picker, so you can choose images without granting full photo library access.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                if let instructions = systemSettingsInstructions(for: .photos) {
                    Text("If you want to review Photos access, open \(instructions).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
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

    private func openAppOrSystemSettings() {
        openSystemSettings(for: nil)
    }

    private func openSystemSettings(for permission: SystemPermissionKind?) {
        #if canImport(UIKit)
        if isMacCatalyst,
           let url = macSystemSettingsURL(for: permission) {
            UIApplication.shared.open(url) { success in
                guard success == false,
                      let fallbackURL = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(fallbackURL)
            }
            return
        }

        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    private func macSystemSettingsURL(for permission: SystemPermissionKind?) -> URL? {
        guard isMacCatalyst else { return nil }

        let urlString: String
        switch permission {
        case .photos:
            urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos"
        case nil:
            urlString = "x-apple.systempreferences:com.apple.preference.security"
        }

        return URL(string: urlString)
    }

    private func systemSettingsInstructions(for permission: SystemPermissionKind) -> String? {
        guard isMacCatalyst else { return nil }

        switch permission {
        case .photos:
            return "System Settings > Privacy & Security > Photos"
        }
    }

    // MARK: - Permission Status

    private func refreshPermissionStates() {

        #if canImport(Photos)
        photosPermissionState = PhotoLibraryAccessManager.shared.authorizationStatus()
        #endif
    }

    private var photosPermissionStatusText: String {
        #if canImport(Photos)
        if isMacCatalyst {
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
                return String(localized: "privacy.permissionStatus.pickerOnly", defaultValue: "Picker Only", comment: "Permission status when photo import uses the system picker without broader library access.")
            @unknown default:
                return String(localized: "privacy.permissionStatus.unknown", defaultValue: "Unknown", comment: "Fallback permission status when the system returns an unknown value.")
            }
        }

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
