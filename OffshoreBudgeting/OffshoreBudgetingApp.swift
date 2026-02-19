//  OffshoreBudgetingApp.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData
#if canImport(UIKit)
import UIKit
#endif

@main
struct OffshoreBudgetingApp: App {

    init() {
        configureLegacyTabBarAppearanceIfNeeded()
    }

    // MARK: - Notifications Delegate

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(NotificationsAppDelegate.self)
    private var notificationsAppDelegate
    #endif

    // MARK: - iCloud Opt-In State

    @AppStorage("app_rootResetToken") private var rootResetToken: String = UUID().uuidString

    // MARK: - ModelContainer

    @State private var modelContainer: ModelContainer = {
        #if DEBUG
        UITestSupport.applyResetIfNeeded()
        #endif

        let desiredUseICloud = UserDefaults.standard.bool(forKey: "icloud_useCloud")
        UserDefaults.standard.set(desiredUseICloud, forKey: "icloud_activeUseCloud")

        if desiredUseICloud {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "icloud_bootstrapStartedAt")
        } else {
            UserDefaults.standard.set(0.0, forKey: "icloud_bootstrapStartedAt")
        }

        #if DEBUG
        // If screenshot mode is enabled, ALWAYS use a local-only container
        // never touch Cloud data while staging screenshots.
        if Self.isScreenshotModeEnabled {
            UserDefaults.standard.set(false, forKey: "icloud_activeUseCloud")
            UserDefaults.standard.set(0.0, forKey: "icloud_bootstrapStartedAt")
            return Self.makeModelContainer(useICloud: false, debugStoreOverride: "Screenshots")
        }
        #endif

        return Self.makeModelContainer(useICloud: desiredUseICloud)
    }()

    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var commandHub: AppCommandHub = AppCommandHub()

    var body: some Scene {
        WindowGroup {
            AppBootstrapRootView(modelContainer: $modelContainer)
                .environment(\.appCommandHub, commandHub)
                .id(rootResetToken)
                .onAppear {
                    ShoppingModeManager.shared.refreshIfExpired()
                    if ShoppingModeManager.shared.status.isActive {
                        ShoppingModeLocationService.shared.startMonitoringIfPossible()
                    }
                }
                .task {
                    #if DEBUG
                    if Self.isScreenshotModeEnabled {
                        DebugSeeder.runIfNeeded(
                            container: modelContainer,
                            forceReset: Self.isSeedResetRequested
                        )
                    }
                    #endif
                }
                .onChange(of: scenePhase) { _, newValue in
                    guard newValue == .active else { return }
                    ShoppingModeManager.shared.refreshIfExpired()
                    if ShoppingModeManager.shared.status.isActive {
                        ShoppingModeLocationService.shared.startMonitoringIfPossible()
                    }
                }
                .onOpenURL { url in
                    _ = ShoppingModeManager.shared.handleDeepLink(url)
                }
        }
        .modelContainer(modelContainer)
        .commands {
            if shouldInstallMenuCommands {
                OffshoreAppCommands(commandHub: commandHub)
            }
        }
    }

    private var shouldInstallMenuCommands: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #elseif canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }

    // MARK: - Legacy UI Configuration

    private func configureLegacyTabBarAppearanceIfNeeded() {
        #if canImport(UIKit)
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        if #available(iOS 26.0, *) { return }

        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.shadowColor = .clear

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        #endif
    }

    // MARK: - Container Factory

    private static let cloudKitContainerIdentifier: String = "iCloud.com.mb.offshore-budgeting"

    static func makeModelContainer(useICloud: Bool, debugStoreOverride: String? = nil) -> ModelContainer {
        do {
            let schema = Schema([
                Workspace.self,
                Budget.self,
                BudgetCategoryLimit.self,
                Card.self,
                BudgetCardLink.self,
                BudgetPresetLink.self,
                Category.self,
                Preset.self,
                PlannedExpense.self,
                VariableExpense.self,
                AllocationAccount.self,
                ExpenseAllocation.self,
                AllocationSettlement.self,
                SavingsAccount.self,
                SavingsLedgerEntry.self,
                ImportMerchantRule.self,
                AssistantAliasRule.self,
                IncomeSeries.self,
                Income.self
            ])

            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let localStoreURL = appSupport.appendingPathComponent("Local.store")
            let cloudStoreURL = appSupport.appendingPathComponent("Cloud.store")

            #if DEBUG
            if let debugStoreOverride {
                let debugURL = appSupport.appendingPathComponent("\(debugStoreOverride).store")
                let configuration = ModelConfiguration(
                    debugStoreOverride,
                    schema: schema,
                    url: debugURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
                return try ModelContainer(for: schema, configurations: [configuration])
            }
            #endif

            let configuration: ModelConfiguration

            if useICloud {
                #if DEBUG
                if UITestSupport.shouldUseLocalCloudStore {
                    let uiTestCloudStoreURL = appSupport.appendingPathComponent("UITestCloud.store")
                    configuration = ModelConfiguration(
                        "Cloud-UITests",
                        schema: schema,
                        url: uiTestCloudStoreURL,
                        allowsSave: true,
                        cloudKitDatabase: .none
                    )
                } else {
                    configuration = ModelConfiguration(
                        "Cloud",
                        schema: schema,
                        url: cloudStoreURL,
                        allowsSave: true,
                        cloudKitDatabase: .private(cloudKitContainerIdentifier)
                    )
                }
                #else
                configuration = ModelConfiguration(
                    "Cloud",
                    schema: schema,
                    url: cloudStoreURL,
                    allowsSave: true,
                    cloudKitDatabase: .private(cloudKitContainerIdentifier)
                )
                #endif
            } else {
                configuration = ModelConfiguration(
                    "Local",
                    schema: schema,
                    url: localStoreURL,
                    allowsSave: true,
                    cloudKitDatabase: .none
                )
            }

            return try ModelContainer(for: schema, configurations: [configuration])

        } catch {
            // Fallback local store (still needs a non-optional URL and CloudKitDatabase)
            let fallbackSchema = Schema([
                Workspace.self,
                Budget.self,
                BudgetCategoryLimit.self,
                Card.self,
                BudgetCardLink.self,
                BudgetPresetLink.self,
                Category.self,
                Preset.self,
                PlannedExpense.self,
                VariableExpense.self,
                AllocationAccount.self,
                ExpenseAllocation.self,
                AllocationSettlement.self,
                SavingsAccount.self,
                SavingsLedgerEntry.self,
                ImportMerchantRule.self,
                AssistantAliasRule.self,
                IncomeSeries.self,
                Income.self
            ])

            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let fallbackStoreURL = appSupport.appendingPathComponent("FallbackLocal.store")

            let fallbackConfiguration = ModelConfiguration(
                "FallbackLocal",
                schema: fallbackSchema,
                url: fallbackStoreURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )

            return (try? ModelContainer(for: fallbackSchema, configurations: [fallbackConfiguration])) ?? {
                fatalError("Failed to create SwiftData ModelContainer: \(error)")
            }()
        }
    }

    // MARK: - DEBUG Screenshot Mode

    #if DEBUG
    private static var isScreenshotModeEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-screenshotMode") { return true }
        return UserDefaults.standard.bool(forKey: "debug_screenshotMode")
    }

    private static var isSeedResetRequested: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-resetSeed") { return true }
        return false
    }
    #endif
}
