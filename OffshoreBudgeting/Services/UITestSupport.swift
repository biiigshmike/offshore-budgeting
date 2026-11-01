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
        case iCloudDelayedWorkspace
        case uncategorizedReview
        case budgetMenus
        case workspaceProgress
    }

    static var scenario: Scenario? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-uiTestScenarioICloudHasExistingWorkspace") { return .iCloudHasExistingWorkspace }
        if args.contains("-uiTestScenarioICloudEmpty") { return .iCloudEmpty }
        if args.contains("-uiTestScenarioICloudDelayedWorkspace") { return .iCloudDelayedWorkspace }
        if args.contains("-uiTestScenarioUncategorizedReview") { return .uncategorizedReview }
        if args.contains("-uiTestScenarioBudgetMenus") { return .budgetMenus }
        if args.contains("-uiTestScenarioWorkspaceProgress") { return .workspaceProgress }
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
        defaults.set(false, forKey: "general_hideFuturePlannedExpenses")
        defaults.set(false, forKey: "general_excludeFuturePlannedExpensesFromCalculations")
        defaults.set(false, forKey: "general_reviewUncategorizedExpensesOnOpen")
        defaults.set(false, forKey: "general_hideFutureVariableExpenses")
        defaults.set(false, forKey: "general_excludeFutureVariableExpensesFromCalculations")

        defaults.set(false, forKey: "icloud_useCloud")
        defaults.set(false, forKey: "icloud_activeUseCloud")
        defaults.set(0.0, forKey: "icloud_bootstrapStartedAt")
    }

    // MARK: - Data

    static func applyScenarioDataIfNeeded(container: ModelContainer) {
        guard isEnabled else { return }

        guard let scenario else { return }
        if scenario == .workspaceProgress,
           ProcessInfo.processInfo.arguments.contains("-uiTestPreserveScenarioData") {
            return
        }

        let context = ModelContext(container)
        wipeAllData(context: context)

        switch scenario {
        case .iCloudHasExistingWorkspace:
            let workspace = Workspace(name: "Existing iCloud Workspace", hexColor: "#3B82F6")
            context.insert(workspace)

        case .iCloudEmpty:
            break

        case .iCloudDelayedWorkspace:
            scheduleDelayedWorkspaceInsert(using: container)

        case .budgetMenus:
            let workspace = Workspace(name: "Budget Menu Workspace", hexColor: "#3B82F6")
            let cardA = Card(name: "Ruby Card", theme: "ruby", effect: "plastic", workspace: workspace)
            let cardB = Card(name: "Ocean Card", theme: "aqua", effect: "plastic", workspace: workspace)
            let category = Category(name: "Bills", hexColor: "#3B82F6", workspace: workspace)
            let presetA = Preset(title: "Internet", plannedAmount: 60, workspace: workspace,
                                 defaultCard: cardA, defaultCategory: category)
            let presetB = Preset(title: "Rent", plannedAmount: 800, workspace: workspace,
                                 defaultCard: cardB, defaultCategory: category)
            context.insert(category)
            let range = Calendar.current.dateInterval(of: .month, for: .now)!
            let budget = Budget(name: "Existing Menu Budget", startDate: range.start,
                endDate: Calendar.current.date(byAdding: .day, value: -1, to: range.end)!, workspace: workspace)
            context.insert(workspace)
            context.insert(cardA)
            context.insert(cardB)
            context.insert(presetA)
            context.insert(presetB)
            context.insert(budget)
            context.insert(BudgetCardLink(budget: budget, card: cardA))
            context.insert(BudgetPresetLink(budget: budget, preset: presetA))
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "didCompleteOnboarding")
            defaults.set(true, forKey: "onboarding_didChooseDataSource")
            defaults.set(true, forKey: "didSeedDefaultWorkspaces")
            defaults.set(workspace.id.uuidString, forKey: "selectedWorkspaceID")
            defaults.set(false, forKey: "privacy_requireBiometrics")
            defaults.set(false, forKey: "general_reviewUncategorizedExpensesOnOpen")
            if let release = SettingsReleaseLogsView.currentReleaseSection {
                defaults.set(release.id, forKey: "releaseLogs_seenReleaseIDs")
            }

        case .workspaceProgress:
            let workspace = Workspace(
                id: UUID(uuidString: "5AA29E56-BBDB-4CC9-A286-720F6F35B001")!,
                name: "Progress Workspace", hexColor: "#3B82F6"
            )
            let other = Workspace(
                id: UUID(uuidString: "5AA29E56-BBDB-4CC9-A286-720F6F35B002")!,
                name: "Other Workspace", hexColor: "#10B981"
            )
            context.insert(workspace)
            context.insert(other)
            let category = Category(name: "Bills", hexColor: "#3B82F6", workspace: workspace)
            let budget = Budget(name: "First Budget", startDate: .now, endDate: .now, workspace: workspace)
            context.insert(category)
            context.insert(budget)
            if ProcessInfo.processInfo.arguments.contains("-uiTestProgressNoCard") {
                workspace.setupHasCreatedCard = true
            } else {
                let card = Card(name: "First Card", workspace: workspace)
                let preset = Preset(title: "Internet", plannedAmount: 60, workspace: workspace,
                                    defaultCard: card, defaultCategory: category)
                context.insert(card)
                context.insert(preset)
                context.insert(BudgetCardLink(budget: budget, card: card))
                context.insert(BudgetPresetLink(budget: budget, preset: preset))
            }
            if ProcessInfo.processInfo.arguments.contains("-uiTestProgressComplete") {
                context.insert(Income(source: "First Paycheck", amount: 2_500, date: .now,
                                      isPlanned: true, workspace: workspace))
            }
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "didCompleteOnboarding")
            defaults.set(true, forKey: "onboarding_didChooseDataSource")
            defaults.set(true, forKey: "didSeedDefaultWorkspaces")
            defaults.set(workspace.id.uuidString, forKey: "selectedWorkspaceID")
            defaults.set(false, forKey: "privacy_requireBiometrics")
            defaults.set(false, forKey: "general_reviewUncategorizedExpensesOnOpen")
            defaults.set(false, forKey: WorkspaceProgressPreferences.hiddenKey(workspaceID: workspace.id))
            defaults.set(false, forKey: WorkspaceProgressPreferences.hiddenKey(workspaceID: other.id))
            if let release = SettingsReleaseLogsView.currentReleaseSection {
                defaults.set(release.id, forKey: "releaseLogs_seenReleaseIDs")
            }

        case .uncategorizedReview:
            let workspace = Workspace(name: "Review Workspace", hexColor: "#3B82F6")
            let card = Card(name: "Review Card", workspace: workspace)
            let category = Category(name: "Dining", hexColor: "#00AA00", workspace: workspace)
            let archived = Category(name: "Archived Review Category", hexColor: "#AAAAAA", workspace: workspace, isArchived: true)
            let expense = VariableExpense(descriptionText: "Review Coffee", amount: 6.50,
                transactionDate: .now, workspace: workspace, card: card)
            let other = Workspace(name: "Other Workspace", hexColor: "#FF0000")
            let foreign = VariableExpense(descriptionText: "Foreign Expense", amount: 99,
                transactionDate: .now, workspace: other)
            context.insert(workspace)
            context.insert(card)
            context.insert(category)
            context.insert(archived)
            context.insert(expense)
            context.insert(other)
            context.insert(foreign)
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: "didCompleteOnboarding")
            defaults.set(true, forKey: "onboarding_didChooseDataSource")
            defaults.set(true, forKey: "didSeedDefaultWorkspaces")
            defaults.set(workspace.id.uuidString, forKey: "selectedWorkspaceID")
            defaults.set(false, forKey: "privacy_requireBiometrics")
            defaults.set(!ProcessInfo.processInfo.arguments.contains("-uiTestReviewDisabled"),
                forKey: "general_reviewUncategorizedExpensesOnOpen")
            if !ProcessInfo.processInfo.arguments.contains("-uiTestReviewReleaseFirst"),
               let release = SettingsReleaseLogsView.currentReleaseSection {
                defaults.set(release.id, forKey: "releaseLogs_seenReleaseIDs")
            } else {
                defaults.set("", forKey: "releaseLogs_seenReleaseIDs")
            }
        }

        do {
            try context.save()
        } catch {
            assertionFailure("UITestSupport failed to save seed data: \(error)")
        }
    }

    private static func wipeAllData(context: ModelContext) {
        deleteAll(SavingsLedgerEntry.self, context: context)
        deleteAll(AllocationSettlement.self, context: context)
        deleteAll(ExpenseAllocation.self, context: context)

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

        deleteAll(SavingsAccount.self, context: context)
        deleteAll(AllocationAccount.self, context: context)
        deleteAll(ImportMerchantRule.self, context: context)
        deleteAll(AssistantAliasRule.self, context: context)
        deleteAll(MarinaChatSession.self, context: context)
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

    private static func scheduleDelayedWorkspaceInsert(using container: ModelContainer) {
        let delaySeconds: TimeInterval = ICloudBootstrap.maxWaitSeconds + 1.5

        DispatchQueue.main.asyncAfter(deadline: .now() + delaySeconds) {
            let context = ModelContext(container)
            let workspace = Workspace(name: "Delayed iCloud Workspace", hexColor: "#14B8A6")
            context.insert(workspace)

            do {
                try context.save()
            } catch {
                assertionFailure("UITestSupport failed to save delayed workspace seed data: \(error)")
            }
        }
    }
}
#endif
