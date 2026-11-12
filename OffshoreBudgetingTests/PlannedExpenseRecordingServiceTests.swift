import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct PlannedExpenseRecordingServiceTests {
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Category.self, Preset.self,
            PlannedExpense.self, VariableExpense.self, AllocationAccount.self,
            ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
            MarinaChatSession.self, IncomeSeries.self, Income.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }

    @Test func recordsOnlySelectedOccurrenceAndPersists() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let preset = Preset(title: "Rent", plannedAmount: 100, workspace: workspace)
        let budgetID = UUID()
        let date = Date.now.addingTimeInterval(86400)
        let expense = PlannedExpense(
            title: "Rent", plannedAmount: 100, expenseDate: date, workspace: workspace,
            sourcePresetID: preset.id, sourceBudgetID: budgetID
        )
        let other = PlannedExpense(
            title: "Rent", plannedAmount: 100, expenseDate: date.addingTimeInterval(86400),
            workspace: workspace, sourcePresetID: preset.id, sourceBudgetID: budgetID
        )
        context.insert(workspace)
        context.insert(preset)
        context.insert(expense)
        context.insert(other)
        try context.save()

        #expect(PlannedExpenseRecordingService.canRecord(expense))
        try PlannedExpenseRecordingService.recordAsPlanned(expense, modelContext: context)

        #expect(expense.actualAmount == 100)
        #expect(!PlannedExpenseRecordingService.canRecord(expense))
        #expect(expense.expenseDate == date)
        #expect(expense.sourcePresetID == preset.id)
        #expect(expense.sourceBudgetID == budgetID)
        #expect(other.actualAmount == 0)
        #expect(preset.plannedAmount == 100)

        let reloaded = ModelContext(context.container)
        let rows = try reloaded.fetch(FetchDescriptor<PlannedExpense>())
        #expect(rows.first(where: { $0.id == expense.id })?.actualAmount == 100)
        #expect(rows.first(where: { $0.id == other.id })?.actualAmount == 0)
    }

    @Test(arguments: [0.0, -10.0, Double.infinity, Double.nan])
    func invalidPlannedAmountsCannotBeRecorded(amount: Double) throws {
        let expense = PlannedExpense(title: "Invalid", plannedAmount: amount, expenseDate: .now)
        #expect(!PlannedExpenseRecordingService.canRecord(expense))
        try PlannedExpenseRecordingService.recordAsPlanned(expense) {
            Issue.record("An ineligible expense must not be saved")
        }
        #expect(expense.actualAmount == 0)
    }

    @Test func doesNotOverwriteActualAmountChangedAfterMenuWasShown() throws {
        let expense = PlannedExpense(title: "Manual", plannedAmount: 100, expenseDate: .now)
        #expect(PlannedExpenseRecordingService.canRecord(expense))
        expense.actualAmount = 85
        try PlannedExpenseRecordingService.recordAsPlanned(expense) {
            Issue.record("A recorded expense must not be saved again")
        }
        #expect(!PlannedExpenseRecordingService.canRecord(expense))
        #expect(expense.actualAmount == 85)
    }

    @Test(arguments: [false, true])
    func preservesSplitGrossAndBudgetImpact(preservesGross: Bool) throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let account = AllocationAccount(name: "Shared", workspace: workspace)
        let expense = PlannedExpense(title: "Dinner", plannedAmount: 100, expenseDate: .now, workspace: workspace)
        let split = ExpenseAllocation(
            allocatedAmount: 30, preservesGrossAmount: preservesGross,
            workspace: workspace, account: account, plannedExpense: expense
        )
        context.insert(workspace)
        context.insert(account)
        context.insert(expense)
        context.insert(split)
        expense.allocation = split
        try context.save()
        let previousUpdatedAt = split.updatedAt
        let previousBalance = AllocationLedgerService.balance(for: account)
        let previousImpact = SavingsMathService.plannedBudgetImpactAmount(for: expense)

        try PlannedExpenseRecordingService.recordAsPlanned(expense, modelContext: context)

        #expect(expense.actualAmount == 100)
        #expect(expense.allocation?.id == split.id)
        #expect(split.preservesGrossAmount)
        #expect(split.allocatedAmount == 30)
        #expect(split.updatedAt == previousUpdatedAt)
        #expect(SavingsMathService.grossRecordedActualAmount(for: expense) == 100)
        #expect(SavingsMathService.plannedBudgetImpactAmount(for: expense) == previousImpact)
        #expect(AllocationLedgerService.balance(for: account) == previousBalance)
    }

    @Test func preservesSavingsAndReconciliationOffsets() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let account = AllocationAccount(name: "Shared", workspace: workspace)
        let savings = SavingsAccount(total: 200, workspace: workspace)
        let expense = PlannedExpense(title: "Offset", plannedAmount: 100, expenseDate: .now, workspace: workspace)
        let settlement = AllocationSettlement(
            date: expense.expenseDate, note: "Existing offset", amount: -100,
            workspace: workspace, account: account, plannedExpense: expense
        )
        let entry = SavingsLedgerEntry(
            date: expense.expenseDate, amount: -10, note: "Savings offset",
            kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
            workspace: workspace, account: savings, plannedExpense: expense
        )
        context.insert(workspace)
        context.insert(account)
        context.insert(savings)
        context.insert(expense)
        context.insert(settlement)
        context.insert(entry)
        expense.offsetSettlement = settlement
        expense.savingsLedgerEntry = entry
        try context.save()
        let previousImpact = SavingsMathService.plannedBudgetImpactAmount(for: expense)
        let previousBalance = AllocationLedgerService.balance(for: account)

        try PlannedExpenseRecordingService.recordAsPlanned(expense, modelContext: context)

        #expect(expense.actualAmount == 100)
        #expect(expense.offsetSettlement?.id == settlement.id)
        #expect(expense.savingsLedgerEntry?.id == entry.id)
        #expect(settlement.amount == -100)
        #expect(entry.amount == -10)
        #expect(savings.total == 200)
        #expect(SavingsMathService.plannedBudgetImpactAmount(for: expense) == previousImpact)
        #expect(AllocationLedgerService.balance(for: account) == previousBalance)
        #expect(try context.fetchCount(FetchDescriptor<AllocationSettlement>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SavingsLedgerEntry>()) == 1)
    }

    @Test func failedSaveRestoresOnlyRecordingChanges() throws {
        enum SaveFailure: Error { case failed }
        let expense = PlannedExpense(title: "Dinner", plannedAmount: 100, expenseDate: .now)
        let split = ExpenseAllocation(allocatedAmount: 30, preservesGrossAmount: false, plannedExpense: expense)
        expense.allocation = split
        // An unrelated pending edit must survive a recording failure.
        expense.title = "Updated dinner"

        #expect(throws: SaveFailure.self) {
            try PlannedExpenseRecordingService.recordAsPlanned(expense) {
                #expect(expense.actualAmount == 100)
                #expect(split.preservesGrossAmount)
                throw SaveFailure.failed
            }
        }

        #expect(expense.actualAmount == 0)
        #expect(!split.preservesGrossAmount)
        #expect(expense.title == "Updated dinner")
        #expect(expense.allocation?.id == split.id)
        #expect(split.allocatedAmount == 30)
        #expect(PlannedExpenseRecordingService.canRecord(expense))
    }
}
