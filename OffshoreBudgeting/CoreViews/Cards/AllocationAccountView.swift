import SwiftUI
import SwiftData

struct AllocationAccountView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCommandHub) private var commandHub

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("sort.sharedBalances.mode") private var sharedBalancesSortModeRaw: String = SharedBalancesSortMode.az.rawValue

    @State private var showingAddAllocationAccount: Bool = false
    @State private var showingEditAllocationAccount: Bool = false
    @State private var editingAllocationAccount: AllocationAccount? = nil

    @State private var showingSharedBalanceDeleteConfirm: Bool = false
    @State private var pendingSharedBalanceDelete: (() -> Void)? = nil
    @State private var showingSharedBalanceArchiveConfirm: Bool = false
    @State private var pendingSharedBalanceArchive: (() -> Void)? = nil

    let workspace: Workspace

    @Query private var allocationAccounts: [AllocationAccount]

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _allocationAccounts = Query(
            filter: #Predicate<AllocationAccount> {
                $0.workspace?.id == workspaceID && $0.isArchived == false
            },
            sort: [SortDescriptor(\AllocationAccount.name, order: .forward)]
        )
    }

    // MARK: - Layout

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 260), spacing: 16)]
    }

    // MARK: - Sorting

    private var sharedBalancesSortMode: SharedBalancesSortMode {
        SharedBalancesSortMode(rawValue: sharedBalancesSortModeRaw) ?? .az
    }

    private func setSharedBalancesSortMode(_ mode: SharedBalancesSortMode) {
        sharedBalancesSortModeRaw = mode.rawValue
    }

    private var sortedAllocationAccounts: [AllocationAccount] {
        switch sharedBalancesSortMode {
        case .az:
            return allocationAccounts.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .za:
            return allocationAccounts.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            }
        case .amountAsc:
            return allocationAccounts.sorted { lhs, rhs in
                let left = AllocationLedgerService.balance(for: lhs)
                let right = AllocationLedgerService.balance(for: rhs)
                if left == right {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return left < right
            }
        case .amountDesc:
            return allocationAccounts.sorted { lhs, rhs in
                let left = AllocationLedgerService.balance(for: lhs)
                let right = AllocationLedgerService.balance(for: rhs)
                if left == right {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return left > right
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if allocationAccounts.isEmpty {
                    ContentUnavailableView(
                        "No Shared Balances Yet",
                        systemImage: "person.2",
                        description: Text("Create an account to track shared expenses and settlements.")
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(sortedAllocationAccounts) { account in
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
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .toolbar {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    sortToolbarButton
                }

                ToolbarSpacer(.flexible, placement: .primaryAction)

                ToolbarItemGroup(placement: .primaryAction) {
                    addToolbarButton
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    addToolbarButton
                }

                ToolbarItem(placement: .primaryAction) {
                    sortToolbarButton
                }
            }
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
        .sheet(isPresented: $showingAddAllocationAccount) {
            NavigationStack {
                AddAllocationAccountView(workspace: workspace)
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
        .onReceive(commandHub.$sequence) { _ in
            guard commandHub.surface == .cards else { return }
            handleCommand(commandHub.latestCommandID)
        }
    }

    @ViewBuilder
    private var addToolbarButton: some View {
        Button {
            showingAddAllocationAccount = true
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add Shared Balance")
    }

    @ViewBuilder
    private var sortToolbarButton: some View {
        Menu {
            sharedBalancesSortMenuButton(title: "A-Z", mode: .az)
            sharedBalancesSortMenuButton(title: "Z-A", mode: .za)
            sharedBalancesSortMenuButton(title: "$ ↑", mode: .amountAsc)
            sharedBalancesSortMenuButton(title: "$ ↓", mode: .amountDesc)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
    }

    private func sharedBalancesSortMenuButton(title: String, mode: SharedBalancesSortMode) -> some View {
        Button {
            setSharedBalancesSortMode(mode)
        } label: {
            HStack {
                Text(title)
                if sharedBalancesSortMode == mode {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    // MARK: - Actions

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
            showingAddAllocationAccount = true
            return
        }

        switch commandID {
        case AppCommandID.SharedBalances.sortAZ:
            setSharedBalancesSortMode(.az)
        case AppCommandID.SharedBalances.sortZA:
            setSharedBalancesSortMode(.za)
        case AppCommandID.SharedBalances.sortAmountAsc:
            setSharedBalancesSortMode(.amountAsc)
        case AppCommandID.SharedBalances.sortAmountDesc:
            setSharedBalancesSortMode(.amountDesc)
        default:
            break
        }
    }
}

private enum SharedBalancesSortMode: String {
    case az
    case za
    case amountAsc
    case amountDesc
}

private struct AllocationAccountTileView: View {
    let account: AllocationAccount

    private var balance: Double {
        AllocationLedgerService.balance(for: account)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Text(balance, format: CurrencyFormatter.currencyStyle())
                .font(.title2.weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

            Text(account.name)
                .font(.headline)
                .lineLimit(2)
                .padding(16)
        }
        .aspectRatio(1.586, contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .leading)
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
