import SwiftUI

struct AccountsView: View {

    enum Segment: String, CaseIterable, Identifiable {
        case cards = "Cards"
        case sharedBalances = "Shared Balances"
        case savings = "Savings"

        var id: String { rawValue }
    }

    let workspace: Workspace

    @State private var selectedSegment: Segment = .cards
    @Environment(\.appCommandHub) private var commandHub

    // MARK: - View

    var body: some View {
        Group {
            switch selectedSegment {
            case .cards:
                CardsView(workspace: workspace)
            case .sharedBalances:
                AllocationAccountView(workspace: workspace)
            case .savings:
                SavingsAccountView(workspace: workspace)
            }
        }
        .navigationTitle("Accounts")
        .navigationBarTitleDisplayMode(.inline)
        .modifier(AccountsSegmentControlModifier(selectedSegment: $selectedSegment))
        .onAppear {
            updateCommandSurface()
        }
        .onChange(of: selectedSegment) { _, _ in
            updateCommandSurface()
        }
        .onDisappear {
            commandHub.deactivate(.cards)
        }
    }

    // MARK: - Commands

    private func updateCommandSurface() {
        switch selectedSegment {
        case .cards:
            commandHub.activate(.cards)
            commandHub.setCardsSortContext(.cards)
        case .sharedBalances:
            commandHub.activate(.cards)
            commandHub.setCardsSortContext(.sharedBalances)
        case .savings:
            commandHub.deactivate(.cards)
        }
    }
}

// MARK: - Segment Control Placement

private struct AccountsSegmentControlModifier: ViewModifier {
    @Binding var selectedSegment: AccountsView.Segment

    func body(content: Content) -> some View {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            content
                .safeAreaBar(edge: .top) {
                    segmentPicker
                }
        } else {
            content
                .safeAreaInset(edge: .top) {
                    segmentPicker
                }
        }
    }

    private var segmentPicker: some View {
        Picker("Section", selection: $selectedSegment) {
            Text("Cards").tag(AccountsView.Segment.cards)
            Text("Shared Balances").tag(AccountsView.Segment.sharedBalances)
            Text("Savings").tag(AccountsView.Segment.savings)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom)
    }
}
