import Foundation

struct FinancialCalculationRow: Identifiable {
    let id: String
    let title: String
    let amount: Double
    var isTotal: Bool = false
    var titleIsVerbatim: Bool = false
}
