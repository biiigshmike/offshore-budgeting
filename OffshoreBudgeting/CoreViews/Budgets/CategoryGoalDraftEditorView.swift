import SwiftUI

struct CategoryGoalDraftEditorView: View {
    let category: Category
    @Binding var draft: CategoryGoalDraft
    let plannedContribution: Double
    let variableContribution: Double

    var body: some View {
        CategoryLimitFormView(
            categoryName: category.name,
            tint: Color(hex: category.hexColor) ?? .accentColor,
            plannedAmount: plannedContribution,
            variableAmount: variableContribution,
            totalAmount: plannedContribution + variableContribution,
            gaugeMin: draft.minimum ?? 0,
            gaugeMax: draft.maximum,
            minText: $draft.minimumText,
            maxText: $draft.maximumText,
            validationMessage: draft.validationMessage
        )
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
