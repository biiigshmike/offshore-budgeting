//
//  SharedExpenseRows.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/28/26.
//

import SwiftUI

struct SharedPlannedExpenseRow: View {
    let expense: PlannedExpense
    var showsCard = false
    var showsPlannedLabel = false
    var showsRecordedAmount = false

    var body: some View {
        let balance = SharedExpenseBalance(
            settlementAmount: expense.offsetSettlement?.amount,
            allocationAmount: expense.allocation?.allocatedAmount
        )
        let grossAmount = SavingsMathService.grossEffectiveAmount(for: expense)
        let amount = showsRecordedAmount ? expense.actualAmount : grossAmount
        let isRecorded = expense.actualAmount > 0
        let statusLabel = if !isRecorded {
            String(localized: "Planned")
        } else if CurrencyFormatter.roundedToCurrency(grossAmount) == CurrencyFormatter.roundedToCurrency(expense.plannedAmount) {
            String(localized: "As Planned")
        } else {
            String(localized: "Recorded")
        }

        SharedExpenseRowContent(
            title: expense.title,
            date: expense.expenseDate,
            amount: CurrencyFormatter.string(from: amount),
            category: expense.category,
            card: showsCard ? expense.card : nil,
            typeLabel: showsPlannedLabel ? statusLabel : nil,
            typeLabelShowsCheckmark: isRecorded,
            accessibilityOnlyTypeLabel: showsPlannedLabel ? nil : statusLabel,
            secondaryAmountSummary: balance.amountSummary
        )
    }
}

struct SharedVariableExpenseRow: View {
    let expense: VariableExpense
    var showsCard = false

    var body: some View {
        let balance = SharedExpenseBalance(
            settlementAmount: expense.offsetSettlement?.amount,
            allocationAmount: expense.allocation?.allocatedAmount
        )
        let isDebit = expense.kind == .debit

        SharedExpenseRowContent(
            title: expense.descriptionText,
            date: expense.transactionDate,
            amount: CurrencyFormatter.string(from: expense.ledgerDisplayAmount()),
            category: expense.category,
            card: showsCard ? expense.card : nil,
            isCredit: expense.kind == .credit,
            typeLabel: isDebit ? nil : expense.kind.displayTitle,
            accessibilityOnlyTypeLabel: isDebit ? expense.kind.displayTitle : nil,
            secondaryAmountSummary: balance.amountSummary
        )
    }
}

private enum SharedExpenseBalance {
    case none
    case split(Double)
    case offset(Double)

    init(settlementAmount: Double?, allocationAmount: Double?) {
        if let settlementAmount, settlementAmount < 0 {
            self = .offset(-settlementAmount)
        } else if let allocationAmount, allocationAmount > 0 {
            self = .split(allocationAmount)
        } else {
            self = .none
        }
    }

    var amountSummary: String? {
        switch self {
        case .none: nil
        case .split(let amount): String(localized: "Split \(CurrencyFormatter.string(from: amount))")
        case .offset(let amount): String(localized: "Offset \(CurrencyFormatter.string(from: amount))")
        }
    }
}

// MARK: - Shared Category Dot

struct SharedCategoryDotView: View {
    let category: Category?

    private var dotColor: Color {
        guard let hex = category?.hexColor, let color = Color(hex: hex) else {
            return Color.secondary.opacity(0.35)
        }
        return color
    }

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 10, height: 10)
    }
}
