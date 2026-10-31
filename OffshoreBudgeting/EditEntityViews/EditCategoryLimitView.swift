import SwiftUI
import SwiftData

struct EditCategoryLimitView: View {
    let budget: Budget
    let category: Category

    /// Already scoped to the budget's cards, dates, and category by BudgetDetailView.
    let plannedContribution: Double
    let variableContribution: Double

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft = CategoryGoalDraft()
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            CategoryGoalDraftEditorView(
                category: category,
                draft: $draft,
                plannedContribution: plannedContribution,
                variableContribution: variableContribution
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let workspaceID = budget.workspace?.id else { return }
                        if BudgetCategoryGoalStore.apply(
                            [category.id: draft],
                            categories: [category],
                            budget: budget,
                            workspaceID: workspaceID,
                            modelContext: modelContext
                        ) {
                            dismiss()
                        }
                    }
                    .disabled(!draft.isValid)
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                draft = BudgetCategoryGoalStore.drafts(for: budget)[category.id] ?? CategoryGoalDraft()
                if DebugScreenshotFormDefaults.isEnabled && !draft.hasValues {
                    draft.minimumText = DebugScreenshotFormDefaults.categoryLimitMinText
                    draft.maximumText = DebugScreenshotFormDefaults.categoryLimitMaxText
                }
            }
        }
    }
}
