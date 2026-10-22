import Foundation
import Testing
@testable import Offshore

struct DateRangeDraftTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ day: Int, hour: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func unchangedCalendarDaysCannotApplyDespiteDifferentTimes() {
        var draft = DateRangeDraft(start: date(1), end: date(31, hour: 23), calendar: calendar)
        draft.start = date(1, hour: 12)
        draft.end = date(31)

        #expect(draft.isValid)
        #expect(!draft.canApply)
    }

    @Test func reversedDatesCannotApply() {
        var draft = DateRangeDraft(start: date(1), end: date(31), calendar: calendar)
        draft.start = date(20)
        draft.end = date(19)

        #expect(!draft.isValid)
        #expect(!draft.canApply)
    }

    @Test func changedSameDayRangeCanApplyEvenWithReversedTimes() {
        var draft = DateRangeDraft(start: date(1), end: date(31), calendar: calendar)
        draft.start = date(15, hour: 23)
        draft.end = date(15)

        #expect(draft.isValid)
        #expect(draft.canApply)
    }

    @Test func quickRangeChangesDraftWithoutChangingOriginals() {
        var draft = DateRangeDraft(start: date(1), end: date(31), calendar: calendar)
        let originalStart = draft.originalStart
        let originalEnd = draft.originalEnd
        draft.select(.today, now: date(15, hour: 12))

        #expect(calendar.isDate(draft.start, inSameDayAs: date(15)))
        #expect(calendar.isDate(draft.end, inSameDayAs: date(15)))
        #expect(draft.originalStart == originalStart)
        #expect(draft.originalEnd == originalEnd)
        #expect(draft.canApply)
    }

    @Test func selectingOriginalQuickRangeLeavesApplyDisabled() {
        let range = CalendarQuickRangePreset.currentMonth.makeRange(now: date(15), calendar: calendar)
        var draft = DateRangeDraft(start: range.start, end: range.end, calendar: calendar)
        draft.select(.today, now: date(15))
        #expect(draft.canApply)
        draft.select(.currentMonth, now: date(15))
        #expect(!draft.canApply)
    }

    @Test func reopeningWithAppliedDatesStartsClean() {
        var draft = DateRangeDraft(start: date(1), end: date(31), calendar: calendar)
        draft.select(.today, now: date(15))
        let reopened = DateRangeDraft(start: draft.start, end: draft.end, calendar: calendar)

        #expect(reopened.isValid)
        #expect(!reopened.canApply)
    }

    @Test func discardingDraftLeavesOriginalRangeAvailableForReopening() {
        var draft = DateRangeDraft(start: date(1), end: date(31), calendar: calendar)
        draft.select(.nextMonth, now: date(15))
        let reopened = DateRangeDraft(start: draft.originalStart, end: draft.originalEnd, calendar: calendar)

        #expect(reopened.start == date(1))
        #expect(reopened.end == date(31))
        #expect(!reopened.canApply)
    }
}
