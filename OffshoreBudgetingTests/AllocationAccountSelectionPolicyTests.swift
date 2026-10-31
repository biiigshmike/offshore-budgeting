import Foundation
import Testing
@testable import Offshore

@MainActor
struct AllocationAccountSelectionPolicyTests {
    @Test func preservesLinkedArchivedAccountsWithoutOfferingOtherArchivedAccounts() {
        let workspace = Workspace(name: "Personal", hexColor: "#123456")
        let active = AllocationAccount(name: "Active", hexColor: "#123456", workspace: workspace)
        let linked = AllocationAccount(name: "Linked", hexColor: "#123456", workspace: workspace)
        let archived = AllocationAccount(name: "Other", hexColor: "#123456", workspace: workspace)
        linked.isArchived = true
        archived.isArchived = true

        let accounts = AllocationAccountSelectionPolicy.selectableAccounts(
            from: [active, linked, archived], workspaceID: workspace.id, linkedAccountIDs: [linked.id]
        )
        #expect(accounts.map(\.id) == [active.id, linked.id])
        #expect(linked.isArchived)
    }

    @Test func linkedIDsNeverPermitAnAccountFromAnotherWorkspace() {
        let personal = Workspace(name: "Personal", hexColor: "#123456")
        let work = Workspace(name: "Work", hexColor: "#123456")
        let foreign = AllocationAccount(name: "Shared name", hexColor: "#123456", workspace: work)
        let accounts = AllocationAccountSelectionPolicy.selectableAccounts(
            from: [foreign], workspaceID: personal.id, linkedAccountIDs: [foreign.id]
        )
        #expect(accounts.isEmpty)
    }
}
