import Foundation

/// Write for someone new to budgeting: explain what the number means first,
/// show what is added or subtracted in the rows, then give short exceptions in notes.
/// Keep product names recognizable and explain them without calculation jargon.
/// Describe the total directly, or name Offshore when needed. Avoid “we” and “our”.
struct FinancialCalculationSection: Identifiable {
    let id: String
    let title: String
    let explanation: String
    let rows: [FinancialCalculationRow]
    var notes: [String] = []
}
