import Foundation

/// A snapshot of a historical budget's category total, suitable for explaining a suggestion.
struct CategoryGoalHistorySample: Identifiable, Equatable {
    let budgetID: UUID
    let name: String
    let startDate: Date
    let endDate: Date
    let amount: Double

    var id: UUID { budgetID }
}
