//
//  PlannedExpenseDisplaySubtitleTests.swift
//  OffshoreBudgetingTests
//
//  Created by Codex on 3/21/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct PlannedExpenseDisplaySubtitleTests {

    @Test func displaySubtitle_includesDebitLabelWithoutCardName() {
        let expense = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: date(year: 2026, month: 3, day: 21, hour: 9, minute: 0)
        )

        let subtitle = expense.displaySubtitle(includeCardName: false)

        #expect(subtitle == "\(AppDateFormat.abbreviatedDate(expense.expenseDate)) • Debit")
    }

    @Test func displaySubtitle_appendsCardNameWhenRequested() {
        let card = Card(name: "Checking")
        let expense = PlannedExpense(
            title: "Rent",
            plannedAmount: 1_200,
            expenseDate: date(year: 2026, month: 3, day: 21, hour: 9, minute: 0),
            card: card
        )

        let subtitle = expense.displaySubtitle()

        #expect(subtitle == "\(AppDateFormat.abbreviatedDate(expense.expenseDate)) • Debit • Checking")
    }

    private func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return Calendar(identifier: .gregorian).date(from: components) ?? .now
    }
}
