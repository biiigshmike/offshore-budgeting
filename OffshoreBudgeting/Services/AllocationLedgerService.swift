import Foundation

// MARK: - AllocationLedgerService

@MainActor
enum AllocationLedgerService {

    // MARK: - LedgerRow

    enum LedgerRowType: String {
        case charge = "Charge"
        case settlement = "Settlement"
    }

    struct LedgerRow: Identifiable {
        let id: String
        let type: LedgerRowType
        let date: Date
        let title: String
        let subtitle: String?
        let amount: Double
        let settlementID: UUID?
        let allocationID: UUID?
        let linkedExpenseID: UUID?
        let isLinkedSettlement: Bool
    }

    // MARK: - Balance

    static func balance(for account: AllocationAccount) -> Double {
        let chargeTotal = (account.expenseAllocations ?? []).reduce(0) { partial, allocation in
            partial + max(0, allocation.allocatedAmount)
        }

        let settlementTotal = (account.settlements ?? []).reduce(0) { partial, settlement in
            partial + settlement.amount
        }

        return chargeTotal + settlementTotal
    }

    // MARK: - Ledger

    static func rows(for account: AllocationAccount) -> [LedgerRow] {
        var rows: [LedgerRow] = []

        for allocation in account.expenseAllocations ?? [] {
            if let expense = allocation.expense {
                let cardName = expense.card?.name ?? "No Card"
                let categoryName = expense.category?.name ?? "Uncategorized"

                rows.append(
                    LedgerRow(
                        id: "charge-\(allocation.id.uuidString)",
                        type: .charge,
                        date: expense.transactionDate,
                        title: expense.descriptionText,
                        subtitle: "\(cardName) • \(categoryName)",
                        amount: allocation.allocatedAmount,
                        settlementID: nil,
                        allocationID: allocation.id,
                        linkedExpenseID: expense.id,
                        isLinkedSettlement: false
                    )
                )
            } else if let plannedExpense = allocation.plannedExpense {
                let cardName = plannedExpense.card?.name ?? "No Card"
                let categoryName = plannedExpense.category?.name ?? "Uncategorized"

                rows.append(
                    LedgerRow(
                        id: "charge-\(allocation.id.uuidString)",
                        type: .charge,
                        date: plannedExpense.expenseDate,
                        title: plannedExpense.title,
                        subtitle: "\(cardName) • \(categoryName)",
                        amount: allocation.allocatedAmount,
                        settlementID: nil,
                        allocationID: allocation.id,
                        linkedExpenseID: plannedExpense.id,
                        isLinkedSettlement: false
                    )
                )
            }
        }

        for settlement in account.settlements ?? [] {
            let note = settlement.note.trimmingCharacters(in: .whitespacesAndNewlines)
            let subtitle: String?
            if let expense = settlement.expense {
                let cardName = expense.card?.name ?? "No Card"
                let categoryName = expense.category?.name ?? "Uncategorized"
                subtitle = "\(cardName) • \(categoryName)"
            } else if let plannedExpense = settlement.plannedExpense {
                let cardName = plannedExpense.card?.name ?? "No Card"
                let categoryName = plannedExpense.category?.name ?? "Uncategorized"
                subtitle = "\(cardName) • \(categoryName)"
            } else {
                subtitle = nil
            }

            rows.append(
                LedgerRow(
                    id: "settlement-\(settlement.id.uuidString)",
                    type: .settlement,
                    date: settlement.date,
                    title: note.isEmpty ? "Settlement" : note,
                    subtitle: subtitle,
                    amount: settlement.amount,
                    settlementID: settlement.id,
                    allocationID: nil,
                    linkedExpenseID: settlement.expense?.id ?? settlement.plannedExpense?.id,
                    isLinkedSettlement: settlement.expense != nil || settlement.plannedExpense != nil
                )
            )
        }

        return rows.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.id > rhs.id
            }
            return lhs.date > rhs.date
        }
    }

    // MARK: - Entry

    static func cappedAllocationAmount(_ value: Double, expenseAmount: Double) -> Double {
        max(0, min(value, max(0, expenseAmount)))
    }
}
