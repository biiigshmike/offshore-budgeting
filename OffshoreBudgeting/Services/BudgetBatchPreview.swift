import Foundation

struct BudgetBatchPreview: Equatable {
    let drafts: [BudgetBatchDraft]
    let plannedExpenseCount: Int
    let overlappingBudgetNames: [String]
}
