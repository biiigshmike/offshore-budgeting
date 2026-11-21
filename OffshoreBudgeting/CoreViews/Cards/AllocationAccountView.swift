import SwiftUI
import SwiftData

struct AllocationAccountView: View {

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCommandHub) private var commandHub

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("view.sharedBalances.mode") private var viewMode: CollectionViewMode = .gallery
    @AppStorage("sort.sharedBalances.mode") private var sharedBalancesSortModeRaw: String = SharedBalancesSortMode.az.rawValue

    @State private var showingAddAllocationAccount: Bool = false
    @State private var editingAllocationAccount: AllocationAccount? = nil

    @State private var showingSharedBalanceDeleteConfirm: Bool = false
    @State private var pendingSharedBalanceDelete: (() -> Void)? = nil
    @State private var showingSharedBalanceArchiveConfirm: Bool = false
    @State private var pendingSharedBalanceArchive: (() -> Void)? = nil
    @State private var lastHandledCommandSequence: Int? = nil

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
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 260), spacing: 16)]
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
        Group {
            if allocationAccounts.isEmpty {
                ContentUnavailableView(
                    "No Reconciliations Yet",
                    systemImage: "person.2",
                    description: Text("Create an account to track shared expenses and settlements.")
                )
            } else if viewMode == .list {
                List(sortedAllocationAccounts) { account in
                    NavigationLink {
                        AllocationAccountDetailView(workspace: workspace, account: account)
                    } label: {
                        LabeledContent {
                            Text(
                                CurrencyFormatter.normalizedCurrencyDisplayValue(AllocationLedgerService.balance(for: account)),
                                format: CurrencyFormatter.currencyStyle()
                            )
                        } label: {
                            Label {
                                Text(account.name)
                            } icon: {
                                Image(systemName: "person.2.fill")
                                    .foregroundStyle(Color(hex: account.hexColor) ?? .blue)
                            }
                        }
                    }
                    .contextMenu { accountActions(account) }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        editAccountButton(account)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        archiveOrDeleteAccountButton(account)
                    }
                }
            } else {
                galleryContent
            }
        }
        .blocksAutomaticExpenseReview(while: showingSharedBalanceDeleteConfirm)
        .alert("Delete Reconciliation?", isPresented: $showingSharedBalanceDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingSharedBalanceDelete?()
                pendingSharedBalanceDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSharedBalanceDelete = nil
            }
        } message: {
            Text("This deletes the Reconciliation permanently.")
        }
        .blocksAutomaticExpenseReview(while: showingSharedBalanceArchiveConfirm)
        .alert("Archive Reconciliation?", isPresented: $showingSharedBalanceArchiveConfirm) {
            Button("Archive", role: .destructive) {
                pendingSharedBalanceArchive?()
                pendingSharedBalanceArchive = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSharedBalanceArchive = nil
            }
        } message: {
            Text("Archived Reconciliations stay in history but are hidden from new allocation choices.")
        }
        .appSheet(isPresented: $showingAddAllocationAccount) {
            NavigationStack {
                AddAllocationAccountView(workspace: workspace)
            }
        }
        .appSheet(item: $editingAllocationAccount) { account in
            NavigationStack {
                EditAllocationAccountView(account: account)
            }
        }
        .onReceive(commandHub.$sequence) { sequence in
            if lastHandledCommandSequence == nil {
                lastHandledCommandSequence = sequence
                return
            }

            guard sequence != lastHandledCommandSequence else { return }
            lastHandledCommandSequence = sequence
            guard commandHub.surface == .cards else { return }
            handleCommand(commandHub.latestCommandID)
        }
    }

    private var galleryContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(sortedAllocationAccounts) { account in
                        NavigationLink {
                            AllocationAccountDetailView(workspace: workspace, account: account)
                        } label: {
                            AllocationAccountTileView(account: account)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            accountActions(account)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private func accountActions(_ account: AllocationAccount) -> some View {
        editAccountButton(account)
        archiveOrDeleteAccountButton(account)
    }

    private func editAccountButton(_ account: AllocationAccount) -> some View {
        Button("Edit", systemImage: "pencil") {
            editingAllocationAccount = account
        }
        .tint(Color("AccentColor"))
    }

    @ViewBuilder
    private func archiveOrDeleteAccountButton(_ account: AllocationAccount) -> some View {
        if hasSharedBalanceHistory(account) {
            Button("Archive", systemImage: "archivebox", role: .destructive) {
                requestArchiveSharedBalance(account)
            }
            .tint(Color("OffshoreDepth"))
        } else if canDeleteSharedBalance(account) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                requestDeleteSharedBalance(account)
            }
            .tint(Color("OffshoreDepth"))
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

    private var backgroundColor: Color {
        Color(hex: account.hexColor) ?? .blue
    }

    private var textColor: Color {
        let hex = backgroundColor.hexRGBString().trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard let rgb = UInt32(hex, radix: 16) else { return .black }

        func linearComponent(_ value: UInt32) -> Double {
            let component = Double(value) / 255
            return component <= 0.04045
                ? component / 12.92
                : pow((component + 0.055) / 1.055, 2.4)
        }

        let luminance = 0.2126 * linearComponent((rgb >> 16) & 0xFF)
            + 0.7152 * linearComponent((rgb >> 8) & 0xFF)
            + 0.0722 * linearComponent(rgb & 0xFF)
        let blackContrast = (luminance + 0.05) / 0.05
        let whiteContrast = 1.05 / (luminance + 0.05)
        return blackContrast >= whiteContrast ? .black : .white
    }

    private var balance: Double {
        CurrencyFormatter.normalizedCurrencyDisplayValue(AllocationLedgerService.balance(for: account))
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
        .foregroundStyle(textColor)
        .aspectRatio(1.586, contentMode: .fit)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(backgroundColor.opacity(0.6), lineWidth: 1)
        )
    }
}

#Preview("Reconciliation Colors — Light") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(["#FFFFFF", "#FFDD00", "#3B82F6", "#CC2222", "#101010"], id: \.self) { hex in
                AllocationAccountTileView(account: AllocationAccount(name: "Shared household expenses", hexColor: hex))
            }
        }
        .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("Reconciliation Colors — Dark") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(["#FFFFFF", "#FFDD00", "#3B82F6", "#CC2222", "#101010"], id: \.self) { hex in
                AllocationAccountTileView(account: AllocationAccount(name: "Shared household expenses", hexColor: hex))
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Reconciliation — Accessibility") {
    AllocationAccountTileView(account: AllocationAccount(
        name: "Shared household expenses and reimbursements",
        hexColor: "#FFDD00"
    ))
    .padding()
    .environment(\.dynamicTypeSize, .accessibility3)
}
