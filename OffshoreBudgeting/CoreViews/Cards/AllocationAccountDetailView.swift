import SwiftUI
import SwiftData

struct AllocationAccountDetailView: View {
    let workspace: Workspace
    @Bindable var account: AllocationAccount

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @State private var showingAddSettlementSheet: Bool = false
    @State private var showingEditAccountSheet: Bool = false
    @State private var showingArchiveConfirm: Bool = false
    @State private var showingDeleteConfirm: Bool = false

    @State private var showingSettlementDeleteConfirm: Bool = false
    @State private var pendingSettlementDeleteID: UUID? = nil

    @State private var showingChargeDeleteConfirm: Bool = false
    @State private var pendingChargeDeleteID: UUID? = nil

    @State private var editingSheetEntry: EditSharedBalanceEntryView.Entry? = nil

    @State private var showingSettlementActionError: Bool = false
    @State private var settlementActionErrorMessage: String = ""

    private var balance: Double {
        CurrencyFormatter.normalizedCurrencyDisplayValue(AllocationLedgerService.balance(for: account))
    }

    private var ledgerRows: [AllocationLedgerService.LedgerRow] {
        AllocationLedgerService.rows(for: account)
    }

    private var hasHistory: Bool {
        !(account.expenseAllocations ?? []).isEmpty || !(account.settlements ?? []).isEmpty
    }

    private var pendingSettlementDeleteIsLinked: Bool {
        guard let settlement = settlement(for: pendingSettlementDeleteID) else { return false }
        return settlement.expense != nil || settlement.plannedExpense != nil
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Balance")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(balance, format: CurrencyFormatter.currencyStyle())
                        .font(.title2.weight(.semibold))
                }
                .padding(.vertical, 4)
            }

            if ledgerRows.isEmpty {
                Section {
                    Text("No ledger entries yet.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Ledger") {
                    ForEach(ledgerRows) { row in
                        ledgerRowView(row)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                if let settlementID = row.settlementID, !account.isArchived {
                                    Button {
                                        guard let settlement = settlement(for: settlementID) else {
                                            showEntryUnavailableError()
                                            return
                                        }
                                        editingSheetEntry = .settlement(settlement)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(Color("AccentColor"))
                                }
                                if isEditableChargeRow(row), !account.isArchived {
                                    Button {
                                        guard let allocationID = row.allocationID,
                                              let allocation = allocation(for: allocationID) else {
                                            showEntryUnavailableError()
                                            return
                                        }
                                        editingSheetEntry = .allocation(allocation)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(Color("AccentColor"))
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if let settlementID = row.settlementID, !account.isArchived {
                                    Button(role: .destructive) {
                                        requestDeleteSettlement(id: settlementID)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                if isEditableChargeRow(row), !account.isArchived, let allocationID = row.allocationID {
                                    Button(role: .destructive) {
                                        requestDeleteChargeAllocation(id: allocationID)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            if account.isArchived {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Text("Archived")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if #available(iOS 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Button {
                            showingEditAccountSheet = true
                        } label: {
                            Label("Edit Reconciliation", systemImage: "pencil")
                        }

                        Divider()

                        if hasHistory {
                            Button(role: .destructive) {
                                if confirmBeforeDeleting {
                                    showingArchiveConfirm = true
                                } else {
                                    archiveAccountAndDismiss()
                                }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        } else {
                            Button(role: .destructive) {
                                if confirmBeforeDeleting {
                                    showingDeleteConfirm = true
                                } else {
                                    deleteAccountAndDismiss()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Reconciliation Actions")
                }

                ToolbarSpacer(.flexible, placement: .primaryAction)

                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        showingAddSettlementSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Settlement")
                }
            } else {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showingEditAccountSheet = true
                        } label: {
                            Label("Edit Reconciliation", systemImage: "pencil")
                        }

                        Divider()

                        if hasHistory {
                            Button(role: .destructive) {
                                if confirmBeforeDeleting {
                                    showingArchiveConfirm = true
                                } else {
                                    archiveAccountAndDismiss()
                                }
                            } label: {
                                Label("Archive", systemImage: "archivebox")
                            }
                        } else {
                            Button(role: .destructive) {
                                if confirmBeforeDeleting {
                                    showingDeleteConfirm = true
                                } else {
                                    deleteAccountAndDismiss()
                                }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Reconciliation Actions")

                    Button {
                        showingAddSettlementSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Settlement")
                }
            }
        }
        .alert("Archive Reconciliation?", isPresented: $showingArchiveConfirm) {
            Button("Archive", role: .destructive) {
                archiveAccountAndDismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Archived Reconciliations stay in history but are hidden from new allocation choices.")
        }
        .alert("Delete Reconciliation?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                deleteAccountAndDismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes the Reconciliation permanently.")
        }
        .alert("Delete Settlement?", isPresented: $showingSettlementDeleteConfirm) {
            Button("Delete", role: .destructive) {
                performPendingSettlementDelete()
            }
            Button("Cancel", role: .cancel) {
                pendingSettlementDeleteID = nil
            }
        } message: {
            if pendingSettlementDeleteIsLinked {
                Text("This settlement is linked to an expense. Deleting it will restore that expense amount.")
            } else {
                Text("This settlement will be deleted.")
            }
        }
        .alert("Delete Split Charge?", isPresented: $showingChargeDeleteConfirm) {
            Button("Delete", role: .destructive) {
                performPendingChargeDelete()
            }
            Button("Cancel", role: .cancel) {
                pendingChargeDeleteID = nil
            }
        } message: {
            Text("Deleting this split charge will remove the split and restore the original gross expense amount.")
        }
        .alert("Couldn't Update Settlement", isPresented: $showingSettlementActionError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(settlementActionErrorMessage)
        }
        .sheet(isPresented: $showingAddSettlementSheet) {
            NavigationStack {
                AddAllocationSettlementView(workspace: workspace, account: account)
            }
        }
        .sheet(isPresented: $showingEditAccountSheet) {
            NavigationStack {
                EditAllocationAccountView(account: account)
            }
        }
        .sheet(item: $editingSheetEntry, onDismiss: {
            editingSheetEntry = nil
        }) { entry in
            NavigationStack {
                EditSharedBalanceEntryView(
                    workspace: workspace,
                    account: account,
                    entry: entry
                )
            }
        }
    }

    private func ledgerRowView(_ row: AllocationLedgerService.LedgerRow) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.headline)

                HStack(spacing: 6) {
                    Text(row.type.rawValue)
                    Text("•")
                    Text(row.date, format: Date.FormatStyle(date: .abbreviated, time: .omitted))
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let subtitle = row.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            }

            Spacer(minLength: 12)

            Text(
                CurrencyFormatter.normalizedCurrencyDisplayValue(row.amount),
                format: CurrencyFormatter.currencyStyle()
            )
                .font(.body.weight(.semibold))
        }
        .padding(.vertical, 2)
    }

    private func requestDeleteSettlement(id: UUID) {
        if confirmBeforeDeleting {
            pendingSettlementDeleteID = id
            showingSettlementDeleteConfirm = true
        } else {
            deleteSettlement(id: id)
        }
    }

    private func performPendingSettlementDelete() {
        guard let id = pendingSettlementDeleteID else { return }
        deleteSettlement(id: id)
        pendingSettlementDeleteID = nil
    }

    private func requestDeleteChargeAllocation(id: UUID) {
        if confirmBeforeDeleting {
            pendingChargeDeleteID = id
            showingChargeDeleteConfirm = true
        } else {
            deleteChargeAllocation(id: id)
        }
    }

    private func performPendingChargeDelete() {
        guard let id = pendingChargeDeleteID else { return }
        deleteChargeAllocation(id: id)
        pendingChargeDeleteID = nil
    }

    private func deleteSettlement(id: UUID) {
        guard let settlement = settlement(for: id) else { return }

        if let expense = settlement.expense {
            let oldOffset = abs(settlement.amount)
            expense.amount = max(0, expense.amount + oldOffset)
            if expense.offsetSettlement?.id == settlement.id {
                expense.offsetSettlement = nil
            }
        } else if let plannedExpense = settlement.plannedExpense {
            plannedExpense.actualAmount = 0
            if plannedExpense.offsetSettlement?.id == settlement.id {
                plannedExpense.offsetSettlement = nil
            }
        }

        modelContext.delete(settlement)

        do {
            try modelContext.save()
        } catch {
            settlementActionErrorMessage = "Unable to delete settlement. \(error.localizedDescription)"
            showingSettlementActionError = true
        }
    }

    private func settlement(for id: UUID?) -> AllocationSettlement? {
        guard let id else { return nil }
        return (account.settlements ?? []).first(where: { $0.id == id })
    }

    private func allocation(for id: UUID?) -> ExpenseAllocation? {
        guard let id else { return nil }
        return (account.expenseAllocations ?? []).first(where: { $0.id == id })
    }

    private func isEditableChargeRow(_ row: AllocationLedgerService.LedgerRow) -> Bool {
        guard row.type == .charge else { return false }
        guard let allocation = allocation(for: row.allocationID) else { return false }
        return allocation.expense != nil || allocation.plannedExpense != nil
    }

    private func showEntryUnavailableError() {
        settlementActionErrorMessage = "The selected reconciliation entry could not be found."
        showingSettlementActionError = true
    }

    private func deleteChargeAllocation(id: UUID) {
        guard let allocation = allocation(for: id) else { return }
        if let expense = allocation.expense {
            let oldSplit = max(0, allocation.allocatedAmount)
            let gross = max(0, expense.amount + oldSplit)
            expense.amount = gross

            if expense.allocation?.id == allocation.id {
                expense.allocation = nil
            }
        } else if let plannedExpense = allocation.plannedExpense {
            plannedExpense.actualAmount = 0

            if plannedExpense.allocation?.id == allocation.id {
                plannedExpense.allocation = nil
            }
        } else {
            return
        }

        modelContext.delete(allocation)

        do {
            try modelContext.save()
        } catch {
            settlementActionErrorMessage = "Unable to delete split charge. \(error.localizedDescription)"
            showingSettlementActionError = true
        }
    }

    private func archiveAccountAndDismiss() {
        account.isArchived = true
        account.archivedAt = .now
        try? modelContext.save()
        dismiss()
    }

    private func deleteAccountAndDismiss() {
        guard !hasHistory else { return }
        modelContext.delete(account)
        try? modelContext.save()
        dismiss()
    }
}

private struct EditSharedBalanceEntryView: View {

    enum Entry: Identifiable {
        case allocation(ExpenseAllocation)
        case settlement(AllocationSettlement)

        var id: String {
            switch self {
            case .allocation(let allocation):
                return "allocation-\(allocation.id.uuidString)"
            case .settlement(let settlement):
                return "settlement-\(settlement.id.uuidString)"
            }
        }
    }

    private enum ActionMode: String, CaseIterable, Identifiable {
        case none
        case split
        case offset

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "None"
            case .split: return "Split"
            case .offset: return "Offset"
            }
        }
    }

    private enum LinkedSource {
        case variable(VariableExpense)
        case planned(PlannedExpense)
        case none
    }

    let workspace: Workspace
    let account: AllocationAccount
    let entry: Entry

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var allocationAccounts: [AllocationAccount]

    @State private var actionMode: ActionMode = .none
    @State private var selectedAccountID: UUID? = nil
    @State private var amountText: String = ""
    @State private var note: String = ""
    @State private var date: Date = .now
    @State private var direction: Int = -1

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingSaveErrorAlert: Bool = false
    @State private var saveErrorMessage: String = ""

    init(workspace: Workspace, account: AllocationAccount, entry: Entry) {
        self.workspace = workspace
        self.account = account
        self.entry = entry

        let workspaceID = workspace.id
        _allocationAccounts = Query(
            filter: #Predicate<AllocationAccount> {
                $0.workspace?.id == workspaceID && $0.isArchived == false
            },
            sort: [SortDescriptor(\AllocationAccount.name, order: .forward)]
        )
    }

    private var linkedSource: LinkedSource {
        switch entry {
        case .allocation(let allocation):
            if let expense = allocation.expense { return .variable(expense) }
            if let plannedExpense = allocation.plannedExpense { return .planned(plannedExpense) }
            return .none
        case .settlement(let settlement):
            if let expense = settlement.expense { return .variable(expense) }
            if let plannedExpense = settlement.plannedExpense { return .planned(plannedExpense) }
            return .none
        }
    }

    private var isLinked: Bool {
        switch linkedSource {
        case .variable, .planned: return true
        case .none: return false
        }
    }

    private var selectedAccount: AllocationAccount? {
        guard let selectedAccountID else { return nil }
        return allocationAccounts.first(where: { $0.id == selectedAccountID })
    }

    private var amountValue: Double? {
        CurrencyFormatter.parseAmount(amountText)
    }

    private var linkedCardName: String {
        switch linkedSource {
        case .variable(let expense):
            return expense.card?.name ?? "No Card"
        case .planned(let plannedExpense):
            return plannedExpense.card?.name ?? "No Card"
        case .none:
            return "No Card"
        }
    }

    private var linkedCategoryName: String {
        switch linkedSource {
        case .variable(let expense):
            return expense.category?.name ?? "Uncategorized"
        case .planned(let plannedExpense):
            return plannedExpense.category?.name ?? "Uncategorized"
        case .none:
            return "Uncategorized"
        }
    }

    private var maxLinkedAmount: Double {
        switch linkedSource {
        case .variable(let expense):
            return variableGrossAmount(for: expense)
        case .planned(let plannedExpense):
            return max(0, plannedExpense.plannedAmount)
        case .none:
            return .greatestFiniteMagnitude
        }
    }

    private var canSave: Bool {
        if isLinked {
            if actionMode == .none {
                return true
            }

            guard selectedAccountID != nil else { return false }
            guard let amount = amountValue, amount > 0 else { return false }
            guard amount <= maxLinkedAmount else { return false }

            if actionMode == .offset, let selectedAccount {
                let available = availableOffsetBalance(for: selectedAccount)
                guard CurrencyFormatter.isLessThanOrEqualCurrency(amount, available) else { return false }
            }

            return true
        }

        guard selectedAccountID != nil else { return false }
        guard let amount = amountValue, amount > 0 else { return false }
        return amount > 0
    }

    var body: some View {
        Form {
            if isLinked {
                Section("Linked Entry") {
                    detailRow(label: "Card", value: linkedCardName)
                    detailRow(label: "Category", value: linkedCategoryName)
                }

                Section("Action") {
                    Picker("Action", selection: $actionMode) {
                        ForEach(ActionMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            Section("Reconciliation Entry") {
                Picker("Reconciliation", selection: $selectedAccountID) {
                    Text("None").tag(UUID?.none)
                    ForEach(allocationAccounts) { account in
                        Text(account.name).tag(Optional(account.id))
                    }
                }

                if !isLinked || actionMode != .none {
                    TextField("Amount", text: $amountText)
                        .keyboardType(.decimalPad)
                }

                if !isLinked || actionMode == .offset {
                    Picker("Direction", selection: $direction) {
                        Text("They Owe Me").tag(1)
                        Text("I Owe Them").tag(-1)
                    }
                    .pickerStyle(.segmented)
                }

                if !isLinked || actionMode == .offset {
                    TextField("Note", text: $note)
                }

                HStack {
                    Text("Date")
                    Spacer()
                    PillDatePickerField(title: "Date", date: $date)
                }

                if let selectedAccount {
                    HStack {
                        Text("Available Balance")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(
                            CurrencyFormatter.normalizedCurrencyDisplayValue(AllocationLedgerService.balance(for: selectedAccount)),
                            format: CurrencyFormatter.currencyStyle()
                        )
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .navigationTitle("Edit Reconciliation")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .buttonStyle(.glassProminent)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }
            }
        }
        .alert("Invalid Amount", isPresented: $showingInvalidAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter a valid amount that matches this action.")
        }
        .alert("Couldn't Save", isPresented: $showingSaveErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .onAppear {
            seedFromEntry()
        }
    }

    private func seedFromEntry() {
        selectedAccountID = account.id
        note = ""
        direction = -1
        date = .now

        switch entry {
        case .allocation(let allocation):
            actionMode = .split
            selectedAccountID = allocation.account?.id ?? account.id
            amountText = CurrencyFormatter.editingString(from: max(0, allocation.allocatedAmount))

            if let expense = allocation.expense {
                date = expense.transactionDate
                note = offsetNote(for: expense.descriptionText)
            } else if let plannedExpense = allocation.plannedExpense {
                date = plannedExpense.expenseDate
                note = offsetNote(for: plannedExpense.title)
            }
        case .settlement(let settlement):
            actionMode = isLinked ? .offset : .none
            selectedAccountID = settlement.account?.id ?? account.id
            amountText = CurrencyFormatter.editingString(from: max(0, abs(settlement.amount)))
            note = settlement.note
            date = settlement.date
            direction = settlement.amount < 0 ? -1 : 1
        }

        if DebugScreenshotFormDefaults.isEnabled {
            if selectedAccountID == nil {
                selectedAccountID = DebugScreenshotFormDefaults.preferredAllocationAccountID(in: allocationAccounts) ?? account.id
            }

            if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                switch actionMode {
                case .split:
                    amountText = DebugScreenshotFormDefaults.splitAmountText
                case .offset:
                    amountText = DebugScreenshotFormDefaults.offsetAmountText
                case .none:
                    amountText = DebugScreenshotFormDefaults.settlementAmountText
                }
            }

            let shouldSeedNote = (!isLinked || actionMode == .offset)
            if shouldSeedNote && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note = DebugScreenshotFormDefaults.settlementNote
            }
        }
    }

    private func save() {
        if isLinked {
            if actionMode != .none {
                guard let selectedAccount else {
                    saveErrorMessage = "Please select a reconciliation account."
                    showingSaveErrorAlert = true
                    return
                }

                guard let rawAmount = amountValue, rawAmount > 0 else {
                    showingInvalidAmountAlert = true
                    return
                }

                guard rawAmount <= maxLinkedAmount else {
                    showingInvalidAmountAlert = true
                    return
                }

                if actionMode == .offset {
                    let available = availableOffsetBalance(for: selectedAccount)
                    guard CurrencyFormatter.isLessThanOrEqualCurrency(rawAmount, available) else {
                        showingInvalidAmountAlert = true
                        return
                    }
                }
            }
        }

        do {
            switch linkedSource {
            case .variable(let expense):
                if actionMode == .none {
                    try saveLinkedVariable(expense, account: account, amount: 0)
                } else if let selectedAccount, let rawAmount = amountValue {
                    try saveLinkedVariable(expense, account: selectedAccount, amount: rawAmount)
                }
            case .planned(let plannedExpense):
                if actionMode == .none {
                    try saveLinkedPlanned(plannedExpense, account: account, amount: 0)
                } else if let selectedAccount, let rawAmount = amountValue {
                    try saveLinkedPlanned(plannedExpense, account: selectedAccount, amount: rawAmount)
                }
            case .none:
                guard let selectedAccount else {
                    saveErrorMessage = "Please select a reconciliation account."
                    showingSaveErrorAlert = true
                    return
                }
                guard let rawAmount = amountValue, rawAmount > 0 else {
                    showingInvalidAmountAlert = true
                    return
                }
                try saveStandaloneSettlement(account: selectedAccount, amount: rawAmount)
            }

            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveErrorAlert = true
        }
    }

    private func saveLinkedVariable(_ expense: VariableExpense, account: AllocationAccount, amount: Double) throws {
        let gross = variableGrossAmount(for: expense)

        switch actionMode {
        case .none:
            if let allocation = expense.allocation {
                expense.allocation = nil
                modelContext.delete(allocation)
            }
            if let settlement = expense.offsetSettlement {
                expense.offsetSettlement = nil
                modelContext.delete(settlement)
            }
            expense.amount = gross
        case .split:
            if let settlement = expense.offsetSettlement {
                expense.offsetSettlement = nil
                modelContext.delete(settlement)
            }

            if let allocation = expense.allocation {
                allocation.allocatedAmount = AllocationLedgerService.cappedAllocationAmount(amount, expenseAmount: gross)
                allocation.updatedAt = .now
                allocation.account = account
                allocation.workspace = workspace
                allocation.expense = expense
            } else {
                let allocation = ExpenseAllocation(
                    allocatedAmount: AllocationLedgerService.cappedAllocationAmount(amount, expenseAmount: gross),
                    createdAt: .now,
                    updatedAt: .now,
                    workspace: workspace,
                    account: account,
                    expense: expense,
                    plannedExpense: nil
                )
                modelContext.insert(allocation)
                expense.allocation = allocation
            }

            expense.amount = max(0, gross - amount)
        case .offset:
            if let allocation = expense.allocation {
                expense.allocation = nil
                modelContext.delete(allocation)
            }

            let signedAmount = Double(direction) * amount
            let trimmedNote = resolvedOffsetNote(for: expense.descriptionText)

            if let settlement = expense.offsetSettlement {
                settlement.note = trimmedNote
                settlement.amount = signedAmount
                settlement.date = date
                settlement.account = account
                settlement.workspace = workspace
                settlement.expense = expense
                settlement.plannedExpense = nil
            } else {
                let settlement = AllocationSettlement(
                    date: date,
                    note: trimmedNote,
                    amount: signedAmount,
                    workspace: workspace,
                    account: account,
                    expense: expense,
                    plannedExpense: nil
                )
                modelContext.insert(settlement)
                expense.offsetSettlement = settlement
            }

            expense.amount = max(0, gross - amount)
        }

        expense.transactionDate = date
        expense.workspace = workspace
    }

    private func saveLinkedPlanned(_ plannedExpense: PlannedExpense, account: AllocationAccount, amount: Double) throws {
        let plannedAmount = max(0, plannedExpense.plannedAmount)

        switch actionMode {
        case .none:
            if let allocation = plannedExpense.allocation {
                plannedExpense.allocation = nil
                modelContext.delete(allocation)
            }
            if let settlement = plannedExpense.offsetSettlement {
                plannedExpense.offsetSettlement = nil
                modelContext.delete(settlement)
            }
            plannedExpense.actualAmount = 0
        case .split:
            if let settlement = plannedExpense.offsetSettlement {
                plannedExpense.offsetSettlement = nil
                modelContext.delete(settlement)
            }

            if let allocation = plannedExpense.allocation {
                allocation.allocatedAmount = AllocationLedgerService.cappedAllocationAmount(amount, expenseAmount: plannedAmount)
                allocation.updatedAt = .now
                allocation.account = account
                allocation.workspace = workspace
                allocation.expense = nil
                allocation.plannedExpense = plannedExpense
            } else {
                let allocation = ExpenseAllocation(
                    allocatedAmount: AllocationLedgerService.cappedAllocationAmount(amount, expenseAmount: plannedAmount),
                    createdAt: .now,
                    updatedAt: .now,
                    workspace: workspace,
                    account: account,
                    expense: nil,
                    plannedExpense: plannedExpense
                )
                modelContext.insert(allocation)
                plannedExpense.allocation = allocation
            }

            plannedExpense.actualAmount = max(0, plannedAmount - amount)
        case .offset:
            if let allocation = plannedExpense.allocation {
                plannedExpense.allocation = nil
                modelContext.delete(allocation)
            }

            let signedAmount = Double(direction) * amount
            let trimmedNote = resolvedOffsetNote(for: plannedExpense.title)

            if let settlement = plannedExpense.offsetSettlement {
                settlement.note = trimmedNote
                settlement.amount = signedAmount
                settlement.date = date
                settlement.account = account
                settlement.workspace = workspace
                settlement.expense = nil
                settlement.plannedExpense = plannedExpense
            } else {
                let settlement = AllocationSettlement(
                    date: date,
                    note: trimmedNote,
                    amount: signedAmount,
                    workspace: workspace,
                    account: account,
                    expense: nil,
                    plannedExpense: plannedExpense
                )
                modelContext.insert(settlement)
                plannedExpense.offsetSettlement = settlement
            }

            plannedExpense.actualAmount = max(0, plannedAmount - amount)
        }

        plannedExpense.expenseDate = date
        plannedExpense.workspace = workspace
    }

    private func saveStandaloneSettlement(account: AllocationAccount, amount: Double) throws {
        guard case .settlement(let settlement) = entry else {
            throw NSError(domain: "EditSharedBalanceEntry", code: 1, userInfo: [NSLocalizedDescriptionKey: "Entry is unavailable."])
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        settlement.note = trimmedNote
        settlement.date = date
        settlement.amount = Double(direction) * amount
        settlement.account = account
        settlement.workspace = workspace
    }

    private func variableGrossAmount(for expense: VariableExpense) -> Double {
        let splitAmount = max(0, expense.allocation?.allocatedAmount ?? 0)
        let offsetAmount = max(0, -(expense.offsetSettlement?.amount ?? 0))
        return max(0, expense.amount + splitAmount + offsetAmount)
    }

    private func availableOffsetBalance(for account: AllocationAccount) -> Double {
        let currentBalance = max(0, AllocationLedgerService.balance(for: account))

        switch linkedSource {
        case .variable(let expense):
            guard let existing = expense.offsetSettlement else { return currentBalance }
            guard existing.account?.id == account.id else { return currentBalance }
            return max(0, currentBalance + max(0, -existing.amount))
        case .planned(let plannedExpense):
            guard let existing = plannedExpense.offsetSettlement else { return currentBalance }
            guard existing.account?.id == account.id else { return currentBalance }
            return max(0, currentBalance + max(0, -existing.amount))
        case .none:
            return currentBalance
        }
    }

    private func resolvedOffsetNote(for title: String) -> String {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? offsetNote(for: title) : trimmed
    }

    private func offsetNote(for title: String) -> String {
        "Offset applied to \(title)"
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct AddAllocationSettlementView: View {
    let workspace: Workspace
    let account: AllocationAccount

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var note: String = ""
    @State private var amountText: String = ""
    @State private var date: Date = .now

    @State private var showingInvalidAmountAlert: Bool = false

    private var canSave: Bool {
        guard let amount = CurrencyFormatter.parseAmount(amountText) else { return false }
        return amount > 0
    }

    var body: some View {
        Form {
            Section {
                TextField("Note", text: $note)

                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)

                Picker("Direction", selection: directionBinding) {
                    Text("They Owe Me").tag(1)
                    Text("I Owe Them").tag(-1)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Date")
                    Spacer()
                    PillDatePickerField(title: "Date", date: $date)
                }
            }
        }
        .navigationTitle("Add Settlement")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }

            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .buttonStyle(.glassProminent)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }
            }
        }
        .alert("Invalid Amount", isPresented: $showingInvalidAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter an amount greater than 0.")
        }
        .onAppear {
            guard DebugScreenshotFormDefaults.isEnabled else { return }

            if note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note = DebugScreenshotFormDefaults.settlementNote
            }

            if amountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                amountText = DebugScreenshotFormDefaults.settlementAmountText
            }

            currentDirection = DebugScreenshotFormDefaults.settlementDirection >= 0 ? 1 : -1
        }
    }

    private var directionBinding: Binding<Int> {
        Binding(
            get: { currentDirection },
            set: { newValue in
                currentDirection = newValue >= 0 ? 1 : -1
            }
        )
    }

    @State private var currentDirection: Int = -1

    private func save() {
        guard let rawAmount = CurrencyFormatter.parseAmount(amountText), rawAmount > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let signedAmount = Double(currentDirection) * rawAmount

        let settlement = AllocationSettlement(
            date: date,
            note: trimmedNote,
            amount: signedAmount,
            workspace: workspace,
            account: account
        )

        modelContext.insert(settlement)
        dismiss()
    }
}
