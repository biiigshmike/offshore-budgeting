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
