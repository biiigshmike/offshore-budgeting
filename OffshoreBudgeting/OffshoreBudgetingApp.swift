//  OffshoreBudgetingApp.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

@main
struct OffshoreBudgetingApp: App {

    // MARK: - Notifications Delegate

    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(NotificationsAppDelegate.self)
    private var notificationsAppDelegate
    #endif

    // MARK: - iCloud Opt-In State

    @AppStorage("app_rootResetToken") private var rootResetToken: String = UUID().uuidString

    // MARK: - Data Source Switching

    @StateObject private var dataSourceSwitchCoordinator = AppDataSourceSwitchCoordinator()

    var body: some Scene {
        WindowGroup {
            RootShellView(rootResetToken: rootResetToken)
                .environmentObject(dataSourceSwitchCoordinator)
                .task {
                    #if DEBUG
                    if Self.isScreenshotModeEnabled {
                        DebugSeeder.runIfNeeded(
                            container: dataSourceSwitchCoordinator.modelContainer,
                            forceReset: Self.isSeedResetRequested
                        )
                    }
                    #endif
                }
        }
        .modelContainer(dataSourceSwitchCoordinator.modelContainer)
    }

    // MARK: - Root Shell

    private struct RootShellView: View {
        let rootResetToken: String

        @EnvironmentObject private var dataSourceSwitchCoordinator: AppDataSourceSwitchCoordinator
        @AppStorage("app_isSwitchingDataSource") private var isSwitchingDataSource: Bool = false

        var body: some View {
            Group {
                if isSwitchingDataSource {
                    Color(.systemBackground)
                        .ignoresSafeArea()
                } else {
                    AppBootstrapRootView()
                }
            }
            .id(rootResetToken)
            .alert(item: $dataSourceSwitchCoordinator.switchAlert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    // MARK: - Container Factory

    private static let cloudKitContainerIdentifier: String = "iCloud.com.mb.offshore-budgeting"

    static func tryMakeModelContainer(useICloud: Bool, debugStoreOverride: String? = nil) throws -> ModelContainer {
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
            ImportMerchantRule.self,
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
    }

    static func makeModelContainer(useICloud: Bool, debugStoreOverride: String? = nil) -> ModelContainer {
        do {
            return try tryMakeModelContainer(useICloud: useICloud, debugStoreOverride: debugStoreOverride)
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
                ImportMerchantRule.self,
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
