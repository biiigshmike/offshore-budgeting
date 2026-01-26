//
//  AppLockGate.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI

struct AppLockGate<Content: View>: View {

    @Binding var isEnabled: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.scenePhase) private var scenePhase

    @State private var isUnlocked: Bool = false
    @State private var isAuthenticating: Bool = false

    @State private var showingError: Bool = false
    @State private var errorMessage: String = ""

    // Handshake timestamp written by SettingsPrivacyView when enabling app lock.
    @AppStorage("privacy_lastSuccessfulAuthAt") private var lastSuccessfulAuthAt: Double = 0

    init(isEnabled: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) {
        self._isEnabled = isEnabled
        self.content = content
    }

    var body: some View {
        ZStack {
            if !isEnabled || isUnlocked {
                content()
            } else {
                lockScreen
            }
        }
        .onAppear {
            isUnlocked = !isEnabled
            if isEnabled {
                Task { await unlockIfNeeded() }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if isEnabled {
                    Task { await unlockIfNeeded() }
                }
            case .inactive, .background:
                // Lock whenever the app leaves the foreground.
                isUnlocked = false
            @unknown default:
                isUnlocked = false
            }
        }
        .onChange(of: isEnabled) { _, newValue in
            if newValue == false {
                isUnlocked = true
            } else {
                // If we JUST authenticated in Settings to enable this,
                // don’t prompt again. Unlock immediately and consume the token.
                if consumeRecentEnableAuthenticationIfPresent() {
                    isUnlocked = true
                    return
                }

                isUnlocked = false
                Task { await unlockIfNeeded() }
            }
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("App Locked")
                .font(.title2.weight(.semibold))

            Text("Authenticate to continue.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task { await unlockIfNeeded() }
            } label: {
                if isAuthenticating {
                    ProgressView()
                        .frame(minWidth: 120, minHeight: 44)
                } else {
                    Text("Unlock")
                        .frame(minWidth: 120, minHeight: 44)
                }
            }
            .buttonStyle(.glassProminent)
            .disabled(isAuthenticating)
        }
        .padding()
    }

    @MainActor
    private func unlockIfNeeded() async {
        guard isEnabled else {
            isUnlocked = true
            return
        }

        guard !isUnlocked, !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let success = try await LocalAuthenticationService.authenticateForUnlock(
                localizedReason: "Unlock the app to access your budgeting data."
            )

            if success {
                isUnlocked = true
            } else {
                // User canceled, stay locked quietly.
                isUnlocked = false
            }
        } catch {
            isUnlocked = false
            errorMessage = LocalAuthenticationService.userFriendlyMessage(for: error)
            showingError = true
        }
    }

    // MARK: - Enable handshake

    /// Returns true if we detect a “just authenticated” signal from Settings,
    /// and consumes it so it only works once.
    private func consumeRecentEnableAuthenticationIfPresent() -> Bool {
        // Small window: only intended to prevent double prompt when enabling.
        let graceSeconds: Double = 3.0

        let now = Date().timeIntervalSince1970
        let elapsed = now - lastSuccessfulAuthAt

        guard lastSuccessfulAuthAt > 0, elapsed >= 0, elapsed <= graceSeconds else {
            return false
        }

        // Consume the token so it doesn't skip future locks.
        lastSuccessfulAuthAt = 0
        return true
    }
}

#if canImport(UIKit)
import UIKit

private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}
#endif
