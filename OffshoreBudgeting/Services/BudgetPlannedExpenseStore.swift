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
        let range = DateRange(start: budget.startDate, end: budget.endDate, calendar: calendar)

        return plannedExpenses(
            workspace.plannedExpenses ?? [],
            budgetID: budgetID,
            linkedCardIDs: linkedCardIDs,
            range: range
        )
    }

    static func plannedExpenses(
        _ expenses: [PlannedExpense],
        budgetID: UUID,
        linkedCardIDs: Set<UUID>,
        range: DateRange
    ) -> [PlannedExpense] {
        guard !linkedCardIDs.isEmpty else { return [] }

        return expenses
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
