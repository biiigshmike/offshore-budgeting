import Foundation
import SwiftData
import Testing
@testable import Offshore

/// Retirement leaves the persisted schema unchanged. Reopening a disk store checks that
/// financial relationships and opaque legacy payloads survive without any chat runtime.
@MainActor
struct LegacyStorageCompatibilityTests {
    @Test func reopeningStorePreservesFinancialHistoryAndDormantAssistantStorage() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LegacyStorageCompatibilityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Local.store")
        let ids = try writeExistingStore(at: storeURL)

        let container = try makeContainer(at: storeURL)
        let context = ModelContext(container)
        let workspaces = try context.fetch(FetchDescriptor<Workspace>())
        #expect(Set(workspaces.map(\.id)) == Set([ids.personal, ids.work]))
        let personal = try #require(workspaces.first { $0.id == ids.personal })
        let work = try #require(workspaces.first { $0.id == ids.work })
        #expect(personal.name == "Personal")
        #expect(work.name == "Work")
        #expect(personal.variableExpenses?.count == 1)
        #expect(work.variableExpenses?.count == 1)

        let expenses = try context.fetch(FetchDescriptor<VariableExpense>())
        let personalExpense = try #require(expenses.first { $0.id == ids.expense })
        let workExpense = try #require(expenses.first { $0.id == ids.workExpense })
        #expect(personalExpense.amount == 85)
        #expect(personalExpense.workspace?.id == ids.personal)
        #expect(personalExpense.card?.id == ids.card)
        #expect(personalExpense.category?.id == ids.category)
        #expect(personalExpense.allocation?.allocatedAmount == 20)
        #expect(personalExpense.allocation?.account?.workspace?.id == ids.personal)
        #expect(workExpense.amount == 40)
        #expect(workExpense.workspace?.id == ids.work)
        #expect(workExpense.card?.workspace?.id == ids.work)

        let planned = try #require(context.fetch(FetchDescriptor<PlannedExpense>()).first)
        #expect(planned.id == ids.planned)
        #expect(planned.plannedAmount == 500)
        #expect(planned.actualAmount == 450)
        #expect(planned.sourceBudgetID == ids.budget)
        #expect(planned.sourcePresetID == ids.preset)
        #expect(planned.card?.id == ids.card)
        #expect(planned.workspace?.id == ids.personal)
        let income = try #require(context.fetch(FetchDescriptor<Income>()).first)
        #expect(income.amount == 2_000)
        #expect(income.isPlanned == false)
        #expect(income.card?.id == ids.card)
        #expect(income.workspace?.id == ids.personal)

        let savings = try #require(context.fetch(FetchDescriptor<SavingsAccount>()).first)
        let ledger = try context.fetch(FetchDescriptor<SavingsLedgerEntry>())
        #expect(savings.total == 200)
        #expect(savings.workspace?.id == ids.personal)
        #expect(ledger.count == 1)
        #expect(ledger.first?.account?.id == savings.id)
        #expect(ledger.first?.workspace?.id == ids.personal)
        #expect(ledger.reduce(0) { $0 + $1.amount } == savings.total)

        let alias = try #require(context.fetch(FetchDescriptor<AssistantAliasRule>()).first)
        #expect(alias.id == ids.alias)
        #expect(alias.aliasKey == "daily card")
        #expect(alias.targetValue == "Personal Card")
        #expect(alias.workspace?.id == ids.personal)
        let chat = try #require(context.fetch(FetchDescriptor<MarinaChatSession>()).first)
        #expect(chat.id == ids.chat)
        #expect(chat.visibleAnswersData == Data([0, 255, 42, 10]))
        #expect(chat.followUpContextData == Data([128, 1, 2]))
        #expect(chat.workspace?.id == ids.personal)
        #expect(personal.marinaChatSessions?.count == 1)
        #expect(work.marinaChatSessions?.isEmpty ?? true)
        #expect(work.assistantAliasRules?.isEmpty ?? true)
    }

    private struct RecordIDs {
        let personal = UUID()
        let work = UUID()
        let card = UUID()
        let category = UUID()
        let expense = UUID()
        let workExpense = UUID()
        let planned = UUID()
        let budget = UUID()
        let preset = UUID()
        let alias = UUID()
        let chat = UUID()
    }

    private func writeExistingStore(at url: URL) throws -> RecordIDs {
        let container = try makeContainer(at: url)
        let context = ModelContext(container)
        let ids = RecordIDs()
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let personal = Workspace(id: ids.personal, name: "Personal", hexColor: "#3B82F6")
        let work = Workspace(id: ids.work, name: "Work", hexColor: "#8B5CF6")
        let card = Card(id: ids.card, name: "Personal Card", workspace: personal)
        let workCard = Card(name: "Work Card", workspace: work)
        let category = Category(id: ids.category, name: "Food", hexColor: "#F59E0B", workspace: personal)
        let expense = VariableExpense(id: ids.expense, descriptionText: "Groceries", amount: 85,
            transactionDate: date, workspace: personal, card: card, category: category)
        let workExpense = VariableExpense(id: ids.workExpense, descriptionText: "Supplies", amount: 40,
            transactionDate: date, workspace: work, card: workCard)
        let planned = PlannedExpense(id: ids.planned, title: "Rent", plannedAmount: 500, actualAmount: 450,
            expenseDate: date, workspace: personal, card: card, category: category,
            sourcePresetID: ids.preset, sourceBudgetID: ids.budget)
        let income = Income(source: "Salary", amount: 2_000, date: date, isPlanned: false,
            workspace: personal, card: card)
        let allocationAccount = AllocationAccount(name: "Shared", workspace: personal)
        let allocation = ExpenseAllocation(allocatedAmount: 20, preservesGrossAmount: true,
            workspace: personal, account: allocationAccount, expense: expense)
        let savings = SavingsAccount(total: 200, workspace: personal)
        let ledger = SavingsLedgerEntry(date: date, amount: 200, note: "Saved",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue, workspace: personal, account: savings)
        let alias = AssistantAliasRule(id: ids.alias, aliasKey: "daily card", targetValue: "Personal Card",
            entityType: .card, workspace: personal)
        let chat = MarinaChatSession(id: ids.chat, title: "Old conversation",
            visibleAnswersData: Data([0, 255, 42, 10]), followUpContextData: Data([128, 1, 2]), workspace: personal)
        context.insert(personal)
        context.insert(work)
        context.insert(card)
        context.insert(workCard)
        context.insert(category)
        context.insert(expense)
        context.insert(workExpense)
        context.insert(planned)
        context.insert(income)
        context.insert(allocationAccount)
        context.insert(allocation)
        context.insert(savings)
        context.insert(ledger)
        context.insert(alias)
        context.insert(chat)
        try context.save()
        return ids
    }

    private func makeContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Category.self, Preset.self,
            PlannedExpense.self, VariableExpense.self, AllocationAccount.self,
            ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
            MarinaChatSession.self, IncomeSeries.self, Income.self
        ])
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
