import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaRetirementServiceTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Offshore.Category.self,
            Preset.self, PlannedExpense.self, VariableExpense.self,
            AllocationAccount.self, ExpenseAllocation.self, AllocationSettlement.self,
            SavingsAccount.self, SavingsLedgerEntry.self, ImportMerchantRule.self,
            AssistantAliasRule.self, MarinaChatSession.self, IncomeSeries.self, Income.self
        ])
        return try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    @Test func purgeCoversAllWorkspacesAndOrphansWithoutChangingFinancialHistory() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let personal = Workspace(name: "Personal", hexColor: "#123456")
        let work = Workspace(name: "Work", hexColor: "#654321")
        context.insert(personal)
        context.insert(work)
        let card = Card(name: "Visa", workspace: personal)
        context.insert(card)
        let expense = VariableExpense(descriptionText: "Coffee", amount: 12,
            transactionDate: .now, workspace: personal, card: card)
        let income = Income(source: "Pay", amount: 1000, date: .now, isPlanned: false, workspace: work)
        context.insert(expense)
        context.insert(income)
        for workspace in [personal, work] {
            context.insert(MarinaChatSession(title: "Old chat", workspace: workspace))
            context.insert(AssistantAliasRule(aliasKey: "main", targetValue: "Visa", entityType: .card, workspace: workspace))
        }
        context.insert(MarinaChatSession(title: "Orphan"))
        context.insert(AssistantAliasRule(aliasKey: "orphan", targetValue: "Visa", entityType: .card))
        try context.save()

        try MarinaRetirementService.purgeLegacyRecords(in: container)
        try MarinaRetirementService.purgeLegacyRecords(in: container)
        let verification = ModelContext(container)
        #expect(try verification.fetchCount(FetchDescriptor<MarinaChatSession>()) == 0)
        #expect(try verification.fetchCount(FetchDescriptor<AssistantAliasRule>()) == 0)
        #expect(try verification.fetchCount(FetchDescriptor<Workspace>()) == 2)
        #expect(try verification.fetchCount(FetchDescriptor<Card>()) == 1)
        #expect(try verification.fetch(FetchDescriptor<VariableExpense>()).first?.amount == 12)
        #expect(try verification.fetch(FetchDescriptor<Income>()).first?.amount == 1000)

        // A later CloudKit import from an old app is cleaned on the next invocation.
        let syncedWorkspace = try verification.fetch(FetchDescriptor<Workspace>()).first
        verification.insert(MarinaChatSession(title: "Late sync", workspace: syncedWorkspace))
        try verification.save()
        try MarinaRetirementService.purgeLegacyRecords(in: container)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<MarinaChatSession>()) == 0)
    }

    @Test func saveFailureRollsBackAndNextAttemptCanRetry() throws {
        enum Failure: Error { case save }
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(MarinaChatSession(title: "Keep until saved"))
        context.insert(AssistantAliasRule(aliasKey: "main", targetValue: "Visa", entityType: .card))
        try context.save()
        do {
            try MarinaRetirementService.purgeLegacyRecords(in: context, save: { _ in throw Failure.save })
            Issue.record("Expected save failure")
        } catch Failure.save {}
        #expect(try context.fetchCount(FetchDescriptor<MarinaChatSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AssistantAliasRule>()) == 1)
        try MarinaRetirementService.purgeLegacyRecords(in: context)
        #expect(try context.fetchCount(FetchDescriptor<MarinaChatSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AssistantAliasRule>()) == 0)
    }

    @Test func containerCleanupDoesNotSaveUnrelatedPendingUserEdits() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let workspace = Workspace(name: "Original", hexColor: "#123456")
        context.insert(workspace)
        context.insert(MarinaChatSession(title: "Old chat", workspace: workspace))
        try context.save()
        workspace.name = "Unsaved edit"
        try MarinaRetirementService.purgeLegacyRecords(in: container)
        #expect(workspace.name == "Unsaved edit")
        #expect(context.hasChanges)
        #expect(try ModelContext(container).fetch(FetchDescriptor<Workspace>()).first?.name == "Original")
    }
}
