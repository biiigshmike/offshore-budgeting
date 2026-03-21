//
//  OffshoreBudgetingTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 1/20/26.
//

import Foundation
import SwiftData
import Testing
@testable import Offshore

struct OffshoreBudgetingTests {

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

    @Test func import_PositiveUnsignedAmountDefaultsToExpense() {
        let categories = [
            Category(name: "Transportation-Fuel", hexColor: "#000000")
        ]

        let parsed = ParsedCSV(
            headers: ["Date", "Description", "Amount", "Category"],
            rows: [
                ["11/10/2025", "ARCO#82639", "45.44", "Transportation-Fuel"]
            ]
        )

        let rows = ExpenseCSVImportMapper.map(
            csv: parsed,
            categories: categories,
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(rows.count == 1)
        #expect(rows[0].kind == .expense)
        #expect(rows[0].bucket == .ready)
        #expect(rows[0].selectedCategory?.name == "Transportation-Fuel")
    }

    @Test func import_PaymentHeuristicMarksCreditWhenUnsigned() {
        let parsed = ParsedCSV(
            headers: ["Date", "Description", "Amount", "Category"],
            rows: [
                ["11/10/2025", "Payment - Thank You", "45.44", ""]
            ]
        )

        let rows = ExpenseCSVImportMapper.map(
            csv: parsed,
            categories: [],
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(rows.count == 1)
        #expect(rows[0].kind == .credit)
        #expect(rows[0].bucket == .payment)
    }

    @Test func import_DirectDepositStaysIncomeWhenUnsigned() {
        let parsed = ParsedCSV(
            headers: ["Date", "Description", "Amount", "Category"],
            rows: [
                ["11/10/2025", "Direct Deposit Payroll", "2817.83", ""]
            ]
        )

        let rows = ExpenseCSVImportMapper.map(
            csv: parsed,
            categories: [],
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(rows.count == 1)
        #expect(rows[0].kind == .income)
        #expect(rows[0].bucket == .payment)
    }

    @Test func import_UsesDebitCreditColumnsForSignWhenPresent() {
        let parsed = ParsedCSV(
            headers: ["Date", "Description", "Debit", "Credit"],
            rows: [
                ["11/10/2025", "ARCO#82639", "45.44", ""]
            ]
        )

        let rows = ExpenseCSVImportMapper.map(
            csv: parsed,
            categories: [],
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(rows.count == 1)
        #expect(rows[0].kind == .expense)
        #expect(rows[0].finalAmount == 45.44)
    }

    @Test func import_PutsInPossibleDuplicatesWhenMatchesPlannedExpense() {
        let cal = Calendar(identifier: .gregorian)
        let date = cal.date(from: DateComponents(year: 2025, month: 11, day: 10))!

        let category = Category(name: "Transportation-Fuel", hexColor: "#000000")
        let planned = PlannedExpense(
            title: "Transportation-Fuel",
            plannedAmount: 45.44,
            expenseDate: date,
            card: nil,
            category: category
        )

        let parsed = ParsedCSV(
            headers: ["Date", "Description", "Amount", "Category"],
            rows: [
                ["11/10/2025", "ARCO#82639", "45.44", "Transportation-Fuel"]
            ]
        )

        let rows = ExpenseCSVImportMapper.map(
            csv: parsed,
            categories: [category],
            existingExpenses: [],
            existingPlannedExpenses: [planned],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(rows.count == 1)
        #expect(rows[0].bucket == ExpenseCSVImportBucket.possibleDuplicate)
        #expect(rows[0].includeInImport == false)
    }

    @Test func import_PutsInPossibleDuplicatesWhenNearDateMatchesPlannedExpenseEvenIfCSVCategoryDoesNotMap() {
        let cal = Calendar(identifier: .gregorian)
        let plannedDate = cal.date(from: DateComponents(year: 2025, month: 11, day: 10))!
        let csvDate = cal.date(from: DateComponents(year: 2025, month: 11, day: 11))!

        let bills = Category(name: "Bills & Utilities", hexColor: "#000000")
        let planned = PlannedExpense(
            title: "Phone Bill",
            plannedAmount: 120.00,
            expenseDate: plannedDate,
            card: nil,
            category: bills
        )

        let parsed = ParsedCSV(
            headers: ["Date", "Description", "Amount", "Category"],
            rows: [
                ["11/11/2025", "T-MOBILE", "120.00", "Phone"]
            ]
        )

        let rows = ExpenseCSVImportMapper.map(
            csv: parsed,
            categories: [bills],
            existingExpenses: [],
            existingPlannedExpenses: [planned],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(rows.count == 1)
        #expect(cal.startOfDay(for: rows[0].finalDate) == cal.startOfDay(for: csvDate))
        #expect(rows[0].bucket == ExpenseCSVImportBucket.possibleDuplicate)
        #expect(rows[0].includeInImport == false)
    }

    @Test func import_PutsInPossibleDuplicatesWhenNearDateMatchesExistingExpenseEvenIfMerchantDiffers() {
        let cal = Calendar(identifier: .gregorian)
        let existingDate = cal.date(from: DateComponents(year: 2025, month: 11, day: 10))!

        let bills = Category(name: "Bills & Utilities", hexColor: "#000000")
        let existing = VariableExpense(
            descriptionText: "Phone Bill",
            amount: 120.00,
            transactionDate: existingDate,
            workspace: nil,
            card: nil,
            category: bills
        )

        let parsed = ParsedCSV(
            headers: ["Date", "Description", "Amount", "Category"],
            rows: [
                ["11/11/2025", "T-MOBILE", "120.00", "Phone"]
            ]
        )

        let rows = ExpenseCSVImportMapper.map(
            csv: parsed,
            categories: [bills],
            existingExpenses: [existing],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(rows.count == 1)
        #expect(rows[0].bucket == ExpenseCSVImportBucket.possibleDuplicate)
        #expect(rows[0].includeInImport == false)
    }

    @Test func import_ChaseFormatDoesNotGetTreatedAsAppleCard() {
        let parsed = ParsedCSV(
            headers: ["Transaction Date", "Post Date", "Description", "Category", "Type", "Amount", "Memo"],
            rows: [
                ["11/26/2025", "11/27/2025", "AMAZON MKTPL*B296F3UD2", "Shopping", "Sale", "-41.31", ""]
            ]
        )

        let rows = ExpenseCSVImportMapper.map(
            csv: parsed,
            categories: [],
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )

        #expect(rows.count == 1)
        #expect(rows[0].finalAmount == 41.31)
        #expect(rows[0].kind == .expense)
    }

    @Test func importMode_IncomeOnlyBlocksExpenseRows() {
        let parsed = ParsedCSV(
            headers: ["Date", "Description", "Amount", "Category", "Type"],
            rows: [
                ["02/10/2026", "Safeway", "50.00", "Groceries", "expense"],
                ["02/10/2026", "Direct Deposit", "2817.83", "", "income"]
            ]
        )

        let mapped = ExpenseCSVImportMapper.map(
            csv: parsed,
            categories: [],
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )
        let adjusted = ExpenseCSVImportViewModel.applyImportModeRules(
            mapped,
            mode: .incomeOnly
        )

        #expect(adjusted.count == 2)

        let expenseRow = adjusted.first { $0.kind == .expense }
        let incomeRow = adjusted.first { $0.kind == .income }

        #expect(expenseRow?.isBlocked == true)
        #expect(expenseRow?.includeInImport == false)
        #expect(expenseRow?.blockedReason?.contains("skipped") == true)

        #expect(incomeRow?.isBlocked == false)
        #expect(incomeRow?.includeInImport == true)
    }

    @Test func importMode_CardTransactionsDoesNotBlockExpenseRows() {
        let parsed = ParsedCSV(
            headers: ["Date", "Description", "Amount", "Category", "Type"],
            rows: [
                ["02/10/2026", "Safeway", "50.00", "Groceries", "expense"]
            ]
        )

        let category = Category(name: "Groceries", hexColor: "#000000")
        let mapped = ExpenseCSVImportMapper.map(
            csv: parsed,
            categories: [category],
            existingExpenses: [],
            existingPlannedExpenses: [],
            existingIncomes: [],
            learnedRules: [:]
        )
        let adjusted = ExpenseCSVImportViewModel.applyImportModeRules(
            mapped,
            mode: .cardTransactions
        )

        #expect(adjusted.count == 1)
        #expect(adjusted[0].kind == .expense)
        #expect(adjusted[0].isBlocked == false)
        #expect(adjusted[0].blockedReason == nil)
    }

    @MainActor
    @Test func importRow_ReconciliationActionSwitchingClearsInactiveState() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: workspace)
        let category = Category(name: "Groceries", hexColor: "#00AA00", workspace: workspace)
        let splitAccount = AllocationAccount(name: "Split Account", workspace: workspace)
        let offsetAccount = AllocationAccount(name: "Offset Account", workspace: workspace)

        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(splitAccount)
        context.insert(offsetAccount)
        try context.save()

        let vm = ExpenseCSVImportViewModel(mode: .cardTransactions)
        vm.prepare(workspace: workspace, modelContext: context)
        vm.loadClipboard(
            text: "Date,Description,Amount,Category\n02/10/2026,Safeway,50.00,Groceries",
            workspace: workspace,
            card: card,
            modelContext: context
        )

        let rowID = try #require(vm.rows.first?.id)

        vm.setReconciliationAction(rowID: rowID, action: .split)
        vm.setSplitAccount(rowID: rowID, account: splitAccount)
        vm.setSplitAmount(rowID: rowID, amountText: "20")

        vm.setReconciliationAction(rowID: rowID, action: .offset)

        let offsetRow = try #require(vm.rows.first)
        #expect(offsetRow.reconciliationAction == .offset)
        #expect(offsetRow.selectedSplitAccount == nil)
        #expect(offsetRow.splitAmountText.isEmpty)
        #expect(offsetRow.selectedOffsetAccount?.id == splitAccount.id)

        vm.setOffsetAccount(rowID: rowID, account: offsetAccount)
        vm.setOffsetAmount(rowID: rowID, amountText: "15")
        vm.setReconciliationAction(rowID: rowID, action: .none)

        let clearedRow = try #require(vm.rows.first)
        #expect(clearedRow.reconciliationAction == .none)
        #expect(clearedRow.selectedSplitAccount == nil)
        #expect(clearedRow.splitAmountText.isEmpty)
        #expect(clearedRow.selectedOffsetAccount == nil)
        #expect(clearedRow.offsetAmountText.isEmpty)
    }

    @MainActor
    @Test func importCommit_SplitCreatesAllocation() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: workspace)
        let category = Category(name: "Groceries", hexColor: "#00AA00", workspace: workspace)
        let account = AllocationAccount(name: "Partner", workspace: workspace)

        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(account)
        try context.save()

        let vm = ExpenseCSVImportViewModel(mode: .cardTransactions)
        vm.prepare(workspace: workspace, modelContext: context)
        vm.loadClipboard(
            text: "Date,Description,Amount,Category\n02/10/2026,Safeway,50.00,Groceries",
            workspace: workspace,
            card: card,
            modelContext: context
        )

        let rowID = try #require(vm.rows.first?.id)
        vm.setReconciliationAction(rowID: rowID, action: .split)
        vm.setSplitAccount(rowID: rowID, account: account)
        vm.setSplitAmount(rowID: rowID, amountText: "20")

        vm.commitImport(workspace: workspace, card: card, modelContext: context)

        let expense = try #require(try context.fetch(FetchDescriptor<VariableExpense>()).first)
        let allocation = try #require(try context.fetch(FetchDescriptor<ExpenseAllocation>()).first)

        #expect(expense.amount == 50)
        #expect(expense.allocation?.id == allocation.id)
        #expect(allocation.allocatedAmount == 20)
        #expect(allocation.account?.id == account.id)
    }

    @MainActor
    @Test func importCommit_OffsetCreatesSettlementAndReducesExpenseAmount() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: workspace)
        let category = Category(name: "Groceries", hexColor: "#00AA00", workspace: workspace)
        let account = AllocationAccount(name: "Partner", workspace: workspace)
        let seedSettlement = AllocationSettlement(
            date: Date(),
            note: "Seed",
            amount: 30,
            workspace: workspace,
            account: account
        )

        context.insert(workspace)
        context.insert(card)
        context.insert(category)
        context.insert(account)
        context.insert(seedSettlement)
        try context.save()

        let vm = ExpenseCSVImportViewModel(mode: .cardTransactions)
        vm.prepare(workspace: workspace, modelContext: context)
        vm.loadClipboard(
            text: "Date,Description,Amount,Category\n02/10/2026,Safeway,50.00,Groceries",
            workspace: workspace,
            card: card,
            modelContext: context
        )

        let rowID = try #require(vm.rows.first?.id)
        vm.setReconciliationAction(rowID: rowID, action: .offset)
        vm.setOffsetAccount(rowID: rowID, account: account)
        vm.setOffsetAmount(rowID: rowID, amountText: "20")

        vm.commitImport(workspace: workspace, card: card, modelContext: context)

        let expense = try #require(try context.fetch(FetchDescriptor<VariableExpense>()).first)
        let settlements = try context.fetch(FetchDescriptor<AllocationSettlement>())
        let offsetSettlement = try #require(settlements.first { $0.expense?.id == expense.id })

        #expect(expense.amount == 30)
        #expect(expense.offsetSettlement?.id == offsetSettlement.id)
        #expect(offsetSettlement.amount == -20)
        #expect(offsetSettlement.account?.id == account.id)
    }

    @MainActor
    @Test func importCommit_CreditCreatesCreditLedgerEntryInsteadOfIncome() throws {
        let context = try makeContext()
        let workspace = Workspace(name: "WS", hexColor: "#3B82F6")
        let card = Card(name: "Visa", workspace: workspace)

        context.insert(workspace)
        context.insert(card)
        try context.save()

        let vm = ExpenseCSVImportViewModel(mode: .cardTransactions)
        vm.prepare(workspace: workspace, modelContext: context)
        vm.loadClipboard(
            text: "Date,Description,Amount,Category\n02/10/2026,Payment - Thank You,50.00,",
            workspace: workspace,
            card: card,
            modelContext: context
        )

        let row = try #require(vm.rows.first)
        #expect(row.kind == .credit)

        vm.commitImport(workspace: workspace, card: card, modelContext: context)

        let expenses = try context.fetch(FetchDescriptor<VariableExpense>())
        let incomes = try context.fetch(FetchDescriptor<Income>())

        let savedExpense = try #require(expenses.first)
        #expect(savedExpense.kind == .credit)
        #expect(savedExpense.amount == 50)
        #expect(savedExpense.card?.id == card.id)
        #expect(incomes.isEmpty)
    }
}
