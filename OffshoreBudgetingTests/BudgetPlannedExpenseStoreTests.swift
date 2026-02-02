//
//  BudgetPlannedExpenseStoreTests.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/1/26.
//

import Foundation
import SwiftData
import Testing
@testable import Offshore

struct BudgetPlannedExpenseStoreTests {

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

    // MARK: - Tests

    @Test func plannedExpenses_AreBudgetScopedEvenWhenCardIsSharedAndDatesOverlap() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Shared Card", workspace: ws)

        let cal = Calendar(identifier: .gregorian)

        let budgetAStart = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let budgetAEnd = cal.date(from: DateComponents(year: 2026, month: 1, day: 31))!
        let budgetA = Budget(name: "Budget A", startDate: budgetAStart, endDate: budgetAEnd, workspace: ws)

        let budgetBStart = cal.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let budgetBEnd = cal.date(from: DateComponents(year: 2026, month: 2, day: 14))!
        let budgetB = Budget(name: "Budget B", startDate: budgetBStart, endDate: budgetBEnd, workspace: ws)

        let sharedExpenseDate = cal.date(from: DateComponents(year: 2026, month: 1, day: 20))!

        let plannedA = PlannedExpense(
            title: "Rent",
            plannedAmount: 1200,
            actualAmount: 0,
            expenseDate: sharedExpenseDate,
            workspace: ws,
            card: card,
            category: nil,
            sourcePresetID: nil,
            sourceBudgetID: budgetA.id
        )

        let plannedB = PlannedExpense(
            title: "Rent",
            plannedAmount: 1200,
            actualAmount: 0,
            expenseDate: sharedExpenseDate,
            workspace: ws,
            card: card,
            category: nil,
            sourcePresetID: nil,
            sourceBudgetID: budgetB.id
        )

        context.insert(ws)
        context.insert(card)
        context.insert(budgetA)
        context.insert(budgetB)

        context.insert(BudgetCardLink(budget: budgetA, card: card))
        context.insert(BudgetCardLink(budget: budgetB, card: card))

        context.insert(plannedA)
        context.insert(plannedB)

        try context.save()

        #expect((card.plannedExpenses ?? []).count == 2)

        let aResults = BudgetPlannedExpenseStore.plannedExpenses(in: ws, for: budgetA, calendar: cal)
        let bResults = BudgetPlannedExpenseStore.plannedExpenses(in: ws, for: budgetB, calendar: cal)

        #expect(aResults.count == 1)
        #expect(bResults.count == 1)

        #expect(aResults.first?.sourceBudgetID == budgetA.id)
        #expect(bResults.first?.sourceBudgetID == budgetB.id)
    }
}

