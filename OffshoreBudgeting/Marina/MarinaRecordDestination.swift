import SwiftUI
import SwiftData

/// Resolves snapshots against live, workspace-owned records before opening app screens.
@available(iOS 26.0, macOS 26.0, *)
struct MarinaRecordDestination: View {
    let workspace: Workspace
    let record: MarinaRecord
    @Environment(\.modelContext) private var context
    @State private var destination: Destination?
    @State private var failure: String?

    private enum Destination {
        case expense(VariableExpense)
        case planned(PlannedExpense)
        case income(Income)
        case budget(Budget)
        case savings(SavingsLedgerEntry)
        case reconciliation(AllocationAccount)
    }

    var body: some View {
        Group {
            if let destination {
                switch destination {
                case .expense(let expense): EditExpenseView(workspace: workspace, expense: expense)
                case .planned(let expense): EditPlannedExpenseView(workspace: workspace, plannedExpense: expense)
                case .income(let income): EditIncomeView(workspace: workspace, income: income)
                case .budget(let budget): BudgetDetailView(workspace: workspace, budget: budget)
                case .savings(let entry): MarinaSavingsEntryView(entry: entry)
                case .reconciliation(let account): AllocationAccountDetailView(workspace: workspace, account: account)
                }
            } else if let failure {
                ContentUnavailableView("Record unavailable", systemImage: "doc.questionmark", description: Text(failure))
            } else {
                ProgressView("Opening record")
            }
        }
        .task { resolve() }
    }

    private func resolve() {
        let recordID = record.id
        let workspaceID = workspace.id
        do {
            switch record.domain {
            case .expenses:
                let descriptor = FetchDescriptor<VariableExpense>(predicate: #Predicate { $0.id == recordID && $0.workspace?.id == workspaceID })
                if let value = try context.fetch(descriptor).first { destination = .expense(value) }
            case .plannedExpenses:
                let descriptor = FetchDescriptor<PlannedExpense>(predicate: #Predicate { $0.id == recordID && $0.workspace?.id == workspaceID })
                if let value = try context.fetch(descriptor).first { destination = .planned(value) }
            case .income:
                let descriptor = FetchDescriptor<Income>(predicate: #Predicate { $0.id == recordID && $0.workspace?.id == workspaceID })
                if let value = try context.fetch(descriptor).first { destination = .income(value) }
            case .budgets:
                let descriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.id == recordID && $0.workspace?.id == workspaceID })
                if let value = try context.fetch(descriptor).first { destination = .budget(value) }
            case .savings:
                let descriptor = FetchDescriptor<SavingsLedgerEntry>(predicate: #Predicate { $0.id == recordID && $0.workspace?.id == workspaceID })
                if let entry = try context.fetch(descriptor).first, let account = entry.account, account.workspace?.id == workspaceID {
                    destination = .savings(entry)
                }
            case .reconciliation:
                let allocations = FetchDescriptor<ExpenseAllocation>(predicate: #Predicate { $0.id == recordID && $0.workspace?.id == workspaceID })
                let settlements = FetchDescriptor<AllocationSettlement>(predicate: #Predicate { $0.id == recordID && $0.workspace?.id == workspaceID })
                if let account = try context.fetch(allocations).first?.account, account.workspace?.id == workspaceID {
                    destination = .reconciliation(account)
                } else if let account = try context.fetch(settlements).first?.account, account.workspace?.id == workspaceID {
                    destination = .reconciliation(account)
                }
            }
            if destination == nil { failure = "This record was removed or is no longer available in this workspace. The saved answer still shows the original snapshot." }
        } catch {
            failure = "The record could not be loaded. Close this screen and try again."
        }
    }
}
