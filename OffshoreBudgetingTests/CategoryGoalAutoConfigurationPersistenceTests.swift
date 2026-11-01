import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct CategoryGoalAutoConfigurationPersistenceTests {
    @Test func defaultsAndNormalizationStayWithinSupportedControls() {
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        #expect(workspace.categoryGoalAutoConfiguration == CategoryGoalAutoConfigurationSettings())
        workspace.categoryGoalAutoConfiguration = .init(suggestMaximums: false, historyCount: 30, cushionPercent: 13)
        #expect(workspace.categoryGoalHistoryCount == 12)
        #expect(workspace.categoryGoalCushionPercent == 15)
        #expect(!workspace.categoryGoalSuggestMaximums)
        workspace.categoryGoalAutoConfiguration = .init(historyCount: -1, cushionPercent: .infinity)
        #expect(workspace.categoryGoalHistoryCount == 1)
        #expect(workspace.categoryGoalCushionPercent == 0)
        #expect(CategoryGoalAutoConfigurationSettings(cushionPercent: 125).normalized.cushionPercent == 100)
        #expect(CategoryGoalAutoConfigurationSettings(cushionPercent: -10).normalized.cushionPercent == 0)
        #expect(CategoryGoalAutoConfigurationSettings(cushionPercent: .nan).normalized.cushionPercent == 0)
    }

    @Test func workspaceDefaultsPersistWithoutChangingOtherWorkspacesOrSavedGoals() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategoryGoalSettings-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Local.store")
        let workspaceID = try writeStore(at: storeURL)

        let container = try makeContainer(at: storeURL)
        let context = ModelContext(container)
        let workspaces = try context.fetch(FetchDescriptor<Workspace>())
        let workspace = try #require(workspaces.first { $0.id == workspaceID })
        let other = try #require(workspaces.first { $0.id != workspaceID })
        #expect(workspace.categoryGoalAutoConfiguration == .init(suggestMaximums: false, historyCount: 6, cushionPercent: 20))
        #expect(other.categoryGoalAutoConfiguration == CategoryGoalAutoConfigurationSettings())
        let goals = try context.fetch(FetchDescriptor<BudgetCategoryLimit>())
        #expect(goals.count == 1)
        #expect(goals.first?.maxAmount == 700)
        #expect(goals.first?.budget?.workspace?.id == workspaceID)
        let expense = try #require(context.fetch(FetchDescriptor<VariableExpense>()).first)
        #expect(expense.amount == 75)
        #expect(expense.workspace?.id == workspaceID)
        #expect(expense.card?.workspace?.id == workspaceID)
    }

    @Test func settingsRoundTripThroughExportEncodingAndImport() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        workspace.categoryGoalAutoConfiguration = .init(suggestMaximums: false, historyCount: 9, cushionPercent: 25)
        context.insert(workspace)
        try context.save()
        let archive = try WorkspaceExportService().exportArchive(
            for: workspace, sections: [.categories], modelContext: context
        )
        let decoded = try JSONDecoder().decode(WorkspaceArchive.self, from: JSONEncoder().encode(archive))
        #expect(decoded.workspace.categoryGoalAutoConfiguration == workspace.categoryGoalAutoConfiguration)
        let imported = try WorkspaceImportService().importArchive(
            decoded, existingWorkspaces: [workspace], modelContext: context
        )
        #expect(imported.id != workspace.id)
        #expect(imported.categoryGoalAutoConfiguration == workspace.categoryGoalAutoConfiguration)
    }

    @Test func legacyArchiveWithoutSettingsDecodesAndImportsWithDefaults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let archive = WorkspaceArchive(
            exportedAt: .now, sourceWorkspaceID: UUID(), selectedSections: [],
            workspace: WorkspacePayload(id: UUID(), name: "Legacy", hexColor: "#123456")
        )
        let encoded = try JSONEncoder().encode(archive)
        let json = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let workspaceJSON = try #require(json["workspace"] as? [String: Any])
        #expect(workspaceJSON["categoryGoalAutoConfiguration"] == nil)
        let decoded = try JSONDecoder().decode(WorkspaceArchive.self, from: encoded)
        #expect(decoded.workspace.categoryGoalAutoConfiguration == nil)
        let imported = try WorkspaceImportService().importArchive(
            decoded, existingWorkspaces: [], modelContext: context
        )
        #expect(imported.categoryGoalAutoConfiguration == CategoryGoalAutoConfigurationSettings())
    }

    @Test func importedOutOfRangeSettingsAreNormalized() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let archive = WorkspaceArchive(
            exportedAt: .now, sourceWorkspaceID: UUID(), selectedSections: [],
            workspace: WorkspacePayload(
                id: UUID(), name: "Imported", hexColor: "#123456",
                categoryGoalAutoConfiguration: .init(historyCount: 100, cushionPercent: 130)
            )
        )
        let imported = try WorkspaceImportService().importArchive(
            archive, existingWorkspaces: [], modelContext: context
        )
        #expect(imported.categoryGoalHistoryCount == 12)
        #expect(imported.categoryGoalCushionPercent == 100)
    }

    private func writeStore(at url: URL) throws -> UUID {
        let container = try makeContainer(at: url)
        let context = ModelContext(container)
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let other = Workspace(name: "Work", hexColor: "#654321")
        let category = Category(name: "Bills", hexColor: "#123456", workspace: workspace)
        let card = Card(name: "Card", workspace: workspace)
        let budget = Budget(name: "Existing", startDate: .now, endDate: .now, workspace: workspace)
        context.insert(workspace)
        context.insert(other)
        context.insert(category)
        context.insert(card)
        context.insert(budget)
        context.insert(BudgetCategoryLimit(maxAmount: 700, budget: budget, category: category))
        context.insert(VariableExpense(descriptionText: "History", amount: 75, transactionDate: .now,
                                       workspace: workspace, card: card, category: category))
        try context.save()
        workspace.categoryGoalAutoConfiguration = .init(suggestMaximums: false, historyCount: 6, cushionPercent: 20)
        try context.save()
        return workspace.id
    }

    private func makeContainer(at url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self, BudgetCardLink.self,
            BudgetPresetLink.self, Category.self, Preset.self, PlannedExpense.self, VariableExpense.self,
            AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self, MarinaChatSession.self,
            IncomeSeries.self, Income.self
        ])
        let configuration: ModelConfiguration
        if let url {
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
