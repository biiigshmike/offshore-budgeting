import Foundation
import Testing
@testable import Offshore

struct DefaultBudgetingPeriodTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func legacyWeeklyUsesCalendarWeekAndRoundTrips() {
        let date = day(2026, 3, 8)
        let period = DefaultBudgetingPeriod(rawValue: "weekly")
        #expect(period.weeklyInterval == 1)
        #expect(period.rawValue == "weekly")
        let range = period.defaultRange(containing: date, calendar: calendar)
        #expect(range.start == day(2026, 3, 2))
        #expect(range.end == date)
        #expect(DefaultBudgetingPeriod(rawValue: "weekly:53").rawValue == "weekly")
        #expect(DefaultBudgetingPeriod(rawValue: "quarterly").period == .quarterly)
        #expect(DefaultBudgetingPeriod(rawValue: nil).period == .monthly)
    }

    @Test(arguments: [
        (1999, 12, 31, 1999, 12, 20),
        (2000, 1, 3, 2000, 1, 3),
        (2025, 12, 31, 2025, 12, 29),
        (2026, 3, 8, 2026, 2, 23)
    ])
    func twoWeekRangesAreConsecutive(
        _ sample: (year: Int, month: Int, day: Int, startYear: Int, startMonth: Int, startDay: Int)
    ) throws {
        let selection = DefaultBudgetingPeriod(.weekly, weeklyInterval: 2)
        #expect(selection.rawValue == "weekly:2")
        let period = DefaultBudgetingPeriod(rawValue: selection.rawValue)
        let date = day(sample.year, sample.month, sample.day)
        let range = period.defaultRange(containing: date, calendar: calendar)
        #expect(range.start == day(sample.startYear, sample.startMonth, sample.startDay))
        #expect(calendar.dateComponents([.day], from: range.start, to: range.end).day == 13)

        let nextDay = try #require(calendar.date(byAdding: .day, value: 1, to: range.end))
        let clockChangeRange = period.defaultRange(containing: nextDay, calendar: calendar)
        #expect(clockChangeRange.start == nextDay)
        #expect(calendar.dateComponents([.day], from: nextDay, to: clockChangeRange.end).day == 13)
        let lastDay = period.defaultRange(containing: range.end, calendar: calendar)
        #expect(lastDay.start == range.start)
        #expect(lastDay.end == range.end)
    }

    @MainActor
    @Test func homeAndSavingsAccountUseTheSameTwoWeeks() {
        let now = day(2025, 12, 31)
        let home = HomeViewBootstrap.canonicalAppliedRangeSeed(
            defaultBudgetingPeriodRaw: "weekly:2", now: now, calendar: calendar
        )
        let savings = SavingsGraphSnapshotService.defaultRange(
            defaultBudgetingPeriodRaw: "weekly:2", now: now, calendar: calendar
        )
        #expect(home.start == day(2025, 12, 29))
        #expect(home.end == day(2026, 1, 11))
        #expect(home.lastSyncedDefaultBudgetingPeriodRaw == "weekly:2")
        #expect(home.start == savings.start)
        #expect(home.end == calendar.startOfDay(for: savings.end))
    }

    @Test func multiWeekStartsOnConfiguredFirstWeekday() {
        var calendar = calendar
        calendar.firstWeekday = 1
        let period = DefaultBudgetingPeriod(.weekly, weeklyInterval: 2)
        let range = period.defaultRange(containing: day(2000, 1, 3), calendar: calendar)
        #expect(range.start == day(2000, 1, 2))
        #expect(range.end == day(2000, 1, 15))
    }
}
