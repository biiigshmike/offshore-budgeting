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

    @Test func deletingPeriodCloseEntry_staysDeleted_andFuturePeriodsStillAutoCapture() throws {
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

        #expect(periodCloseEntriesAfterRecapture.isEmpty)

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
        #expect(periodCloseEntriesAfterMarchRun.count == 1)
        #expect(periodCloseEntriesAfterMarchRun.first?.amount == 1200)
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
        #expect(accounts[0].id == primary.id)
        #expect(accounts[0].didBackfillHistory)
        #expect(accounts[0].autoCaptureThroughDate == makeDate(2026, 1, 31))
        #expect(accounts[0].total == 125)

        let entries = try fetchAll(SavingsLedgerEntry.self, in: context)
        #expect(entries.count == 3)
        #expect(entries.allSatisfy { $0.account?.id == primary.id })

        #expect(report.mergedAccountsCount == 1)
        #expect(report.reassignedEntriesCount == 2)
        #expect(report.dedupedPeriodCloseCount == 0)
        #expect(report.dedupedManualAdjustmentCount == 0)
        #expect(report.recalculatedTotal == 125)
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
        #expect(entries[0].account?.id == second.id)
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
        #expect(accounts[0].total == 400)
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

    @Test func currencyBoundary_rejectsOffset_whenRequestedExceedsAvailableByOneCent() throws {
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

        #expect(!applied)
        #expect(variable.savingsLedgerEntry == nil)
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
