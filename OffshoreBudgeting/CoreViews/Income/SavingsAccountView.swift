import SwiftUI
import SwiftData
import Charts

struct SavingsAccountView: View {

    let workspace: Workspace

    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCommandHub) private var commandHub

    @Query private var savingsAccounts: [SavingsAccount]
    @Query private var savingsEntries: [SavingsLedgerEntry]

    @State private var didInitializeDateRange: Bool = false
    @State private var draftStartDate: Date = .now
    @State private var draftEndDate: Date = .now
    @State private var appliedStartDate: Date = .now
    @State private var appliedEndDate: Date = .now
    @State private var isApplyingQuickRange: Bool = false

    @State private var showingEntrySheet: Bool = false
    @State private var editingEntry: SavingsLedgerEntry? = nil

    @State private var showingDeleteConfirm: Bool = false
    @State private var pendingDeleteEntry: SavingsLedgerEntry? = nil
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool
    @State private var lastHandledCommandSequence: Int? = nil

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _savingsAccounts = Query(
            filter: #Predicate<SavingsAccount> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\SavingsAccount.createdAt, order: .forward)]
        )

        _savingsEntries = Query(
            filter: #Predicate<SavingsLedgerEntry> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\SavingsLedgerEntry.date, order: .reverse)]
        )
    }

    private var account: SavingsAccount? {
        savingsAccounts.first
    }

    private var displayRows: [SavingsLedgerEntry] {
        let dateFiltered = savingsEntries
            .filter { entry in
                entry.date >= normalizedStart(appliedStartDate) && entry.date <= normalizedEnd(appliedEndDate)
            }
            .sorted { lhs, rhs in
                if lhs.date == rhs.date {
                    return lhs.createdAt > rhs.createdAt
                }
                return lhs.date > rhs.date
            }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return dateFiltered }
        return dateFiltered.filter { entry in
            entryMatchesSearch(entry, query: trimmedSearch)
        }
    }

    private var isDateDirty: Bool {
        let cal = Calendar.current
        let s1 = cal.startOfDay(for: draftStartDate)
        let s2 = cal.startOfDay(for: appliedStartDate)
        let e1 = cal.startOfDay(for: draftEndDate)
        let e2 = cal.startOfDay(for: appliedEndDate)
        return s1 != s2 || e1 != e2
    }

    private var runningTotal: Double {
        account?.total ?? 0
    }

    private var chartPoints: [SavingsChartPoint] {
        let rangeStart = normalizedStart(appliedStartDate)
        let rangeEnd = normalizedEnd(appliedEndDate)

        let entriesAsc = savingsEntries.sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.date < rhs.date
        }

        let totalBeforeRange = entriesAsc
            .filter { $0.date < rangeStart }
            .reduce(0) { $0 + $1.amount }

        let entriesInRange = entriesAsc.filter { entry in
            entry.date >= rangeStart && entry.date <= rangeEnd
        }

        guard !entriesInRange.isEmpty else { return [] }

        var total: Double = totalBeforeRange
        var totalsByDay: [Date: Double] = [:]
        totalsByDay[rangeStart] = totalBeforeRange

        for entry in entriesInRange {
            total += entry.amount
            let day = Calendar.current.startOfDay(for: entry.date)
            totalsByDay[day] = total
        }

        return totalsByDay
            .keys
            .sorted()
            .map { day in
                SavingsChartPoint(date: day, total: totalsByDay[day] ?? 0)
            }
    }

    var body: some View {
        List {


            Section {
                savingsChartSection
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            Section("Date Range") {
                DateRangeFilterRow(
                    draftStartDate: $draftStartDate,
                    draftEndDate: $draftEndDate,
                    isGoEnabled: isDateDirty && !isApplyingQuickRange,
                    onTapGo: applyDraftDates,
                    onSelectQuickRange: applyQuickRangePresetDeferred
                )
            }

            Section("Savings Account") {
                HStack {
                    Text("Running Total")
                    Spacer()
                    Text(runningTotal, format: CurrencyFormatter.currencyStyle())
                        .font(.headline)
                        .foregroundStyle(runningTotal >= 0 ? .green : .red)
                }
            }

            Section("Ledger") {
                if displayRows.isEmpty {
                    Text("No savings entries for this date range.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayRows) { entry in
                        Button {
                            editingEntry = entry
                            showingEntrySheet = true
                        } label: {
                            SavingsLedgerRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingEntry = entry
                                showingEntrySheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Color("AccentColor"))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                requestDelete(entry)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .tint(Color("OffshoreDepth"))
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            initializeDateRangeIfNeeded()
            if account == nil {
                _ = SavingsAccountService.ensureSavingsAccount(for: workspace, modelContext: modelContext)
                try? modelContext.save()
            }
        }
        .onChange(of: defaultBudgetingPeriodRaw) { _, _ in
            applyDefaultPeriodRange()
        }
        .onReceive(commandHub.$sequence) { sequence in
            if lastHandledCommandSequence == nil {
                lastHandledCommandSequence = sequence
                return
            }

            guard sequence != lastHandledCommandSequence else { return }
            lastHandledCommandSequence = sequence
            handleCommand(commandHub.latestCommandID)
        }
        .alert("Delete Entry?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let pendingDeleteEntry {
                    deleteEntry(pendingDeleteEntry)
                }
                pendingDeleteEntry = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteEntry = nil
            }
        } message: {
            Text("This savings entry will be deleted.")
        }
        .sheet(isPresented: $showingEntrySheet, onDismiss: {
            editingEntry = nil
        }) {
            NavigationStack {
                SavingsLedgerEntryFormView(
                    workspace: workspace,
                    account: account,
                    entry: editingEntry,
                    onSave: { date, amount, note, kind in
                        saveEntry(date: date, amount: amount, note: note, kind: kind)
                    }
                )
            }
        }
    }

    // MARK: - Chart

    private var savingsChartSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Savings Trend")
                .font(.headline.weight(.semibold))

            if chartPoints.isEmpty {
                Text("No savings history yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(chartPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("Total", point.total)
                    )
                    .foregroundStyle(.green)

                    AreaMark(
                        x: .value("Date", point.date),
                        y: .value("Total", point.total)
                    )
                    .foregroundStyle(.green.opacity(0.2))
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel(format: CurrencyFormatter.currencyStyle())
                    }
                }
                .frame(height: 240)
//                .padding(.horizontal, 12)
//                .padding(.bottom, 12)
            }
        }
////        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
//        .padding(.horizontal, 16)
//        .padding(.vertical, 8)
        .padding(14)
    }

    // MARK: - Date Range

    private func initializeDateRangeIfNeeded() {
        guard !didInitializeDateRange else { return }
        didInitializeDateRange = true
        applyDefaultPeriodRange()
    }

    private func applyDefaultPeriodRange() {
        let now = Date()
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let range = period.defaultRange(containing: now, calendar: .current)

        draftStartDate = normalizedStart(range.start)
        draftEndDate = normalizedEnd(range.end)
        appliedStartDate = draftStartDate
        appliedEndDate = draftEndDate
    }

    private func applyDraftDates() {
        appliedStartDate = normalizedStart(draftStartDate)
        appliedEndDate = normalizedEnd(draftEndDate)
    }

    private func applyQuickRangePresetDeferred(_ preset: CalendarQuickRangePreset) {
        isApplyingQuickRange = true
        let range = preset.makeRange(now: Date(), calendar: .current)
        draftStartDate = normalizedStart(range.start)
        draftEndDate = normalizedEnd(range.end)

        DispatchQueue.main.async {
            applyDraftDates()
            isApplyingQuickRange = false
        }
    }

    private func normalizedStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func normalizedEnd(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private func entryMatchesSearch(_ entry: SavingsLedgerEntry, query: String) -> Bool {
        let normalized = query.lowercased()

        let typeLabel = kindLabel(for: entry.kind)
        let searchableFields = [
            entry.note,
            typeLabel,
            AppDateFormat.abbreviatedDate(entry.date),
            AppDateFormat.numericDate(entry.date),
            CurrencyFormatter.string(from: entry.amount),
            CurrencyFormatter.editingString(from: entry.amount),
            String(entry.amount),
            String(format: "%.2f", entry.amount)
        ]

        return searchableFields.contains { field in
            field.lowercased().contains(normalized)
        }
    }

    private func kindLabel(for kind: SavingsLedgerEntryKind) -> String {
        switch kind {
        case .periodClose:
            return "Period Close"
        case .manualAdjustment:
            return "Manual Adjustment"
        case .expenseOffset:
            return "Expense Offset"
        }
    }

    // MARK: - Actions

    private func saveEntry(date: Date, amount: Double, note: String, kind: SavingsLedgerEntryKind) {
        guard let account else { return }

        if let editingEntry {
            editingEntry.date = date
            editingEntry.amount = amount
            editingEntry.note = note
            editingEntry.kind = kind
            editingEntry.updatedAt = .now
        } else {
            let entry = SavingsLedgerEntry(
                date: date,
                amount: amount,
                note: note,
                kindRaw: kind.rawValue,
                workspace: workspace,
                account: account
            )
            modelContext.insert(entry)
        }

        SavingsAccountService.recalculateAccountTotal(account)
        try? modelContext.save()
    }

    private func requestDelete(_ entry: SavingsLedgerEntry) {
        if confirmBeforeDeleting {
            pendingDeleteEntry = entry
            showingDeleteConfirm = true
        } else {
            deleteEntry(entry)
        }
    }

    private func deleteEntry(_ entry: SavingsLedgerEntry) {
        SavingsAccountService.deleteEntry(entry, modelContext: modelContext)
    }

    private func handleCommand(_ commandID: String) {
        guard commandID == AppCommandID.Savings.newEntry else { return }
        editingEntry = nil
        showingEntrySheet = true
    }
}

private struct SavingsChartPoint: Identifiable {
    let id = UUID()
    let date: Date
    let total: Double
}

private struct SavingsLedgerRow: View {
    let entry: SavingsLedgerEntry

    private var subtitle: String {
        switch entry.kind {
        case .periodClose:
            return "Period Close"
        case .manualAdjustment:
            return "Manual Adjustment"
        case .expenseOffset:
            return "Expense Offset"
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.note.isEmpty ? subtitle : entry.note)
                    .font(.headline)

                Text("\(subtitle) • \(AppDateFormat.abbreviatedDate(entry.date))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(entry.amount, format: CurrencyFormatter.currencyStyle())
                .font(.headline)
                .foregroundStyle(entry.amount >= 0 ? .green : .red)
        }
    }
}

private struct SavingsLedgerEntryFormView: View {
    let workspace: Workspace
    let account: SavingsAccount?
    let entry: SavingsLedgerEntry?
    let onSave: (Date, Double, String, SavingsLedgerEntryKind) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = .now
    @State private var amountText: String = ""
    @State private var note: String = ""
    @State private var kind: SavingsLedgerEntryKind = .manualAdjustment

    @State private var showingInvalidAmount: Bool = false

    private var saveTitle: String {
        entry == nil ? "Add Savings Entry" : "Edit Savings Entry"
    }

    var body: some View {
        List {
            Section("Details") {
                HStack {
                    Text("Date")
                    Spacer()
                    PillDatePickerField(title: "Date", date: $date)
                }

                TextField("Amount", text: $amountText)
                    .keyboardType(.decimalPad)

                TextField("Note", text: $note)

                Picker("Type", selection: $kind) {
                    Text("Manual").tag(SavingsLedgerEntryKind.manualAdjustment)
                    Text("Period Close").tag(SavingsLedgerEntryKind.periodClose)
                    Text("Expense Offset").tag(SavingsLedgerEntryKind.expenseOffset)
                }
            }

            if let account {
                Section("Current Balance") {
                    Text(account.total, format: CurrencyFormatter.currencyStyle())
                }
            }
        }
        .navigationTitle(saveTitle)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
            }
        }
        .alert("Invalid Amount", isPresented: $showingInvalidAmount) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter a valid amount.")
        }
        .onAppear {
            if let entry {
                date = entry.date
                amountText = CurrencyFormatter.editingString(from: entry.amount)
                note = entry.note
                kind = entry.kind
            }
        }
    }

    private func save() {
        guard let amount = CurrencyFormatter.parseAmount(amountText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            showingInvalidAmount = true
            return
        }

        onSave(date, amount, note.trimmingCharacters(in: .whitespacesAndNewlines), kind)
        dismiss()
    }
}
