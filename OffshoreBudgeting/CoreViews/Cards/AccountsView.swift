import SwiftUI

struct AccountsView: View {

    enum Segment: String, CaseIterable, Identifiable {
        case cards = "Cards"
        case sharedBalances = "Reconciliations"
        case savings = "Savings"

        var id: String { rawValue }

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

        var tint: Color {
            switch self {
            case .cards:
                return .blue
            case .sharedBalances:
                return .orange
            case .savings:
                return .green
            }
        }
    }

    let workspace: Workspace

    @State private var selectedSegment: Segment = .cards
    @State private var isSegmentControlExpanded: Bool = false
    @Namespace private var glassNamespace

    @AppStorage("sort.cards.mode") private var cardsSortModeRaw: String = "az"
    @AppStorage("sort.sharedBalances.mode") private var sharedBalancesSortModeRaw: String = "az"

    @Environment(\.appCommandHub) private var commandHub

    private var isPhone: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var shouldSyncCommandSurface: Bool {
        isPhone == false
    }

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
        .navigationTitle(navigationTitleText)
        .toolbar {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    AccountsGlassSegmentControl(
                        selectedSegment: $selectedSegment,
                        isExpanded: $isSegmentControlExpanded,
                        namespace: glassNamespace
                    )
                }

                ToolbarSpacer(.fixed, placement: .primaryAction)

                ToolbarItemGroup(placement: .primaryAction) {
                    sortToolbarButton
                }

                ToolbarSpacer(.flexible, placement: .primaryAction)

                ToolbarItemGroup(placement: .primaryAction) {
                    addToolbarButton
                }
            } else {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    segmentMenuPicker
                    sortToolbarButton
                    addToolbarButton
                }
            }
        }
        .onAppear {
            updateCommandSurface()
        }
        .onChange(of: selectedSegment) { _, _ in
            if isSegmentControlExpanded {
                isSegmentControlExpanded = false
            }
            updateCommandSurface()
        }
        .onDisappear {
            if shouldSyncCommandSurface {
                commandHub.deactivate(.cards)
            }
        }
    }

    // MARK: - Commands

    private func updateCommandSurface() {
        guard shouldSyncCommandSurface else { return }

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

    @ViewBuilder
    private var addToolbarButton: some View {
        Button {
            switch selectedSegment {
            case .cards, .sharedBalances:
                commandHub.dispatch(AppCommandID.Cards.newCard)
            case .savings:
                commandHub.dispatch(AppCommandID.Savings.newEntry)
            }
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(addButtonAccessibilityLabel)
    }

    @ViewBuilder
    private var sortToolbarButton: some View {
        switch selectedSegment {
        case .cards:
            Menu {
                sortMenuButton(
                    title: "A-Z",
                    isSelected: cardsSortModeRaw == "az",
                    commandID: AppCommandID.Cards.sortAZ
                )
                sortMenuButton(
                    title: "Z-A",
                    isSelected: cardsSortModeRaw == "za",
                    commandID: AppCommandID.Cards.sortZA
                )
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
        case .sharedBalances:
            Menu {
                sortMenuButton(
                    title: "A-Z",
                    isSelected: sharedBalancesSortModeRaw == "az",
                    commandID: AppCommandID.SharedBalances.sortAZ
                )
                sortMenuButton(
                    title: "Z-A",
                    isSelected: sharedBalancesSortModeRaw == "za",
                    commandID: AppCommandID.SharedBalances.sortZA
                )
                sortMenuButton(
                    title: "$ \u{2191}",
                    isSelected: sharedBalancesSortModeRaw == "amountAsc",
                    commandID: AppCommandID.SharedBalances.sortAmountAsc
                )
                sortMenuButton(
                    title: "$ \u{2193}",
                    isSelected: sharedBalancesSortModeRaw == "amountDesc",
                    commandID: AppCommandID.SharedBalances.sortAmountDesc
                )
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel("Sort")
        case .savings:
            Button {
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .disabled(true)
            .accessibilityLabel("Sort Unavailable")
        }
    }

    private var segmentMenuPicker: some View {
        Menu {
            ForEach(Segment.allCases) { segment in
                Button {
                    selectedSegment = segment
                } label: {
                    HStack {
                        Text(segment.rawValue)
                        if selectedSegment == segment {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(selectedSegment.rawValue)
        }
        .accessibilityLabel("Section")
    }

    private func sortMenuButton(title: String, isSelected: Bool, commandID: String) -> some View {
        Button {
            commandHub.dispatch(commandID)
        } label: {
            HStack {
                Text(title)
                if isSelected {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private var addButtonAccessibilityLabel: String {
        switch selectedSegment {
        case .cards:
            return "Add Card"
        case .sharedBalances:
            return "Add Reconciliation"
        case .savings:
            return "Add Savings Entry"
        }
    }

    private var navigationTitleText: String {
        selectedSegment.rawValue
    }
}

// MARK: - Glass Segment Control

@available(iOS 26.0, macCatalyst 26.0, *)
private struct AccountsGlassSegmentControl: View {
    @Binding var selectedSegment: AccountsView.Segment
    @Binding var isExpanded: Bool

    let namespace: Namespace.ID

    var body: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                if isExpanded {
                    ForEach(orderedSegments) { segment in
                        segmentButton(for: segment)
                    }
                } else {
                    segmentButton(for: selectedSegment)
                }
            }
            .animation(.smooth, value: isExpanded)
        }
    }

    private var orderedSegments: [AccountsView.Segment] {
        AccountsView.Segment.allCases
    }

    private func segmentButton(for segment: AccountsView.Segment) -> some View {
        Button {
            if isExpanded {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    isExpanded = false
                }

                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    selectedSegment = segment
                }
            } else {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    isExpanded = true
                }
            }
        } label: {
            Image(systemName: segment.symbolName)
                .font(.headline.weight(.semibold))
                .foregroundStyle(segment.tint)
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .contentShape(.capsule)
        }
        .glassEffectID(segment.id, in: namespace)
        .glassEffectTransition(.matchedGeometry)
        .accessibilityLabel(segment.rawValue)
    }
}
