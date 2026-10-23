import Foundation
import Testing
@testable import Offshore

@MainActor
struct DateRangeEditorDraftTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    private func date(_ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test func sameDayRangeIsValidRegardlessOfTimeComponents() {
        let draft = DateRangeEditorDraft(startDate: date(10, 22, hour: 23), endDate: date(10, 22, hour: 0))
        #expect(draft.isValid(calendar: calendar))
    }

    @Test func reversedDatesCannotBeApplied() {
        var draft = DateRangeEditorDraft(startDate: date(10, 22), endDate: date(10, 21))
        #expect(!draft.isValid(calendar: calendar))
        draft.endDate = date(10, 23)
        #expect(draft.isValid(calendar: calendar))
    }

    @Test func rangesAcrossDaylightSavingChangesAreValid() {
        let spring = DateRangeEditorDraft(startDate: date(3, 7), endDate: date(3, 9))
        let fall = DateRangeEditorDraft(startDate: date(10, 31), endDate: date(11, 2))
        #expect(spring.isValid(calendar: calendar))
        #expect(fall.isValid(calendar: calendar))
    }

    @Test func editingLocalCopyLeavesPresentationSeedUnchanged() {
        let seed = DateRangeEditorDraft(startDate: date(10, 1), endDate: date(10, 31))
        var localDraft = seed
        localDraft.startDate = date(10, 10)
        localDraft.endDate = date(10, 20)
        #expect(seed.startDate == date(10, 1))
        #expect(seed.endDate == date(10, 31))
    }
}
