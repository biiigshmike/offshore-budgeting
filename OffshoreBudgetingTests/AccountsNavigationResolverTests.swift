import Testing
@testable import Offshore

struct AccountsNavigationResolverTests {
    @Test func explicitSavingsRequestWinsOverEarlierCardsAction() {
        let destination = AccountsNavigationResolver.destination(
            pendingSegmentRaw: "savings",
            queuedDestination: .cards,
            pendingActionRaw: AppShortcutNavigationStore.PendingAction.openQuickAddExpense.rawValue
        )
        #expect(destination == .savings)
    }

    @Test func queuedRequestSurvivesClearingTheSharedStoreKey() {
        #expect(AccountsNavigationResolver.destination(
            pendingSegmentRaw: "", queuedDestination: .sharedBalances, pendingActionRaw: ""
        ) == .sharedBalances)
    }

    @Test func cardActionsBypassTheOverviewAndIncomeActionsDoNotClaimCards() {
        for action in [AppShortcutNavigationStore.PendingAction.openCardImportReview,
                       .openQuickAddExpense, .openQuickAddExpenseFromShoppingMode] {
            #expect(AccountsView.Segment(pendingActionRaw: action.rawValue) == .cards)
        }
        #expect(AccountsView.Segment(pendingActionRaw: AppShortcutNavigationStore.PendingAction.openQuickAddIncome.rawValue) == nil)
        #expect(AccountsView.Segment(pendingActionRaw: AppShortcutNavigationStore.PendingAction.openIncomeImportReview.rawValue) == nil)
    }

    @Test func legacySectionOnlyAndInvalidRequestsKeepExistingCardsDestination() {
        #expect(AccountsNavigationResolver.destination(
            pendingSegmentRaw: "", queuedDestination: nil, pendingActionRaw: ""
        ) == .cards)
        #expect(AccountsNavigationResolver.destination(
            pendingSegmentRaw: "unknown", queuedDestination: nil, pendingActionRaw: "unknown"
        ) == .cards)
        #expect(AccountsNavigationResolver.destination(
            pendingSegmentRaw: " shared_balances ", queuedDestination: nil, pendingActionRaw: ""
        ) == .sharedBalances)
    }
}
