import Foundation
import SwiftData

#if DEBUG
enum UITestSupport {

    // MARK: - Flags

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-uiTesting")
    }

    static var shouldResetOnLaunch: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-uiTestingReset")
    }

    static var shouldForceICloudAvailable: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-uiTestingForceICloudAvailable")
    }

    static var shouldUseLocalCloudStore: Bool {
        isEnabled && ProcessInfo.processInfo.arguments.contains("-uiTestingUseLocalCloudStore")
    }

    enum Scenario {
        case iCloudHasExistingWorkspace
        case iCloudEmpty
    }

    static var scenario: Scenario? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestScenarioICloudHasExistingWorkspace") { return .iCloudHasExistingWorkspace }
        if args.contains("-uiTestScenarioICloudEmpty") { return .iCloudEmpty }
        return nil
    }

    // MARK: - UserDefaults

    static func applyResetIfNeeded() {
        guard shouldResetOnLaunch else { return }

        let defaults = UserDefaults.standard

        defaults.set(false, forKey: "didCompleteOnboarding")
        defaults.set(false, forKey: "onboarding_didChooseDataSource")
        defaults.set(false, forKey: "onboarding_didPressGetStarted")
        defaults.set(0, forKey: "onboarding_step")

        defaults.set("", forKey: "selectedWorkspaceID")
        defaults.set(false, forKey: "didSeedDefaultWorkspaces")

        defaults.set(false, forKey: "icloud_useCloud")
        defaults.set(false, forKey: "icloud_activeUseCloud")
        defaults.set(0.0, forKey: "icloud_bootstrapStartedAt")
    }

    // MARK: - Data

    static func applyScenarioDataIfNeeded(container: ModelContainer) {
        guard isEnabled else { return }
        guard let scenario else { return }

        let context = ModelContext(container)
        wipeAllData(context: context)

        switch scenario {
        case .iCloudHasExistingWorkspace:
            let workspace = Workspace(name: "Existing iCloud Workspace", hexColor: "#3B82F6")
            context.insert(workspace)

        case .iCloudEmpty:
            break
        }

        do {
            try context.save()
        } catch {
            assertionFailure("UITestSupport failed to save seed data: \(error)")
        }
    }

    private static func wipeAllData(context: ModelContext) {
        deleteAll(Income.self, context: context)
        deleteAll(IncomeSeries.self, context: context)

        deleteAll(VariableExpense.self, context: context)
        deleteAll(PlannedExpense.self, context: context)

        deleteAll(BudgetCategoryLimit.self, context: context)
        deleteAll(BudgetPresetLink.self, context: context)
        deleteAll(BudgetCardLink.self, context: context)

        deleteAll(Preset.self, context: context)
        deleteAll(Category.self, context: context)
        deleteAll(Card.self, context: context)
        deleteAll(Budget.self, context: context)

        deleteAll(ImportMerchantRule.self, context: context)
        deleteAll(AssistantAliasRule.self, context: context)
        deleteAll(Workspace.self, context: context)
    }

    private static func deleteAll<T: PersistentModel>(_ type: T.Type, context: ModelContext) {
        do {
            let items = try context.fetch(FetchDescriptor<T>())
            for item in items {
                context.delete(item)
            }
        } catch {
            // Swallow in DEBUG
        }
    }
}
#endif
