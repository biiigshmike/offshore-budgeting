import SwiftData
import SwiftUI

struct RecordPlannedExpenseButton: View {
    let expense: PlannedExpense
    @Binding var showingSaveError: Bool
    var onRecorded: () -> Void = { }

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Button("As Planned", systemImage: "checkmark", action: record)
            .tint(.green)
            .accessibilityHint("Sets the actual amount to the planned amount.")
            .accessibilityIdentifier("plannedExpense.recordAsPlanned.\(expense.id.uuidString)")
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

extension View {
    func plannedExpenseRecordingAlert(isPresented: Binding<Bool>) -> some View {
        blocksAutomaticExpenseReview(while: isPresented.wrappedValue)
            .alert("Couldn’t Record Expense", isPresented: isPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The actual amount couldn’t be saved. Please try again.")
            }
    }
}
