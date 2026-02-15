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

    @State private var showingEditSettlementSheet: Bool = false
    @State private var editingSettlementID: UUID? = nil

    @State private var showingSettlementActionError: Bool = false
    @State private var settlementActionErrorMessage: String = ""

    private var balance: Double {
        AllocationLedgerService.balance(for: account)
    }

    private var ledgerRows: [AllocationLedgerService.LedgerRow] {
        AllocationLedgerService.rows(for: account)
    }

    private var hasHistory: Bool {
        !(account.expenseAllocations ?? []).isEmpty || !(account.settlements ?? []).isEmpty
    }

    private var pendingSettlementDeleteIsLinked: Bool {
        guard let settlement = settlement(for: pendingSettlementDeleteID) else { return false }
        return settlement.expense != nil
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
                                        editingSettlementID = settlementID
                                        showingEditSettlementSheet = true
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
                            }
                    }
                }
            }
        }
        .navigationTitle(account.name)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if account.isArchived {
                    Text("Archived")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Button {
                        showingAddSettlementSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Settlement")

                    Menu {
                        Button {
                            showingEditAccountSheet = true
                        } label: {
                            Label("Edit Shared Balance", systemImage: "pencil")
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
                    .accessibilityLabel("Shared Balance Actions")
                }
            }
        }
        .alert("Archive Shared Balance?", isPresented: $showingArchiveConfirm) {
            Button("Archive", role: .destructive) {
                archiveAccountAndDismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Archived Shared Balances stay in history but are hidden from new allocation choices.")
        }
        .alert("Delete Shared Balance?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                deleteAccountAndDismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This deletes the Shared Balance permanently.")
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
        .sheet(isPresented: $showingEditSettlementSheet, onDismiss: {
            editingSettlementID = nil
        }) {
            NavigationStack {
                if let settlement = settlement(for: editingSettlementID) {
                    EditAllocationSettlementView(settlement: settlement)
                } else {
                    ContentUnavailableView(
                        "Settlement Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text("The selected settlement could not be found.")
                    )
                }
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

                if row.isLinkedSettlement {
                    Text("Linked to expense")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 12)

            Text(row.amount, format: CurrencyFormatter.currencyStyle())
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

    private func deleteSettlement(id: UUID) {
        guard let settlement = settlement(for: id) else { return }

        if let expense = settlement.expense {
            let oldOffset = max(0, -settlement.amount)
            expense.amount = max(0, expense.amount + oldOffset)
            if expense.offsetSettlement?.id == settlement.id {
                expense.offsetSettlement = nil
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
            Section("Settlement") {
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
                        .controlSize(.large)
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

private struct EditAllocationSettlementView: View {
    @Bindable var settlement: AllocationSettlement

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var note: String = ""
    @State private var amountText: String = ""
    @State private var date: Date = .now

    @State private var direction: Int = -1

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingSaveErrorAlert: Bool = false
    @State private var saveErrorMessage: String = ""

    private var isLinkedToExpense: Bool {
        settlement.expense != nil
    }

    private var canSave: Bool {
        guard let rawAmount = CurrencyFormatter.parseAmount(amountText) else { return false }
        return rawAmount > 0
    }

    var body: some View {
        Form {
            if isLinkedToExpense {
                Section {
                    Text("This settlement is linked to an expense. Saving updates the expense amount and date.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Settlement") {
                TextField("Note", text: $note)

                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)

                if isLinkedToExpense {
                    HStack {
                        Text("Direction")
                        Spacer()
                        Text("I Owe Them")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Direction", selection: $direction) {
                        Text("They Owe Me").tag(1)
                        Text("I Owe Them").tag(-1)
                    }
                    .pickerStyle(.segmented)
                }

                HStack {
                    Text("Date")
                    Spacer()
                    PillDatePickerField(title: "Date", date: $date)
                }
            }
        }
        .navigationTitle("Edit Settlement")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }

            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
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
        .alert("Couldn't Save Settlement", isPresented: $showingSaveErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
        .onAppear {
            note = settlement.note
            date = settlement.date

            if settlement.amount < 0 {
                direction = -1
                amountText = CurrencyFormatter.editingString(from: -settlement.amount)
            } else {
                direction = 1
                amountText = CurrencyFormatter.editingString(from: settlement.amount)
            }
        }
    }

    private func save() {
        guard let rawAmount = CurrencyFormatter.parseAmount(amountText), rawAmount > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)

        if let expense = settlement.expense {
            let oldOffset = max(0, -settlement.amount)
            let grossAmount = max(0, expense.amount + oldOffset)
            let newOffset = rawAmount

            guard newOffset <= grossAmount else {
                saveErrorMessage = "Offset can't exceed the linked expense amount."
                showingSaveErrorAlert = true
                return
            }

            settlement.note = trimmedNote
            settlement.date = date
            settlement.amount = -newOffset

            expense.amount = max(0, grossAmount - newOffset)
            expense.transactionDate = date
        } else {
            settlement.note = trimmedNote
            settlement.date = date
            settlement.amount = Double(direction) * rawAmount
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveErrorAlert = true
        }
    }
}
