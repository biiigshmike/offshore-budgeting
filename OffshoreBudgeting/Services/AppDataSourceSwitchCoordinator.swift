//
//  AppDataSourceSwitchCoordinator.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/2/26.
//

import Foundation
import Combine
import SwiftData

@MainActor
final class AppDataSourceSwitchCoordinator: ObservableObject {

    // MARK: - Types

    enum DataSource {
        case onDevice
        case iCloud

        var usesICloud: Bool {
            switch self {
            case .onDevice: return false
            case .iCloud: return true
            }
        }
    }

    struct SwitchAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: - Published

    @Published var modelContainer: ModelContainer
    @Published var switchAlert: SwitchAlert? = nil

    // MARK: - Init

    init() {
        #if DEBUG
        UITestSupport.applyResetIfNeeded()
        #endif

        let desiredUseICloud = UserDefaults.standard.bool(forKey: "icloud_useCloud")
        Self.updateICloudActivationState(useICloud: desiredUseICloud)

        #if DEBUG
        if Self.isScreenshotModeEnabled {
            UserDefaults.standard.set(false, forKey: "icloud_activeUseCloud")
            UserDefaults.standard.set(0.0, forKey: "icloud_bootstrapStartedAt")
            self.modelContainer = OffshoreBudgetingApp.makeModelContainer(
                useICloud: false,
                debugStoreOverride: "Screenshots"
            )
            return
        }
        #endif

        self.modelContainer = OffshoreBudgetingApp.makeModelContainer(useICloud: desiredUseICloud)
    }

    // MARK: - Activation

    func activateDataSource(useICloud: Bool) {
        UserDefaults.standard.set(useICloud, forKey: "icloud_useCloud")
        Self.updateICloudActivationState(useICloud: useICloud)
        modelContainer = OffshoreBudgetingApp.makeModelContainer(useICloud: useICloud)
    }

    func switchDataSource(to dataSource: DataSource) {
        #if DEBUG
        if Self.isScreenshotModeEnabled {
            switchAlert = SwitchAlert(
                title: "Unavailable",
                message: "Data source switching is disabled while screenshot mode is enabled."
            )
            return
        }
        #endif

        let wantsICloud = dataSource.usesICloud
        let currentlyUsingICloud = UserDefaults.standard.bool(forKey: "icloud_activeUseCloud")
        guard wantsICloud != currentlyUsingICloud else { return }

        if wantsICloud, FileManager.default.ubiquityIdentityToken == nil {
            switchAlert = SwitchAlert(
                title: "iCloud Unavailable",
                message: "Sign into iCloud in Settings, then try again."
            )
            return
        }

        do {
            let container = try OffshoreBudgetingApp.tryMakeModelContainer(useICloud: wantsICloud)

            // Swap the UI into a SwiftData-free shell before we apply the new container,
            // so we don't read stale model instances during the transition.
            UserDefaults.standard.set(true, forKey: "app_isSwitchingDataSource")
            UserDefaults.standard.set(UUID().uuidString, forKey: "app_rootResetToken")

            Task { @MainActor in
                await Task.yield()

                modelContainer = container

                UserDefaults.standard.set(wantsICloud, forKey: "icloud_useCloud")
                Self.updateICloudActivationState(useICloud: wantsICloud)

                UserDefaults.standard.set("", forKey: "selectedWorkspaceID")
                UserDefaults.standard.set(false, forKey: "app_isSwitchingDataSource")

                if wantsICloud {
                    switchAlert = SwitchAlert(
                        title: "Switched to iCloud",
                        message: "Data may take a moment to finish syncing."
                    )
                } else {
                    switchAlert = SwitchAlert(
                        title: "Switched to On Device",
                        message: "Your iCloud data stays in iCloud and will be available if you switch back."
                    )
                }
            }
        } catch {
            if wantsICloud {
                switchAlert = SwitchAlert(
                    title: "Failed to Load iCloud",
                    message: "Sign into iCloud in Settings, then try again."
                )
            } else {
                switchAlert = SwitchAlert(
                    title: "Failed to Switch Data Source",
                    message: "Please try again."
                )
            }
        }
    }

    // MARK: - Private

    private static func updateICloudActivationState(useICloud: Bool) {
        UserDefaults.standard.set(useICloud, forKey: "icloud_activeUseCloud")

        if useICloud {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "icloud_bootstrapStartedAt")
        } else {
            UserDefaults.standard.set(0.0, forKey: "icloud_bootstrapStartedAt")
        }
    }

    // MARK: - Debug Helpers

    #if DEBUG
    private static var isScreenshotModeEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-screenshotMode") { return true }
        return UserDefaults.standard.bool(forKey: "debug_screenshotMode")
    }
    #endif
}
