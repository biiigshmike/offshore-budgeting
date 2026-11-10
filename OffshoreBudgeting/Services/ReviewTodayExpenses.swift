import Foundation
import SwiftData

struct ReviewTodayExpenses {
    let day: Date
    let variable: [VariableExpense]
    let planned: [PlannedExpense]

    @MainActor
    static func load(
        workspaceID: UUID,
        in context: ModelContext,
        date: Date = .now,
        calendar: Calendar = .current
    ) throws -> Self {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let variableExpenses = try context.fetch(FetchDescriptor<VariableExpense>(
            predicate: #Predicate { expense in
                expense.workspace?.id == workspaceID
                    && expense.transactionDate >= start
                    && expense.transactionDate < end
            }
        ))
        let plannedExpenses = try context.fetch(FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.workspace?.id == workspaceID
                    && expense.expenseDate >= start
                    && expense.expenseDate < end
            }
        ))

        return Self(day: start, variable: variableExpenses, planned: plannedExpenses)
    }
}
