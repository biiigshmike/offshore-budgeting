import SwiftUI

extension View {
    /// Keeps the native context menu and both swipe edges backed by the same actions.
    func rowActions<Leading: View, Trailing: View>(
        allowsFullLeadingSwipe: Bool = true,
        allowsFullTrailingSwipe: Bool = true,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let leadingActions = leading()
        let trailingActions = trailing()

        return contextMenu {
            leadingActions
            trailingActions
        }
        .swipeActions(edge: .leading, allowsFullSwipe: allowsFullLeadingSwipe) {
            leadingActions
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullTrailingSwipe) {
            trailingActions
        }
    }

    func rowActions<Trailing: View>(
        allowsFullTrailingSwipe: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        let trailingActions = trailing()

        return contextMenu {
            trailingActions
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: allowsFullTrailingSwipe) {
            trailingActions
        }
    }
}
