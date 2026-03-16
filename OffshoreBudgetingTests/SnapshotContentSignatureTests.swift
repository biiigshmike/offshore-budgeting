//
//  SnapshotContentSignatureTests.swift
//  OffshoreBudgetingTests
//
//  Created by OpenAI Codex on 3/16/26.
//

import Foundation
import Testing
@testable import Offshore

struct SnapshotContentSignatureTests {

    @Test func variableExpenseSignatureChangesWhenAmountChangesWithoutDateChange() {
        let expense = VariableExpense(
            descriptionText: "Groceries",
            amount: 40,
            transactionDate: Date(timeIntervalSinceReferenceDate: 1_000)
        )

        let before = SnapshotContentSignature.variableExpenses([expense])
        expense.amount = 55
        let after = SnapshotContentSignature.variableExpenses([expense])

        #expect(before != after)
    }

    @Test func plannedExpenseSignatureChangesWhenCategoryChangesWithoutDateChange() {
        let originalCategory = Category(name: "Bills", hexColor: "#111111")
        let replacementCategory = Category(name: "Utilities", hexColor: "#222222")
        let expense = PlannedExpense(
            title: "Power",
            plannedAmount: 90,
            actualAmount: 0,
            expenseDate: Date(timeIntervalSinceReferenceDate: 2_000),
            category: originalCategory
        )

        let before = SnapshotContentSignature.plannedExpenses([expense])
        expense.category = replacementCategory
        let after = SnapshotContentSignature.plannedExpenses([expense])

        #expect(before != after)
    }

    @Test func incomeSignatureChangesWhenAmountChangesWithoutDateChange() {
        let income = Income(
            source: "Payroll",
            amount: 2_500,
            date: Date(timeIntervalSinceReferenceDate: 3_000),
            isPlanned: false
        )

        let before = SnapshotContentSignature.incomes([income])
        income.amount = 2_800
        let after = SnapshotContentSignature.incomes([income])

        #expect(before != after)
    }

    @Test func categorySignatureChangesWhenNameChanges() {
        let category = Category(name: "Fuel", hexColor: "#333333")

        let before = SnapshotContentSignature.categories([category])
        category.name = "Gas"
        let after = SnapshotContentSignature.categories([category])

        #expect(before != after)
    }

    @Test func variableExpenseSignatureIsStableAcrossCollectionOrder() {
        let first = VariableExpense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            descriptionText: "Coffee",
            amount: 6,
            transactionDate: Date(timeIntervalSinceReferenceDate: 4_000)
        )
        let second = VariableExpense(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            descriptionText: "Lunch",
            amount: 14,
            transactionDate: Date(timeIntervalSinceReferenceDate: 5_000)
        )

        let forward = SnapshotContentSignature.variableExpenses([first, second])
        let reverse = SnapshotContentSignature.variableExpenses([second, first])

        #expect(forward == reverse)
    }
}
