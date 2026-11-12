import SwiftData

@MainActor
enum PlannedExpenseRecordingService {
    static func canRecord(_ expense: PlannedExpense) -> Bool {
        expense.actualAmount == 0 && expense.plannedAmount > 0 && expense.plannedAmount.isFinite
    }

    static func recordAsPlanned(_ expense: PlannedExpense, modelContext: ModelContext) throws {
        try recordAsPlanned(expense) { try modelContext.save() }
    }

    // Keep the save boundary injectable so restoration can be verified on failure.
    static func recordAsPlanned(_ expense: PlannedExpense, save: () throws -> Void) throws {
        guard canRecord(expense) else { return }

        let previousActualAmount = expense.actualAmount
        let allocation = expense.allocation
        let previousPreservesGrossAmount = allocation?.preservesGrossAmount

        expense.actualAmount = expense.plannedAmount
        // Planned amounts are gross. Legacy net-stored splits must not add their share again.
        allocation?.preservesGrossAmount = true

        do {
            try save()
        } catch {
            expense.actualAmount = previousActualAmount
            if let previousPreservesGrossAmount {
                allocation?.preservesGrossAmount = previousPreservesGrossAmount
            }
            throw error
        }
    }
}
