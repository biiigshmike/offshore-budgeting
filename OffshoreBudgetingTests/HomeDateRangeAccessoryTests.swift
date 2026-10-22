import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeDateRangeAccessoryTests {
    @Test func registrationUpdatesWorkspaceDatesAndApplyAction() {
        let accessory = HomeDateRangeAccessory()
        let ownerID = UUID()
        let firstWorkspace = UUID()
        let secondWorkspace = UUID()
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)
        var firstCalls = 0
        var appliedStart: Date?
        var appliedEnd: Date?
        accessory.register(ownerID: ownerID, workspaceID: firstWorkspace, start: start, end: end) { _, _ in
            firstCalls += 1
        }
        accessory.register(ownerID: ownerID, workspaceID: secondWorkspace, start: end, end: end) { start, end in
            appliedStart = start
            appliedEnd = end
        }
        accessory.apply(start, end)

        #expect(accessory.workspaceID == secondWorkspace)
        #expect(accessory.ownerID == ownerID)
        #expect(accessory.startDate == end)
        #expect(accessory.endDate == end)
        #expect(firstCalls == 0)
        #expect(appliedStart == start)
        #expect(appliedEnd == end)
    }

    @Test func staleOwnerCannotClearNewRegistration() {
        let accessory = HomeDateRangeAccessory()
        let oldOwner = UUID()
        let currentOwner = UUID()
        let currentWorkspace = UUID()
        let date = Date(timeIntervalSince1970: 1_000)
        var applyCount = 0
        accessory.register(ownerID: oldOwner, workspaceID: UUID(), start: date, end: date) { _, _ in }
        accessory.register(ownerID: currentOwner, workspaceID: currentWorkspace, start: date, end: date) { _, _ in
            applyCount += 1
        }
        accessory.clear(ownerID: oldOwner)
        accessory.apply(date, date)

        #expect(accessory.ownerID == currentOwner)
        #expect(accessory.workspaceID == currentWorkspace)
        #expect(applyCount == 1)
    }

    @Test func clearingCurrentOwnerRemovesWorkspaceAndAction() {
        let accessory = HomeDateRangeAccessory()
        let owner = UUID()
        let date = Date(timeIntervalSince1970: 1_000)
        var applyCount = 0
        accessory.register(ownerID: owner, workspaceID: UUID(), start: date, end: date) { _, _ in
            applyCount += 1
        }
        accessory.clear(ownerID: owner)
        accessory.apply(date, date)

        #expect(accessory.ownerID == nil)
        #expect(accessory.workspaceID == nil)
        #expect(applyCount == 0)
    }
}
