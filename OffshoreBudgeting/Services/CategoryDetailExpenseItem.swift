import Foundation

enum CategoryDetailExpenseItem: Identifiable {
    case planned(PlannedExpense)
    case variable(VariableExpense)

    var id: String {
        switch self {
        case .planned(let expense): "planned-\(expense.id.uuidString)"
        case .variable(let expense): "variable-\(expense.id.uuidString)"
        }
    }

    var title: String {
        switch self {
        case .planned(let expense): expense.title
        case .variable(let expense): expense.descriptionText
        }
    }

    var date: Date {
        switch self {
        case .planned(let expense): expense.expenseDate
        case .variable(let expense): expense.transactionDate
        }
    }

    var sortAmount: Double {
        switch self {
        case .planned(let expense): expense.effectiveAmount()
        case .variable(let expense): expense.ledgerDisplayAmount()
        }
    }
}
