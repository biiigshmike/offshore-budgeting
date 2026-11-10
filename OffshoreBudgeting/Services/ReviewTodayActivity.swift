import Foundation
import SwiftData

struct ReviewTodayActivity {
    enum Entry: Identifiable {
        case variable(VariableExpense)
        case planned(PlannedExpense)

        var id: PersistentIdentifier {
            switch self {
            case .variable(let expense): expense.persistentModelID
            case .planned(let expense): expense.persistentModelID
            }
        }

        var date: Date {
            switch self {
            case .variable(let expense): expense.transactionDate
            case .planned(let expense): expense.expenseDate
            }
        }

        fileprivate var sortID: UUID {
            switch self {
            case .variable(let expense): expense.id
            case .planned(let expense): expense.id
            }
        }
    }

    struct CategoryTotal: Identifiable {
        let id: UUID?
        let name: String
        let colorHex: String?
        var amount: Double
    }

    struct CardTotal: Identifiable {
        enum ID: Hashable {
            case card(UUID)
            case noCard

            fileprivate var sortKey: String {
                switch self {
                case .card(let id): id.uuidString
                case .noCard: ""
                }
            }
        }

        let id: ID
        let name: String
        let amount: Double
        let categories: [CategoryTotal]
    }

    let day: Date
    let spent: Double
    let refunded: Double
    let entries: [Entry]
    let stillPlanned: [PlannedExpense]
    let categories: [CategoryTotal]
    let cards: [CardTotal]

    var isEmpty: Bool { entries.isEmpty && stillPlanned.isEmpty }

    init(expenses: ReviewTodayExpenses) {
        day = expenses.day
        var categoryTotals: [UUID?: CategoryTotal] = [:]
        var categoriesByCard: [UUID?: [UUID?: CategoryTotal]] = [:]
        var cardsByID: [UUID: Card] = [:]
        var refundTotal = 0.0
        var activity = expenses.variable.map(Entry.variable)
        var planned: [PlannedExpense] = []

        func addSpending(_ amount: Double, category: Category?, card: Card?) {
            guard amount > 0 else { return }
            let id = category?.id
            let categoryTotal = CategoryTotal(
                id: id,
                name: category?.name ?? String(localized: "Uncategorized"),
                colorHex: category?.hexColor,
                amount: 0
            )
            categoryTotals[id, default: categoryTotal].amount += amount
            categoriesByCard[card?.id, default: [:]][id, default: categoryTotal].amount += amount
            if let card {
                cardsByID[card.id] = card
            }
        }

        for expense in expenses.variable {
            addSpending(expense.spendingAmount(), category: expense.category, card: expense.card)
            if expense.kind == .credit {
                refundTotal += expense.ledgerDisplayAmount()
            }
        }
        for expense in expenses.planned {
            let actual = SavingsMathService.grossRecordedActualAmount(for: expense)
            if actual > 0 {
                activity.append(.planned(expense))
                addSpending(actual, category: expense.category, card: expense.card)
            } else {
                planned.append(expense)
            }
        }

        refunded = refundTotal
        entries = activity.sorted {
            $0.date == $1.date ? $0.sortID.uuidString < $1.sortID.uuidString : $0.date > $1.date
        }
        stillPlanned = planned.sorted {
            $0.expenseDate == $1.expenseDate
                ? $0.id.uuidString < $1.id.uuidString : $0.expenseDate < $1.expenseDate
        }
        let sortedCategories = Self.sortedCategories(categoryTotals)
        categories = sortedCategories
        spent = sortedCategories.reduce(0) { $0 + $1.amount }
        cards = categoriesByCard.map { id, totals in
            let sorted = Self.sortedCategories(totals)
            let card = id.flatMap { cardsByID[$0] }
            return CardTotal(
                id: id.map(CardTotal.ID.card) ?? .noCard,
                name: card?.name ?? String(localized: "No Card"),
                amount: sorted.reduce(0) { $0 + $1.amount },
                categories: sorted
            )
        }.sorted {
            if $0.amount != $1.amount { return $0.amount > $1.amount }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.id.sortKey < $1.id.sortKey
        }
    }

    private static func sortedCategories(_ totals: [UUID?: CategoryTotal]) -> [CategoryTotal] {
        totals.values.sorted {
            if $0.amount != $1.amount { return $0.amount > $1.amount }
            if $0.name != $1.name { return $0.name < $1.name }
            return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
        }
    }
}
