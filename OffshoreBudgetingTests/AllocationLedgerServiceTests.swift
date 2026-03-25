import Foundation
import SwiftData
import Testing
@testable import Offshore

struct AllocationLedgerServiceTests {

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
            IncomeSeries.self,
            ImportMerchantRule.self,
            Income.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    @MainActor
    @Test func rows_computeRunningBalanceAcrossFullHistory() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: workspace)
        let category = Category(name: "Travel", hexColor: "#00AA00", workspace: workspace)
        let account = AllocationAccount(name: "Alex", workspace: workspace)

        let expenseOne = VariableExpense(
            descriptionText: "Dinner",
            amount: 40,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: Self.makeDate(year: 2026, month: 3, day: 10),
            workspace: workspace,
            card: card,
            category: category
        )
        let allocationOne = ExpenseAllocation(
            allocatedAmount: 25,
            workspace: workspace,
            account: account,
            expense: expenseOne
        )

        let expenseTwo = VariableExpense(
            descriptionText: "Concert",
            amount: 30,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: Self.makeDate(year: 2026, month: 3, day: 11),
            workspace: workspace,
            card: card,
            category: category
        )
        let allocationTwo = ExpenseAllocation(
            allocatedAmount: 15,
            workspace: workspace,
            account: account,
            expense: expenseTwo
        )

        let settlement = AllocationSettlement(
            date: Self.makeDate(year: 2026, month: 3, day: 12),
            note: "Venmo",
            amount: -10,
            workspace: workspace,
            account: account
        )

        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(account)
        context.insert(expenseOne)
        context.insert(expenseTwo)
        context.insert(allocationOne)
        context.insert(allocationTwo)
        context.insert(settlement)
        try context.save()

        let rows = AllocationLedgerService.rows(for: account)

        #expect(rows.map(\.title) == ["Venmo", "Concert", "Dinner"])
        #expect(rows.map(\.runningBalance) == [30, 40, 25])
    }

    @MainActor
    @Test func rows_useAscendingIDTiebreakWhenComputingSameDayRunningBalance() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: workspace)
        let category = Category(name: "Shared", hexColor: "#00AA00", workspace: workspace)
        let account = AllocationAccount(name: "Jamie", workspace: workspace)
        let date = Self.makeDate(year: 2026, month: 3, day: 12)

        let allocationAID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let allocationBID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        let expenseA = VariableExpense(
            descriptionText: "Alpha",
            amount: 20,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: date,
            workspace: workspace,
            card: card,
            category: category
        )
        let expenseB = VariableExpense(
            descriptionText: "Bravo",
            amount: 20,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: date,
            workspace: workspace,
            card: card,
            category: category
        )
        let allocationA = ExpenseAllocation(
            id: allocationAID,
            allocatedAmount: 5,
            workspace: workspace,
            account: account,
            expense: expenseA
        )
        let allocationB = ExpenseAllocation(
            id: allocationBID,
            allocatedAmount: 7,
            workspace: workspace,
            account: account,
            expense: expenseB
        )

        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(account)
        context.insert(expenseA)
        context.insert(expenseB)
        context.insert(allocationA)
        context.insert(allocationB)
        try context.save()

        let rows = AllocationLedgerService.rows(for: account)

        #expect(rows.map(\.title) == ["Bravo", "Alpha"])
        #expect(rows.map(\.runningBalance) == [12, 5])
    }

    @MainActor
    @Test func rows_keepFullHistoryRunningBalanceAfterCallerFiltersVisibleRange() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: workspace)
        let category = Category(name: "Food", hexColor: "#00AA00", workspace: workspace)
        let account = AllocationAccount(name: "Sam", workspace: workspace)

        let earlyExpense = VariableExpense(
            descriptionText: "Older",
            amount: 50,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: Self.makeDate(year: 2026, month: 3, day: 1),
            workspace: workspace,
            card: card,
            category: category
        )
        let visibleExpense = VariableExpense(
            descriptionText: "Visible",
            amount: 50,
            kindRaw: VariableExpenseKind.debit.rawValue,
            transactionDate: Self.makeDate(year: 2026, month: 3, day: 20),
            workspace: workspace,
            card: card,
            category: category
        )

        let earlyAllocation = ExpenseAllocation(
            allocatedAmount: 12,
            workspace: workspace,
            account: account,
            expense: earlyExpense
        )
        let visibleAllocation = ExpenseAllocation(
            allocatedAmount: 8,
            workspace: workspace,
            account: account,
            expense: visibleExpense
        )

        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(account)
        context.insert(earlyExpense)
        context.insert(visibleExpense)
        context.insert(earlyAllocation)
        context.insert(visibleAllocation)
        try context.save()

        let filteredRows = AllocationLedgerService.rows(for: account).filter {
            $0.date >= Self.makeDate(year: 2026, month: 3, day: 15)
        }

        #expect(filteredRows.count == 1)
        #expect(filteredRows[0].title == "Visible")
        #expect(filteredRows[0].runningBalance == 20)
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }
}
