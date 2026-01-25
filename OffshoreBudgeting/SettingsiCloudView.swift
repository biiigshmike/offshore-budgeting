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

struct SettingsiCloudView: View {

    // MARK: - Persisted Settings

    @AppStorage("icloud_useCloud") private var useICloud: Bool = false
    @AppStorage("app_rootResetToken") private var rootResetToken: String = UUID().uuidString

    // MARK: - UI State

    @State private var showingUnavailableAlert: Bool = false

    private let cloudKitContainerIdentifier: String = "iCloud.com.mb.offshore-budgeting"

    var body: some View {
        List {
            Section("iCloud Sync") {
                Toggle("Use iCloud to Sync Data", isOn: Binding(
                    get: { useICloud },
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
        if useICloud {
            return isICloudAvailable ? "checkmark.icloud.fill" : "exclamationmark.icloud.fill"
        } else {
            return "icloud"
        }
    }

    private var statusIconColor: Color {
        if useICloud {
            return isICloudAvailable ? .green : .orange
        } else {
            return .secondary
        }
    }

    private var statusTitle: String {
        if useICloud {
            return isICloudAvailable ? "Syncing Enabled" : "Enabled, But Not Available"
        } else {
            return "Syncing Disabled"
        }
    }

    private var statusSubtitle: String {
        if useICloud {
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
                useICloud = false
                showingUnavailableAlert = true
                return
            }

            useICloud = true
            bumpRootResetToken()
        } else {
            useICloud = false
            bumpRootResetToken()
        }
    }

    private func bumpRootResetToken() {
        // Forces a full SwiftUI rebuild, so the app recreates the SwiftData container.
        rootResetToken = UUID().uuidString
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
