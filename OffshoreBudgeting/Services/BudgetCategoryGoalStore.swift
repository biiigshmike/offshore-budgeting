import Foundation
import SwiftData

@MainActor
enum BudgetCategoryGoalStore {
    static func drafts(for budget: Budget) -> [UUID: CategoryGoalDraft] {
        var result: [UUID: CategoryGoalDraft] = [:]
        for goal in budget.categoryLimits ?? [] {
            guard let category = goal.category,
                  category.workspace?.id == budget.workspace?.id,
                  result[category.id] == nil else { continue }
            result[category.id] = CategoryGoalDraft(minimum: goal.minAmount, maximum: goal.maxAmount)
        }
        return result
    }

    /// Applies only explicitly supplied categories in this budget's workspace.
    /// Other budgets, hidden categories, and historical expenses are untouched.
    @discardableResult
    static func apply(
        _ drafts: [UUID: CategoryGoalDraft],
        categories: [Category],
        budget: Budget,
        workspaceID: UUID,
        modelContext: ModelContext
    ) -> Bool {
        guard budget.workspace?.id == workspaceID, drafts.values.allSatisfy(\.isValid) else { return false }

        for category in categories where category.workspace?.id == workspaceID {
            guard let draft = drafts[category.id] else { continue }
            let existing = (budget.categoryLimits ?? []).first { $0.category?.id == category.id }

            if let existing {
                if !draft.hasValues {
                    modelContext.delete(existing)
                } else {
                    existing.minAmount = draft.minimum
                    existing.maxAmount = draft.maximum
                }
            } else if draft.hasValues {
                modelContext.insert(BudgetCategoryLimit(
                    minAmount: draft.minimum,
                    maxAmount: draft.maximum,
                    budget: budget,
                    category: category
                ))
            }
        }
        return true
    }
}
