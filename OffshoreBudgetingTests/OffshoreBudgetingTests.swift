//
//  OffshoreBudgetingTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 1/20/26.
//

import Foundation
import Testing
@testable import Offshore

struct OffshoreBudgetingTests {

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

    @Test func import_PaymentHeuristicMarksIncomeWhenUnsigned() {
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
}
