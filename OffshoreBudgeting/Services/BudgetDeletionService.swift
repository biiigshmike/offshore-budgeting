import Foundation
import SwiftData

@MainActor
enum BudgetDeletionService {
    static func deleteBudgetOnly(_ budget: Budget, modelContext: ModelContext) throws {
        modelContext.delete(budget)
        try modelContext.save()
    }

    static func deleteBudgetAndGeneratedPlannedExpenses(_ budget: Budget, modelContext: ModelContext) throws {
        let budgetID: UUID? = budget.id
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID
            }
        )

        let expenses = try modelContext.fetch(descriptor)
        for expense in expenses {
            PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        }

        modelContext.delete(budget)
        try modelContext.save()
    }
}
