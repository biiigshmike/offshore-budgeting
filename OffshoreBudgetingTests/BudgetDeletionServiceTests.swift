import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct BudgetDeletionServiceTests {
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

    private func makeFileBackedContainer(url: URL) throws -> ModelContainer {
        let config = ModelConfiguration(url: url, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: makeSchema(), configurations: config)
    }

    @Test func deleteBudgetAndGeneratedPlannedExpenses_persistsAcrossContainerReload() throws {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("BudgetDeletionServiceTests-\(UUID().uuidString).store")
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
