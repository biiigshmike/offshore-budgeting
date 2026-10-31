import Foundation

enum AllocationAccountSelectionPolicy {
    /// Keep a historical account selectable while editing its existing expense.
    /// Archived accounts are otherwise unavailable for new reconciliation actions.
    static func selectableAccounts(
        from accounts: [AllocationAccount],
        workspaceID: UUID,
        linkedAccountIDs: Set<UUID>
    ) -> [AllocationAccount] {
        accounts.filter {
            $0.workspace?.id == workspaceID
                && (!$0.isArchived || linkedAccountIDs.contains($0.id))
        }
    }
}
