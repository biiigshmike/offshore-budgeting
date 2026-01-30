//
//  BudgetAggregationMathTests.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/29/26.
//


import Foundation
import SwiftData
import Testing
@testable import Offshore

struct BudgetAggregationMathTests {

    // MARK: - Totals model (test-only)

    private struct Totals: Equatable {
        var plannedExpensePlannedTotal: Double
        var plannedExpenseActualTotal: Double
        var variableExpenseTotal: Double
        var plannedIncomeTotal: Double
        var actualIncomeTotal: Double

        var potentialSavings: Double {
            plannedIncomeTotal - plannedExpensePlannedTotal
        }

        var actualSavings: Double {
            actualIncomeTotal - (plannedExpenseActualTotal + variableExpenseTotal)
        }
    }

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

    // MARK: - Aggregator (test-only, but uses real SwiftData fetches)

    private func totals(
        for workspace: Workspace,
        start: Date,
        end: Date,
        card: Card?,
        in context: ModelContext
    ) throws -> Totals {

        let wsID = workspace.persistentModelID

        let windowStart = Calendar.current.startOfDay(for: start)
        let windowEnd = Calendar.current.startOfDay(for: end)

        let plannedDescriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { exp in
                exp.workspace?.persistentModelID == wsID
            }
        )

        let variableDescriptor = FetchDescriptor<VariableExpense>(
            predicate: #Predicate<VariableExpense> { exp in
                exp.workspace?.persistentModelID == wsID
            }
        )

        let incomeDescriptor = FetchDescriptor<Income>(
            predicate: #Predicate<Income> { inc in
                inc.workspace?.persistentModelID == wsID
            }
        )

        let plannedExpenses = try context.fetch(plannedDescriptor)
        let variableExpenses = try context.fetch(variableDescriptor)
        let incomes = try context.fetch(incomeDescriptor)

        let plannedInWindow = plannedExpenses.filter { exp in
            let day = Calendar.current.startOfDay(for: exp.expenseDate)
            let inWindow = (day >= windowStart && day <= windowEnd)
            let matchesCard = card == nil ? true : (exp.card?.persistentModelID == card?.persistentModelID)
            return inWindow && matchesCard
        }

        let variableInWindow = variableExpenses.filter { exp in
            let day = Calendar.current.startOfDay(for: exp.transactionDate)
            let inWindow = (day >= windowStart && day <= windowEnd)
            let matchesCard = card == nil ? true : (exp.card?.persistentModelID == card?.persistentModelID)
            return inWindow && matchesCard
        }

        let incomesInWindow = incomes.filter { inc in
            let day = Calendar.current.startOfDay(for: inc.date)
            let inWindow = (day >= windowStart && day <= windowEnd)
            let matchesCard = card == nil ? true : (inc.card?.persistentModelID == card?.persistentModelID)
            return inWindow && matchesCard
        }

        let plannedExpensePlannedTotal = plannedInWindow.reduce(0) { $0 + $1.plannedAmount }
        let plannedExpenseActualTotal = plannedInWindow.reduce(0) { $0 + $1.actualAmount }
        let variableExpenseTotal = variableInWindow.reduce(0) { $0 + $1.amount }

        let plannedIncomeTotal = incomesInWindow.filter { $0.isPlanned }.reduce(0) { $0 + $1.amount }
        let actualIncomeTotal = incomesInWindow.filter { !$0.isPlanned }.reduce(0) { $0 + $1.amount }

        return Totals(
            plannedExpensePlannedTotal: plannedExpensePlannedTotal,
            plannedExpenseActualTotal: plannedExpenseActualTotal,
            variableExpenseTotal: variableExpenseTotal,
            plannedIncomeTotal: plannedIncomeTotal,
            actualIncomeTotal: actualIncomeTotal
        )
    }

    // MARK: - Tests

    @Test func aggregation_allCards_windowedMathIsCorrect() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let cardA = Card(name: "Card A", workspace: ws)
        let cardB = Card(name: "Card B", workspace: ws)
        let cat = Category(name: "Cat", hexColor: "#111111", workspace: ws)

        context.insert(ws)
        context.insert(cardA)
        context.insert(cardB)
        context.insert(cat)

        let d1 = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        let d2 = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let dOut = Calendar.current.date(from: DateComponents(year: 2026, month: 2, day: 1))!

        // Planned expenses (2 in-window, 1 out-of-window)
        context.insert(PlannedExpense(title: "P1", plannedAmount: 100, actualAmount: 80, expenseDate: d1, workspace: ws, card: cardA, category: cat))
        context.insert(PlannedExpense(title: "P2", plannedAmount: 50, actualAmount: 50, expenseDate: d2, workspace: ws, card: cardB, category: cat))
        context.insert(PlannedExpense(title: "POut", plannedAmount: 999, actualAmount: 999, expenseDate: dOut, workspace: ws, card: cardA, category: cat))

        // Variable expenses (1 in-window, 1 out-of-window)
        context.insert(VariableExpense(descriptionText: "V1", amount: 25, transactionDate: d1, workspace: ws, card: cardA, category: cat))
        context.insert(VariableExpense(descriptionText: "VOut", amount: 888, transactionDate: dOut, workspace: ws, card: cardB, category: cat))

        // Incomes (planned + actual in-window, plus one out-of-window)
        context.insert(Income(source: "Planned Income", amount: 1000, date: d1, isPlanned: true, workspace: ws, series: nil, card: cardA))
        context.insert(Income(source: "Actual Income", amount: 900, date: d2, isPlanned: false, workspace: ws, series: nil, card: cardB))
        context.insert(Income(source: "Out", amount: 777, date: dOut, isPlanned: true, workspace: ws, series: nil, card: cardA))

        try context.save()

        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31))!

        let t = try totals(for: ws, start: start, end: end, card: nil, in: context)

        #expect(t.plannedExpensePlannedTotal == 150) // 100 + 50
        #expect(t.plannedExpenseActualTotal == 130)  // 80 + 50
        #expect(t.variableExpenseTotal == 25)
        #expect(t.plannedIncomeTotal == 1000)
        #expect(t.actualIncomeTotal == 900)

        #expect(t.potentialSavings == 850) // 1000 - 150
        #expect(t.actualSavings == 745)    // 900 - (130 + 25)
    }

    @Test func aggregation_cardFiltered_onlyIncludesThatCard() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let cardA = Card(name: "Card A", workspace: ws)
        let cardB = Card(name: "Card B", workspace: ws)
        let cat = Category(name: "Cat", hexColor: "#111111", workspace: ws)

        context.insert(ws)
        context.insert(cardA)
        context.insert(cardB)
        context.insert(cat)

        let d = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        context.insert(PlannedExpense(title: "A", plannedAmount: 100, actualAmount: 90, expenseDate: d, workspace: ws, card: cardA, category: cat))
        context.insert(PlannedExpense(title: "B", plannedAmount: 50, actualAmount: 50, expenseDate: d, workspace: ws, card: cardB, category: cat))

        context.insert(VariableExpense(descriptionText: "A", amount: 10, transactionDate: d, workspace: ws, card: cardA, category: cat))
        context.insert(VariableExpense(descriptionText: "B", amount: 20, transactionDate: d, workspace: ws, card: cardB, category: cat))

        context.insert(Income(source: "A Planned", amount: 500, date: d, isPlanned: true, workspace: ws, series: nil, card: cardA))
        context.insert(Income(source: "B Actual", amount: 400, date: d, isPlanned: false, workspace: ws, series: nil, card: cardB))

        try context.save()

        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 31))!

        let tA = try totals(for: ws, start: start, end: end, card: cardA, in: context)
        #expect(tA.plannedExpensePlannedTotal == 100)
        #expect(tA.plannedExpenseActualTotal == 90)
        #expect(tA.variableExpenseTotal == 10)
        #expect(tA.plannedIncomeTotal == 500)
        #expect(tA.actualIncomeTotal == 0)

        let tB = try totals(for: ws, start: start, end: end, card: cardB, in: context)
        #expect(tB.plannedExpensePlannedTotal == 50)
        #expect(tB.plannedExpenseActualTotal == 50)
        #expect(tB.variableExpenseTotal == 20)
        #expect(tB.plannedIncomeTotal == 0)
        #expect(tB.actualIncomeTotal == 400)
    }
}
