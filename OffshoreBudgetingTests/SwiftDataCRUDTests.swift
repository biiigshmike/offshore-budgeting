//
//  SwiftDataCRUDTests.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/29/26.
//


import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct SwiftDataCRUDTests {

    // MARK: - Test Store

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

    private func fetchAll<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> [T] {
        try context.fetch(FetchDescriptor<T>())
    }

    // MARK: - Workspace

    @Test func workspace_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "Personal", hexColor: "#3B82F6")
        context.insert(ws)
        try context.save()

        let fetched1 = try fetchAll(Workspace.self, in: context)
        #expect(fetched1.count == 1)
        #expect(fetched1.first?.name == "Personal")

        ws.name = "Personal Updated"
        try context.save()

        let fetched2 = try fetchAll(Workspace.self, in: context)
        #expect(fetched2.first?.name == "Personal Updated")

        context.delete(ws)
        try context.save()

        let fetched3 = try fetchAll(Workspace.self, in: context)
        #expect(fetched3.isEmpty)
    }

    // MARK: - Card

    @Test func card_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", theme: "default", effect: "none", workspace: ws)

        context.insert(ws)
        context.insert(card)
        try context.save()

        let cards = try fetchAll(Card.self, in: context)
        #expect(cards.count == 1)
        #expect(cards.first?.name == "Visa")

        card.name = "Visa Updated"
        try context.save()

        let cards2 = try fetchAll(Card.self, in: context)
        #expect(cards2.first?.name == "Visa Updated")

        context.delete(card)
        try context.save()

        let cards3 = try fetchAll(Card.self, in: context)
        #expect(cards3.isEmpty)
    }

    // MARK: - Category

    @Test func category_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let cat = Category(name: "Groceries", hexColor: "#00FF00", workspace: ws)

        context.insert(ws)
        context.insert(cat)
        try context.save()

        let cats = try fetchAll(Category.self, in: context)
        #expect(cats.count == 1)
        #expect(cats.first?.name == "Groceries")

        cat.name = "Groceries Updated"
        try context.save()

        let cats2 = try fetchAll(Category.self, in: context)
        #expect(cats2.first?.name == "Groceries Updated")

        context.delete(cat)
        try context.save()

        let cats3 = try fetchAll(Category.self, in: context)
        #expect(cats3.isEmpty)
    }

    // MARK: - Preset

    @Test func preset_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let cat = Category(name: "Rent", hexColor: "#111111", workspace: ws)
        let preset = Preset(title: "Rent", plannedAmount: 1200, workspace: ws, defaultCategory: cat)

        context.insert(ws)
        context.insert(cat)
        context.insert(preset)
        try context.save()

        let presets = try fetchAll(Preset.self, in: context)
        #expect(presets.count == 1)
        #expect(presets.first?.title == "Rent")
        #expect(presets.first?.plannedAmount == 1200)

        preset.plannedAmount = 1250
        try context.save()

        let presets2 = try fetchAll(Preset.self, in: context)
        #expect(presets2.first?.plannedAmount == 1250)

        context.delete(preset)
        try context.save()

        let presets3 = try fetchAll(Preset.self, in: context)
        #expect(presets3.isEmpty)
    }

    // MARK: - Budget + join links

    @Test func budget_withLinks_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Amex", workspace: ws)
        let preset = Preset(title: "Netflix", plannedAmount: 19.99, workspace: ws)

        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let budget = Budget(name: "January", startDate: start, endDate: end, workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(preset)
        context.insert(budget)

        let link1 = BudgetCardLink(budget: budget, card: card)
        let link2 = BudgetPresetLink(budget: budget, preset: preset)
        context.insert(link1)
        context.insert(link2)

        try context.save()

        let budgets = try fetchAll(Budget.self, in: context)
        #expect(budgets.count == 1)
        #expect(budgets.first?.name == "January")

        let cardLinks = try fetchAll(BudgetCardLink.self, in: context)
        let presetLinks = try fetchAll(BudgetPresetLink.self, in: context)
        #expect(cardLinks.count == 1)
        #expect(presetLinks.count == 1)

        budget.name = "January Updated"
        try context.save()

        let budgets2 = try fetchAll(Budget.self, in: context)
        #expect(budgets2.first?.name == "January Updated")

        context.delete(budget)
        try context.save()

        let budgets3 = try fetchAll(Budget.self, in: context)
        #expect(budgets3.isEmpty)
    }

    // MARK: - Income, PlannedExpense, VariableExpense

    @Test func transactions_CRUD() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "Food", hexColor: "#FF0000", workspace: ws)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        let income = Income(source: "Paycheck", amount: 2000, date: date, isPlanned: true, workspace: ws, card: card)
        let planned = PlannedExpense(title: "Dinner", plannedAmount: 50, actualAmount: 40, expenseDate: date, workspace: ws, card: card, category: cat)
        let variable = VariableExpense(descriptionText: "Coffee", amount: 6.50, transactionDate: date, workspace: ws, card: card, category: cat)

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(income)
        context.insert(planned)
        context.insert(variable)
        try context.save()

        #expect(try fetchAll(Income.self, in: context).count == 1)
        #expect(try fetchAll(PlannedExpense.self, in: context).count == 1)
        #expect(try fetchAll(VariableExpense.self, in: context).count == 1)

        income.amount = 2100
        planned.actualAmount = 45
        variable.amount = 7.25
        try context.save()

        let income2 = try fetchAll(Income.self, in: context).first
        let planned2 = try fetchAll(PlannedExpense.self, in: context).first
        let variable2 = try fetchAll(VariableExpense.self, in: context).first

        #expect(income2?.amount == 2100)
        #expect(planned2?.actualAmount == 45)
        #expect(variable2?.amount == 7.25)

        context.delete(income)
        context.delete(planned)
        context.delete(variable)
        try context.save()

        #expect(try fetchAll(Income.self, in: context).isEmpty)
        #expect(try fetchAll(PlannedExpense.self, in: context).isEmpty)
        #expect(try fetchAll(VariableExpense.self, in: context).isEmpty)
    }

    // MARK: - Linked settlement integrity

    @Test func deletingLinkedSettlement_restoresExpenseAmountAndUnlinks() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "Food", hexColor: "#FF0000", workspace: ws)
        let account = AllocationAccount(name: "Partner", workspace: ws)
        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        let expense = VariableExpense(
            descriptionText: "Groceries",
            amount: 60,
            transactionDate: date,
            workspace: ws,
            card: card,
            category: cat
        )

        let settlement = AllocationSettlement(
            date: date,
            note: "Offset applied",
            amount: -20,
            workspace: ws,
            account: account,
            expense: expense
        )
        expense.offsetSettlement = settlement

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(account)
        context.insert(expense)
        context.insert(settlement)
        try context.save()

        let oldOffset = max(0, -settlement.amount)
        expense.amount = max(0, expense.amount + oldOffset)
        expense.offsetSettlement = nil
        context.delete(settlement)
        try context.save()

        let fetchedExpense = try fetchAll(VariableExpense.self, in: context).first
        let settlements = try fetchAll(AllocationSettlement.self, in: context)

        #expect(settlements.isEmpty)
        #expect(fetchedExpense?.amount == 80)
        #expect(fetchedExpense?.offsetSettlement == nil)
    }

    @Test func editingLinkedSettlement_updatesExpenseAmountAndDate() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "Food", hexColor: "#FF0000", workspace: ws)
        let account = AllocationAccount(name: "Partner", workspace: ws)

        let originalDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let updatedDate = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 12))!

        let expense = VariableExpense(
            descriptionText: "Groceries",
            amount: 60,
            transactionDate: originalDate,
            workspace: ws,
            card: card,
            category: cat
        )

        let settlement = AllocationSettlement(
            date: originalDate,
            note: "Offset applied",
            amount: -20,
            workspace: ws,
            account: account,
            expense: expense
        )
        expense.offsetSettlement = settlement

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(account)
        context.insert(expense)
        context.insert(settlement)
        try context.save()

        let oldOffset = max(0, -settlement.amount)
        let gross = max(0, expense.amount + oldOffset)
        let newOffset = 10.0

        settlement.amount = -newOffset
        settlement.date = updatedDate
        settlement.note = "Updated offset"

        expense.amount = max(0, gross - newOffset)
        expense.transactionDate = updatedDate

        try context.save()

        let fetchedExpense = try fetchAll(VariableExpense.self, in: context).first
        let fetchedSettlement = try fetchAll(AllocationSettlement.self, in: context).first

        #expect(fetchedExpense?.amount == 70)
        #expect(fetchedExpense?.transactionDate == updatedDate)
        #expect(fetchedSettlement?.amount == -10)
        #expect(fetchedSettlement?.date == updatedDate)
    }
}
