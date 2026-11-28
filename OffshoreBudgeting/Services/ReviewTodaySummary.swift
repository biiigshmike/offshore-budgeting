import Foundation
import SwiftData

struct ReviewTodaySummary {
    struct CardTotal: Identifiable, Equatable {
        let name: String
        let amount: Double

        var id: String { name }
    }

    let total: Double
    let variableCount: Int
    let plannedCount: Int
    let topCards: [CardTotal]

    var isEmpty: Bool { variableCount == 0 && plannedCount == 0 }

    @MainActor
    static func load(
        workspaceID: UUID,
        in context: ModelContext,
        date: Date = .now,
        calendar: Calendar = .current
    ) throws -> Self {
        let expenses = try ReviewTodayExpenses.load(
            workspaceID: workspaceID, in: context, date: date, calendar: calendar
        )
        let variableExpenses = expenses.variable
        let plannedExpenses = expenses.planned

        var variableTotal = 0.0
        var plannedTotal = 0.0
        var totalsByCardName: [String?: Double] = [:]

        for expense in variableExpenses {
            let amount = expense.ledgerSignedAmount()
            variableTotal += amount
            totalsByCardName[expense.card?.name, default: 0] += amount
        }
        for expense in plannedExpenses {
            let amount = expense.effectiveAmount()
            plannedTotal += amount
            totalsByCardName[expense.card?.name, default: 0] += amount
        }

        let topCards = totalsByCardName
            .sorted { lhs, rhs in
                if lhs.value == rhs.value {
                    // Preserve the missing-card bucket's sort position across app languages.
                    let lhsName = lhs.key ?? "Unknown Card"
                    let rhsName = rhs.key ?? "Unknown Card"
                    if lhsName == rhsName { return lhs.key != nil && rhs.key == nil }
                    return lhsName < rhsName
                }
                return lhs.value > rhs.value
            }
            .prefix(2)
            .map { CardTotal(name: $0.key ?? String(localized: "No Card"), amount: $0.value) }

        return Self(
            total: variableTotal + plannedTotal,
            variableCount: variableExpenses.count,
            plannedCount: plannedExpenses.count,
            topCards: topCards
        )
    }
}
