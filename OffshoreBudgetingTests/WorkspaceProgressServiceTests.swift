import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct WorkspaceProgressServiceTests {
    private func makeSchema() -> Schema {
        Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Offshore.Category.self, Preset.self,
            PlannedExpense.self, VariableExpense.self, AllocationAccount.self,
            ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
            MarinaChatSession.self, IncomeSeries.self, Income.self
        ])
    }

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return ModelContext(try ModelContainer(for: makeSchema(), configurations: configuration))
    }

    @Test func eachPermanentMilestoneAddsTwentyPercentExactlyOnce() {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        #expect(WorkspaceProgressService.completedSteps(in: workspace).isEmpty)
        #expect(WorkspaceProgressService.percentage(in: workspace) == 0)
        #expect(!WorkspaceProgressService.canHideProgress(in: workspace))
        #expect(WorkspaceProgressService.settingsSymbol(in: workspace) == "gauge.with.dots.needle.0percent")

        let expectedSymbols = [
            "gauge.with.dots.needle.33percent", "gauge.with.dots.needle.50percent",
            "gauge.with.dots.needle.67percent", "gauge.with.dots.needle.67percent",
            "gauge.with.dots.needle.100percent"
        ]

        for (index, step) in WorkspaceProgressStep.allCases.enumerated() {
            #expect(WorkspaceProgressService.markCompleted(step, in: workspace))
            #expect(WorkspaceProgressService.percentage(in: workspace) == (index + 1) * 20)
            #expect(WorkspaceProgressService.completedSteps(in: workspace).count == index + 1)
            #expect(WorkspaceProgressService.settingsSymbol(in: workspace) == expectedSymbols[index])
            #expect(WorkspaceProgressService.canHideProgress(in: workspace) == (index == 4))
            #expect(!WorkspaceProgressService.markCompleted(step, in: workspace))
            #expect(WorkspaceProgressService.percentage(in: workspace) == (index + 1) * 20)
        }
        #expect(WorkspaceProgressService.completedSteps(in: workspace) == Set(WorkspaceProgressStep.allCases))
    }

    @Test func failedSaveRestoresOnlyNewMilestonesAndPreservesUnrelatedEdits() {
        enum SaveFailure: Error { case rejected }
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        WorkspaceProgressService.markCompleted(.card, in: workspace)
        var saveAttempted = false

        #expect(throws: SaveFailure.self) {
            try WorkspaceProgressService.saveCompleting([.card, .income, .budget], in: workspace) {
                saveAttempted = true
                #expect(WorkspaceProgressService.completedSteps(in: workspace) == [.card, .income, .budget])
                workspace.name = "Keep this unrelated edit"
                throw SaveFailure.rejected
            }
        }

        #expect(saveAttempted)
        #expect(WorkspaceProgressService.completedSteps(in: workspace) == [.card])
        #expect(workspace.name == "Keep this unrelated edit")
    }

    @Test func successfulCreationSavesRecordAndMilestoneTogether() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        let card = Card(name: "Visa", workspace: workspace)
        context.insert(card)

        try WorkspaceProgressService.saveCompleting([.card], in: workspace) {
            try context.save()
        }

        let freshContext = ModelContext(context.container)
        let savedWorkspace = try #require(freshContext.fetch(FetchDescriptor<Workspace>()).first)
        #expect(WorkspaceProgressService.completedSteps(in: savedWorkspace) == [.card])
        #expect(try freshContext.fetch(FetchDescriptor<Card>()).first?.workspace?.id == savedWorkspace.id)
    }

    @Test(arguments: [true, false])
    func incomeEntryPersistsIncomeAndMilestoneOnlyInTargetWorkspace(isPlanned: Bool) throws {
        let context = try makeContext()
        let target = Workspace(name: "Personal", hexColor: "#3B82F6")
        let other = Workspace(name: "Work", hexColor: "#10B981")
        context.insert(target)
        context.insert(other)
        try context.save()
        let entryDate = Date(timeIntervalSince1970: 1_790_000_000)

        let income = try TransactionEntryService().addIncome(
            source: "  Salary  ", amount: 1_000, date: entryDate, isPlanned: isPlanned,
            workspace: target, modelContext: context
        )

        #expect(WorkspaceProgressService.completedSteps(in: target) == [.income])
        #expect(WorkspaceProgressService.completedSteps(in: other).isEmpty)
        let freshContext = ModelContext(context.container)
        let savedWorkspaces = try freshContext.fetch(FetchDescriptor<Workspace>())
        let savedTarget = try #require(savedWorkspaces.first { $0.id == target.id })
        let savedOther = try #require(savedWorkspaces.first { $0.id == other.id })
        let savedIncomes = try freshContext.fetch(FetchDescriptor<Income>())
        let savedIncome = try #require(savedIncomes.first)
        #expect(savedIncomes.count == 1)
        #expect(savedIncome.id == income.id)
        #expect(savedIncome.workspace?.id == savedTarget.id)
        #expect(savedIncome.source == "Salary")
        #expect(savedIncome.amount == 1_000)
        #expect(savedIncome.isPlanned == isPlanned)
        #expect(savedIncome.date == Calendar.current.startOfDay(for: entryDate))
        #expect(WorkspaceProgressService.completedSteps(in: savedTarget) == [.income])
        #expect(WorkspaceProgressService.completedSteps(in: savedOther).isEmpty)
    }

    @Test func invalidIncomeEntryCreatesNeitherRecordNorMilestone() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        WorkspaceProgressService.markCompleted(.card, in: workspace)
        try context.save()
        let service = TransactionEntryService()
        let invalidEntries: [(source: String, amount: Double)] = [
            ("  \n", 1_000), ("Salary", 0), ("Salary", -1)
        ]

        for entry in invalidEntries {
            #expect(throws: TransactionEntryService.ValidationError.self) {
                _ = try service.addIncome(source: entry.source, amount: entry.amount, date: .now,
                                          isPlanned: false, workspace: workspace, modelContext: context)
            }
            #expect(WorkspaceProgressService.completedSteps(in: workspace) == [.card])
            #expect(try context.fetch(FetchDescriptor<Income>()).isEmpty)
            #expect(!context.hasChanges)
        }

        let freshContext = ModelContext(context.container)
        let savedWorkspace = try #require(freshContext.fetch(FetchDescriptor<Workspace>()).first)
        #expect(WorkspaceProgressService.completedSteps(in: savedWorkspace) == [.card])
        #expect(try freshContext.fetch(FetchDescriptor<Income>()).isEmpty)
    }

    @Test func backfillDoesNotPersistPendingCoreRecordsOrAwardTheirMilestones() throws {
        let context = try makeContext()
        context.autosaveEnabled = false
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()
        context.insert(Card(name: "Pending card", workspace: workspace))
        context.insert(Income(source: "Pending salary", amount: 1_000,
                              date: Date(timeIntervalSince1970: 1_790_000_000),
                              isPlanned: true, workspace: workspace))

        try WorkspaceProgressService.backfill(in: workspace, modelContext: context)

        #expect(WorkspaceProgressService.completedSteps(in: workspace).isEmpty)
        #expect(context.hasChanges)
        let verificationContext = ModelContext(context.container)
        #expect(try verificationContext.fetch(FetchDescriptor<Card>()).isEmpty)
        #expect(try verificationContext.fetch(FetchDescriptor<Income>()).isEmpty)
        let savedWorkspace = try #require(verificationContext.fetch(FetchDescriptor<Workspace>()).first)
        #expect(WorkspaceProgressService.percentage(in: savedWorkspace) == 0)

        try context.save()
        try WorkspaceProgressService.backfill(in: workspace, modelContext: context)
        #expect(WorkspaceProgressService.completedSteps(in: workspace) == [.card, .income])
        let completedContext = ModelContext(context.container)
        let completedWorkspace = try #require(completedContext.fetch(FetchDescriptor<Workspace>()).first)
        #expect(WorkspaceProgressService.percentage(in: completedWorkspace) == 40)
        #expect(try completedContext.fetch(FetchDescriptor<Card>()).count == 1)
        #expect(try completedContext.fetch(FetchDescriptor<Income>()).count == 1)
    }

    @Test func backfillUsesOnlyTheExplicitWorkspace() throws {
        let context = try makeContext()
        let selected = Workspace(name: "Personal", hexColor: "#3B82F6")
        let other = Workspace(name: "Work", hexColor: "#10B981")
        context.insert(selected)
        context.insert(other)
        insertCoreRecords(in: other, context: context)
        try context.save()

        try WorkspaceProgressService.backfill(in: selected, modelContext: context)
        #expect(WorkspaceProgressService.percentage(in: selected) == 0)
        #expect(WorkspaceProgressService.percentage(in: other) == 0)

        try WorkspaceProgressService.backfill(in: other, modelContext: context)
        #expect(WorkspaceProgressService.percentage(in: selected) == 0)
        #expect(WorkspaceProgressService.percentage(in: other) == 100)
    }

    @Test func backfillCountsArchivedCategoriesPresetsAndBudgetsOutsideCurrentDates() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        let category = Offshore.Category(name: "Old category", hexColor: "#AAAAAA", workspace: workspace,
                                        isArchived: true, archivedAt: .now)
        let preset = Preset(title: "Old preset", plannedAmount: 50, workspace: workspace,
                            isArchived: true, archivedAt: .now)
        let longAgo = Date(timeIntervalSince1970: 0)
        let budget = Budget(name: "Past budget", startDate: longAgo, endDate: longAgo, workspace: workspace)
        context.insert(category)
        context.insert(preset)
        context.insert(budget)
        try context.save()

        try WorkspaceProgressService.backfill(in: workspace, modelContext: context)
        #expect(WorkspaceProgressService.completedSteps(in: workspace) == [.category, .preset, .budget])
        #expect(category.isArchived)
        #expect(preset.isArchived)
        #expect(budget.startDate == longAgo)
    }

    @Test(arguments: [true, false])
    func eitherPlannedOrReceivedIncomeCountsRegardlessOfDate(isPlanned: Bool) throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        let futureDate = Date(timeIntervalSince1970: 4_102_444_800)
        let income = Income(source: "Salary", amount: 1_000, date: futureDate,
                            isPlanned: isPlanned, workspace: workspace)
        context.insert(income)
        try context.save()

        try WorkspaceProgressService.backfill(in: workspace, modelContext: context)
        #expect(WorkspaceProgressService.completedSteps(in: workspace) == [.income])
        #expect(income.isPlanned == isPlanned)
        #expect(income.amount == 1_000)
    }

    @Test func bareIncomeSeriesAndVirtualUncategorizedDoNotEarnMilestones() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        let series = IncomeSeries(source: "Salary", amount: 1_000, isPlanned: true,
                                  frequencyRaw: RecurrenceFrequency.monthly.rawValue, interval: 1,
                                  weeklyWeekday: 6, monthlyDayOfMonth: 15, monthlyIsLastDay: false,
                                  yearlyMonth: 1, yearlyDayOfMonth: 15, startDate: day, endDate: day,
                                  workspace: workspace)
        let uncategorized = VariableExpense(descriptionText: "Uncategorized transaction", amount: 15,
                                            transactionDate: day, workspace: workspace, category: nil)
        context.insert(series)
        context.insert(uncategorized)
        try context.save()

        try WorkspaceProgressService.backfill(in: workspace, modelContext: context)
        #expect(WorkspaceProgressService.completedSteps(in: workspace).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Income>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Offshore.Category>()).isEmpty)
        #expect(uncategorized.category == nil)
    }

    @Test func milestonesSurviveDeletionOfEveryCoreAndContainerReload() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceProgressServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Local.store")
        let workspaceID = try saveCompletedThenDeletedCoreRecords(at: storeURL)

        let configuration = ModelConfiguration(schema: makeSchema(), url: storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: makeSchema(), configurations: configuration)
        let context = ModelContext(container)
        let workspace = try #require(context.fetch(FetchDescriptor<Workspace>()).first)
        #expect(workspace.id == workspaceID)
        #expect(WorkspaceProgressService.percentage(in: workspace) == 100)

        try WorkspaceProgressService.backfill(in: workspace, modelContext: context)
        #expect(WorkspaceProgressService.percentage(in: workspace) == 100)
        #expect(WorkspaceProgressService.canHideProgress(in: workspace))
        #expect(try context.fetch(FetchDescriptor<Card>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Offshore.Category>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Preset>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Income>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<Budget>()).isEmpty)
    }

    @Test func repeatingOnboardingPreservesEarnedMilestones() throws {
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        WorkspaceProgressService.markCompleted(.card, in: workspace)
        WorkspaceProgressService.markCompleted(.category, in: workspace)
        let suiteName = "WorkspaceProgressServiceTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let hiddenKey = WorkspaceProgressPreferences.hiddenKey(workspaceID: workspace.id)
        let otherWorkspaceKey = WorkspaceProgressPreferences.hiddenKey(workspaceID: UUID())
        #expect(!defaults.bool(forKey: hiddenKey))
        #expect(!defaults.bool(forKey: otherWorkspaceKey))
        defaults.set(true, forKey: hiddenKey)
        defaults.set(true, forKey: OnboardingResetService.didCompleteOnboardingKey)

        OnboardingResetService.repeatOnboarding(defaults: defaults)

        #expect(!defaults.bool(forKey: OnboardingResetService.didCompleteOnboardingKey))
        #expect(WorkspaceProgressService.completedSteps(in: workspace) == [.card, .category])
        #expect(defaults.bool(forKey: hiddenKey))
        #expect(!defaults.bool(forKey: otherWorkspaceKey))
    }

    @Test func legacyHideChoicesPersistPerWorkspaceAfterReopeningStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkspaceProgressPreferences-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let schema = makeSchema()
        let configuration = ModelConfiguration(
            schema: schema,
            url: directory.appendingPathComponent("Local.store"),
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = ModelContext(container)
            for (name, legacyChoice) in [("Hidden", true), ("Visible", false), ("Unset", nil)] as [(String, Bool?)] {
                let workspace = Workspace(name: name, hexColor: "#3B82F6")
                context.insert(workspace)
                if let legacyChoice {
                    defaults.set(legacyChoice, forKey: WorkspaceProgressPreferences.hiddenKey(workspaceID: workspace.id))
                }
                try WorkspaceProgressPreferences.migrateLegacyChoice(for: workspace, defaults: defaults) {
                    try context.save()
                }
            }
            try context.save()
        }

        let container = try ModelContainer(for: schema, configurations: configuration)
        let context = ModelContext(container)
        let workspaces = try context.fetch(FetchDescriptor<Workspace>())
        #expect(workspaces.first { $0.name == "Hidden" }?.hideWorkspaceProgress == true)
        let visible = try #require(workspaces.first { $0.name == "Visible" })
        #expect(visible.hideWorkspaceProgress == false)
        let unset = try #require(workspaces.first { $0.name == "Unset" })
        #expect(unset.hideWorkspaceProgress == nil)

        defaults.set(true, forKey: WorkspaceProgressPreferences.hiddenKey(workspaceID: visible.id))
        WorkspaceProgressPreferences.migrateLegacyChoice(for: visible, defaults: defaults) {
            Issue.record("A persisted choice should prevent migration")
        }
        #expect(WorkspaceProgressPreferences.savedChoice(for: visible, defaults: defaults) == false)
    }

    @Test func failedChoiceSaveRestoresPriorValueAndCanRetryMigration() throws {
        enum SaveError: Error { case unavailable }
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let suiteName = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: WorkspaceProgressPreferences.hiddenKey(workspaceID: workspace.id))

        #expect(throws: SaveError.unavailable) {
            try WorkspaceProgressPreferences.migrateLegacyChoice(for: workspace, defaults: defaults) {
                throw SaveError.unavailable
            }
        }
        #expect(workspace.hideWorkspaceProgress == nil)
        #expect(WorkspaceProgressPreferences.savedChoice(for: workspace, defaults: defaults) == true)

        WorkspaceProgressPreferences.migrateLegacyChoice(for: workspace, defaults: defaults) {}
        #expect(workspace.hideWorkspaceProgress == true)

        #expect(throws: SaveError.unavailable) {
            try WorkspaceProgressPreferences.saveChoice(false, for: workspace) {
                throw SaveError.unavailable
            }
        }
        #expect(workspace.hideWorkspaceProgress == true)
    }

    private func insertCoreRecords(in workspace: Workspace, context: ModelContext) {
        let day = Date(timeIntervalSince1970: 1_790_000_000)
        context.insert(Card(name: "Visa", workspace: workspace))
        context.insert(Offshore.Category(name: "Bills", hexColor: "#AAAAAA", workspace: workspace))
        context.insert(Preset(title: "Rent", plannedAmount: 500, workspace: workspace))
        context.insert(Income(source: "Salary", amount: 1_000, date: day, isPlanned: true, workspace: workspace))
        context.insert(Budget(name: "Any budget", startDate: day, endDate: day, workspace: workspace))
    }

    private func saveCompletedThenDeletedCoreRecords(at url: URL) throws -> UUID {
        let configuration = ModelConfiguration(schema: makeSchema(), url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: makeSchema(), configurations: configuration)
        let context = ModelContext(container)
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        insertCoreRecords(in: workspace, context: context)
        try context.save()
        try WorkspaceProgressService.backfill(in: workspace, modelContext: context)
        #expect(WorkspaceProgressService.percentage(in: workspace) == 100)

        for record in try context.fetch(FetchDescriptor<Card>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<Offshore.Category>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<Preset>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<Income>()) { context.delete(record) }
        for record in try context.fetch(FetchDescriptor<Budget>()) { context.delete(record) }
        try context.save()
        return workspace.id
    }
}
