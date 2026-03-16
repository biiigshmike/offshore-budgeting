//
//  SnapshotContentSignature.swift
//  OffshoreBudgeting
//
//  Created by OpenAI Codex on 3/16/26.
//

import Foundation

enum SnapshotContentSignature {

    static func budgets(_ budgets: [Budget]) -> Int {
        var hasher = Hasher()
        hasher.combine(budgets.count)

        for budget in budgets.sorted(by: compareIDs(\.id)) {
            hasher.combine(budget.id)
            hasher.combine(budget.name)
            hasher.combine(stamp(for: budget.startDate))
            hasher.combine(stamp(for: budget.endDate))
        }

        return hasher.finalize()
    }

    static func cards(_ cards: [Card]) -> Int {
        var hasher = Hasher()
        hasher.combine(cards.count)

        for card in cards.sorted(by: compareIDs(\.id)) {
            hasher.combine(card.id)
            hasher.combine(card.name)
            hasher.combine(card.theme)
            hasher.combine(card.effect)
        }

        return hasher.finalize()
    }

    static func categories(_ categories: [Category]) -> Int {
        var hasher = Hasher()
        hasher.combine(categories.count)

        for category in categories.sorted(by: compareIDs(\.id)) {
            hasher.combine(category.id)
            hasher.combine(category.name)
            hasher.combine(category.hexColor)
        }

        return hasher.finalize()
    }

    static func presets(_ presets: [Preset]) -> Int {
        var hasher = Hasher()
        hasher.combine(presets.count)

        for preset in presets.sorted(by: compareIDs(\.id)) {
            hasher.combine(preset.id)
            hasher.combine(preset.title)
            hasher.combine(preset.plannedAmount.bitPattern)
            hasher.combine(preset.isArchived)
            hasher.combine(optionalUUID: preset.defaultCard?.id)
            hasher.combine(optionalUUID: preset.defaultCategory?.id)
        }

        return hasher.finalize()
    }

    static func budgetCategoryLimits(_ limits: [BudgetCategoryLimit]) -> Int {
        var hasher = Hasher()
        hasher.combine(limits.count)

        for limit in limits.sorted(by: compareIDs(\.id)) {
            hasher.combine(limit.id)
            hasher.combine(optionalUUID: limit.category?.id)
            hasher.combine(optionalDouble: limit.minAmount)
            hasher.combine(optionalDouble: limit.maxAmount)
        }

        return hasher.finalize()
    }

    static func incomes(_ incomes: [Income]) -> Int {
        var hasher = Hasher()
        hasher.combine(incomes.count)

        for income in incomes.sorted(by: compareIDs(\.id)) {
            hasher.combine(income.id)
            hasher.combine(income.source)
            hasher.combine(income.amount.bitPattern)
            hasher.combine(stamp(for: income.date))
            hasher.combine(income.isPlanned)
            hasher.combine(income.isException)
            hasher.combine(optionalUUID: income.card?.id)
        }

        return hasher.finalize()
    }

    static func plannedExpenses(_ expenses: [PlannedExpense]) -> Int {
        var hasher = Hasher()
        hasher.combine(expenses.count)

        for expense in expenses.sorted(by: compareIDs(\.id)) {
            hasher.combine(expense.id)
            hasher.combine(expense.title)
            hasher.combine(expense.plannedAmount.bitPattern)
            hasher.combine(expense.actualAmount.bitPattern)
            hasher.combine(stamp(for: expense.expenseDate))
            hasher.combine(optionalUUID: expense.card?.id)
            hasher.combine(optionalUUID: expense.category?.id)
            hasher.combine(optionalUUID: expense.sourcePresetID)
            hasher.combine(optionalUUID: expense.sourceBudgetID)
            combineAllocation(expense.allocation, into: &hasher)
            combineSettlement(expense.offsetSettlement, into: &hasher)
            combineSavingsEntry(expense.savingsLedgerEntry, into: &hasher)
        }

        return hasher.finalize()
    }

    static func variableExpenses(_ expenses: [VariableExpense]) -> Int {
        var hasher = Hasher()
        hasher.combine(expenses.count)

        for expense in expenses.sorted(by: compareIDs(\.id)) {
            hasher.combine(expense.id)
            hasher.combine(expense.descriptionText)
            hasher.combine(expense.amount.bitPattern)
            hasher.combine(stamp(for: expense.transactionDate))
            hasher.combine(optionalUUID: expense.card?.id)
            hasher.combine(optionalUUID: expense.category?.id)
            combineAllocation(expense.allocation, into: &hasher)
            combineSettlement(expense.offsetSettlement, into: &hasher)
            combineSavingsEntry(expense.savingsLedgerEntry, into: &hasher)
        }

        return hasher.finalize()
    }

    private static func stamp(for date: Date) -> Int64 {
        Int64(date.timeIntervalSinceReferenceDate)
    }

    private static func combineAllocation(_ allocation: ExpenseAllocation?, into hasher: inout Hasher) {
        hasher.combine(optionalUUID: allocation?.id)
        hasher.combine(optionalDouble: allocation?.allocatedAmount)
        hasher.combine(optionalUUID: allocation?.account?.id)
    }

    private static func combineSettlement(_ settlement: AllocationSettlement?, into hasher: inout Hasher) {
        hasher.combine(optionalUUID: settlement?.id)
        hasher.combine(optionalDouble: settlement?.amount)
        hasher.combine(optionalStamp: settlement?.date)
        hasher.combine(optionalUUID: settlement?.account?.id)
    }

    private static func combineSavingsEntry(_ entry: SavingsLedgerEntry?, into hasher: inout Hasher) {
        hasher.combine(optionalUUID: entry?.id)
        hasher.combine(optionalDouble: entry?.amount)
        hasher.combine(optionalStamp: entry?.date)
        hasher.combine(optionalString: entry?.note)
        hasher.combine(optionalString: entry?.kindRaw)
    }

    private static func compareIDs<T>(_ keyPath: KeyPath<T, UUID>) -> (T, T) -> Bool {
        { lhs, rhs in
            lhs[keyPath: keyPath].uuidString < rhs[keyPath: keyPath].uuidString
        }
    }
}

private extension Hasher {
    mutating func combine(optionalUUID value: UUID?) {
        combine(value?.uuidString ?? "nil")
    }

    mutating func combine(optionalString value: String?) {
        combine(value ?? "nil")
    }

    mutating func combine(optionalDouble value: Double?) {
        combine(value?.bitPattern ?? UInt64.max)
    }

    mutating func combine(optionalStamp value: Date?) {
        combine(value.map { Int64($0.timeIntervalSinceReferenceDate) } ?? Int64.min)
    }
}
