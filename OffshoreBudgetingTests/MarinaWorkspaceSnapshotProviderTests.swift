import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaWorkspaceSnapshotProviderTests {
    @Test func snapshotLoadsWorkspaceScopedResolutionEvidence() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#2563EB")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#7C3AED")
        let groceries = Offshore.Category(name: "Groceries", hexColor: "#16A34A", workspace: workspace)
        let otherCategory = Offshore.Category(name: "Travel", hexColor: "#F59E0B", workspace: otherWorkspace)
        let incomeSeries = makeIncomeSeries(source: "Consulting", workspace: workspace)
        let otherIncomeSeries = makeIncomeSeries(source: "Work Salary", workspace: otherWorkspace)
        let merchantRule = ImportMerchantRule(
            merchantKey: "WHOLE FOODS",
            preferredName: "Whole Foods",
            preferredCategory: groceries,
            workspace: workspace
        )
        let otherMerchantRule = ImportMerchantRule(
            merchantKey: "AIRLINE",
            preferredName: "Airline",
            preferredCategory: otherCategory,
            workspace: otherWorkspace
        )
        let alias = AssistantAliasRule(
            aliasKey: "Food",
            targetValue: "Groceries",
            entityType: .category,
            workspace: workspace
        )
        let otherAlias = AssistantAliasRule(
            aliasKey: "Trips",
            targetValue: "Travel",
            entityType: .category,
            workspace: otherWorkspace
        )

        context.insert(workspace)
        context.insert(otherWorkspace)
        context.insert(groceries)
        context.insert(otherCategory)
        context.insert(incomeSeries)
        context.insert(otherIncomeSeries)
        context.insert(merchantRule)
        context.insert(otherMerchantRule)
        context.insert(alias)
        context.insert(otherAlias)
        try context.save()

        let snapshot = try MarinaWorkspaceSnapshotProvider().snapshot(
            for: workspace,
            modelContext: context,
            now: date(2026, 7, 13)
        )

        #expect(snapshot.incomeSeries.map(\.source) == ["Consulting"])
        #expect(snapshot.importMerchantRules.map(\.merchantKey) == ["WHOLE FOODS"])
        #expect(snapshot.assistantAliasRules.map(\.aliasKey) == ["Food"])
        #expect(snapshot.categories.map(\.name) == ["Groceries"])
    }

    private func makeIncomeSeries(source: String, workspace: Workspace) -> IncomeSeries {
        IncomeSeries(
            source: source,
            amount: 1_000,
            isPlanned: true,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 2,
            monthlyDayOfMonth: 15,
            monthlyIsLastDay: false,
            yearlyMonth: 1,
            yearlyDayOfMonth: 15,
            startDate: date(2026, 1, 1),
            endDate: date(2026, 12, 31),
            workspace: workspace
        )
    }

    private func makeContext() throws -> ModelContext {
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
            MarinaChatSession.self,
            IncomeSeries.self,
            Income.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(
            from: DateComponents(year: year, month: month, day: day)
        ) ?? Date()
    }
}
