import SwiftUI

struct AccountsView: View {

    enum Segment: String, CaseIterable, Identifiable, Hashable {
        case cards
        case sharedBalances
        case savings

        var id: String { rawValue }

        var title: String {
            switch self {
            case .cards:
                return String(localized: "accounts.segment.cards", defaultValue: "Cards", comment: "Accounts section segment for cards.")
            case .sharedBalances:
                return String(localized: "accounts.segment.reconciliations", defaultValue: "Reconciliations", comment: "Accounts section segment for reconciliations.")
            case .savings:
                return String(localized: "accounts.segment.savings", defaultValue: "Offshore Savings", comment: "Accounts section segment for Offshore Savings.")
            }
        }

        var symbolName: String {
            switch self {
            case .cards:
                return "creditcard.fill"
            case .sharedBalances:
                return "person.2.fill"
            case .savings:
                return "banknote.fill"
            }
        }

    }

    let workspace: Workspace
    @Binding var selectedDestination: Segment?

    var body: some View {
        Group {
            if let destination = selectedDestination {
                AccountsDestinationView(
                    workspace: workspace,
                    initialSegment: destination,
                    directSelection: $selectedDestination
                )
            } else {
                AccountsOverviewView()
            }
        }
        .navigationTitle(selectedDestination?.title ?? String(localized: "app.section.cards", defaultValue: "Accounts", comment: "Main tab title for the Accounts section."))
        .navigationDestination(for: Segment.self) { destination in
            AccountsDestinationView(workspace: workspace, initialSegment: destination)
        }
    }
}

struct AccountsSegmentCommandConfiguration: Equatable {
    let surface: AppCommandSurface
    let cardsSortContext: AppCardsSortCommandContext?
}

enum AccountsPhoneSortTarget: Equatable {
    case cards(String)
    case sharedBalances(String)
    case savings(String)

    static func target(for commandID: String) -> AccountsPhoneSortTarget? {
        switch commandID {
        case AppCommandID.Cards.sortAZ:
            return .cards("az")
        case AppCommandID.Cards.sortZA:
            return .cards("za")
        case AppCommandID.SharedBalances.sortAZ:
            return .sharedBalances("az")
        case AppCommandID.SharedBalances.sortZA:
            return .sharedBalances("za")
        case AppCommandID.SharedBalances.sortAmountAsc:
            return .sharedBalances("amountAsc")
        case AppCommandID.SharedBalances.sortAmountDesc:
            return .sharedBalances("amountDesc")
        case AppCommandID.Savings.sortAZ:
            return .savings(SavingsLedgerSortMode.az.rawValue)
        case AppCommandID.Savings.sortZA:
            return .savings(SavingsLedgerSortMode.za.rawValue)
        case AppCommandID.Savings.sortAmountAsc:
            return .savings(SavingsLedgerSortMode.amountAsc.rawValue)
        case AppCommandID.Savings.sortAmountDesc:
            return .savings(SavingsLedgerSortMode.amountDesc.rawValue)
        case AppCommandID.Savings.sortDateAsc:
            return .savings(SavingsLedgerSortMode.dateAsc.rawValue)
        case AppCommandID.Savings.sortDateDesc:
            return .savings(SavingsLedgerSortMode.dateDesc.rawValue)
        default:
            return nil
        }
    }
}

extension AccountsView.Segment {
    var commandConfiguration: AccountsSegmentCommandConfiguration {
        switch self {
        case .cards:
            return AccountsSegmentCommandConfiguration(
                surface: .cards,
                cardsSortContext: .cards
            )
        case .sharedBalances:
            return AccountsSegmentCommandConfiguration(
                surface: .cards,
                cardsSortContext: .sharedBalances
            )
        case .savings:
            return AccountsSegmentCommandConfiguration(
                surface: .savings,
                cardsSortContext: nil
            )
        }
    }

    init?(pendingSegmentRaw: String) {
        switch pendingSegmentRaw {
        case AppShortcutNavigationStore.PendingAccountsSegment.cards.rawValue:
            self = .cards
        case AppShortcutNavigationStore.PendingAccountsSegment.sharedBalances.rawValue:
            self = .sharedBalances
        case AppShortcutNavigationStore.PendingAccountsSegment.savings.rawValue:
            self = .savings
        default:
            return nil
        }
    }

    init?(pendingActionRaw: String) {
        switch AppShortcutNavigationStore.PendingAction(rawValue: pendingActionRaw) {
        case .openCardImportReview, .openQuickAddExpense, .openQuickAddExpenseFromShoppingMode:
            self = .cards
        case .openIncomeImportReview, .openQuickAddIncome, nil:
            return nil
        }
    }
}
