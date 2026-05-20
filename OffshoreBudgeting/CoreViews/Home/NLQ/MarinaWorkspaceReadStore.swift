import Foundation
import SwiftData

@MainActor
struct MarinaWorkspaceReadCatalog {
    let workspace: Workspace?
    let budgets: [Budget]
    let budgetCategoryLimits: [BudgetCategoryLimit]
    let cards: [Card]
    let budgetCardLinks: [BudgetCardLink]
    let budgetPresetLinks: [BudgetPresetLink]
    let categories: [Category]
    let presets: [Preset]
    let plannedExpenses: [PlannedExpense]
    let variableExpenses: [VariableExpense]
    let allocationAccounts: [AllocationAccount]
    let expenseAllocations: [ExpenseAllocation]
    let allocationSettlements: [AllocationSettlement]
    let savingsAccounts: [SavingsAccount]
    let savingsLedgerEntries: [SavingsLedgerEntry]
    let importMerchantRules: [ImportMerchantRule]
    let assistantAliasRules: [AssistantAliasRule]
    let incomeSeries: [IncomeSeries]
    let incomes: [Income]
}

@MainActor
struct MarinaWorkspaceReadStore {
    let modelContext: ModelContext
    let workspaceID: UUID

    func fetchCatalog() throws -> MarinaWorkspaceReadCatalog {
        MarinaWorkspaceReadCatalog(
            workspace: try fetchWorkspace(),
            budgets: try fetchBudgets(),
            budgetCategoryLimits: try fetchBudgetCategoryLimits(),
            cards: try fetchCards(),
            budgetCardLinks: try fetchBudgetCardLinks(),
            budgetPresetLinks: try fetchBudgetPresetLinks(),
            categories: try fetchCategories(),
            presets: try fetchPresets(),
            plannedExpenses: try fetchPlannedExpenses(),
            variableExpenses: try fetchVariableExpenses(),
            allocationAccounts: try fetchAllocationAccounts(),
            expenseAllocations: try fetchExpenseAllocations(),
            allocationSettlements: try fetchAllocationSettlements(),
            savingsAccounts: try fetchSavingsAccounts(),
            savingsLedgerEntries: try fetchSavingsLedgerEntries(),
            importMerchantRules: try fetchImportMerchantRules(),
            assistantAliasRules: try fetchAssistantAliasRules(),
            incomeSeries: try fetchIncomeSeries(),
            incomes: try fetchIncomes()
        )
    }

    func fetchWorkspace() throws -> Workspace? {
        try fetch(
            descriptor: FetchDescriptor<Workspace>(
                predicate: #Predicate { $0.id == workspaceID },
                sortBy: [SortDescriptor(\Workspace.name, order: .forward)]
            )
        ).first
    }

    func fetchBudgets() throws -> [Budget] {
        try fetch(
            descriptor: FetchDescriptor<Budget>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Budget.startDate, order: .reverse)]
            )
        )
    }

    func fetchBudgetCategoryLimits() throws -> [BudgetCategoryLimit] {
        try fetch(descriptor: FetchDescriptor<BudgetCategoryLimit>())
            .filter { $0.budget?.workspace?.id == workspaceID }
            .sorted { lhs, rhs in
                let lhsName = lhs.category?.name ?? ""
                let rhsName = rhs.category?.name ?? ""
                if lhsName != rhsName {
                    return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
                }
                return (lhs.budget?.startDate ?? .distantPast) > (rhs.budget?.startDate ?? .distantPast)
            }
    }

    func fetchCards() throws -> [Card] {
        try fetch(
            descriptor: FetchDescriptor<Card>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Card.name, order: .forward)]
            )
        )
    }

    func fetchBudgetCardLinks() throws -> [BudgetCardLink] {
        try fetch(descriptor: FetchDescriptor<BudgetCardLink>())
            .filter { $0.budget?.workspace?.id == workspaceID }
            .sorted { lhs, rhs in
                let lhsBudget = lhs.budget?.startDate ?? .distantPast
                let rhsBudget = rhs.budget?.startDate ?? .distantPast
                if lhsBudget != rhsBudget {
                    return lhsBudget > rhsBudget
                }
                return (lhs.card?.name ?? "").localizedCaseInsensitiveCompare(rhs.card?.name ?? "") == .orderedAscending
            }
    }

    func fetchBudgetPresetLinks() throws -> [BudgetPresetLink] {
        try fetch(descriptor: FetchDescriptor<BudgetPresetLink>())
            .filter { $0.budget?.workspace?.id == workspaceID }
            .sorted { lhs, rhs in
                let lhsBudget = lhs.budget?.startDate ?? .distantPast
                let rhsBudget = rhs.budget?.startDate ?? .distantPast
                if lhsBudget != rhsBudget {
                    return lhsBudget > rhsBudget
                }
                return (lhs.preset?.title ?? "").localizedCaseInsensitiveCompare(rhs.preset?.title ?? "") == .orderedAscending
            }
    }

    func fetchCategories() throws -> [Category] {
        try fetch(
            descriptor: FetchDescriptor<Category>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Category.name, order: .forward)]
            )
        )
    }

    func fetchPresets() throws -> [Preset] {
        try fetch(
            descriptor: FetchDescriptor<Preset>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Preset.title, order: .forward)]
            )
        )
    }

    func fetchPlannedExpenses() throws -> [PlannedExpense] {
        try fetch(
            descriptor: FetchDescriptor<PlannedExpense>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\PlannedExpense.expenseDate, order: .forward)]
            )
        )
    }

    func fetchVariableExpenses() throws -> [VariableExpense] {
        try fetch(
            descriptor: FetchDescriptor<VariableExpense>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\VariableExpense.transactionDate, order: .forward)]
            )
        )
    }

    func fetchAllocationAccounts() throws -> [AllocationAccount] {
        try fetch(
            descriptor: FetchDescriptor<AllocationAccount>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\AllocationAccount.name, order: .forward)]
            )
        )
    }

    func fetchExpenseAllocations() throws -> [ExpenseAllocation] {
        try fetch(
            descriptor: FetchDescriptor<ExpenseAllocation>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\ExpenseAllocation.createdAt, order: .reverse)]
            )
        )
    }

    func fetchAllocationSettlements() throws -> [AllocationSettlement] {
        try fetch(
            descriptor: FetchDescriptor<AllocationSettlement>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\AllocationSettlement.date, order: .reverse)]
            )
        )
    }

    func fetchSavingsAccounts() throws -> [SavingsAccount] {
        try fetch(
            descriptor: FetchDescriptor<SavingsAccount>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\SavingsAccount.name, order: .forward)]
            )
        )
    }

    func fetchSavingsLedgerEntries() throws -> [SavingsLedgerEntry] {
        try fetch(
            descriptor: FetchDescriptor<SavingsLedgerEntry>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .reverse)]
            )
        )
    }

    func fetchImportMerchantRules() throws -> [ImportMerchantRule] {
        try fetch(
            descriptor: FetchDescriptor<ImportMerchantRule>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\ImportMerchantRule.merchantKey, order: .forward)]
            )
        )
    }

    func fetchAssistantAliasRules() throws -> [AssistantAliasRule] {
        try fetch(
            descriptor: FetchDescriptor<AssistantAliasRule>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\AssistantAliasRule.aliasKey, order: .forward)]
            )
        )
    }

    func fetchIncomeSeries() throws -> [IncomeSeries] {
        try fetch(
            descriptor: FetchDescriptor<IncomeSeries>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\IncomeSeries.startDate, order: .forward)]
            )
        )
    }

    func fetchIncomes() throws -> [Income] {
        try fetch(
            descriptor: FetchDescriptor<Income>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Income.date, order: .forward)]
            )
        )
    }

    private func fetch<T>(descriptor: FetchDescriptor<T>) throws -> [T] where T: PersistentModel {
        try modelContext.fetch(descriptor)
    }
}

@MainActor
extension MarinaDataProvider {
    var workspaceReadStore: MarinaWorkspaceReadStore {
        MarinaWorkspaceReadStore(modelContext: modelContext, workspaceID: workspaceID)
    }
}
