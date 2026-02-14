//
//  CardsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct CardsView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCommandHub) private var commandHub

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage(AppShortcutNavigationStore.pendingActionKey) private var pendingShortcutActionRaw: String = ""
    @AppStorage(AppShortcutNavigationStore.pendingImportClipboardTextKey) private var pendingImportClipboardText: String = ""
    @AppStorage(AppShortcutNavigationStore.pendingImportCardIDKey) private var pendingImportCardID: String = ""
    @AppStorage(AppShortcutNavigationStore.pendingExpenseDescriptionKey) private var pendingExpenseDescription: String = ""

    @State private var showingAddExpenseSheet: Bool = false
    @State private var showingImportExpensesSheet: Bool = false
    @State private var showingAddCard: Bool = false
    @State private var showingAddAllocationAccount: Bool = false
    @State private var showingEditCard: Bool = false
    @State private var editingCard: Card? = nil
    @State private var showingEditAllocationAccount: Bool = false
    @State private var editingAllocationAccount: AllocationAccount? = nil
    @State private var shortcutImportCard: Card? = nil
    @State private var shortcutImportClipboardText: String? = nil
    @State private var shortcutExpenseDescription: String? = nil

    @State private var showingCardDeleteConfirm: Bool = false
    @State private var pendingCardDelete: (() -> Void)? = nil
    @State private var showingSharedBalanceDeleteConfirm: Bool = false
    @State private var pendingSharedBalanceDelete: (() -> Void)? = nil
    @State private var showingSharedBalanceArchiveConfirm: Bool = false
    @State private var pendingSharedBalanceArchive: (() -> Void)? = nil

    @State private var selectedSegment: CardsSegment = .cards

    let workspace: Workspace
    @Query private var cards: [Card]
    @Query private var allocationAccounts: [AllocationAccount]

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _allocationAccounts = Query(
            filter: #Predicate<AllocationAccount> {
                $0.workspace?.id == workspaceID && $0.isArchived == false
            },
            sort: [SortDescriptor(\AllocationAccount.name, order: .forward)]
        )
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 16)]
    }

    private var navigationTitleText: String {
        selectedSegment == .cards ? "Cards" : "Shared Balances"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Picker("View", selection: $selectedSegment) {
                    Text("Cards").tag(CardsSegment.cards)
                    Text("Shared Balances").tag(CardsSegment.sharedBalances)
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)

                Group {
                    if selectedSegment == .cards {
                        if cards.isEmpty {
                            ContentUnavailableView(
                                "No Cards Yet",
                                systemImage: "creditcard",
                                description: Text("Create a card to start tracking expenses.")
                            )
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(cards) { card in
                                    NavigationLink {
                                        CardDetailView(workspace: workspace, card: card)
                                    } label: {
                                        CardVisualView(
                                            title: card.name,
                                            theme: CardThemeOption(rawValue: card.theme) ?? .ruby,
                                            effect: CardEffectOption(rawValue: card.effect) ?? .plastic
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            editingCard = card
                                            showingEditCard = true
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(Color("AccentColor"))

                                        Button(role: .destructive) {
                                            if confirmBeforeDeleting {
                                                pendingCardDelete = {
                                                    delete(card)
                                                }
                                                showingCardDeleteConfirm = true
                                            } else {
                                                delete(card)
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .tint(Color("OffshoreDepth"))
                                    }
                                }
                            }
                        }
                    } else {
                        if allocationAccounts.isEmpty {
                            ContentUnavailableView(
                                "No Shared Balances Yet",
                                systemImage: "person.2",
                                description: Text("Create an account to track shared expenses and settlements.")
                            )
                            .frame(maxWidth: .infinity)
                        } else {
                            LazyVGrid(columns: columns, spacing: 16) {
                                ForEach(allocationAccounts) { account in
                                    NavigationLink {
                                        AllocationAccountDetailView(workspace: workspace, account: account)
                                    } label: {
                                        AllocationAccountTileView(account: account)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            editingAllocationAccount = account
                                            showingEditAllocationAccount = true
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(Color("AccentColor"))

                                        if hasSharedBalanceHistory(account) {
                                            Button(role: .destructive) {
                                                requestArchiveSharedBalance(account)
                                            } label: {
                                                Label("Archive", systemImage: "archivebox")
                                            }
                                            .tint(Color("OffshoreDepth"))
                                        } else if canDeleteSharedBalance(account) {
                                            Button(role: .destructive) {
                                                requestDeleteSharedBalance(account)
                                            } label: {
                                                Label("Delete", systemImage: "trash")
                                            }
                                            .tint(Color("OffshoreDepth"))
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .postBoardingTip(
            key: "tip.cards.v1",
            title: "Cards",
            items: [
                PostBoardingTipItem(
                    systemImage: "creditcard.fill",
                    title: "Cards",
                    detail: "Browse stored cards. Single press to open a card to add expense and to view and filter spending. Long press a card to edit or delete it."
                )
            ]
        )
        .navigationTitle(navigationTitleText)
        .toolbar {
            Button {
                handleAddAction()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel(selectedSegment == .cards ? "Add Card" : "Add Shared Balance")
        }
        .alert("Delete Card?", isPresented: $showingCardDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingCardDelete?()
                pendingCardDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingCardDelete = nil
            }
        } message: {
            Text("This deletes the card and all of its expenses.")
        }
        .alert("Delete Shared Balance?", isPresented: $showingSharedBalanceDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingSharedBalanceDelete?()
                pendingSharedBalanceDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSharedBalanceDelete = nil
            }
        } message: {
            Text("This deletes the Shared Balance permanently.")
        }
        .alert("Archive Shared Balance?", isPresented: $showingSharedBalanceArchiveConfirm) {
            Button("Archive", role: .destructive) {
                pendingSharedBalanceArchive?()
                pendingSharedBalanceArchive = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSharedBalanceArchive = nil
            }
        } message: {
            Text("Archived Shared Balances stay in history but are hidden from new allocation choices.")
        }
        .sheet(isPresented: $showingAddCard) {
            NavigationStack {
                AddCardView(workspace: workspace)
            }
        }
        .sheet(isPresented: $showingAddAllocationAccount) {
            NavigationStack {
                AddAllocationAccountView(workspace: workspace)
            }
        }
        .sheet(isPresented: $showingAddExpenseSheet) {
            NavigationStack {
                AddExpenseView(
                    workspace: workspace,
                    prefilledDescription: shortcutExpenseDescription
                )
            }
            .onDisappear {
                shortcutExpenseDescription = nil
            }
        }
        .sheet(isPresented: $showingImportExpensesSheet, onDismiss: {
            shortcutImportCard = nil
            shortcutImportClipboardText = nil
        }) {
            NavigationStack {
                if let shortcutImportCard {
                    ExpenseCSVImportFlowView(
                        workspace: workspace,
                        card: shortcutImportCard,
                        initialClipboardText: shortcutImportClipboardText
                    )
                } else {
                    ContentUnavailableView(
                        "Card Unavailable",
                        systemImage: "creditcard",
                        description: Text("The selected card for this shortcut import could not be found.")
                    )
                }
            }
        }
        .sheet(isPresented: $showingEditCard, onDismiss: { editingCard = nil }) {
            NavigationStack {
                if let editingCard {
                    EditCardView(workspace: workspace, card: editingCard)
                } else {
                    EmptyView()
                }
            }
        }
        .sheet(isPresented: $showingEditAllocationAccount, onDismiss: { editingAllocationAccount = nil }) {
            NavigationStack {
                if let editingAllocationAccount {
                    EditAllocationAccountView(account: editingAllocationAccount)
                } else {
                    EmptyView()
                }
            }
        }
        .onAppear {
            consumePendingShortcutActionIfNeeded()
            commandHub.activate(.cards)
        }
        .onDisappear {
            commandHub.deactivate(.cards)
        }
        .onChange(of: pendingShortcutActionRaw) { _, _ in
            consumePendingShortcutActionIfNeeded()
        }
        .onReceive(commandHub.$sequence) { _ in
            guard commandHub.surface == .cards else { return }
            handleCommand(commandHub.latestCommandID)
        }
    }

    // MARK: - Delete

    private func delete(_ card: Card) {
        let cardID = card.id
        let workspaceID = workspace.id

        HomePinnedItemsStore(workspaceID: workspaceID).removePinnedCard(id: cardID)
        HomePinnedCardsStore(workspaceID: workspaceID).removePinnedCardID(cardID)

        // I prefer being explicit here even though SwiftData delete rules are set to cascade.
        // This keeps behavior predictable if those rules ever change.
        if let planned = card.plannedExpenses {
            for expense in planned {
                modelContext.delete(expense)
            }
        }

        if let variable = card.variableExpenses {
            for expense in variable {
                if let allocation = expense.allocation {
                    expense.allocation = nil
                    modelContext.delete(allocation)
                }
                if let offsetSettlement = expense.offsetSettlement {
                    expense.offsetSettlement = nil
                    modelContext.delete(offsetSettlement)
                }
                modelContext.delete(expense)
            }
        }

        if let incomes = card.incomes {
            for income in incomes {
                modelContext.delete(income)
            }
        }

        if let links = card.budgetLinks {
            for link in links {
                modelContext.delete(link)
            }
        }

        modelContext.delete(card)
    }

    private func consumePendingShortcutActionIfNeeded() {
        let pending = pendingShortcutActionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty else { return }

        if pending == AppShortcutNavigationStore.PendingAction.openQuickAddExpense.rawValue
            || pending == AppShortcutNavigationStore.PendingAction.openQuickAddExpenseFromShoppingMode.rawValue {
            let prefill = pendingExpenseDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            shortcutExpenseDescription = prefill.isEmpty ? nil : prefill
            showingAddExpenseSheet = true
        } else if pending == AppShortcutNavigationStore.PendingAction.openCardImportReview.rawValue {
            let cardID = pendingImportCardID.trimmingCharacters(in: .whitespacesAndNewlines)
            shortcutImportCard = cards.first { $0.id.uuidString == cardID }

            let clipboard = pendingImportClipboardText.trimmingCharacters(in: .whitespacesAndNewlines)
            shortcutImportClipboardText = clipboard.isEmpty ? nil : clipboard
            showingImportExpensesSheet = shortcutImportCard != nil
        }

        pendingShortcutActionRaw = ""
        pendingImportClipboardText = ""
        pendingImportCardID = ""
        pendingExpenseDescription = ""
    }

    private func openNewCard() {
        handleAddAction()
    }

    private func handleAddAction() {
        if selectedSegment == .cards {
            showingAddCard = true
        } else {
            showingAddAllocationAccount = true
        }
    }

    private func hasSharedBalanceHistory(_ account: AllocationAccount) -> Bool {
        !(account.expenseAllocations ?? []).isEmpty || !(account.settlements ?? []).isEmpty
    }

    private func canDeleteSharedBalance(_ account: AllocationAccount) -> Bool {
        !hasSharedBalanceHistory(account)
    }

    private func requestDeleteSharedBalance(_ account: AllocationAccount) {
        let action = { deleteSharedBalance(account) }

        if confirmBeforeDeleting {
            pendingSharedBalanceDelete = action
            showingSharedBalanceDeleteConfirm = true
        } else {
            action()
        }
    }

    private func deleteSharedBalance(_ account: AllocationAccount) {
        guard canDeleteSharedBalance(account) else { return }
        modelContext.delete(account)
    }

    private func requestArchiveSharedBalance(_ account: AllocationAccount) {
        let action = { archiveSharedBalance(account) }

        if confirmBeforeDeleting {
            pendingSharedBalanceArchive = action
            showingSharedBalanceArchiveConfirm = true
        } else {
            action()
        }
    }

    private func archiveSharedBalance(_ account: AllocationAccount) {
        guard hasSharedBalanceHistory(account) else { return }
        account.isArchived = true
        account.archivedAt = .now
    }

    private func handleCommand(_ commandID: String) {
        if commandID == AppCommandID.Cards.newCard {
            openNewCard()
        }
    }
}

private enum CardsSegment: String, CaseIterable, Identifiable {
    case cards
    case sharedBalances

    var id: String { rawValue }
}

private struct AllocationAccountTileView: View {
    let account: AllocationAccount

    private var balance: Double {
        AllocationLedgerService.balance(for: account)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(account.name)
                    .font(.headline)
                    .lineLimit(2)

                Spacer(minLength: 8)

                Text("Shared Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(balance, format: CurrencyFormatter.currencyStyle())
                .font(.title3.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill((Color(hex: account.hexColor) ?? .blue).opacity(0.25))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke((Color(hex: account.hexColor) ?? .blue).opacity(0.6), lineWidth: 1)
        )
    }
}

#Preview("Cards") {
    let container = PreviewSeed.makeContainer()
    let context = container.mainContext

    _ = PreviewSeed.seedBasicData(in: context)

    let workspace = (try? context.fetch(FetchDescriptor<Workspace>()).first)

    return NavigationStack {
        if let workspace {
            CardsView(workspace: workspace)
        } else {
            ContentUnavailableView(
                "Missing Preview Data",
                systemImage: "creditcard",
                description: Text("PreviewSeed did not create a Workspace.")
            )
        }
    }
    .modelContainer(container)
}
