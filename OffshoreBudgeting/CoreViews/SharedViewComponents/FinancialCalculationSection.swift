import Foundation

struct FinancialCalculationSection: Identifiable {
    let id: String
    let title: String
    let explanation: String
    let rows: [FinancialCalculationRow]
    var notes: [String] = []
}
