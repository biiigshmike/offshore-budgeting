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

        for key in [
            ReminderPreferences.Key.enabled, ReminderPreferences.Key.daily,
            ReminderPreferences.Key.income, ReminderPreferences.Key.preset,
            ReminderPreferences.Key.hour, ReminderPreferences.Key.minute,
            ReminderPreferences.Key.configured
        ] {
            defaults.removeObject(forKey: key)
        }

        defaults.set(false, forKey: "didCompleteOnboarding")
        defaults.set(false, forKey: "onboarding_didChooseDataSource")
        defaults.set(false, forKey: "onboarding_didPressGetStarted")
        defaults.set(0, forKey: "onboarding_step")
        defaults.removeObject(forKey: WorkspaceProgressHandoffStore.pendingWorkspaceIDKey)

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
            if ProcessInfo.processInfo.arguments.contains("-uiTestCategoryGoalHistory") {
                context.insert(Category(name: "New Category", hexColor: "#123456", workspace: workspace))
                for monthsAgo in 1...3 {
                    let start = Calendar.current.date(byAdding: .month, value: -monthsAgo, to: range.start)!
                    let end = Calendar.current.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
                    let historical = Budget(name: "History \(monthsAgo)", startDate: start, endDate: end,
                                            workspace: workspace)
                    context.insert(historical)
                    context.insert(BudgetCardLink(budget: historical, card: cardA))
                    context.insert(PlannedExpense(title: "Historical bill", plannedAmount: 900,
                                                 expenseDate: start, workspace: workspace,
                                                 card: cardA, category: category, sourceBudgetID: historical.id))
                    context.insert(VariableExpense(descriptionText: "Historical variable",
                                                  amount: Double(100 + monthsAgo * 200), transactionDate: end,
                                                  workspace: workspace, card: cardA, category: category))
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-uiTestCategoryDetailHistory") {
                seedCategoryDetailHistory(context: context, workspace: workspace, cardA: cardA, cardB: cardB,
                                          monthStart: range.start)
            }
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
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("-uiTestProgressDelayedWorkspace") {
                let workspaceID = UUID(uuidString: "5AA29E56-BBDB-4CC9-A286-720F6F35B001")!
                let defaults = UserDefaults.standard
                defaults.set(true, forKey: "didCompleteOnboarding")
                defaults.set(true, forKey: "onboarding_didChooseDataSource")
                defaults.set(true, forKey: "onboarding_didPressGetStarted")
                defaults.set(true, forKey: "didSeedDefaultWorkspaces")
                defaults.set(workspaceID.uuidString, forKey: "selectedWorkspaceID")
                // Simulate asynchronous cloud discovery; the scenario container remains local-only.
                defaults.set(true, forKey: "icloud_activeUseCloud")
                defaults.set(Date().timeIntervalSince1970, forKey: "icloud_bootstrapStartedAt")
                defaults.set(false, forKey: "privacy_requireBiometrics")
                defaults.set(false, forKey: "general_reviewUncategorizedExpensesOnOpen")
                defaults.set(false, forKey: WorkspaceProgressPreferences.hiddenKey(workspaceID: workspaceID))
                WorkspaceProgressHandoffStore(defaults: defaults).enqueue(workspaceID: workspaceID)
                if let release = SettingsReleaseLogsView.currentReleaseSection {
                    defaults.set(release.id, forKey: "releaseLogs_seenReleaseIDs")
                }
                scheduleDelayedProgressWorkspaceInsert(using: container)
                break
            }
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
            var progressCard: Card?
            if ProcessInfo.processInfo.arguments.contains("-uiTestProgressNoCard") {
                workspace.setupHasCreatedCard = true
            } else {
                let card = Card(name: "First Card", workspace: workspace)
                progressCard = card
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
            let finishesOnboarding = arguments.contains("-uiTestProgressFinishOnboarding")
            let skipsCloudOnboarding = arguments.contains("-uiTestProgressSkipOnboarding")
            defaults.set(!(finishesOnboarding || skipsCloudOnboarding), forKey: "didCompleteOnboarding")
            defaults.set(true, forKey: "onboarding_didChooseDataSource")
            defaults.set(true, forKey: "onboarding_didPressGetStarted")
            defaults.set(finishesOnboarding ? OnboardingStep.presets.rawValue : 0, forKey: "onboarding_step")
            if skipsCloudOnboarding {
                // Exercise the existing-data skip prompt using this isolated local fixture.
                defaults.set(true, forKey: "icloud_activeUseCloud")
            }
            defaults.set(true, forKey: "didSeedDefaultWorkspaces")
            defaults.set(workspace.id.uuidString, forKey: "selectedWorkspaceID")
            defaults.set(false, forKey: "privacy_requireBiometrics")
            defaults.set(false, forKey: "general_reviewUncategorizedExpensesOnOpen")
            if arguments.contains("-uiTestProgressPendingPrompts"), let progressCard {
                context.insert(VariableExpense(descriptionText: "Handoff review expense", amount: 12,
                    transactionDate: .now, workspace: workspace, card: progressCard, category: nil))
                defaults.set(true, forKey: "general_reviewUncategorizedExpensesOnOpen")
            }
            defaults.set(false, forKey: WorkspaceProgressPreferences.hiddenKey(workspaceID: workspace.id))
            defaults.set(false, forKey: WorkspaceProgressPreferences.hiddenKey(workspaceID: other.id))
            if arguments.contains("-uiTestProgressHandoff") {
                WorkspaceProgressHandoffStore(defaults: defaults).enqueue(workspaceID: workspace.id)
            } else {
                WorkspaceProgressHandoffStore(defaults: defaults).cancel()
            }
            if arguments.contains("-uiTestProgressPendingPrompts") {
                defaults.set("", forKey: "releaseLogs_seenReleaseIDs")
            } else if let release = SettingsReleaseLogsView.currentReleaseSection {
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

    private static func seedCategoryDetailHistory(
        context: ModelContext, workspace: Workspace, cardA: Card, cardB: Card, monthStart: Date
    ) {
        let dining = Category(id: UUID(uuidString: "C1000000-0000-0000-0000-000000000001")!,
                              name: "Detail Dining", hexColor: "#F97316", workspace: workspace)
        let archived = Category(id: UUID(uuidString: "C1000000-0000-0000-0000-000000000002")!,
                                name: "Archived Dining", hexColor: "#64748B", workspace: workspace,
                                isArchived: true, archivedAt: .now)
        let other = Category(id: UUID(uuidString: "C1000000-0000-0000-0000-000000000003")!,
                             name: "Other Detail Category", hexColor: "#10B981", workspace: workspace)
        context.insert(dining)
        context.insert(archived)
        context.insert(other)
        let date = Calendar.current.date(byAdding: .hour, value: 12, to: monthStart)!
        context.insert(VariableExpense(id: UUID(uuidString: "D1000000-0000-0000-0000-000000000001")!,
            descriptionText: "Lunch Ruby", amount: 25, transactionDate: date,
            workspace: workspace, card: cardA, category: dining))
        context.insert(VariableExpense(id: UUID(uuidString: "D1000000-0000-0000-0000-000000000002")!,
            descriptionText: "Coffee Ocean", amount: 5, transactionDate: date,
            workspace: workspace, card: cardB, category: dining))
        context.insert(PlannedExpense(id: UUID(uuidString: "E1000000-0000-0000-0000-000000000001")!,
            title: "Planned Dinner", plannedAmount: 40, expenseDate: date,
            workspace: workspace, card: cardB, category: dining))
        context.insert(VariableExpense(id: UUID(uuidString: "D1000000-0000-0000-0000-000000000003")!,
            descriptionText: "Archived Supper", amount: 15,
            transactionDate: date, workspace: workspace, card: cardA, category: archived))
        context.insert(VariableExpense(descriptionText: "Other Category Purchase", amount: 99,
            transactionDate: date, workspace: workspace, card: cardA, category: other))
        let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: date)!
        context.insert(VariableExpense(id: UUID(uuidString: "D1000000-0000-0000-0000-000000000004")!,
            descriptionText: "Previous Month Dining", amount: 12,
            transactionDate: previousMonth, workspace: workspace, card: cardA, category: dining))
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

    private static func scheduleDelayedProgressWorkspaceInsert(using container: ModelContainer) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let context = ModelContext(container)
            let other = Workspace(id: UUID(uuidString: "5AA29E56-BBDB-4CC9-A286-720F6F35B002")!,
                                  name: "Other Workspace", hexColor: "#10B981")
            context.insert(other)
            do {
                try context.save()
            } catch {
                assertionFailure("UITestSupport failed to insert first remote workspace: \(error)")
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            let context = ModelContext(container)
            let workspace = Workspace(id: UUID(uuidString: "5AA29E56-BBDB-4CC9-A286-720F6F35B001")!,
                                      name: "Progress Workspace", hexColor: "#3B82F6")
            let card = Card(name: "First Card", workspace: workspace)
            let category = Category(name: "Bills", hexColor: "#3B82F6", workspace: workspace)
            let preset = Preset(title: "Internet", plannedAmount: 60, workspace: workspace,
                                defaultCard: card, defaultCategory: category)
            let budget = Budget(name: "First Budget", startDate: .now, endDate: .now, workspace: workspace)
            context.insert(workspace)
            context.insert(card)
            context.insert(category)
            context.insert(preset)
            context.insert(budget)
            context.insert(BudgetCardLink(budget: budget, card: card))
            context.insert(BudgetPresetLink(budget: budget, preset: preset))
            do {
                try context.save()
            } catch {
                assertionFailure("UITestSupport failed to insert requested remote workspace: \(error)")
            }
        }
    }
}
#endif
