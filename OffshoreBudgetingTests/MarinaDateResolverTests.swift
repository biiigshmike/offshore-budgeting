//
//  MarinaDateResolverTests.swift
//  OffshoreBudgetingTests
//
//  Created by OpenAI Codex on 4/15/26.
//

import Foundation
import Testing
@testable import Offshore

struct MarinaDateResolverTests {
    @Test func resolveRelativeRange_lastWeek_returnsPreviousFullWeek() throws {
        let resolver = makeResolver(now: date(2026, 4, 15, 12, 0, 0))

        let range = resolver.resolveRelativeRange("last week", now: date(2026, 4, 15, 12, 0, 0))

        #expect(range?.start == date(2026, 4, 6, 0, 0, 0))
        #expect(range?.end == date(2026, 4, 12, 23, 59, 59))
    }

    @Test func resolveRelativeRange_thisMonth_returnsFullCurrentMonth() throws {
        let resolver = makeResolver(now: date(2026, 4, 15, 12, 0, 0))

        let range = resolver.resolveRelativeRange("this month", now: date(2026, 4, 15, 12, 0, 0))

        #expect(range?.start == date(2026, 4, 1, 0, 0, 0))
        #expect(range?.end == date(2026, 4, 30, 23, 59, 59))
    }

    @Test func resolveExplicitRange_aprilRange2026_returnsInclusiveBounds() throws {
        let resolver = makeResolver(now: date(2026, 4, 15, 12, 0, 0))

        let range = resolver.resolveTextRange("April 1 through April 14 2026")

        #expect(range?.start == date(2026, 4, 1, 0, 0, 0))
        #expect(range?.end == date(2026, 4, 14, 23, 59, 59))
    }

    @Test func resolveExplicitRange_invalidInput_returnsNil() throws {
        let resolver = makeResolver(now: date(2026, 4, 15, 12, 0, 0))

        let range = resolver.resolveExplicitRange(start: "not-a-date", end: "still-not-a-date")

        #expect(range == nil)
    }

    @Test func resolve_modelISOWinsOverPromptText() throws {
        let resolver = makeResolver(now: date(2026, 4, 15, 12, 0, 0))

        let range = resolver.resolve(
            input: "What did I spend last week",
            modelStartISO8601: "2026-04-01",
            modelEndISO8601: "2026-04-14",
            defaultPeriodUnit: .month
        )

        #expect(range?.start == date(2026, 4, 1, 0, 0, 0))
        #expect(range?.end == date(2026, 4, 14, 23, 59, 59))
    }

    @Test func resolve_namedMonthWithoutYearUsesCurrentOrPriorYear() throws {
        let resolver = makeResolver(now: date(2026, 5, 15, 12, 0, 0))

        let may = resolver.resolveTextRange("spend in May")
        let december = resolver.resolveTextRange("spend in December")

        #expect(may?.start == date(2026, 5, 1, 0, 0, 0))
        #expect(may?.end == date(2026, 5, 31, 23, 59, 59))
        #expect(december?.start == date(2025, 12, 1, 0, 0, 0))
        #expect(december?.end == date(2025, 12, 31, 23, 59, 59))
    }

    @Test func resolve_currentPeriodUsesDefaultPeriodUnit() throws {
        let resolver = makeResolver(now: date(2026, 5, 15, 12, 0, 0))

        let range = resolver.resolve(
            input: "active period",
            modelStartISO8601: nil,
            modelEndISO8601: nil,
            defaultPeriodUnit: .quarter
        )

        #expect(range?.start == date(2026, 4, 1, 0, 0, 0))
        #expect(range?.end == date(2026, 6, 30, 23, 59, 59))
    }

    @Test func resolve_explicitISODateTimeRangeReturnsInclusiveDays() throws {
        let resolver = makeResolver(now: date(2026, 5, 15, 12, 0, 0))

        let range = resolver.resolve(
            input: "ignored",
            modelStartISO8601: "2026-05-01T10:30:00Z",
            modelEndISO8601: "2026-05-14T18:45:00Z",
            defaultPeriodUnit: .month
        )

        #expect(range?.start == date(2026, 5, 1, 0, 0, 0))
        #expect(range?.end == date(2026, 5, 14, 23, 59, 59))
    }

    private func makeResolver(now: Date) -> MarinaDateResolver {
        MarinaDateResolver(
            calendar: calendar,
            nowProvider: { now }
        )
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: components) ?? .distantPast
    }
}
