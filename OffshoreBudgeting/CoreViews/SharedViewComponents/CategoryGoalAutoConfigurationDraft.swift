import Foundation

/// Tracks only generated fields so turning Auto-Configure off preserves manual edits.
struct CategoryGoalAutoConfigurationDraft {
    private var previousMinimums: [UUID: String] = [:]
    private var generatedMinimums: [UUID: String] = [:]
    private var previousMaximums: [UUID: String] = [:]
    private var generatedMaximums: [UUID: String] = [:]

    mutating func apply(
        to drafts: inout [UUID: CategoryGoalDraft],
        categoryIDs: [UUID],
        plannedContributions: [UUID: Double],
        suggestions: [UUID: CategoryGoalSuggestion],
        replacesExistingGoals: Bool = false
    ) {
        for categoryID in categoryIDs {
            var draft = drafts[categoryID] ?? CategoryGoalDraft()
            let enteredMinimum = draft.minimum
            let plannedMinimum = plannedContributions[categoryID] ?? 0
            let suggestedMinimum = suggestions[categoryID]?.minimum
            let historicalMinimum = (replacesExistingGoals || draft.minimumText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                && (replacesExistingGoals || (suggestedMinimum ?? 0) <= (draft.maximum ?? .infinity)) ? suggestedMinimum : nil
            let generatedMinimum = plannedMinimum.isFinite && plannedMinimum > 0 ? plannedMinimum : historicalMinimum
            if let generatedMinimum {
                previousMinimums[categoryID] = draft.minimumText
                draft.minimumText = CurrencyFormatter.editingString(from: generatedMinimum)
                generatedMinimums[categoryID] = draft.minimumText
            }
            if replacesExistingGoals || draft.maximumText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let suggestion = suggestions[categoryID] {
                previousMaximums[categoryID] = draft.maximumText
                draft.maximumText = CurrencyFormatter.editingString(from: suggestion.maximum(
                    plannedMinimum: plannedMinimum, enteredMinimum: replacesExistingGoals ? generatedMinimum : enteredMinimum
                ))
                generatedMaximums[categoryID] = draft.maximumText
            }
            if draft.hasValues || drafts[categoryID] != nil {
                drafts[categoryID] = draft
            }
        }
    }

    mutating func restore(in drafts: inout [UUID: CategoryGoalDraft]) {
        for (categoryID, generated) in generatedMinimums {
            guard var draft = drafts[categoryID], draft.minimumText == generated else { continue }
            draft.minimumText = previousMinimums[categoryID] ?? ""
            drafts[categoryID] = draft
        }
        for (categoryID, generated) in generatedMaximums {
            guard var draft = drafts[categoryID], draft.maximumText == generated else { continue }
            draft.maximumText = previousMaximums[categoryID] ?? ""
            drafts[categoryID] = draft
        }
        self = CategoryGoalAutoConfigurationDraft()
    }
}
