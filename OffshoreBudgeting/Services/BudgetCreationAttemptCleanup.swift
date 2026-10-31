import SwiftData

@MainActor
enum BudgetCreationAttemptCleanup {
    /// Discards the exact unsaved objects created by one Add Budget save attempt.
    /// Persisted budgets and unrelated pending edits must never be rolled back.
    @discardableResult
    static func discard(
        budget: Budget,
        createdPlannedExpenses: [PlannedExpense],
        modelContext: ModelContext
    ) -> Bool {
        let insertedIDs = Set(modelContext.insertedModelsArray.map { $0.persistentModelID })
        guard insertedIDs.contains(budget.persistentModelID) else { return false }

        for expense in createdPlannedExpenses where insertedIDs.contains(expense.persistentModelID)
            && expense.sourceBudgetID == budget.id
            && expense.workspace?.id == budget.workspace?.id {
            PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        }
        modelContext.delete(budget) // Cascades this attempt's new links and goals.
        return true
    }
}
