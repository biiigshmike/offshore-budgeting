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

    private func makeMonthlySavingsFixture(
        in context: ModelContext
    ) throws -> (
        workspace: Workspace,
        card: Card,
        category: Offshore.Category,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) {
        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Offshore.Category(name: "General", hexColor: "#22AA66", workspace: ws)
        context.insert(ws)
        context.insert(card)
        context.insert(cat)

        let incomes = [
            Income(
                source: "Pay",
                amount: 2500,
                date: makeDate(2026, 1, 5),
                isPlanned: false,
                workspace: ws,
                card: card
            ),
            Income(
                source: "Pay",
                amount: 2600,
                date: makeDate(2026, 2, 5),
                isPlanned: false,
                workspace: ws,
                card: card
            )
        ]
        let plannedExpenses = [
            PlannedExpense(
                title: "Rent",
                plannedAmount: 1000,
                actualAmount: 1000,
                expenseDate: makeDate(2026, 1, 10),
                workspace: ws,
                card: card,
                category: cat
            ),
            PlannedExpense(
                title: "Rent",
                plannedAmount: 1000,
                actualAmount: 1000,
                expenseDate: makeDate(2026, 2, 10),
                workspace: ws,
                card: card,
                category: cat
            )
        ]
        let variableExpenses = [
            VariableExpense(
                descriptionText: "Groceries",
                amount: 500,
                transactionDate: makeDate(2026, 1, 15),
                workspace: ws,
                card: card,
                category: cat
            ),
            VariableExpense(
                descriptionText: "Groceries",
                amount: 400,
                transactionDate: makeDate(2026, 2, 15),
                workspace: ws,
                card: card,
                category: cat
            )
        ]

        incomes.forEach(context.insert)
        plannedExpenses.forEach(context.insert)
        variableExpenses.forEach(context.insert)
        try context.save()

        return (ws, card, cat, incomes, plannedExpenses, variableExpenses)
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
        let account = try #require(accounts.first)
        #expect(account.total == 5600)
    }

    @Test func autoCapture_refreshesExistingClosedMonthWhenBackdatedActivityChanges() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "General", hexColor: "#22AA66", workspace: ws)
        context.insert(ws)
        context.insert(card)
        context.insert(cat)

        let januaryIncome = Income(
            source: "Pay",
            amount: 2500,
            date: makeDate(2026, 1, 5),
            isPlanned: false,
            workspace: ws,
            card: card
        )
        let januaryPlanned = PlannedExpense(
            title: "Rent",
            plannedAmount: 1000,
            actualAmount: 1000,
            expenseDate: makeDate(2026, 1, 10),
            workspace: ws,
            card: card,
            category: cat
        )
        let januaryVariable = VariableExpense(
            descriptionText: "Groceries",
            amount: 500,
            transactionDate: makeDate(2026, 1, 15),
            workspace: ws,
            card: card,
            category: cat
        )

        let februaryIncome = Income(
            source: "Pay",
            amount: 2600,
            date: makeDate(2026, 2, 5),
            isPlanned: false,
            workspace: ws,
            card: card
        )
        let februaryPlanned = PlannedExpense(
            title: "Rent",
            plannedAmount: 1000,
            actualAmount: 1000,
            expenseDate: makeDate(2026, 2, 10),
            workspace: ws,
            card: card,
            category: cat
        )
        let februaryVariable = VariableExpense(
            descriptionText: "Groceries",
            amount: 400,
            transactionDate: makeDate(2026, 2, 15),
            workspace: ws,
            card: card,
            category: cat
        )

        let incomes = [januaryIncome, februaryIncome]
        let plannedExpenses = [januaryPlanned, februaryPlanned]
        let variableExpenses = [januaryVariable, februaryVariable]

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
            now: makeDate(2026, 3, 15)
        )

        var entries = try fetchAll(
            SavingsLedgerEntry.self,
            in: context,
            sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .forward)]
        )
        var periodCloseEntries = entries.filter { $0.kind == .periodClose }
        #expect(periodCloseEntries.count == 2)
        #expect(periodCloseEntries.map(\.amount) == [1000, 1200])

        let februaryEntryID = try #require(periodCloseEntries.last?.id)

        let backdatedFebruaryExpense = VariableExpense(
            descriptionText: "Utilities",
            amount: 200,
            transactionDate: makeDate(2026, 2, 20),
            workspace: ws,
            card: card,
            category: cat
        )
        context.insert(backdatedFebruaryExpense)
        try context.save()

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: ws,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses + [backdatedFebruaryExpense],
            modelContext: context,
            now: makeDate(2026, 3, 21)
        )

        entries = try fetchAll(
            SavingsLedgerEntry.self,
            in: context,
            sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .forward)]
        )
        periodCloseEntries = entries.filter { $0.kind == .periodClose }

        #expect(periodCloseEntries.count == 2)
        #expect(periodCloseEntries.map(\.amount) == [1000, 1000])
        #expect(periodCloseEntries.last?.id == februaryEntryID)

        let account = try #require(fetchAll(SavingsAccount.self, in: context).first)
        #expect(account.total == 2000)
    }

    @Test func runningTotalSnapshot_startsAtFirstClosedPeriodStartDate() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let account = SavingsAccount(name: "Savings", total: 3886.55, workspace: ws)
        let periodClose = SavingsLedgerEntry(
            date: makeDate(2026, 2, 28),
            amount: 3886.55,
            note: "Period close Feb 1, 2026 - Feb 28, 2026",
            kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
            periodStartDate: makeDate(2026, 2, 1),
            periodEndDate: makeDate(2026, 2, 28),
            workspace: ws,
            account: account
        )

        context.insert(ws)
        context.insert(account)
        context.insert(periodClose)
        try context.save()

        let snapshot = SavingsGraphSnapshotService.buildSnapshot(
            for: ws,
            rangeStart: makeDate(2026, 3, 1),
            rangeEnd: makeDate(2026, 3, 31),
            modelContext: context
        )
        let calendar = Calendar.current

        #expect(snapshot.runningTotal == 3886.55)
        #expect(snapshot.runningTotalPoints.count == 2)
        #expect(snapshot.runningTotalPoints.first?.date == calendar.startOfDay(for: makeDate(2026, 2, 1)))
        #expect(snapshot.runningTotalPoints.first?.total == 0)
        #expect(snapshot.runningTotalPoints.last?.date == calendar.startOfDay(for: makeDate(2026, 2, 28)))
        #expect(snapshot.runningTotalPoints.last?.total == 3886.55)
    }

    @Test func deletingPeriodCloseEntry_recreatesMissingClosedPeriodWhenActivityStillExists() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "General", hexColor: "#22AA66", workspace: ws)
        context.insert(ws)
        context.insert(card)
        context.insert(cat)

        let incomes = [
            Income(source: "Pay", amount: 2500, date: makeDate(2026, 1, 5), isPlanned: false, workspace: ws, card: card)
        ]
        let plannedExpenses = [
            PlannedExpense(title: "Rent", plannedAmount: 1000, actualAmount: 1000, expenseDate: makeDate(2026, 1, 10), workspace: ws, card: card, category: cat)
        ]
        let variableExpenses = [
            VariableExpense(descriptionText: "Groceries", amount: 500, transactionDate: makeDate(2026, 1, 15), workspace: ws, card: card, category: cat)
        ]

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
            now: makeDate(2026, 2, 15)
        )

        var entries = try fetchAll(
            SavingsLedgerEntry.self,
            in: context,
            sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .forward)]
        )
        let originalPeriodCloseEntries = entries.filter { $0.kind == .periodClose }
        #expect(originalPeriodCloseEntries.count == 1)

        if let originalPeriodCloseEntry = originalPeriodCloseEntries.first {
            SavingsAccountService.deleteEntry(originalPeriodCloseEntry, modelContext: context)
        }

        entries = try fetchAll(
            SavingsLedgerEntry.self,
            in: context,
            sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .forward)]
        )
        let periodCloseEntriesAfterDelete = entries.filter { $0.kind == .periodClose }
        #expect(periodCloseEntriesAfterDelete.isEmpty)

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: ws,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: incomes,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            modelContext: context,
            now: makeDate(2026, 2, 15)
        )

        entries = try fetchAll(
            SavingsLedgerEntry.self,
            in: context,
            sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .forward)]
        )
        let periodCloseEntriesAfterRecapture = entries.filter { $0.kind == .periodClose }

        #expect(periodCloseEntriesAfterRecapture.count == 1)
        #expect(periodCloseEntriesAfterRecapture.first?.amount == 1000)

        let febIncome = Income(
            source: "Pay",
            amount: 2600,
            date: makeDate(2026, 2, 5),
            isPlanned: false,
            workspace: ws,
            card: card
        )
        let febPlanned = PlannedExpense(
            title: "Rent",
            plannedAmount: 1000,
            actualAmount: 1000,
            expenseDate: makeDate(2026, 2, 10),
            workspace: ws,
            card: card,
            category: cat
        )
        let febVariable = VariableExpense(
            descriptionText: "Groceries",
            amount: 400,
            transactionDate: makeDate(2026, 2, 15),
            workspace: ws,
            card: card,
            category: cat
        )
        context.insert(febIncome)
        context.insert(febPlanned)
        context.insert(febVariable)
        try context.save()

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: ws,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: incomes + [febIncome],
            plannedExpenses: plannedExpenses + [febPlanned],
            variableExpenses: variableExpenses + [febVariable],
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        entries = try fetchAll(
            SavingsLedgerEntry.self,
            in: context,
            sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .forward)]
        )
        let periodCloseEntriesAfterMarchRun = entries.filter { $0.kind == .periodClose }
        #expect(periodCloseEntriesAfterMarchRun.count == 2)
        #expect(periodCloseEntriesAfterMarchRun.map(\.amount) == [1000, 1200])
    }

    @Test func autoCapture_repairsDuplicatePeriodCloseEntries_keepingOldest() throws {
        let context = try makeContext()
        let calendar = Calendar.current
        let janStart = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1)) ?? .distantPast
        let janEnd = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31)) ?? .distantPast
        let createdOldest = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1)) ?? .distantPast
        let createdDuplicate = calendar.date(from: DateComponents(year: 2026, month: 2, day: 2)) ?? .distantPast
        let captureNow = calendar.date(from: DateComponents(year: 2026, month: 2, day: 15)) ?? .distantPast

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        context.insert(ws)

        let account = SavingsAccountService.ensureSavingsAccount(for: ws, modelContext: context)
        account.didBackfillHistory = true
        account.autoCaptureThroughDate = janEnd

        let oldest = SavingsLedgerEntry(
            date: janEnd,
            amount: 500,
            note: "Period close Jan",
            kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
            periodStartDate: janStart,
            periodEndDate: janEnd,
            createdAt: createdOldest,
            updatedAt: createdOldest,
            workspace: ws,
            account: account
        )
        let duplicate = SavingsLedgerEntry(
            date: janEnd,
            amount: 500,
            note: "Period close Jan duplicate",
            kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
            periodStartDate: janStart,
            periodEndDate: janEnd,
            createdAt: createdDuplicate,
            updatedAt: createdDuplicate,
            workspace: ws,
            account: account
        )
        context.insert(oldest)
        context.insert(duplicate)
        try context.save()

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: ws,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: [],
            plannedExpenses: [],
            variableExpenses: [],
            modelContext: context,
            now: captureNow
        )

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.workspace?.id == ws.id && $0.kind == .periodClose }
        #expect(entries.count == 1)
        #expect(entries.first?.id == oldest.id)
    }

    @Test func autoCapture_repairsExactDuplicateManualAdjustments_keepingOldest() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        context.insert(ws)

        let account = SavingsAccountService.ensureSavingsAccount(for: ws, modelContext: context)
        account.didBackfillHistory = true
        account.autoCaptureThroughDate = makeDate(2026, 1, 31)

        let oldest = SavingsLedgerEntry(
            date: makeDate(2026, 1, 20),
            amount: 125,
            note: "Emergency Fund",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            createdAt: makeDate(2026, 1, 20),
            updatedAt: makeDate(2026, 1, 20),
            workspace: ws,
            account: account
        )
        let duplicate = SavingsLedgerEntry(
            date: makeDate(2026, 1, 20),
            amount: 125.00,
            note: "Emergency   Fund",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            createdAt: makeDate(2026, 1, 21),
            updatedAt: makeDate(2026, 1, 21),
            workspace: ws,
            account: account
        )
        context.insert(oldest)
        context.insert(duplicate)
        try context.save()

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: ws,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: [],
            plannedExpenses: [],
            variableExpenses: [],
            modelContext: context,
            now: makeDate(2026, 2, 15)
        )

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.workspace?.id == ws.id && $0.kind == .manualAdjustment }
        #expect(entries.count == 1)
        #expect(entries.first?.id == oldest.id)
    }

    @Test func autoCapture_keepsDistinctManualAdjustments_whenNotesDiffer() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        context.insert(ws)

        let account = SavingsAccountService.ensureSavingsAccount(for: ws, modelContext: context)
        account.didBackfillHistory = true
        account.autoCaptureThroughDate = makeDate(2026, 1, 31)

        context.insert(
            SavingsLedgerEntry(
                date: makeDate(2026, 1, 20),
                amount: 125,
                note: "Emergency Fund",
                kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
                createdAt: makeDate(2026, 1, 20),
                updatedAt: makeDate(2026, 1, 20),
                workspace: ws,
                account: account
            )
        )
        context.insert(
            SavingsLedgerEntry(
                date: makeDate(2026, 1, 20),
                amount: 125,
                note: "Vacation",
                kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
                createdAt: makeDate(2026, 1, 21),
                updatedAt: makeDate(2026, 1, 21),
                workspace: ws,
                account: account
            )
        )
        try context.save()

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: ws,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: [],
            plannedExpenses: [],
            variableExpenses: [],
            modelContext: context,
            now: makeDate(2026, 2, 15)
        )

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.kind == .manualAdjustment }
        #expect(entries.count == 2)
    }

    // MARK: - Integrity

    @Test func normalization_mergesDuplicateSavingsAccounts_andReassignsWorkspaceEntries() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        context.insert(ws)

        let primary = SavingsAccount(
            name: "Primary",
            total: 999,
            didBackfillHistory: false,
            autoCaptureThroughDate: makeDate(2025, 12, 31),
            createdAt: makeDate(2025, 9, 1),
            workspace: ws
        )
        let duplicate = SavingsAccount(
            name: "Duplicate",
            total: 111,
            didBackfillHistory: true,
            autoCaptureThroughDate: makeDate(2026, 1, 31),
            createdAt: makeDate(2025, 10, 1),
            workspace: ws
        )
        context.insert(primary)
        context.insert(duplicate)

        let primaryEntry = SavingsLedgerEntry(
            date: makeDate(2026, 1, 5),
            amount: 100,
            note: "Primary",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: ws,
            account: primary
        )
        let duplicateEntry = SavingsLedgerEntry(
            date: makeDate(2026, 1, 10),
            amount: -25,
            note: "Duplicate",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: ws,
            account: duplicate
        )
        let orphanEntry = SavingsLedgerEntry(
            date: makeDate(2026, 1, 12),
            amount: 50,
            note: "Orphan",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: ws
        )
        context.insert(primaryEntry)
        context.insert(duplicateEntry)
        context.insert(orphanEntry)
        try context.save()

        let report = SavingsAccountService.normalizeSavingsData(for: ws, modelContext: context)

        let accounts = try fetchAll(
            SavingsAccount.self,
            in: context,
            sortBy: [SortDescriptor(\SavingsAccount.createdAt, order: .forward)]
        )
        #expect(accounts.count == 1)
        let account = try #require(accounts.first)
        #expect(account.id == primary.id)
        #expect(account.didBackfillHistory)
        #expect(account.autoCaptureThroughDate == makeDate(2026, 1, 31))
        #expect(account.total == 125)

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.account?.id == primary.id })

        #expect(report.mergedAccountsCount == 1)
        #expect(report.reassignedEntriesCount == 2)
        #expect(report.dedupedPeriodCloseCount == 0)
        #expect(report.dedupedManualAdjustmentCount == 0)
        #expect(report.removedReconciliationSettlementCount == 0)
        #expect(report.recalculatedTotal == 125)
    }

    @Test func normalizeSavingsData_removesMirroredStandaloneReconciliationSettlements() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let savingsAccount = SavingsAccount(workspace: ws)
        context.insert(ws)
        context.insert(savingsAccount)

        let mirroredIn = SavingsLedgerEntry(
            date: makeDate(2026, 2, 10),
            amount: 40,
            note: "They paid me back",
            kindRaw: SavingsLedgerEntryKind.reconciliationSettlement.rawValue,
            linkedAllocationSettlementID: UUID(),
            workspace: ws,
            account: savingsAccount
        )
        let mirroredOut = SavingsLedgerEntry(
            date: makeDate(2026, 2, 11),
            amount: -15,
            note: "I paid them back",
            kindRaw: SavingsLedgerEntryKind.reconciliationSettlement.rawValue,
            linkedAllocationSettlementID: UUID(),
            workspace: ws,
            account: savingsAccount
        )
        context.insert(mirroredIn)
        context.insert(mirroredOut)
        try context.save()

        let report = SavingsAccountService.normalizeSavingsData(for: ws, modelContext: context)

        let savingsAccounts = try fetchAll(SavingsAccount.self, in: context)
        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.kind == .reconciliationSettlement }

        #expect(savingsAccounts.count == 1)
        let normalizedAccount = try #require(savingsAccounts.first)
        #expect(normalizedAccount.total == 0)
        #expect(entries.isEmpty)
        #expect(report.removedReconciliationSettlementCount == 2)
        #expect(report.recalculatedTotal == 0)
    }

    @Test func ensureSavingsAccount_keepsExistingDuplicateAccountsUntilRepairRuns() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        context.insert(ws)

        let first = SavingsAccount(
            name: "First",
            createdAt: makeDate(2025, 9, 1),
            workspace: ws
        )
        let second = SavingsAccount(
            name: "Second",
            createdAt: makeDate(2025, 9, 2),
            workspace: ws
        )
        context.insert(first)
        context.insert(second)

        let duplicateEntry = SavingsLedgerEntry(
            date: makeDate(2026, 1, 8),
            amount: 75,
            note: "Dup",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: ws,
            account: second
        )
        context.insert(duplicateEntry)
        try context.save()

        let ensured = SavingsAccountService.ensureSavingsAccount(for: ws, modelContext: context)

        let accounts = try fetchAll(SavingsAccount.self, in: context)
        #expect(accounts.count == 2)
        #expect(ensured.id == first.id)

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.account?.id == second.id)
    }

    @Test func rebuildRunningTotal_recomputesFromLedgerEntries() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        context.insert(ws)

        let account = SavingsAccountService.ensureSavingsAccount(for: ws, modelContext: context)
        let entries = [
            SavingsLedgerEntry(
                date: makeDate(2026, 1, 1),
                amount: 500,
                note: "A",
                kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
                workspace: ws,
                account: account
            ),
            SavingsLedgerEntry(
                date: makeDate(2026, 1, 2),
                amount: -120,
                note: "B",
                kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
                workspace: ws,
                account: account
            ),
            SavingsLedgerEntry(
                date: makeDate(2026, 1, 3),
                amount: 20,
                note: "C",
                kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
                workspace: ws,
                account: account
            )
        ]
        entries.forEach(context.insert)
        account.total = 9999
        try context.save()

        let rebuilt = SavingsAccountService.rebuildRunningTotal(for: ws, modelContext: context)
        #expect(rebuilt == 400)

        let accounts = try fetchAll(SavingsAccount.self, in: context)
        #expect(accounts.count == 1)
        let rebuiltAccount = try #require(accounts.first)
        #expect(rebuiltAccount.total == 400)
    }

    // MARK: - Manual Sync

    @Test func manualSyncStatus_reportsUnavailableWhenSavingsAccountIsCurrent() throws {
        let context = try makeContext()
        let fixture = try makeMonthlySavingsFixture(in: context)

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        let status = SavingsAccountService.manualSyncStatus(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        #expect(status.isUpToDate)
        #expect(status.canSync == false)
        #expect(status.reason == SavingsAccountService.ManualSavingsSyncReason.upToDate)
        #expect(status.expectedChangeCount == 0)
    }

    @Test func manualSync_doesNotCreateLedgerRowWhenNothingChanged() throws {
        let context = try makeContext()
        let fixture = try makeMonthlySavingsFixture(in: context)

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        let rowsBefore = try fetchAll(SavingsLedgerEntry.self, in: context).count

        let result = SavingsAccountService.runManualSyncIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        let rowsAfter = try fetchAll(SavingsLedgerEntry.self, in: context).count
        #expect(result.didApplyChanges == false)
        #expect(result.meaningfulChangeCount == 0)
        #expect(rowsAfter == rowsBefore)
    }

    @Test func manualSync_createsAtMostOneMeaningfulRepairPass_forMissingClosedPeriod() throws {
        let context = try makeContext()
        let fixture = try makeMonthlySavingsFixture(in: context)

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 2, 15)
        )

        let firstResult = SavingsAccountService.runManualSyncIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        let periodCloseEntries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.workspace?.id == fixture.workspace.id && $0.kind == .periodClose }
            .sorted { $0.date < $1.date }

        #expect(firstResult.didApplyChanges)
        #expect(firstResult.insertedPeriodCloseCount == 1)
        #expect(firstResult.refreshedPeriodCloseCount == 0)
        #expect(periodCloseEntries.count == 2)
        #expect(periodCloseEntries.map { $0.amount } == [1000, 1200])

        let secondResult = SavingsAccountService.runManualSyncIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        let rowsAfterSecondRun = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.workspace?.id == fixture.workspace.id }
        #expect(secondResult.didApplyChanges == false)
        #expect(secondResult.meaningfulChangeCount == 0)
        #expect(rowsAfterSecondRun.count == 2)
    }

    @Test func manualSyncStatus_reportsStaleAfterBackdatedClosedPeriodActivity_untilSyncRepairsIt() throws {
        let context = try makeContext()
        let fixture = try makeMonthlySavingsFixture(in: context)

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        let backdatedExpense = VariableExpense(
            descriptionText: "Utilities",
            amount: 200,
            transactionDate: makeDate(2026, 2, 20),
            workspace: fixture.workspace,
            card: fixture.card,
            category: fixture.category
        )
        context.insert(backdatedExpense)
        try context.save()

        let staleStatus = SavingsAccountService.manualSyncStatus(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses + [backdatedExpense],
            modelContext: context,
            now: makeDate(2026, 3, 21)
        )

        #expect(staleStatus.isUpToDate == false)
        #expect(staleStatus.canSync)
        #expect(
            staleStatus.reason == SavingsAccountService.ManualSavingsSyncReason.closedPeriodsNeedRefresh
        )

        let result = SavingsAccountService.runManualSyncIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses + [backdatedExpense],
            modelContext: context,
            now: makeDate(2026, 3, 21)
        )

        let periodCloseEntries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.workspace?.id == fixture.workspace.id && $0.kind == .periodClose }
            .sorted { $0.date < $1.date }

        #expect(result.didApplyChanges)
        #expect(result.insertedPeriodCloseCount == 0)
        #expect(result.refreshedPeriodCloseCount == 1)
        #expect(periodCloseEntries.map { $0.amount } == [1000, 1000])

        let refreshedStatus = SavingsAccountService.manualSyncStatus(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses + [backdatedExpense],
            modelContext: context,
            now: makeDate(2026, 3, 21)
        )
        #expect(refreshedStatus.isUpToDate)
    }

    @Test func manualSyncStatus_detectsBrokenRunningTotalAndRepairsItWithoutExtraRows() throws {
        let context = try makeContext()
        let fixture = try makeMonthlySavingsFixture(in: context)

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        let account = try #require(fetchAll(SavingsAccount.self, in: context).first)
        let rowsBefore = try fetchAll(SavingsLedgerEntry.self, in: context).count
        account.total = 9999
        try context.save()

        let staleStatus = SavingsAccountService.manualSyncStatus(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        #expect(staleStatus.isUpToDate == false)
        #expect(staleStatus.canSync)
        #expect(
            staleStatus.reason == SavingsAccountService.ManualSavingsSyncReason.runningTotalNeedsRebuild
        )
        #expect(staleStatus.wouldChangeRunningTotal)

        let result = SavingsAccountService.runManualSyncIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        let rowsAfter = try fetchAll(SavingsLedgerEntry.self, in: context).count
        let repairedAccount = try #require(fetchAll(SavingsAccount.self, in: context).first)
        #expect(result.didApplyChanges)
        #expect(result.rebuiltRunningTotal)
        #expect(rowsAfter == rowsBefore)
        #expect(repairedAccount.total == 2200)
    }

    @Test func manualSyncStatus_detectsDuplicateSavingsDataAsStale() throws {
        let context = try makeContext()
        let fixture = try makeMonthlySavingsFixture(in: context)

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 2, 15)
        )

        let account = try #require(fetchAll(SavingsAccount.self, in: context).first)
        let allEntries = try fetchAll(SavingsLedgerEntry.self, in: context)
        let existingPeriodCloseEntries = allEntries.filter {
            $0.workspace?.id == fixture.workspace.id && $0.kind == .periodClose
        }
        let oldest = try #require(existingPeriodCloseEntries.first)

        let duplicate = SavingsLedgerEntry(
            date: oldest.date,
            amount: oldest.amount,
            note: "Period close Jan duplicate",
            kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
            periodStartDate: oldest.periodStartDate,
            periodEndDate: oldest.periodEndDate,
            createdAt: makeDate(2026, 2, 2),
            updatedAt: makeDate(2026, 2, 2),
            workspace: fixture.workspace,
            account: account
        )
        context.insert(duplicate)
        try context.save()

        let staleStatus = SavingsAccountService.manualSyncStatus(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        #expect(staleStatus.isUpToDate == false)
        #expect(staleStatus.canSync)
        #expect(
            staleStatus.reason == SavingsAccountService.ManualSavingsSyncReason.closedPeriodsNeedRefresh
                || staleStatus.reason == SavingsAccountService.ManualSavingsSyncReason.savingsDataNeedsRepair
        )

        let result = SavingsAccountService.runManualSyncIfNeeded(
            for: fixture.workspace,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: fixture.incomes,
            plannedExpenses: fixture.plannedExpenses,
            variableExpenses: fixture.variableExpenses,
            modelContext: context,
            now: makeDate(2026, 3, 15)
        )

        let repairedPeriodCloseEntries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.workspace?.id == fixture.workspace.id && $0.kind == .periodClose }
        #expect(result.didApplyChanges)
        #expect(result.repairedSavingsDataCount >= 1 || result.refreshedPeriodCloseCount >= 1)
        #expect(repairedPeriodCloseEntries.count == 2)
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

    @Test func savingsOffsets_canExceedAvailableBalance_whenWithinOwnedAmount() throws {
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
            amount: 40,
            note: "Seed",
            modelContext: context
        )

        let variable = VariableExpense(
            descriptionText: "AirPods",
            amount: 120,
            transactionDate: makeDate(2026, 6, 2),
            workspace: ws,
            card: card,
            category: cat
        )
        let planned = PlannedExpense(
            title: "Desk",
            plannedAmount: 140,
            actualAmount: 140,
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
            offsetAmount: 90,
            note: "Overdraw variable",
            date: variable.transactionDate,
            modelContext: context
        )
        let plannedApplied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            plannedExpense: planned,
            offsetAmount: 60,
            note: "Overdraw planned",
            date: planned.expenseDate,
            modelContext: context
        )

        #expect(variableApplied)
        #expect(plannedApplied)
        #expect(CurrencyFormatter.roundedToCurrency(variable.savingsLedgerEntry?.amount ?? 0) == -90)
        #expect(CurrencyFormatter.roundedToCurrency(planned.savingsLedgerEntry?.amount ?? 0) == -60)

        SavingsAccountService.recalculateAccountTotal(account)
        #expect(CurrencyFormatter.roundedToCurrency(account.total) == -110)
    }

    @Test func splitAllocations_reduceSavingsImpact_toOwnedShare() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "General", hexColor: "#22AA66", workspace: ws)
        let allocationAccount = AllocationAccount(name: "Shared", workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(allocationAccount)

        let variable = VariableExpense(
            descriptionText: "Dinner",
            amount: 300,
            transactionDate: makeDate(2026, 6, 4),
            workspace: ws,
            card: card,
            category: cat
        )
        let variableAllocation = ExpenseAllocation(
            allocatedAmount: 150,
            preservesGrossAmount: true,
            workspace: ws,
            account: allocationAccount,
            expense: variable
        )
        variable.allocation = variableAllocation

        let planned = PlannedExpense(
            title: "Hotel",
            plannedAmount: 300,
            actualAmount: 280,
            expenseDate: makeDate(2026, 6, 5),
            workspace: ws,
            card: card,
            category: cat
        )
        let plannedAllocation = ExpenseAllocation(
            allocatedAmount: 150,
            preservesGrossAmount: true,
            workspace: ws,
            account: allocationAccount,
            plannedExpense: planned
        )
        planned.allocation = plannedAllocation

        context.insert(variable)
        context.insert(variableAllocation)
        context.insert(planned)
        context.insert(plannedAllocation)
        try context.save()

        #expect(SavingsMathService.ownedAmount(for: variable) == 150)
        #expect(SavingsMathService.variableBudgetImpactAmount(for: variable) == 150)
        #expect(SavingsMathService.ownedPlannedAmount(for: planned) == 150)
        #expect(SavingsMathService.plannedProjectedBudgetImpactAmount(for: planned) == 150)
        #expect(SavingsMathService.ownedEffectiveAmount(for: planned) == 130)
        #expect(SavingsMathService.plannedBudgetImpactAmount(for: planned) == 130)
    }

    @Test func splitAllocations_andOffsets_clampSavingsImpactAtOwnedShare() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "General", hexColor: "#22AA66", workspace: ws)
        let allocationAccount = AllocationAccount(name: "Shared", workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(allocationAccount)

        let savingsAccount = SavingsAccountService.ensureSavingsAccount(for: ws, modelContext: context)
        SavingsAccountService.addManualAdjustment(
            workspace: ws,
            account: savingsAccount,
            date: makeDate(2026, 6, 1),
            amount: 500,
            note: "Seed",
            modelContext: context
        )

        let variable = VariableExpense(
            descriptionText: "Tickets",
            amount: 300,
            transactionDate: makeDate(2026, 6, 4),
            workspace: ws,
            card: card,
            category: cat
        )
        let variableAllocation = ExpenseAllocation(
            allocatedAmount: 150,
            preservesGrossAmount: true,
            workspace: ws,
            account: allocationAccount,
            expense: variable
        )
        variable.allocation = variableAllocation

        let planned = PlannedExpense(
            title: "Cabin",
            plannedAmount: 300,
            actualAmount: 280,
            expenseDate: makeDate(2026, 6, 5),
            workspace: ws,
            card: card,
            category: cat
        )
        let plannedAllocation = ExpenseAllocation(
            allocatedAmount: 150,
            preservesGrossAmount: true,
            workspace: ws,
            account: allocationAccount,
            plannedExpense: planned
        )
        planned.allocation = plannedAllocation

        context.insert(variable)
        context.insert(variableAllocation)
        context.insert(planned)
        context.insert(plannedAllocation)
        try context.save()

        let variableRejected = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            variableExpense: variable,
            offsetAmount: 151,
            note: "Too high",
            date: variable.transactionDate,
            modelContext: context
        )
        let plannedRejected = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            plannedExpense: planned,
            offsetAmount: 131,
            note: "Too high",
            date: planned.expenseDate,
            modelContext: context
        )

        let variableApplied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            variableExpense: variable,
            offsetAmount: 140,
            note: "Partial offset",
            date: variable.transactionDate,
            modelContext: context
        )
        let plannedApplied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            plannedExpense: planned,
            offsetAmount: 130,
            note: "Full offset",
            date: planned.expenseDate,
            modelContext: context
        )

        #expect(!variableRejected)
        #expect(!plannedRejected)
        #expect(variableApplied)
        #expect(plannedApplied)
        #expect(SavingsMathService.variableBudgetImpactAmount(for: variable) == 10)
        #expect(SavingsMathService.plannedBudgetImpactAmount(for: planned) == 0)
    }

    @Test func autoCapture_usesOwnedShare_forSplitExpenses() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "General", hexColor: "#22AA66", workspace: ws)
        let allocationAccount = AllocationAccount(name: "Shared", workspace: ws)

        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(allocationAccount)

        let income = Income(
            source: "Pay",
            amount: 1000,
            date: makeDate(2026, 1, 5),
            isPlanned: false,
            workspace: ws,
            card: card
        )
        let variable = VariableExpense(
            descriptionText: "Shared dinner",
            amount: 300,
            transactionDate: makeDate(2026, 1, 10),
            workspace: ws,
            card: card,
            category: cat
        )
        let allocation = ExpenseAllocation(
            allocatedAmount: 150,
            preservesGrossAmount: true,
            workspace: ws,
            account: allocationAccount,
            expense: variable
        )
        variable.allocation = allocation

        context.insert(income)
        context.insert(variable)
        context.insert(allocation)
        try context.save()

        SavingsAccountService.runAutoCaptureIfNeeded(
            for: ws,
            defaultBudgetingPeriodRaw: BudgetingPeriod.monthly.rawValue,
            incomes: [income],
            plannedExpenses: [],
            variableExpenses: [variable],
            modelContext: context,
            now: makeDate(2026, 2, 15)
        )

        let entries = try fetchAll(
            SavingsLedgerEntry.self,
            in: context,
            sortBy: [SortDescriptor(\SavingsLedgerEntry.date, order: .forward)]
        )
        let periodCloseEntries = entries.filter { $0.kind == .periodClose }

        #expect(periodCloseEntries.count == 1)
        #expect(periodCloseEntries.first?.amount == 850)
    }

    @Test func standaloneReconciliationSettlement_doesNotMirrorToSavings() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let reconciliation = AllocationAccount(name: "Partner", workspace: ws)
        context.insert(ws)
        context.insert(reconciliation)

        let settlement = AllocationSettlement(
            date: makeDate(2026, 6, 4),
            note: "Initial",
            amount: -30,
            workspace: ws,
            account: reconciliation
        )
        context.insert(settlement)

        SavingsAccountService.upsertStandaloneReconciliationSettlement(
            workspace: ws,
            settlement: settlement,
            modelContext: context
        )

        var savingsEntries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.kind == .reconciliationSettlement }
        #expect(savingsEntries.isEmpty)

        settlement.amount = 55
        settlement.note = "Updated"
        settlement.date = makeDate(2026, 6, 6)

        SavingsAccountService.upsertStandaloneReconciliationSettlement(
            workspace: ws,
            settlement: settlement,
            modelContext: context
        )

        savingsEntries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.kind == .reconciliationSettlement }
        #expect(savingsEntries.isEmpty)
        #expect(try fetchAll(SavingsAccount.self, in: context).isEmpty)
    }

    @Test func removingStandaloneReconciliationSettlement_cleansUpAnyExistingMirroredSavingsEntry() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let reconciliation = AllocationAccount(name: "Partner", workspace: ws)
        let savingsAccount = SavingsAccount(workspace: ws)
        context.insert(ws)
        context.insert(reconciliation)
        context.insert(savingsAccount)

        let settlement = AllocationSettlement(
            date: makeDate(2026, 6, 4),
            note: "Paid back",
            amount: 70,
            workspace: ws,
            account: reconciliation
        )
        context.insert(settlement)

        context.insert(
            SavingsLedgerEntry(
                date: makeDate(2026, 6, 4),
                amount: 70,
                note: "Paid back",
                kindRaw: SavingsLedgerEntryKind.reconciliationSettlement.rawValue,
                linkedAllocationSettlementID: settlement.id,
                workspace: ws,
                account: savingsAccount
            )
        )
        SavingsAccountService.removeStandaloneReconciliationSettlement(
            for: settlement,
            workspace: ws,
            modelContext: context
        )

        let savingsEntries = try fetchAll(SavingsLedgerEntry.self, in: context)
            .filter { $0.kind == .reconciliationSettlement }
        let fetchedSavingsAccount = try #require(fetchAll(SavingsAccount.self, in: context).first)

        #expect(savingsEntries.isEmpty)
        #expect(fetchedSavingsAccount.total == 0)
    }

    @Test func actualSavingsAdjustments_includeManualEntries_only() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let account = SavingsAccount(workspace: ws)
        context.insert(ws)
        context.insert(account)

        let includedManual = SavingsLedgerEntry(
            date: makeDate(2026, 6, 2),
            amount: 40,
            note: "Manual in",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            workspace: ws,
            account: account
        )
        let includedSettlement = SavingsLedgerEntry(
            date: makeDate(2026, 6, 3),
            amount: -25,
            note: "I owe them",
            kindRaw: SavingsLedgerEntryKind.reconciliationSettlement.rawValue,
            workspace: ws,
            account: account
        )
        let excludedPeriodClose = SavingsLedgerEntry(
            date: makeDate(2026, 6, 4),
            amount: 200,
            note: "Period close",
            kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
            workspace: ws,
            account: account
        )
        let excludedOffset = SavingsLedgerEntry(
            date: makeDate(2026, 6, 5),
            amount: -10,
            note: "Offset",
            kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
            workspace: ws,
            account: account
        )

        context.insert(includedManual)
        context.insert(includedSettlement)
        context.insert(excludedPeriodClose)
        context.insert(excludedOffset)
        try context.save()

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
        let total = SavingsMathService.actualSavingsAdjustmentTotal(
            from: entries,
            startDate: makeDate(2026, 6, 1),
            endDate: makeDate(2026, 6, 30)
        )

        #expect(total == 40)
    }

    @Test func normalizeSavingsData_leavesLegacySplitAllocations_unchanged() throws {
        let context = try makeContext()

        let ws = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: ws)
        let cat = Category(name: "General", hexColor: "#22AA66", workspace: ws)
        let account = AllocationAccount(name: "Partner", workspace: ws)
        context.insert(ws)
        context.insert(card)
        context.insert(cat)
        context.insert(account)

        let variable = VariableExpense(
            descriptionText: "Dinner",
            amount: 150,
            transactionDate: makeDate(2026, 7, 1),
            workspace: ws,
            card: card,
            category: cat
        )
        let variableAllocation = ExpenseAllocation(
            allocatedAmount: 150,
            workspace: ws,
            account: account,
            expense: variable
        )
        variable.allocation = variableAllocation

        let planned = PlannedExpense(
            title: "Trip",
            plannedAmount: 500,
            actualAmount: 350,
            expenseDate: makeDate(2026, 7, 2),
            workspace: ws,
            card: card,
            category: cat
        )
        let plannedAllocation = ExpenseAllocation(
            allocatedAmount: 150,
            workspace: ws,
            account: account,
            plannedExpense: planned
        )
        planned.allocation = plannedAllocation

        context.insert(variable)
        context.insert(variableAllocation)
        context.insert(planned)
        context.insert(plannedAllocation)
        try context.save()

        let report = SavingsAccountService.normalizeSavingsData(for: ws, modelContext: context)

        #expect(variable.amount == 150)
        #expect(planned.actualAmount == 350)
        #expect(variableAllocation.preservesGrossAmount == false)
        #expect(plannedAllocation.preservesGrossAmount == false)
        #expect(report.removedReconciliationSettlementCount == 0)
    }

    // MARK: - Currency Boundary

    @Test func currencyBoundary_allowsExactOffset_whenAvailableHasFloatingResidue() throws {
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
            amount: 0.3,
            note: "Seed",
            modelContext: context
        )
        SavingsAccountService.addManualAdjustment(
            workspace: ws,
            account: account,
            date: makeDate(2026, 6, 2),
            amount: -0.2,
            note: "Seed",
            modelContext: context
        )

        let variable = VariableExpense(
            descriptionText: "Coffee",
            amount: 0.1,
            transactionDate: makeDate(2026, 6, 4),
            workspace: ws,
            card: card,
            category: cat
        )
        context.insert(variable)
        try context.save()

        let applied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            variableExpense: variable,
            offsetAmount: 0.1,
            note: "Boundary",
            date: variable.transactionDate,
            modelContext: context
        )

        #expect(applied)
        #expect(variable.savingsLedgerEntry != nil)
        #expect(CurrencyFormatter.roundedToCurrency(variable.savingsLedgerEntry?.amount ?? 0) == -0.1)
    }

    @Test func currencyBoundary_allowsOffset_whenRequestedExceedsAvailableByOneCent() throws {
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
            amount: 0.3,
            note: "Seed",
            modelContext: context
        )
        SavingsAccountService.addManualAdjustment(
            workspace: ws,
            account: account,
            date: makeDate(2026, 6, 2),
            amount: -0.2,
            note: "Seed",
            modelContext: context
        )

        let variable = VariableExpense(
            descriptionText: "Coffee",
            amount: 1.0,
            transactionDate: makeDate(2026, 6, 4),
            workspace: ws,
            card: card,
            category: cat
        )
        context.insert(variable)
        try context.save()

        let applied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            variableExpense: variable,
            offsetAmount: 0.11,
            note: "Boundary",
            date: variable.transactionDate,
            modelContext: context
        )

        #expect(applied)
        #expect(CurrencyFormatter.roundedToCurrency(variable.savingsLedgerEntry?.amount ?? 0) == -0.11)
    }

    // MARK: - Negative Balances

    @Test func negativeSavings_allowsOffsetRequests_forVariableAndPlanned() throws {
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
            note: "Allowed while negative",
            date: variable.transactionDate,
            modelContext: context
        )
        let plannedApplied = SavingsAccountService.upsertSavingsOffset(
            workspace: ws,
            plannedExpense: planned,
            offsetAmount: 30,
            note: "Allowed while negative",
            date: planned.expenseDate,
            modelContext: context
        )

        #expect(variableApplied)
        #expect(plannedApplied)
        #expect(CurrencyFormatter.roundedToCurrency(variable.savingsLedgerEntry?.amount ?? 0) == -30)
        #expect(CurrencyFormatter.roundedToCurrency(planned.savingsLedgerEntry?.amount ?? 0) == -30)

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
        #expect(entries.count == 3)
        #expect(entries.filter { $0.kind == .manualAdjustment }.count == 1)
        #expect(entries.filter { $0.kind == .expenseOffset }.count == 2)
        #expect(account.total == -160)
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

    @Test func savingsLedgerSortMode_titleSort_usesVisibleRowTitle() {
        let blankNote = SavingsLedgerEntry(
            date: makeDate(2026, 8, 3),
            amount: 10,
            note: "",
            kindRaw: SavingsLedgerEntryKind.periodClose.rawValue,
            createdAt: makeDate(2026, 8, 3)
        )
        let alpha = SavingsLedgerEntry(
            date: makeDate(2026, 8, 2),
            amount: 20,
            note: "Alpha",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            createdAt: makeDate(2026, 8, 2)
        )
        let zulu = SavingsLedgerEntry(
            date: makeDate(2026, 8, 1),
            amount: 30,
            note: "Zulu",
            kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue,
            createdAt: makeDate(2026, 8, 1)
        )

        let entries = [blankNote, zulu, alpha]

        #expect(SavingsLedgerSortMode.az.sorted(entries: entries).map(\.ledgerDisplayTitle) == ["Alpha", "Period Close", "Zulu"])
        #expect(SavingsLedgerSortMode.za.sorted(entries: entries).map(\.ledgerDisplayTitle) == ["Zulu", "Period Close", "Alpha"])
    }

    @Test func savingsLedgerSortMode_amountSort_ordersByAmount() {
        let small = SavingsLedgerEntry(
            date: makeDate(2026, 8, 1),
            amount: 5,
            note: "Small",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            createdAt: makeDate(2026, 8, 1)
        )
        let medium = SavingsLedgerEntry(
            date: makeDate(2026, 8, 2),
            amount: 25,
            note: "Medium",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            createdAt: makeDate(2026, 8, 2)
        )
        let large = SavingsLedgerEntry(
            date: makeDate(2026, 8, 3),
            amount: 100,
            note: "Large",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            createdAt: makeDate(2026, 8, 3)
        )

        let entries = [medium, large, small]

        #expect(SavingsLedgerSortMode.amountAsc.sorted(entries: entries).map(\.amount) == [5, 25, 100])
        #expect(SavingsLedgerSortMode.amountDesc.sorted(entries: entries).map(\.amount) == [100, 25, 5])
    }

    @Test func savingsLedgerSortMode_dateSort_isStableForSameDayEntries() {
        let olderCreatedAt = SavingsLedgerEntry(
            date: makeDate(2026, 8, 4),
            amount: 10,
            note: "Older",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            createdAt: makeDate(2026, 8, 4)
        )
        let newerCreatedAt = SavingsLedgerEntry(
            date: makeDate(2026, 8, 4),
            amount: 20,
            note: "Newer",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            createdAt: makeDate(2026, 8, 5)
        )
        let earlierDate = SavingsLedgerEntry(
            date: makeDate(2026, 8, 1),
            amount: 30,
            note: "Earlier Date",
            kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue,
            createdAt: makeDate(2026, 8, 1)
        )

        let entries = [olderCreatedAt, earlierDate, newerCreatedAt]

        #expect(SavingsLedgerSortMode.dateAsc.sorted(entries: entries).map(\.note) == ["Earlier Date", "Older", "Newer"])
        #expect(SavingsLedgerSortMode.dateDesc.sorted(entries: entries).map(\.note) == ["Newer", "Older", "Earlier Date"])
    }
}
