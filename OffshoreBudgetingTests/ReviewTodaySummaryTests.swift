import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct ReviewTodaySummaryTests {
    @Test func scopesBothExpenseTypesToTheWorkspaceAndLocalDay() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Work", hexColor: "#3B82F6")
        let card = Card(name: "Everyday", workspace: workspace)
        let backup = Card(name: "Backup", workspace: workspace)
        let otherCard = Card(name: "Other", workspace: workspace)
        context.insert(workspace)
        context.insert(otherWorkspace)
        context.insert(card)
        context.insert(backup)
        context.insert(otherCard)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        // The clock goes back during this local day, so its boundaries are 25 hours apart.
        let date = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12)))
        let start = calendar.startOfDay(for: date)
        let end = try #require(calendar.date(byAdding: .day, value: 1, to: start))
        let before = start.addingTimeInterval(-0.25)
        let last = end.addingTimeInterval(-0.25)

        func insertVariable(
            _ amount: Double,
            at date: Date,
            in owner: Workspace,
            card: Card? = nil,
            kind: VariableExpenseKind = .debit
        ) {
            context.insert(VariableExpense(
                descriptionText: "Purchase",
                amount: amount,
                kindRaw: kind.rawValue,
                transactionDate: date,
                workspace: owner,
                card: card
            ))
        }

        func insertPlanned(
            _ planned: Double,
            actual: Double = 0,
            at date: Date,
            in owner: Workspace,
            card: Card? = nil
        ) {
            context.insert(PlannedExpense(
                title: "Bill",
                plannedAmount: planned,
                actualAmount: actual,
                expenseDate: date,
                workspace: owner,
                card: card
            ))
        }

        insertVariable(80, at: start, in: workspace, card: card)
        insertVariable(25, at: last, in: workspace, card: card, kind: .credit)
        insertVariable(5, at: date, in: workspace, card: otherCard)
        insertVariable(1_000, at: before, in: workspace)
        insertVariable(1_000, at: end, in: workspace)
        insertVariable(1_000, at: date, in: otherWorkspace)

        insertPlanned(100, actual: 70, at: start, in: workspace, card: backup)
        insertPlanned(10, at: last, in: workspace, card: card)
        insertPlanned(1_000, at: before, in: workspace)
        insertPlanned(1_000, at: end, in: workspace)
        insertPlanned(1_000, at: date, in: otherWorkspace)
        try context.save()

        let summary = try ReviewTodaySummary.load(
            workspaceID: workspace.id,
            in: context,
            date: date,
            calendar: calendar
        )
        #expect(summary.total == 140)
        #expect(summary.variableCount == 3)
        #expect(summary.plannedCount == 2)
        #expect(summary.topCards == [
            .init(name: "Backup", amount: 70),
            .init(name: "Everyday", amount: 65)
        ])
        #expect(!summary.isEmpty)

        let expenses = try ReviewTodayExpenses.load(
            workspaceID: workspace.id, in: context, date: date, calendar: calendar
        )
        let activity = ReviewTodayActivity(expenses: expenses)
        #expect(activity.day == start)
        #expect(activity.entries.count == 4)
        #expect(activity.entries.map(\.date) == [last, date, start, start])
        #expect(activity.stillPlanned.map(\.expenseDate) == [last])
        #expect(activity.spent == 155)
        #expect(activity.refunded == 25)
        #expect(activity.cards.map(\.id) == [.card(card.id), .card(backup.id), .card(otherCard.id)])
        #expect(activity.cards.map(\.amount) == [80, 70, 5])
        #expect(activity.cards.reduce(0) { $0 + $1.amount } == activity.spent)
    }

    @Test func returnsAnEmptySummaryWhenWorkspaceHasNoExpenses() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        try context.save()

        let summary = try ReviewTodaySummary.load(workspaceID: workspace.id, in: context)
        #expect(summary.isEmpty)
        #expect(summary.total == 0)
        #expect(summary.topCards.isEmpty)
    }

    @Test func reviewUsesGrossSpendingAndRefreshesAfterEdits() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(workspace)
        let firstCategory = Offshore.Category(name: "Food", hexColor: "#112233", workspace: workspace)
        let secondCategory = Offshore.Category(name: "Food", hexColor: "#445566", workspace: workspace)
        context.insert(firstCategory)
        context.insert(secondCategory)

        let date = Date.now
        let firstCard = Card(name: "Everyday", workspace: workspace)
        let secondCard = Card(name: "Everyday", workspace: workspace)
        context.insert(firstCard)
        context.insert(secondCard)
        let purchase = VariableExpense(descriptionText: "Purchase", amount: 80,
                                       transactionDate: date, workspace: workspace, card: firstCard, category: firstCategory)
        let refund = VariableExpense(descriptionText: "Refund", amount: 20, kindRaw: VariableExpenseKind.credit.rawValue,
                                     transactionDate: date, workspace: workspace, category: secondCategory)
        let adjustment = VariableExpense(descriptionText: "Adjustment", amount: 5, kindRaw: VariableExpenseKind.adjustment.rawValue,
                                         transactionDate: date, workspace: workspace, category: secondCategory)
        let recorded = PlannedExpense(title: "Recorded", plannedAmount: 90, actualAmount: 30,
                                      expenseDate: date, workspace: workspace, card: secondCard, category: secondCategory)
        let pending = PlannedExpense(title: "Pending", plannedAmount: 50, actualAmount: 0,
                                     expenseDate: date, workspace: workspace)
        let uncategorized = VariableExpense(descriptionText: "Uncategorized", amount: 10,
                                             transactionDate: date, workspace: workspace)
        context.insert(purchase)
        context.insert(refund)
        context.insert(adjustment)
        context.insert(uncategorized)
        context.insert(recorded)
        context.insert(pending)
        context.insert(ExpenseAllocation(allocatedAmount: 15, workspace: workspace, plannedExpense: recorded))
        try context.save()

        func load() throws -> ReviewTodayActivity {
            let expenses = try ReviewTodayExpenses.load(workspaceID: workspace.id, in: context, date: date)
            return ReviewTodayActivity(expenses: expenses)
        }

        let original = try load()
        #expect(original.spent == 135)
        #expect(original.refunded == 20)
        #expect(original.categories.map(\.id) == [firstCategory.id, secondCategory.id, nil])
        #expect(original.categories.map(\.amount) == [80, 45, 10])
        #expect(original.categories.reduce(0) { $0 + $1.amount } == original.spent)
        #expect(original.cards.map(\.id) == [.card(firstCard.id), .card(secondCard.id), .noCard])
        #expect(original.cards.map(\.amount) == [80, 45, 10])
        #expect(original.cards[2].categories.map(\.id) == [nil])
        #expect(original.cards.allSatisfy { card in
            card.categories.reduce(0) { $0 + $1.amount } == card.amount
        })
        #expect(original.entries.count == 5)
        #expect(original.stillPlanned.map(\.id) == [pending.id])

        pending.actualAmount = 25
        purchase.category = secondCategory
        try context.save()

        let updated = try load()
        #expect(updated.stillPlanned.isEmpty)
        #expect(updated.entries.contains { $0.id == pending.persistentModelID })
        #expect(updated.spent == 160)
        #expect(updated.categories.map(\.id) == [secondCategory.id, nil])
        #expect(updated.categories.map(\.amount) == [125, 35])
        #expect(updated.cards[0].categories.map(\.id) == [secondCategory.id])
        #expect(updated.cards.map(\.amount) == [80, 45, 35])
    }

    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Workspace.self, Budget.self, BudgetCategoryLimit.self, Card.self,
            BudgetCardLink.self, BudgetPresetLink.self, Offshore.Category.self, Preset.self,
            PlannedExpense.self, VariableExpense.self, AllocationAccount.self,
            ExpenseAllocation.self, AllocationSettlement.self, SavingsAccount.self,
            SavingsLedgerEntry.self, ImportMerchantRule.self, AssistantAliasRule.self,
            MarinaChatSession.self, IncomeSeries.self, Income.self
        ])
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }
}
