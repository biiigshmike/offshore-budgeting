import Foundation
import Testing
@testable import Offshore

@MainActor
struct MacMarinaToolbarStateTests {
    @Test func disappearingOldPanelCannotClearCurrentActions() {
        let state = MacMarinaToolbarState()
        let oldOwner = UUID()
        let newOwner = UUID()
        var invoked = false
        state.publish(owner: oldOwner, creation: [], management: [])
        state.publish(owner: newOwner, creation: [
            MarinaToolbarAction(id: "history", title: "History", systemImage: "clock", perform: { invoked = true })
        ], management: [])

        state.clear(owner: oldOwner)

        #expect(state.owner == newOwner)
        state.creation.first?.perform()
        #expect(invoked)
    }

    @Test func republishingReplacesAvailabilityAndActions() {
        let state = MacMarinaToolbarState()
        let owner = UUID()
        var selectedSession = ""
        state.publish(owner: owner, creation: [], management: [
            MarinaToolbarAction(id: "rename", title: "Rename", systemImage: "pencil", isEnabled: false, perform: {})
        ])
        #expect(state.management.first?.isEnabled == false)

        state.publish(owner: owner, creation: [], management: [
            MarinaToolbarAction(id: "rename", title: "Rename", systemImage: "pencil", perform: { selectedSession = "new" })
        ])
        #expect(state.management.count == 1)
        #expect(state.management.first?.isEnabled == true)
        state.management.first?.perform()
        #expect(selectedSession == "new")
    }

    @Test func dismissalClearsActionsAndOwner() {
        let state = MacMarinaToolbarState()
        state.publish(owner: UUID(), creation: [
            MarinaToolbarAction(id: "new", title: "New", systemImage: "plus", perform: {})
        ], management: [])

        state.clear()

        #expect(state.owner == nil)
        #expect(state.creation.isEmpty)
        #expect(state.management.isEmpty)
    }
}
