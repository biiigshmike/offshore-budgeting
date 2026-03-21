//
//  PlannedExpense+DisplaySubtitle.swift
//  OffshoreBudgeting
//
//  Created by Codex on 3/21/26.
//

import Foundation

extension PlannedExpense {
    @MainActor
    func displaySubtitle(includeCardName: Bool = true) -> String {
        var components: [String] = [
            AppDateFormat.abbreviatedDate(expenseDate),
            VariableExpenseKind.debit.displayTitle
        ]

        if includeCardName, let cardName = card?.name, !cardName.isEmpty {
            components.append(cardName)
        }

        return components.joined(separator: " • ")
    }
}
