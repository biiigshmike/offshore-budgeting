import SwiftData
import SwiftUI

struct RecordPlannedExpenseButton: View {
    let expense: PlannedExpense
    var onRecorded: () -> Void = { }

    @Environment(\.modelContext) private var modelContext
    @State private var showingSaveError = false

    var body: some View {
        Group {
            if PlannedExpenseRecordingService.canRecord(expense) {
                Button("As Planned", systemImage: "checkmark", action: record)
                    .tint(.green)
                    .accessibilityHint("Sets the actual amount to the planned amount.")
                    .accessibilityIdentifier("plannedExpense.recordAsPlanned.\(expense.id.uuidString)")
            }
        }
        .blocksAutomaticExpenseReview(while: showingSaveError)
        .alert("Couldn’t Record Expense", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("The actual amount couldn’t be saved. Please try again.")
        }
    }

    private func record() {
        do {
            try PlannedExpenseRecordingService.recordAsPlanned(expense, modelContext: modelContext)
            onRecorded()
        } catch {
            showingSaveError = true
        }
    }
}
