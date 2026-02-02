//
//  BudgetPlannedExpenseStore.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/1/26.
//

import Foundation

enum BudgetPlannedExpenseStore {

    // MARK: - Query

    static func plannedExpenses(
        in workspace: Workspace,
        for budget: Budget,
        calendar: Calendar = .current
    ) -> [PlannedExpense] {
        let budgetID = budget.id
        let linkedCardIDs = linkedCardIDs(for: budget)
        guard !linkedCardIDs.isEmpty else { return [] }

        let range = DateRange(start: budget.startDate, end: budget.endDate, calendar: calendar)

        return (workspace.plannedExpenses ?? [])
            .filter { $0.sourceBudgetID == budgetID }
            .filter { expense in
                guard let cardID = expense.card?.id else { return false }
                return linkedCardIDs.contains(cardID)
            }
            .filter { range.start <= $0.expenseDate && $0.expenseDate <= range.end }
            .sorted { $0.expenseDate > $1.expenseDate }
    }

    // MARK: - Helpers

    static func linkedCardIDs(for budget: Budget) -> Set<UUID> {
        Set((budget.cardLinks ?? []).compactMap { $0.card?.id })
    }
}

