//
//  SharedExpenseRows.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/28/26.
//

import SwiftUI

// MARK: - Shared Planned Expense Row

struct SharedPlannedExpenseRow: View {
    let expense: PlannedExpense
    let showsCardName: Bool

    init(expense: PlannedExpense, showsCardName: Bool = false) {
        self.expense = expense
        self.showsCardName = showsCardName
    }

    private enum SharedBalancePresentation {
        case none
        case split
        case offset
    }

    private var amountToShow: Double {
        SavingsMathService.grossEffectiveAmount(for: expense)
    }

    private var offsetAmount: Double {
        max(0, -(expense.offsetSettlement?.amount ?? 0))
    }

    private var splitAmount: Double {
        max(0, expense.allocation?.allocatedAmount ?? 0)
    }

    private var presentation: SharedBalancePresentation {
        if offsetAmount > 0 { return .offset }
        if splitAmount > 0 { return .split }
        return .none
    }

    private var indicatorSymbolName: String? {
        switch presentation {
        case .none:
            return nil
        case .split:
            return "arrow.trianglehead.branch"
        case .offset:
            return "arrow.trianglehead.2.clockwise"
        }
    }

    private var indicatorAccessibilityLabel: String {
        switch presentation {
        case .none:
            return ""
        case .split:
            return "Shared balance split"
        case .offset:
            return "Shared balance offset"
        }
    }

    var body: some View {
        SharedExpenseRowContent(
            title: expense.title,
            subtitle: expense.displaySubtitle(includeCardName: showsCardName),
            amount: CurrencyFormatter.string(from: amountToShow),
            categoryColorHex: expense.category?.hexColor,
            indicatorSymbolName: indicatorSymbolName,
            indicatorAccessibilityLabel: indicatorAccessibilityLabel
        )
    }

}

// MARK: - Shared Variable Expense Row

struct SharedVariableExpenseRow: View {
    let expense: VariableExpense
    let showsCardName: Bool

    init(expense: VariableExpense, showsCardName: Bool = false) {
        self.expense = expense
        self.showsCardName = showsCardName
    }

    private enum SharedBalancePresentation {
        case none
        case split
        case offset
    }

    private var offsetAmount: Double {
        max(0, -(expense.offsetSettlement?.amount ?? 0))
    }

    private var splitAmount: Double {
        max(0, expense.allocation?.allocatedAmount ?? 0)
    }

    private var originalChargeAmount: Double {
        expense.ledgerDisplayAmount()
    }

    private var presentation: SharedBalancePresentation {
        if offsetAmount > 0 { return .offset }
        if splitAmount > 0 { return .split }
        return .none
    }

    private var indicatorSymbolName: String? {
        switch presentation {
        case .none:
            return nil
        case .split:
            return "arrow.trianglehead.branch"
        case .offset:
            return "arrow.trianglehead.2.clockwise"
        }
    }

    private var indicatorAccessibilityLabel: String {
        switch presentation {
        case .none:
            return ""
        case .split:
            return "Shared balance split"
        case .offset:
            return "Shared balance offset"
        }
    }

    private var secondaryAmountSummary: String? {
        switch presentation {
        case .none:
            return nil
        case .split:
            return "Split \(CurrencyFormatter.string(from: splitAmount))"
        case .offset:
            let offset = CurrencyFormatter.string(from: offsetAmount)
            return "Offset \(offset)"
        }
    }

    private var subtitle: String {
        var parts = [
            expense.transactionDate.formatted(date: .abbreviated, time: .omitted),
            expense.kind.displayTitle
        ]
        if showsCardName, let cardName = expense.card?.name {
            parts.append(cardName)
        }
        return parts.joined(separator: " • ")
    }

    var body: some View {
        SharedExpenseRowContent(
            title: expense.descriptionText,
            subtitle: subtitle,
            amount: CurrencyFormatter.string(from: originalChargeAmount),
            categoryColorHex: expense.category?.hexColor,
            isCredit: expense.kind == .credit,
            indicatorSymbolName: indicatorSymbolName,
            indicatorAccessibilityLabel: indicatorAccessibilityLabel,
            secondaryAmountSummary: secondaryAmountSummary
        )
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
