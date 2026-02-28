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

    private enum SharedBalancePresentation {
        case none
        case split
        case offset
    }

    private var amountToShow: Double {
        expense.effectiveAmount()
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
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                SharedCategoryDotView(category: expense.category)

                if let indicatorSymbolName {
                    Image(systemName: indicatorSymbolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(indicatorAccessibilityLabel)
                }
            }
            .frame(width: 12)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.body)

                HStack(spacing: 6) {
                    Text(
                        expense.expenseDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(amountToShow, format: CurrencyFormatter.currencyStyle())
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Shared Variable Expense Row

struct SharedVariableExpenseRow: View {
    let expense: VariableExpense

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
        max(0, expense.amount + offsetAmount)
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
            let net = CurrencyFormatter.string(from: expense.amount)
            let offset = CurrencyFormatter.string(from: offsetAmount)
            return "Net \(net) • Offset \(offset)"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                SharedCategoryDotView(category: expense.category)

                if let indicatorSymbolName {
                    Image(systemName: indicatorSymbolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(indicatorAccessibilityLabel)
                }
            }
            .frame(width: 12)
            .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(expense.descriptionText)
                    .font(.body)

                HStack(spacing: 6) {
                    Text(
                        expense.transactionDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 2) {
                Text(originalChargeAmount, format: CurrencyFormatter.currencyStyle())
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)

                if let secondaryAmountSummary {
                    Text(secondaryAmountSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 4)
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
