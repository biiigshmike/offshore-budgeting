import SwiftUI
import SwiftData

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
    @State private var mountedSegments: Set<Segment> = []
    @State private var stagingSegments: Set<Segment> = []
    @State private var isSegmentControlExpanded: Bool = false
    @State private var showingAddCardFromAccounts: Bool = false
    @State private var showingAddAllocationAccountFromAccounts: Bool = false
    @Namespace private var glassNamespace

    @AppStorage("sort.cards.mode") private var cardsSortModeRaw: String = "az"
    @AppStorage("sort.sharedBalances.mode") private var sharedBalancesSortModeRaw: String = "az"
    @AppStorage("sort.savings.mode") private var savingsSortModeRaw: String = SavingsLedgerSortMode.dateDesc.rawValue
    @AppStorage(AppShortcutNavigationStore.pendingAccountsSegmentKey) private var pendingAccountsSegmentRaw: String = ""

    @Environment(\.appTabActivationContext) private var tabActivationContext
    @Environment(\.appCommandHub) private var commandHub
    @Environment(\.modelContext) private var modelContext
    @Environment(DetailViewSnapshotCache.self) private var detailSnapshotCache

    @State private var savingsGraphWarmTask: Task<Void, Never>? = nil

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
            stagedSegmentContent
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
            requestPrepareSelectedSegment(reason: "onAppear")
            scheduleSavingsGraphWarmIfNeeded(reason: "onAppear")
            updateCommandSurface()
        }
        .onChange(of: pendingAccountsSegmentRaw) { _, _ in
            consumePendingAccountsSegmentIfNeeded()
        }
        .onChange(of: selectedSegment) { _, _ in
            if isSegmentControlExpanded {
                isSegmentControlExpanded = false
            }
            requestPrepareSelectedSegment(reason: "segmentChanged")
            scheduleSavingsGraphWarmIfNeeded(reason: "segmentChanged")
            updateCommandSurface()
        }
        .onChange(of: tabActivationContext) { _, newValue in
            guard newValue.sectionRawValue == AppSection.cards.rawValue else { return }
            if newValue.isVisible {
                requestPrepareSelectedSegment(reason: "tabPhaseChanged")
                scheduleSavingsGraphWarmIfNeeded(reason: "tabPhaseChanged")
            } else {
                cancelSavingsGraphWarm(reason: "tabPhaseChanged")
            }
        }
        .onDisappear {
            cancelSavingsGraphWarm(reason: "onDisappear")
            if shouldSyncCommandSurface {
                switch selectedSegment.commandConfiguration.surface {
                case .cards:
                    commandHub.deactivate(.cards)
                case .savings:
                    commandHub.deactivate(.savings)
                default:
                    break
                }
            }
        }
    }

    // MARK: - Commands

    @ViewBuilder
    private var stagedSegmentContent: some View {
        if mountedSegments.contains(selectedSegment) {
            switch selectedSegment {
            case .cards:
                CardsView(workspace: workspace)
            case .sharedBalances:
                AllocationAccountView(workspace: workspace)
            case .savings:
                SavingsAccountView(workspace: workspace)
            }
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }

    private func updateCommandSurface() {
        guard shouldSyncCommandSurface else { return }

        let configuration = selectedSegment.commandConfiguration

        commandHub.activate(configuration.surface)

        if let cardsSortContext = configuration.cardsSortContext {
            commandHub.setCardsSortContext(cardsSortContext)
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

    private func requestPrepareSelectedSegment(reason: String) {
        requestPrepareSegment(selectedSegment, reason: reason)
    }

    private func requestPrepareSegment(_ segment: Segment, reason: String) {
        guard segment == selectedSegment else {
            TabFlickerDiagnostics.markEvent(
                "accountsSegmentWarmPrevented",
                metadata: [
                    "segment": segment.rawValue,
                    "reason": "nonSelected:\(reason)"
                ]
            )
            return
        }

        if tabActivationContext.sectionRawValue == AppSection.cards.rawValue,
           tabActivationContext.phase == .inactive {
            TabFlickerDiagnostics.markEvent(
                "accountsSegmentWarmPrevented",
                metadata: [
                    "segment": segment.rawValue,
                    "reason": "inactiveTab:\(reason)"
                ]
            )
            return
        }

        prepareSegment(segment)
    }

    private func prepareSegment(_ segment: Segment) {
        guard mountedSegments.contains(segment) == false else { return }
        guard stagingSegments.contains(segment) == false else { return }

        stagingSegments.insert(segment)
        TabFlickerDiagnostics.markEvent(
            "accountsSegmentMountScheduled",
            metadata: ["segment": segment.rawValue]
        )
        DispatchQueue.main.async {
            mountedSegments.insert(segment)
            stagingSegments.remove(segment)
            TabFlickerDiagnostics.markEvent(
                "accountsSegmentMountActivated",
                metadata: ["segment": segment.rawValue]
            )
        }
    }

    private func scheduleSavingsGraphWarmIfNeeded(reason: String) {
        guard tabActivationContext.sectionRawValue == AppSection.cards.rawValue else { return }
        guard tabActivationContext.phase == .active else { return }
        guard selectedSegment != .savings else {
            cancelSavingsGraphWarm(reason: "savingsVisible")
            return
        }

        cancelSavingsGraphWarm(reason: "reschedule")
        let activationToken = tabActivationContext.token
        let defaultRange = SavingsGraphSnapshotService.defaultRange(
            defaultBudgetingPeriodRaw: UserDefaults.standard.string(forKey: "general_defaultBudgetingPeriod")
                ?? BudgetingPeriod.monthly.rawValue
        )

        TabFlickerDiagnostics.markEvent(
            "savingsGraphWarmScheduled",
            metadata: [
                "reason": reason,
                "token": String(activationToken)
            ]
        )

        savingsGraphWarmTask = Task {
            try? await Task.sleep(nanoseconds: 320_000_000)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                guard tabActivationContext.sectionRawValue == AppSection.cards.rawValue,
                      tabActivationContext.phase == .active,
                      tabActivationContext.token == activationToken,
                      selectedSegment != .savings else {
                    TabFlickerDiagnostics.markEvent(
                        "savingsGraphWarmCancelled",
                        metadata: [
                            "reason": reason,
                            "cancel": "activationChanged"
                        ]
                    )
                    return
                }

                let cacheKey = SavingsGraphSnapshotService.cacheKey(
                    workspaceID: workspace.id,
                    rangeStart: defaultRange.start,
                    rangeEnd: defaultRange.end
                )
                let existing: SavingsGraphSnapshot? = detailSnapshotCache.snapshot(for: cacheKey)
                let signature = SavingsGraphSnapshotService.signature(
                    for: workspace,
                    rangeStart: defaultRange.start,
                    rangeEnd: defaultRange.end,
                    modelContext: modelContext
                )

                guard existing?.signature != signature else { return }

                let snapshot = SavingsGraphSnapshotService.buildSnapshot(
                    for: workspace,
                    rangeStart: defaultRange.start,
                    rangeEnd: defaultRange.end,
                    modelContext: modelContext
                )
                detailSnapshotCache.store(snapshot, for: cacheKey)
                TabFlickerDiagnostics.markEvent("savingsGraphWarmFinished")
            }
        }
    }

    private func cancelSavingsGraphWarm(reason: String) {
        guard savingsGraphWarmTask != nil else { return }
        savingsGraphWarmTask?.cancel()
        savingsGraphWarmTask = nil
        TabFlickerDiagnostics.markEvent(
            "savingsGraphWarmCancelled",
            metadata: ["reason": reason]
        )
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
            handleSortSelection(commandID)
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

    private func handleSortSelection(_ commandID: String) {
        if isPhone, let phoneSortTarget = AccountsPhoneSortTarget.target(for: commandID) {
            applyPhoneSort(phoneSortTarget)
            return
        }

        commandHub.dispatch(commandID)
    }

    private func applyPhoneSort(_ target: AccountsPhoneSortTarget) {
        switch target {
        case .cards(let mode):
            cardsSortModeRaw = mode
        case .sharedBalances(let mode):
            sharedBalancesSortModeRaw = mode
        case .savings(let mode):
            savingsSortModeRaw = mode
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
