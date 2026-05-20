import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct MarinaWorkspaceReadStoreTests {
    @Test func fetchCatalog_scopesAllSchemaModelsToWorkspace() throws {
        let context = try makeContext()
        let target = try seedWorkspace(named: "Target", in: context)
        _ = try seedWorkspace(named: "Other", in: context)

        let catalog = try MarinaWorkspaceReadStore(
            modelContext: context,
            workspaceID: target.workspace.id
        ).fetchCatalog()

        #expect(catalog.workspace?.id == target.workspace.id)
        #expect(catalog.budgets.map(\.id) == [target.budget.id])
        #expect(catalog.budgetCategoryLimits.map(\.id) == [target.categoryLimit.id])
        #expect(catalog.cards.map(\.id) == [target.card.id])
        #expect(catalog.budgetCardLinks.map(\.id) == [target.cardLink.id])
        #expect(catalog.budgetPresetLinks.map(\.id) == [target.presetLink.id])
        #expect(catalog.categories.map(\.id) == [target.category.id])
        #expect(catalog.presets.map(\.id) == [target.preset.id])
        #expect(catalog.plannedExpenses.map(\.id) == [target.plannedExpense.id])
        #expect(catalog.variableExpenses.map(\.id) == [target.variableExpense.id])
        #expect(catalog.allocationAccounts.map(\.id) == [target.allocationAccount.id])
        #expect(catalog.expenseAllocations.map(\.id) == [target.expenseAllocation.id])
        #expect(catalog.allocationSettlements.map(\.id) == [target.allocationSettlement.id])
        #expect(catalog.savingsAccounts.map(\.id) == [target.savingsAccount.id])
        #expect(catalog.savingsLedgerEntries.map(\.id) == [target.savingsLedgerEntry.id])
        #expect(catalog.importMerchantRules.map(\.id) == [target.importMerchantRule.id])
        #expect(catalog.assistantAliasRules.map(\.id) == [target.aliasRule.id])
        #expect(catalog.incomeSeries.map(\.id) == [target.incomeSeries.id])
        #expect(catalog.incomes.map(\.id) == [target.income.id])
    }

    @Test func fetchCatalog_missingWorkspaceReturnsEmptyDataWithoutThrowing() throws {
        let context = try makeContext()
        _ = try seedWorkspace(named: "Existing", in: context)

        let catalog = try MarinaWorkspaceReadStore(
            modelContext: context,
            workspaceID: UUID()
        ).fetchCatalog()

        #expect(catalog.workspace == nil)
        #expect(catalog.budgets.isEmpty)
        #expect(catalog.budgetCategoryLimits.isEmpty)
        #expect(catalog.cards.isEmpty)
        #expect(catalog.budgetCardLinks.isEmpty)
        #expect(catalog.budgetPresetLinks.isEmpty)
        #expect(catalog.categories.isEmpty)
        #expect(catalog.presets.isEmpty)
        #expect(catalog.plannedExpenses.isEmpty)
        #expect(catalog.variableExpenses.isEmpty)
        #expect(catalog.allocationAccounts.isEmpty)
        #expect(catalog.expenseAllocations.isEmpty)
        #expect(catalog.allocationSettlements.isEmpty)
        #expect(catalog.savingsAccounts.isEmpty)
        #expect(catalog.savingsLedgerEntries.isEmpty)
        #expect(catalog.importMerchantRules.isEmpty)
        #expect(catalog.assistantAliasRules.isEmpty)
        #expect(catalog.incomeSeries.isEmpty)
        #expect(catalog.incomes.isEmpty)
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
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
        let config = ModelConfiguration(UUID().uuidString, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func seedWorkspace(named name: String, in context: ModelContext) throws -> SeededWorkspace {
        let workspace = Workspace(name: name, hexColor: "#3B82F6")
        let start = date(2026, 5, 1)
        let end = date(2026, 5, 31)

        let budget = Budget(name: "\(name) Budget", startDate: start, endDate: end, workspace: workspace)
        let card = Card(name: "\(name) Card", workspace: workspace)
        let cardLink = BudgetCardLink(budget: budget, card: card)
        let category = Category(name: "\(name) Category", hexColor: "#22C55E", workspace: workspace)
        let preset = Preset(
            title: "\(name) Preset",
            plannedAmount: 40,
            workspace: workspace,
            defaultCard: card,
            defaultCategory: category
        )
        let presetLink = BudgetPresetLink(budget: budget, preset: preset)
        let categoryLimit = BudgetCategoryLimit(maxAmount: 100, budget: budget, category: category)
        let plannedExpense = PlannedExpense(
            title: "\(name) Planned",
            plannedAmount: 30,
            expenseDate: date(2026, 5, 7),
            workspace: workspace,
            card: card,
            category: category,
            sourcePresetID: preset.id,
            sourceBudgetID: budget.id
        )
        let variableExpense = VariableExpense(
            descriptionText: "\(name) Variable",
            amount: 20,
            transactionDate: date(2026, 5, 8),
            workspace: workspace,
            card: card,
            category: category
        )
        let allocationAccount = AllocationAccount(name: "\(name) Shared", workspace: workspace)
        let expenseAllocation = ExpenseAllocation(
            allocatedAmount: 10,
            workspace: workspace,
            account: allocationAccount,
            expense: variableExpense
        )
        let allocationSettlement = AllocationSettlement(
            date: date(2026, 5, 9),
            note: "\(name) Settlement",
            amount: 5,
            workspace: workspace,
            account: allocationAccount,
            plannedExpense: plannedExpense
        )
        let savingsAccount = SavingsAccount(name: "\(name) Savings", workspace: workspace)
        let savingsLedgerEntry = SavingsLedgerEntry(
            date: date(2026, 5, 10),
            amount: 15,
            note: "\(name) Saved",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: workspace,
            account: savingsAccount,
            variableExpense: variableExpense
        )
        let importMerchantRule = ImportMerchantRule(
            merchantKey: "\(name.lowercased())-merchant",
            preferredName: "\(name) Merchant",
            preferredCategory: category,
            workspace: workspace
        )
        let aliasRule = AssistantAliasRule(
            aliasKey: "\(name.lowercased())-alias",
            targetValue: category.name,
            entityType: .category,
            workspace: workspace
        )
        let incomeSeries = IncomeSeries(
            source: "\(name) Paycheck",
            amount: 1_000,
            isPlanned: true,
            frequencyRaw: RecurrenceFrequency.monthly.rawValue,
            interval: 1,
            weeklyWeekday: 6,
            monthlyDayOfMonth: 15,
            monthlyIsLastDay: false,
            yearlyMonth: 1,
            yearlyDayOfMonth: 15,
            startDate: start,
            endDate: end,
            workspace: workspace
        )
        let income = Income(
            source: "\(name) Paycheck",
            amount: 1_000,
            date: date(2026, 5, 15),
            isPlanned: true,
            workspace: workspace,
            series: incomeSeries,
            card: card
        )

        context.insert(workspace)
        context.insert(budget)
        context.insert(card)
        context.insert(cardLink)
        context.insert(category)
        context.insert(preset)
        context.insert(presetLink)
        context.insert(categoryLimit)
        context.insert(plannedExpense)
        context.insert(variableExpense)
        context.insert(allocationAccount)
        context.insert(expenseAllocation)
        context.insert(allocationSettlement)
        context.insert(savingsAccount)
        context.insert(savingsLedgerEntry)
        context.insert(importMerchantRule)
        context.insert(aliasRule)
        context.insert(incomeSeries)
        context.insert(income)
        try context.save()

        return SeededWorkspace(
            workspace: workspace,
            budget: budget,
            categoryLimit: categoryLimit,
            card: card,
            cardLink: cardLink,
            presetLink: presetLink,
            category: category,
            preset: preset,
            plannedExpense: plannedExpense,
            variableExpense: variableExpense,
            allocationAccount: allocationAccount,
            expenseAllocation: expenseAllocation,
            allocationSettlement: allocationSettlement,
            savingsAccount: savingsAccount,
            savingsLedgerEntry: savingsLedgerEntry,
            importMerchantRule: importMerchantRule,
            aliasRule: aliasRule,
            incomeSeries: incomeSeries,
            income: income
        )
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: month, day: day))!
    }
}

private struct SeededWorkspace {
    let workspace: Workspace
    let budget: Budget
    let categoryLimit: BudgetCategoryLimit
    let card: Card
    let cardLink: BudgetCardLink
    let presetLink: BudgetPresetLink
    let category: Offshore.Category
    let preset: Preset
    let plannedExpense: PlannedExpense
    let variableExpense: VariableExpense
    let allocationAccount: AllocationAccount
    let expenseAllocation: ExpenseAllocation
    let allocationSettlement: AllocationSettlement
    let savingsAccount: SavingsAccount
    let savingsLedgerEntry: SavingsLedgerEntry
    let importMerchantRule: ImportMerchantRule
    let aliasRule: AssistantAliasRule
    let incomeSeries: IncomeSeries
    let income: Income
}
