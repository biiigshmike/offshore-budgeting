//
//  OffshoreBudgetingTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 1/20/26.
//

import Foundation
import Testing
@testable import OffshoreBudgeting

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
}
