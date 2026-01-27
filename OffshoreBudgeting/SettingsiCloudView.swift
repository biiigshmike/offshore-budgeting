//
//  SettingsiCloudView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

import SwiftData

struct SettingsiCloudView: View {

    // MARK: - Persisted Settings

    @AppStorage("icloud_useCloud") private var desiredUseICloud: Bool = false
    @AppStorage("icloud_activeUseCloud") private var activeUseICloud: Bool = false
    @AppStorage("selectedWorkspaceID") private var selectedWorkspaceID: String = ""

    // MARK: - UI State

    @State private var showingUnavailableAlert: Bool = false
    @State private var showingEnableConfirm: Bool = false
    @State private var showingRestartRequired: Bool = false

    @Query(sort: \Workspace.name, order: .forward)
    private var workspaces: [Workspace]

    var body: some View {
        List {
            Section("iCloud Sync") {
                Toggle("Use iCloud to Sync Data", isOn: Binding(
                    get: { desiredUseICloud },
                    set: { newValue in
                        handleToggleChange(newValue)
                    }
                ))

                statusRow

                Text("When enabled, your budgets and transactions sync across devices with the same Apple ID. When disabled, data stays only on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

//            Section("Container") {
//                Text(cloudKitContainerIdentifier)
//                    .font(.footnote.monospaced())
//                    .foregroundStyle(.secondary)
//                    .textSelection(.enabled)
//            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("iCloud")
        .alert("iCloud Unavailable", isPresented: $showingUnavailableAlert) {
            #if canImport(UIKit)
            Button("Open Settings") { openSystemSettings() }
            #endif
            Button("OK", role: .cancel) { }
        } message: {
            Text("To use iCloud sync, sign in to iCloud in the Settings app, then return here and try again.")
        }
        .alert("Switch to iCloud?", isPresented: $showingEnableConfirm) {
            Button("Enable iCloud") { requestEnableICloud() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will switch you to your iCloud data. Your on-device data stays on this device and can be accessed by switching back to On Device.")
        }
        .sheet(isPresented: $showingRestartRequired) {
            RestartRequiredView(
                title: "Restart Required",
                message: AppRestartService.restartRequiredMessage(
                    debugMessage: "Changing iCloud sync takes effect after you close and reopen Offshore."
                ),
                primaryButtonTitle: AppRestartService.closeAppButtonTitle,
                onPrimary: { AppRestartService.closeAppOrDismiss { showingRestartRequired = false } },
                secondaryButtonTitle: "Not Now",
                onSecondary: { showingRestartRequired = false }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - UI

    private var statusRow: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIconName)
                .foregroundStyle(statusIconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))

                Text(statusSubtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.vertical, 4)
    }

    private var isICloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    private var statusIconName: String {
        if activeUseICloud {
            return isICloudAvailable ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill"
        } else {
            return "icloud"
        }
    }

    private var statusIconColor: Color {
        if activeUseICloud {
            return isICloudAvailable ? .green : .orange
        } else {
            return .secondary
        }
    }

    private var statusTitle: String {
        if desiredUseICloud != activeUseICloud {
            return "Restart Required"
        }

        if activeUseICloud {
            return isICloudAvailable ? "Syncing Enabled" : "Enabled, But Not Available"
        } else {
            return "Syncing Disabled"
        }
    }

    private var statusSubtitle: String {
        if desiredUseICloud != activeUseICloud {
            return "Close and reopen Offshore to apply this change."
        }

        if activeUseICloud {
            return isICloudAvailable
            ? "Your data will sync via iCloud."
            : "Sign in to iCloud in Settings to enable syncing."
        } else {
            return "Data is stored only on this device."
        }
    }

    // MARK: - Actions

    private func handleToggleChange(_ wantsEnabled: Bool) {
        if wantsEnabled {
            guard isICloudAvailable else {
                // Revert toggle and explain.
                desiredUseICloud = false
                showingUnavailableAlert = true
                return
            }

            if !workspaces.isEmpty {
                desiredUseICloud = false
                showingEnableConfirm = true
                return
            }

            requestEnableICloud()
        } else {
            desiredUseICloud = false
            if desiredUseICloud != activeUseICloud {
                showingRestartRequired = true
            }
        }
    }

    private func requestEnableICloud() {
        desiredUseICloud = true
        if desiredUseICloud != activeUseICloud {
            showingRestartRequired = true
        }
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}

#Preview("iCloud") {
    NavigationStack { SettingsiCloudView() }
}
