import Foundation
import SwiftData

@MainActor
enum BudgetPlannedExpenseCleanupService {
    static func cleanup(
        budget: Budget,
        workspaceID: UUID,
        selectedPresetIDs: Set<UUID>,
        selectedCardIDs: Set<UUID>,
        modelContext: ModelContext,
        calendar: Calendar = .current
    ) throws {
        guard budget.workspace?.id == workspaceID else { return }
        let budgetID = budget.id
        let expenses = try modelContext.fetch(FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.workspace?.id == workspaceID && expense.sourceBudgetID == budgetID
            }
        ))
        let presets = try modelContext.fetch(FetchDescriptor<Preset>(
            predicate: #Predicate { $0.workspace?.id == workspaceID }
        ))
        let existingPresetIDs = Set(presets.map(\.id))
        let windowStart = calendar.startOfDay(for: budget.startDate)
        let windowEnd = calendar.startOfDay(for: budget.endDate)

        for expense in expenses {
            // A missing source preset is historical provenance, not a deselection.
            // Keep the existing cleanup behavior for rows without a source ID.
            let presetDeselected = expense.sourcePresetID.map {
                existingPresetIDs.contains($0) && !selectedPresetIDs.contains($0)
            } ?? true
            let day = calendar.startOfDay(for: expense.expenseDate)
            let inWindow = windowStart <= day && day <= windowEnd
            let cardStillLinked = expense.card.map { selectedCardIDs.contains($0.id) } ?? true

            if presetDeselected || !inWindow || !cardStillLinked {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        }
    }
}
