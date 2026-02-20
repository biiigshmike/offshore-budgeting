//
//  SavingsAccountServiceTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/17/26.
//

import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct SavingsAccountServiceTests {

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
            Income.self,
            SavingsAccount.self,
            SavingsLedgerEntry.self
        ])

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: config)
        return ModelContext(container)
    }

    private func fetchAll<T: PersistentModel>(
        _ type: T.Type,
        in context: ModelContext,
        sortBy: [SortDescriptor<T>] = []
    ) throws -> [T] {
        try context.fetch(FetchDescriptor<T>(sortBy: sortBy))
    }

    private func makeDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return cal.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
    }

    // MARK: - Overlap

    @Test func budgetRangeOverlap_picksLargestOverlap_thenNewestStartDateOnTie() {
        let targetRange = DateRange(start: makeDate(2026, 1, 10), end: makeDate(2026, 1, 20))

        let smallest = Budget(
            name: "Small",
            startDate: makeDate(2026, 1, 1),
            endDate: makeDate(2026, 1, 12)
        )
        let largest = Budget(
            name: "Largest",
            startDate: makeDate(2026, 1, 8),
            endDate: makeDate(2026, 1, 30)
        )
        let tieOlder = Budget(
            name: "Tie Older",
            startDate: makeDate(2026, 1, 1),
            endDate: makeDate(2026, 1, 25)
        )
        let tieNewer = Budget(
            name: "Tie Newer",
            startDate: makeDate(2026, 1, 2),
            endDate: makeDate(2026, 1, 25)
        )

        let winningLargest = BudgetRangeOverlap.pickActiveBudget(
            from: [smallest, largest],
            for: targetRange
        )
        #expect(winningLargest?.name == "Largest")

        let winningTie = BudgetRangeOverlap.pickActiveBudget(
            from: [tieOlder, tieNewer],
            for: targetRange
        )
        #expect(winningTie?.name == "Tie Newer")
    }

    // MARK: - Auto Capture

    @Test func autoCapture_monthly_createsPeriodCloseEntries_andRunningTotalIsCorrect() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "General", hexColor: "#22AA66", workspace: ws)

        let janBudget = Budget(name: "January", startDate: makeDate(2026, 1, 1), endDate: makeDate(2026, 1, 31), workspace: ws)
        let overlapBudget = Budget(name: "Overlap", startDate: makeDate(2026, 1, 20), endDate: makeDate(2026, 2, 19), workspace: ws)
        context.insert(janBudget)
        context.insert(overlapBudget)

        let incomes = [
            Income(source: "Pay", amount: 3000, date: makeDate(2026, 1, 5), isPlanned: false, workspace: ws, card: card),
            Income(source: "Pay", amount: 3000, date: makeDate(2026, 2, 5), isPlanned: false, workspace: ws, card: card),
            Income(source: "Pay", amount: 3000, date: makeDate(2026, 3, 5), isPlanned: false, workspace: ws, card: card),
            Income(source: "Pay", amount: 3000, date: makeDate(2026, 4, 5), isPlanned: false, workspace: ws, card: card)
        ]

        let plannedExpenses = [
            PlannedExpense(title: "Rent", plannedAmount: 1000, actualAmount: 1100, expenseDate: makeDate(2026, 1, 10), workspace: ws, card: card, category: cat),
            PlannedExpense(title: "Rent", plannedAmount: 1000, actualAmount: 900, expenseDate: makeDate(2026, 2, 10), workspace: ws, card: card, category: cat),
            PlannedExpense(title: "Rent", plannedAmount: 1000, actualAmount: 1000, expenseDate: makeDate(2026, 3, 10), workspace: ws, card: card, category: cat),
            PlannedExpense(title: "Rent", plannedAmount: 1000, actualAmount: 1200, expenseDate: makeDate(2026, 4, 10), workspace: ws, card: card, category: cat)
        ]

        let variableExpenses = [
            VariableExpense(descriptionText: "Groceries", amount: 500, transactionDate: makeDate(2026, 1, 15), workspace: ws, card: card, category: cat),
            VariableExpense(descriptionText: "Groceries", amount: 700, transactionDate: makeDate(2026, 2, 15), workspace: ws, card: card, category: cat),
            VariableExpense(descriptionText: "Groceries", amount: 400, transactionDate: makeDate(2026, 3, 15), workspace: ws, card: card, category: cat),
            VariableExpense(descriptionText: "Groceries", amount: 600, transactionDate: makeDate(2026, 4, 15), workspace: ws, card: card, category: cat)
        ]

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        incomes.forEach(context.insert)
        plannedExpenses.forEach(context.insert)
        variableExpenses.forEach(context.insert)
        try context.save()

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: ws,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            modelContext: context,
            now: makeDate(2026, 5, 15)
        )

        let entries = try fetchAll(
            SavingsLedgerEntry.self,
            in: context,
            sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .forward)]
        )
        let periodCloseEntries = entries.filter { $0.kind == .periodClose }

        #expect(periodCloseEntries.count == 4)
        #expect(periodCloseEntries.map(\.amount) == [1400, 1400, 1600, 1200])

        let accounts = try fetchAll(SavingsAccount.self, in: context)
        #expect(accounts.count == 1)
        #expect(accounts[0].total == 5600)
    }

    // MARK: - Positive Offset

    @Test func positiveSavings_allowsVariableAndPlannedOffsets_andBudgetImpactUsesNet() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "General", hexColor: "#22AA66", workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(cat)

        let account = SavingsAccountService.ensureSavingsAccount(for: ws, modelContext: context)
        SavingsAccountService.addManualAdjustment(
            workspace: ws,
            account: account,
            date: makeDate(2026, 6, 1),
            amount: 500,
            note: "Start",
            modelContext: context
        )

        let variable = VariableExpense(
            descriptionText: "AirPods",
            amount: 200,
            transactionDate: makeDate(2026, 6, 2),
            workspace: ws,
            card: card,
            category: cat
        )
        let planned = PlannedExpense(
            title: "Desk",
            plannedAmount: 300,
            actualAmount: 250,
            expenseDate: makeDate(2026, 6, 3),
            workspace: ws,
            card: card,
            category: cat
        )

        context.insert(variable)
        context.insert(planned)
        try context.save()

        let variableApplied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            variableExpense: variable,
            offsetAmount: 120,
            note: "Use savings for AirPods",
            date: variable.transactionDate,
            modelContext: context
        )
        let plannedApplied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            plannedExpense: planned,
            offsetAmount: 80,
            note: "Use savings for Desk",
            date: planned.expenseDate,
            modelContext: context
        )

        #expect(variableApplied)
        #expect(plannedApplied)

        let expenseOffsetEntries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.kind == .expenseOffset }
        #expect(expenseOffsetEntries.count == 2)
        #expect(expenseOffsetEntries.map(\.amount).sorted() == [-120, -80])

        #expect(SavingsMathService.variableBudgetImpactAmount(for: variable) == 80)
        #expect(SavingsMathService.plannedBudgetImpactAmount(for: planned) == 170)

        SavingsAccountService.recalculateAccountTotal(account)
        #expect(account.total == 300)
    }

    // MARK: - Negative Guard

    @Test func negativeSavings_rejectsOffsetRequests_forVariableAndPlanned() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "General", hexColor: "#22AA66", workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(cat)

        let account = SavingsAccountService.ensureSavingsAccount(for: ws, modelContext: context)
        SavingsAccountService.addManualAdjustment(
            workspace: ws,
            account: account,
            date: makeDate(2026, 6, 1),
            amount: -100,
            note: "Negative start",
            modelContext: context
        )

        let variable = VariableExpense(
            descriptionText: "Shoes",
            amount: 70,
            transactionDate: makeDate(2026, 6, 4),
            workspace: ws,
            card: card,
            category: cat
        )
        let planned = PlannedExpense(
            title: "Chair",
            plannedAmount: 100,
            actualAmount: 60,
            expenseDate: makeDate(2026, 6, 4),
            workspace: ws,
            card: card,
            category: cat
        )

        context.insert(variable)
        context.insert(planned)
        try context.save()

        let variableApplied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            variableExpense: variable,
            offsetAmount: 30,
            note: "Should fail",
            date: variable.transactionDate,
            modelContext: context
        )
        let plannedApplied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            plannedExpense: planned,
            offsetAmount: 30,
            note: "Should fail",
            date: planned.expenseDate,
            modelContext: context
        )

        #expect(!variableApplied)
        #expect(!plannedApplied)
        #expect(variable.savingsLedgerEntry == nil)
        #expect(planned.savingsLedgerEntry == nil)

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
        #expect(entries.count == 1)
        #expect(entries.first?.kind == .manualAdjustment)
        #expect(account.total == -100)
    }

    // MARK: - Edit/Delete

    @Test func manualEditAndDelete_updatesTotals_andClearsExpenseLinkage() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "General", hexColor: "#22AA66", workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(cat)

        let account = SavingsAccountService.ensureSavingsAccount(for: ws, modelContext: context)
        SavingsAccountService.addManualAdjustment(
            workspace: ws,
            account: account,
            date: makeDate(2026, 6, 1),
            amount: 100,
            note: "Start",
            modelContext: context
        )

        let variable = VariableExpense(
            descriptionText: "Keyboard",
            amount: 60,
            transactionDate: makeDate(2026, 6, 5),
            workspace: ws,
            card: card,
            category: cat
        )
        let planned = PlannedExpense(
            title: "Lamp",
            plannedAmount: 50,
            actualAmount: 50,
            expenseDate: makeDate(2026, 6, 5),
            workspace: ws,
            card: card,
            category: cat
        )

        context.insert(variable)
        context.insert(planned)
        try context.save()

        let variableApplied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            variableExpense: variable,
            offsetAmount: 30,
            note: "Keyboard offset",
            date: variable.transactionDate,
            modelContext: context
        )
        let plannedApplied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            plannedExpense: planned,
            offsetAmount: 20,
            note: "Lamp offset",
            date: planned.expenseDate,
            modelContext: context
        )

        #expect(variableApplied)
        #expect(plannedApplied)
        #expect(account.total == 50)

        if let edited = variable.savingsLedgerEntry {
            edited.amount = -10
            edited.note = "Edited"
            edited.kind = .manualAdjustment
            edited.date = makeDate(2026, 6, 6)
            edited.updatedAt = .now
            SavingsAccountService.recalculateAccountTotal(account)
            try context.save()
        }

        #expect(account.total == 70)

        if let variableEntry = variable.savingsLedgerEntry {
            SavingsAccountService.deleteEntry(variableEntry, modelContext: context)
        }
        #expect(variable.savingsLedgerEntry == nil)

        let remainingOffsetEntries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.kind == .expenseOffset }
        for entry in remainingOffsetEntries {
            SavingsAccountService.deleteEntry(entry, modelContext: context)
        }
        #expect(planned.savingsLedgerEntry == nil)

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
        #expect(entries.count == 1)
        #expect(entries.first?.kind == .manualAdjustment)
        #expect(account.total == 100)
    }

    @Test func deletingLastSavingsEntry_setsRunningTotalToZero() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        context.insert(ws)

        let account = SavingsAccountService.ensureSavingsAccount(for: ws, modelContext: context)
        SavingsAccountService.addManualAdjustment(
            workspace: ws,
            account: account,
            date: makeDate(2026, 7, 1),
            amount: 250,
            note: "Initial contribution",
            modelContext: context
        )
        #expect(account.total == 250)

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
        #expect(entries.count == 1)

        if let onlyEntry = entries.first {
            SavingsAccountService.deleteEntry(onlyEntry, modelContext: context)
        }

        let remainingEntries = try fetchAll(SavingsLedgerEntry.self, in: context)
        #expect(remainingEntries.isEmpty)
        #expect(account.total == 0)
    }
}
