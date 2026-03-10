import SwiftUI

struct AccountsView: View {

    enum Segment: String, CaseIterable, Identifiable {
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
                return String(localized: "accounts.segment.savings", defaultValue: "Savings", comment: "Accounts section segment for savings.")
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
    @State private var showingAddCardFromAccounts: Bool = false
    @State private var showingAddAllocationAccountFromAccounts: Bool = false
    @Namespace private var glassNamespace

    @AppStorage("sort.cards.mode") private var cardsSortModeRaw: String = "az"
    @AppStorage("sort.sharedBalances.mode") private var sharedBalancesSortModeRaw: String = "az"
    @AppStorage("sort.savings.mode") private var savingsSortModeRaw: String = SavingsLedgerSortMode.dateDesc.rawValue
    @AppStorage(AppShortcutNavigationStore.pendingAccountsSegmentKey) private var pendingAccountsSegmentRaw: String = ""

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
        .sheet(isPresented: $showingAddCardFromAccounts) {
            NavigationStack {
                AddCardView(workspace: workspace)
            }
        }
        .sheet(isPresented: $showingAddAllocationAccountFromAccounts) {
            NavigationStack {
                AddAllocationAccountView(workspace: workspace)
            }
        }
        .onAppear {
            consumePendingAccountsSegmentIfNeeded()
            updateCommandSurface()
        }
        .onChange(of: pendingAccountsSegmentRaw) { _, _ in
            consumePendingAccountsSegmentIfNeeded()
        }
        .onChange(of: selectedSegment) { _, _ in
            if isSegmentControlExpanded {
                isSegmentControlExpanded = false
            }
            updateCommandSurface()
        }
        .onDisappear {
            if shouldSyncCommandSurface {
                switch selectedSegment {
                case .cards, .sharedBalances:
                    commandHub.deactivate(.cards)
                case .savings:
                    commandHub.deactivate(.savings)
                }
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
            commandHub.activate(.savings)
        }
    }

    private func consumePendingAccountsSegmentIfNeeded() {
        let pending = pendingAccountsSegmentRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty else { return }

        if let segment = Segment(pendingSegmentRaw: pending) {
            selectedSegment = segment
        }

        pendingAccountsSegmentRaw = ""
    }

    @ViewBuilder
    private var addToolbarButton: some View {
        Button {
            switch selectedSegment {
            case .cards:
                if isPhone {
                    showingAddCardFromAccounts = true
                } else {
                    commandHub.dispatch(AppCommandID.Cards.newCard)
                }
            case .sharedBalances:
                if isPhone {
                    showingAddAllocationAccountFromAccounts = true
                } else {
                    commandHub.dispatch(AppCommandID.Cards.newCard)
                }
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
                    title: "A–Z",
                    isSelected: cardsSortModeRaw == "az",
                    commandID: AppCommandID.Cards.sortAZ
                )
                sortMenuButton(
                    title: "Z–A",
                    isSelected: cardsSortModeRaw == "za",
                    commandID: AppCommandID.Cards.sortZA
                )
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel(String(localized: "common.sort", defaultValue: "Sort", comment: "Accessibility label for sort actions."))
        case .sharedBalances:
            Menu {
                sortMenuButton(
                    title: "A–Z",
                    isSelected: sharedBalancesSortModeRaw == "az",
                    commandID: AppCommandID.SharedBalances.sortAZ
                )
                sortMenuButton(
                    title: "Z–A",
                    isSelected: sharedBalancesSortModeRaw == "za",
                    commandID: AppCommandID.SharedBalances.sortZA
                )
                sortMenuButton(
                    title: "$↑",
                    isSelected: sharedBalancesSortModeRaw == "amountAsc",
                    commandID: AppCommandID.SharedBalances.sortAmountAsc
                )
                sortMenuButton(
                    title: "$↓",
                    isSelected: sharedBalancesSortModeRaw == "amountDesc",
                    commandID: AppCommandID.SharedBalances.sortAmountDesc
                )
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel(String(localized: "common.sort", defaultValue: "Sort", comment: "Accessibility label for sort actions."))
        case .savings:
            Menu {
                sortMenuButton(
                    title: "A–Z",
                    isSelected: savingsSortModeRaw == SavingsLedgerSortMode.az.rawValue,
                    commandID: AppCommandID.Savings.sortAZ
                )
                sortMenuButton(
                    title: "Z–A",
                    isSelected: savingsSortModeRaw == SavingsLedgerSortMode.za.rawValue,
                    commandID: AppCommandID.Savings.sortZA
                )
                sortMenuButton(
                    title: "\(CurrencyFormatter.currencySymbol)↑",
                    isSelected: savingsSortModeRaw == SavingsLedgerSortMode.amountAsc.rawValue,
                    commandID: AppCommandID.Savings.sortAmountAsc
                )
                sortMenuButton(
                    title: "\(CurrencyFormatter.currencySymbol)↓",
                    isSelected: savingsSortModeRaw == SavingsLedgerSortMode.amountDesc.rawValue,
                    commandID: AppCommandID.Savings.sortAmountDesc
                )
                sortMenuButton(
                    title: String(localized: "Date ↑", defaultValue: "Date ↑", comment: "Ascending date sort label."),
                    isSelected: savingsSortModeRaw == SavingsLedgerSortMode.dateAsc.rawValue,
                    commandID: AppCommandID.Savings.sortDateAsc
                )
                sortMenuButton(
                    title: String(localized: "Date ↓", defaultValue: "Date ↓", comment: "Descending date sort label."),
                    isSelected: savingsSortModeRaw == SavingsLedgerSortMode.dateDesc.rawValue,
                    commandID: AppCommandID.Savings.sortDateDesc
                )
            } label: {
                Image(systemName: "arrow.up.arrow.down")
            }
            .accessibilityLabel(String(localized: "common.sort", defaultValue: "Sort", comment: "Accessibility label for sort actions."))
        }
    }

    private var segmentMenuPicker: some View {
        Menu {
            ForEach(Segment.allCases) { segment in
                Button {
                    selectedSegment = segment
                } label: {
                    HStack {
                        Text(segment.title)
                        if selectedSegment == segment {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Text(selectedSegment.title)
        }
        .accessibilityLabel(String(localized: "common.section", defaultValue: "Section", comment: "Accessibility label for section picker."))
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
            return String(localized: "accounts.addCard", defaultValue: "Add Card", comment: "Accessibility label for add card action.")
        case .sharedBalances:
            return String(localized: "accounts.addReconciliation", defaultValue: "Add Reconciliation", comment: "Accessibility label for add reconciliation action.")
        case .savings:
            return String(localized: "accounts.addSavingsEntry", defaultValue: "Add Savings Entry", comment: "Accessibility label for add savings entry action.")
        }
    }

    private var navigationTitleText: String {
        selectedSegment.title
    }
}

private extension AccountsView.Segment {
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
        .accessibilityLabel(segment.title)
    }
}
