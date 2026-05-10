import Foundation
import SwiftData

@MainActor
struct MarinaDataProvider {
    let modelContext: ModelContext
    let workspaceID: UUID

    func fetchAllCategories() -> [Category] {
        fetch(
            descriptor: FetchDescriptor<Category>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Category.name, order: .forward)]
            )
        )
    }

    func fetchAllPlannedExpenses() -> [PlannedExpense] {
        fetch(
            descriptor: FetchDescriptor<PlannedExpense>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\PlannedExpense.expenseDate, order: .forward)]
            )
        )
    }

    func fetchAllVariableExpenses() -> [VariableExpense] {
        fetch(
            descriptor: FetchDescriptor<VariableExpense>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\VariableExpense.transactionDate, order: .forward)]
            )
        )
    }

    func fetchAllExpenses() -> (planned: [PlannedExpense], variable: [VariableExpense]) {
        (fetchAllPlannedExpenses(), fetchAllVariableExpenses())
    }

    func fetchAllCards() -> [Card] {
        fetch(
            descriptor: FetchDescriptor<Card>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Card.name, order: .forward)]
            )
        )
    }

    func fetchAllBudgets() -> [Budget] {
        fetch(
            descriptor: FetchDescriptor<Budget>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Budget.startDate, order: .reverse)]
            )
        )
    }

    func fetchAllPresets() -> [Preset] {
        fetch(
            descriptor: FetchDescriptor<Preset>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Preset.title, order: .forward)]
            )
        )
    }

    func fetchAllIncomes() -> [Income] {
        fetch(
            descriptor: FetchDescriptor<Income>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\Income.date, order: .forward)]
            )
        )
    }

    func fetchAllAllocationAccounts() -> [AllocationAccount] {
        fetch(
            descriptor: FetchDescriptor<AllocationAccount>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\AllocationAccount.name, order: .forward)]
            )
        )
    }

    func fetchAllSavingsAccounts() -> [SavingsAccount] {
        fetch(
            descriptor: FetchDescriptor<SavingsAccount>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\SavingsAccount.name, order: .forward)]
            )
        )
    }

    func fetchAllSavingsLedgerEntries() -> [SavingsLedgerEntry] {
        fetch(
            descriptor: FetchDescriptor<SavingsLedgerEntry>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .reverse)]
            )
        )
    }

    func fetchAllAllocationSettlements() -> [AllocationSettlement] {
        fetch(
            descriptor: FetchDescriptor<AllocationSettlement>(
                predicate: #Predicate { $0.workspace?.id == workspaceID },
                sortBy: [SortDescriptor(\AllocationSettlement.date, order: .reverse)]
            )
        )
    }

    func fetchWorkspace() -> Workspace? {
        fetch(
            descriptor: FetchDescriptor<Workspace>(
                predicate: #Predicate { $0.id == workspaceID },
                sortBy: [SortDescriptor(\Workspace.name, order: .forward)]
            )
        ).first
    }

    private func fetch<T>(descriptor: FetchDescriptor<T>) -> [T] where T: PersistentModel {
        (try? modelContext.fetch(descriptor)) ?? []
    }
}
