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

    // MARK: - ModelContainer

    @State private var modelContainer: ModelContainer = {
        let desiredUseICloud = UserDefaults.standard.bool(forKey: "icloud_useCloud")
        UserDefaults.standard.set(desiredUseICloud, forKey: "icloud_activeUseCloud")

        if desiredUseICloud {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "icloud_bootstrapStartedAt")
        } else {
            UserDefaults.standard.set(0.0, forKey: "icloud_bootstrapStartedAt")
        }

        return Self.makeModelContainer(useICloud: desiredUseICloud)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .id(rootResetToken)
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Container Factory

    private static let cloudKitContainerIdentifier: String = "iCloud.com.mb.offshore-budgeting"

    private static func makeModelContainer(useICloud: Bool) -> ModelContainer {
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
                ImportMerchantRule.self,
                IncomeSeries.self,
                Income.self
            ])

            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

            let localStoreURL = appSupport.appendingPathComponent("Local.store")
            let cloudStoreURL = appSupport.appendingPathComponent("Cloud.store")

            let configuration: ModelConfiguration

            if useICloud {
                configuration = ModelConfiguration(
                    "Cloud",
                    schema: schema,
                    url: cloudStoreURL,
                    allowsSave: true,
                    cloudKitDatabase: .private(cloudKitContainerIdentifier)
                )
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
}
