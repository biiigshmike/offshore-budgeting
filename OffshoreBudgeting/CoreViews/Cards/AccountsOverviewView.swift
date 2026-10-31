import SwiftUI

/// The three account workflows share a workspace, but keep distinct balances.
struct AccountsOverviewView: View {
    var body: some View {
        List {
            Section {
                ForEach(AccountsView.Segment.allCases) { destination in
                    NavigationLink(value: destination) {
                        HStack(alignment: .center, spacing: 14) {
                            Image(systemName: destination.symbolName)
                                .font(.title2)
                                .foregroundStyle(.tint)
                                .frame(width: 34)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 5) {
                                Text(destination.title)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(destination.overviewDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 8)
                        }
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("accounts.destination.\(destination.rawValue)")
                }
            }
        }
        .listStyle(.insetGrouped)
        .postBoardingTip(
            key: "tip.cards.v1",
            title: "Accounts",
            items: [
                PostBoardingTipItem(
                    systemImage: "creditcard.fill",
                    title: "Cards",
                    detail: "Manage credit cards, checking accounts, or cash. Open a card to track spending, add expenses, and review its activity."
                ),
                PostBoardingTipItem(
                    systemImage: "person.2.fill",
                    title: "Reconciliations",
                    detail: "Use Reconciliations to track shared balances, split amounts, and settle up clearly."
                ),
                PostBoardingTipItem(
                    systemImage: "banknote.fill",
                    title: "Offshore Savings",
                    detail: "Use Offshore Savings to track money left over at the end of each budgeting period."
                )
            ]
        )
    }
}

extension AccountsView.Segment {
    var overviewDescription: LocalizedStringResource {
        switch self {
        case .cards:
            "Record spending and review activity for credit cards, checking accounts, or cash."
        case .sharedBalances:
            "Track what you owe and what you’re owed."
        case .savings:
            "Review leftover money available for future expenses."
        }
    }
}
