//
//  SwiftDataDeletionRulesTests.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/29/26.
//


import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct SwiftDataDeletionRulesTests {

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
            IncomeSeries.self,
            ImportMerchantRule.self,
            Income.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func count<T: PersistentModel>(_ type: T.Type, in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<T>())
    }

    // MARK: - Workspace cascade

    @Test func deletingWorkspace_CascadesToChildren() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Card", workspace: ws)
        let category = Category(name: "Cat", hexColor: "#123456", workspace: ws)
        let preset = Preset(title: "Preset", plannedAmount: 10, workspace: ws, defaultCard: card, defaultCategory: category)

        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let budget = Budget(name: "Budget", startDate: start, endDate: end, workspace: ws)

        let date = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let income = Income(source: "Pay", amount: 100, date: date, isPlanned: true, workspace: ws, card: card)
        let planned = PlannedExpense(title: "Planned", plannedAmount: 10, actualAmount: 0, expenseDate: date, workspace: ws, card: card, category: category)
        let variable = VariableExpense(descriptionText: "Var", amount: 5, transactionDate: date, workspace: ws, card: card, category: category)

        let merchantRule = ImportMerchantRule(merchantKey: "AMAZON", preferredName: "Amazon", preferredCategory: category, workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(category)
        context.insert(preset)
        context.insert(budget)
        context.insert(income)
        context.insert(planned)
        context.insert(variable)
        context.insert(merchantRule)

        try context.save()

        #expect(try count(Workspace.self, in: context) == 1)
        #expect(try count(Card.self, in: context) == 1)
        #expect(try count(Category.self, in: context) == 1)
        #expect(try count(Preset.self, in: context) == 1)
        #expect(try count(Budget.self, in: context) == 1)
        #expect(try count(Income.self, in: context) == 1)
        #expect(try count(PlannedExpense.self, in: context) == 1)
        #expect(try count(VariableExpense.self, in: context) == 1)
        #expect(try count(ImportMerchantRule.self, in: context) == 1)

        context.delete(ws)
        try context.save()

        #expect(try count(Workspace.self, in: context) == 0)
        #expect(try count(Card.self, in: context) == 0)
        #expect(try count(Category.self, in: context) == 0)
        #expect(try count(Preset.self, in: context) == 0)
        #expect(try count(Budget.self, in: context) == 0)
        #expect(try count(Income.self, in: context) == 0)
        #expect(try count(PlannedExpense.self, in: context) == 0)
        #expect(try count(VariableExpense.self, in: context) == 0)
        #expect(try count(ImportMerchantRule.self, in: context) == 0)
    }

    // MARK: - Card deletion removes links (unassign behavior)

    @Test func deletingCard_CascadesBudgetCardLinks() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Card", workspace: ws)

        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let budget = Budget(name: "Budget", startDate: start, endDate: end, workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(budget)

        let link = BudgetCardLink(budget: budget, card: card)
        context.insert(link)

        try context.save()

        #expect(try count(Card.self, in: context) == 1)
        #expect(try count(Budget.self, in: context) == 1)
        #expect(try count(BudgetCardLink.self, in: context) == 1)

        context.delete(card)
        try context.save()

        // Budget remains, but link should be gone (this is your “unassigns itself” behavior).
        #expect(try count(Card.self, in: context) == 0)
        #expect(try count(Budget.self, in: context) == 1)
        #expect(try count(BudgetCardLink.self, in: context) == 0)
    }

    // MARK: - Budget deletion removes join rows

    @Test func deletingBudget_CascadesJoinRows() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Card", workspace: ws)
        let preset = Preset(title: "Preset", plannedAmount: 10, workspace: ws)

        let category = Category(name: "Cat", hexColor: "#123456", workspace: ws)

        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let budget = Budget(name: "Budget", startDate: start, endDate: end, workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(preset)
        context.insert(category)
        context.insert(budget)

        context.insert(BudgetCardLink(budget: budget, card: card))
        context.insert(BudgetPresetLink(budget: budget, preset: preset))
        context.insert(BudgetCategoryLimit(minAmount: 0, maxAmount: 100, budget: budget, category: category))

        try context.save()

        #expect(try count(Budget.self, in: context) == 1)
        #expect(try count(BudgetCardLink.self, in: context) == 1)
        #expect(try count(BudgetPresetLink.self, in: context) == 1)
        #expect(try count(BudgetCategoryLimit.self, in: context) == 1)

        context.delete(budget)
        try context.save()

        #expect(try count(Budget.self, in: context) == 0)
        #expect(try count(BudgetCardLink.self, in: context) == 0)
        #expect(try count(BudgetPresetLink.self, in: context) == 0)
        #expect(try count(BudgetCategoryLimit.self, in: context) == 0)
    }
}
