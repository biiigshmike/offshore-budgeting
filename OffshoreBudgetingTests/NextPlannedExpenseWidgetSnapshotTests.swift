import Foundation
import Testing
@testable import Offshore

struct NextPlannedExpenseWidgetSnapshotTests {
    @Test func selectedCardSnapshotsMergeInDateOrderWithoutDuplicates() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let yesterday = try #require(calendar.date(byAdding: .day, value: -1, to: today))
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let dayAfterTomorrow = try #require(calendar.date(byAdding: .day, value: 2, to: today))

        let first = snapshot(
            from: yesterday,
            to: dayAfterTomorrow,
            items: [item("stale", on: yesterday), item("same", on: today), item("last", on: dayAfterTomorrow)]
        )
        let second = snapshot(
            from: yesterday,
            to: dayAfterTomorrow,
            items: [item("same", on: today), item("next", on: tomorrow), item("another", on: tomorrow), item("later", on: dayAfterTomorrow)]
        )

        let merged = try #require(NextPlannedExpenseWidgetSnapshot.merging([first, second], asOf: today, calendar: calendar))
        #expect(merged.items.map(\.expenseID) == ["same", "another", "next", "last"])
    }

    @Test func selectedCardSnapshotsDoNotMergeAcrossPeriodRanges() throws {
        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: .now)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: today))
        let current = snapshot(from: today, to: today, items: [item("today", on: today)])
        let future = snapshot(from: tomorrow, to: tomorrow, items: [item("tomorrow", on: tomorrow)])

        #expect(NextPlannedExpenseWidgetSnapshot.merging([current, future], asOf: today, calendar: calendar) == nil)
    }

    private func snapshot(
        from start: Date,
        to end: Date,
        items: [NextPlannedExpenseWidgetSnapshot.Item]
    ) -> NextPlannedExpenseWidgetSnapshot {
        .init(title: "Next Planned Expense", periodToken: "P", rangeStart: start, rangeEnd: end, items: items)
    }

    private func item(_ id: String, on date: Date) -> NextPlannedExpenseWidgetSnapshot.Item {
        .init(
            expenseID: id,
            expenseTitle: id,
            cardName: "Card",
            cardThemeToken: "ruby",
            cardEffectToken: "plastic",
            expenseDate: date,
            plannedAmount: 25,
            actualAmount: 0
        )
    }
}
