import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct StarterBudgetServiceTests {
    private func makeSchema() -> Schema {
        Schema([
            Workspace.self,
            Budget.self,
            Card.self,
            BudgetCardLink.self,
            Category.self,
            Preset.self,
            BudgetPresetLink.self,
            BudgetCategoryLimit.self,
            PlannedExpense.self,
            VariableExpense.self,
            AllocationAccount.self,
            ExpenseAllocation.self,
            AllocationSettlement.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self,
            ImportMerchantRule.self,
            AssistantAliasRule.self,
            IncomeSeries.self,
            Income.self
        ])
    }

    private func makeInMemoryContext() throws -> ModelContext {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: makeSchema(), configurations: config)
        return ModelContext(container)
    }

    private func makeFileBackedContainer(url: URL) throws -> ModelContainer {
        let config = ModelConfiguration(url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: makeSchema(), configurations: config)
    }

    @Test func createIfNeeded_createsCurrentMonthlyBudgetForWorkspace() throws {
        let context = try makeInMemoryContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()

        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 3, day: 20))!

        let created = try StarterBudgetService.createIfNeeded(
            in: workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            modelContext: context,
            calendar: calendar,
            now: now
        )

        let budgets = try context.fetch(FetchDescriptor<Budget>())
        #expect(created != nil)
        #expect(budgets.count == 1)
        #expect(budgets.first?.name == "March 2026")
        #expect(budgets.first?.startDate == calendar.date(from: DateComponents(year: 2026, month: 3, day: 1)))
        #expect(budgets.first?.endDate == calendar.date(from: DateComponents(year: 2026, month: 3, day: 31)))
    }

    @Test func createIfNeeded_returnsNilWhenWorkspaceAlreadyHasBudget() throws {
        let context = try makeInMemoryContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31))!
        let existingBudget = Budget(name: "March 2026", startDate: start, endDate: end, workspace: workspace)

        context.insert(workspace)
        context.insert(existingBudget)
        try context.save()

        let created = try StarterBudgetService.createIfNeeded(
            in: workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            modelContext: context
        )

        let budgets = try context.fetch(FetchDescriptor<Budget>())
        #expect(created == nil)
        #expect(budgets.count == 1)
    }

    @Test func deleteBudgetAndGeneratedPlannedExpenses_persistsAcrossContainerReload() throws {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("StarterBudgetServiceTests-\(UUID().uuidString).store")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let initialContainer = try makeFileBackedContainer(url: storeURL)
        let initialContext = ModelContext(initialContainer)

        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let budgetStart = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let budgetEnd = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 31))!
        let budget = Budget(name: "March 2026", startDate: budgetStart, endDate: budgetEnd, workspace: workspace)
        let plannedExpense = PlannedExpense(
            title: "Rent",
            plannedAmount: 1200,
            actualAmount: 0,
            expenseDate: budgetStart,
            workspace: workspace,
            sourceBudgetID: budget.id
        )

        initialContext.insert(workspace)
        initialContext.insert(budget)
        initialContext.insert(plannedExpense)
        try initialContext.save()

        try BudgetDeletionService.deleteBudgetAndGeneratedPlannedExpenses(
            budget,
            modelContext: initialContext
        )

        let reloadedContainer = try makeFileBackedContainer(url: storeURL)
        let reloadedContext = ModelContext(reloadedContainer)

        #expect(try reloadedContext.fetch(FetchDescriptor<Budget>()).isEmpty)
        #expect(try reloadedContext.fetch(FetchDescriptor<PlannedExpense>()).isEmpty)
    }
}
