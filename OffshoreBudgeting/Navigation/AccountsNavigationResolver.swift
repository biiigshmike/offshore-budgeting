import Foundation

/// Explicit Accounts navigation bypasses the overview. Ordinary tab/sidebar
/// selection starts at the overview without manufacturing a stored request.
enum AccountsNavigationResolver {
    static func destination(
        pendingSegmentRaw: String,
        queuedDestination: AccountsView.Segment?,
        pendingActionRaw: String
    ) -> AccountsView.Segment {
        AccountsView.Segment(pendingSegmentRaw: pendingSegmentRaw.trimmingCharacters(in: .whitespacesAndNewlines))
            ?? queuedDestination
            ?? AccountsView.Segment(pendingActionRaw: pendingActionRaw)
            ?? .cards
    }
}
