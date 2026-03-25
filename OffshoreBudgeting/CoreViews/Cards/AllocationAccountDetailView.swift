import SwiftUI
import SwiftData

struct AllocationAccountDetailView: View {
    let workspace: Workspace
    @Bindable var account: AllocationAccount

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

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
    @State private var didInitializeDateRange: Bool = false
    @State private var draftStartDate: Date = .now
    @State private var draftEndDate: Date = .now
    @State private var appliedStartDate: Date = .now
    @State private var appliedEndDate: Date = .now
    @State private var isApplyingQuickRange: Bool = false
    @State private var selectedCategoryIDs: Set<UUID> = []
    @State private var sortMode: ReconciliationDetailSortMode = .dateDesc
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

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

    private var isDateDirty: Bool {
        let cal = Calendar.current
        let s1 = cal.startOfDay(for: draftStartDate)
        let s2 = cal.startOfDay(for: appliedStartDate)
        let e1 = cal.startOfDay(for: draftEndDate)
        let e2 = cal.startOfDay(for: appliedEndDate)
        return s1 != s2 || e1 != e2
    }

    private var derivedState: ReconciliationDetailDerivedState {
        buildDerivedState()
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            balanceSection(derivedState)
            dateRangeSection

            if !derivedState.availableCategoriesForChips.isEmpty {
                categorySection(derivedState)
            }

            sortSection
            ledgerSection(derivedState)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(account.name)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search"
        )
        .searchFocused($searchFocused)
        .onAppear {
            initializeDateRangeIfNeeded()
        }
        .onDisappear {
            searchFocused = false
        }
        .onChange(of: defaultBudgetingPeriodRaw) { _, _ in
            applyDefaultPeriodRange()
        }
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
            Text("Deleting this split charge will remove the split without changing the original expense amount.")
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

    private func buildDerivedState() -> ReconciliationDetailDerivedState {
        let rows = ledgerRows

        var categoriesByID: [UUID: Category] = [:]
        for row in rows {
            if let category = category(for: row) {
                categoriesByID[category.id] = category
            }
        }
        let availableCategoriesForChips = categoriesByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        let start = normalizedStart(appliedStartDate)
        let end = normalizedEnd(appliedEndDate)
        let query = SearchQueryParser.parse(searchText)

        let dateFiltered = rows.filter { row in
            row.date >= start && row.date <= end
        }

        let categoryFiltered: [AllocationLedgerService.LedgerRow]
        if selectedCategoryIDs.isEmpty {
            categoryFiltered = dateFiltered
        } else {
            categoryFiltered = dateFiltered.filter { row in
                guard let categoryID = category(for: row)?.id else { return false }
                return selectedCategoryIDs.contains(categoryID)
            }
        }

        let searchedRows: [AllocationLedgerService.LedgerRow]
        if query.isEmpty {
            searchedRows = categoryFiltered
        } else {
            searchedRows = categoryFiltered.filter { row in
                ReconciliationDetailSearch.matches(
                    row: row,
                    categoryName: category(for: row)?.name,
                    query: query
                )
            }
        }

        let sortedRows = sortMode.sorted(searchedRows)
        let slices = categoryHeatSlices(for: searchedRows, limit: 10)

        return ReconciliationDetailDerivedState(
            availableCategoriesForChips: availableCategoriesForChips,
            filteredLedgerRows: sortedRows,
            filteredAmountValue: CurrencyFormatter.normalizedCurrencyDisplayValue(
                searchedRows
                    .filter { $0.type == .charge }
                    .reduce(0) { partial, row in
                        partial + max(0, row.amount)
                    }
            ),
            heatMapStops: gradientStops(from: slices)
        )
    }

    private func category(for row: AllocationLedgerService.LedgerRow) -> Category? {
        if let allocationID = row.allocationID {
            let allocation = allocation(for: allocationID)
            return allocation?.expense?.category ?? allocation?.plannedExpense?.category
        }

        if let settlementID = row.settlementID {
            let settlement = settlement(for: settlementID)
            return settlement?.expense?.category ?? settlement?.plannedExpense?.category
        }

        return nil
    }

    private func categoryHeatSlices(
        for rows: [AllocationLedgerService.LedgerRow],
        limit: Int
    ) -> [ReconciliationCategorySpendSlice] {
        var totalsByCategoryID: [UUID: (category: Category, total: Double)] = [:]

        for row in rows {
            guard let category = category(for: row) else { continue }
            let amount = abs(row.amount)
            guard amount > 0 else { continue }

            if let existing = totalsByCategoryID[category.id] {
                totalsByCategoryID[category.id] = (existing.category, existing.total + amount)
            } else {
                totalsByCategoryID[category.id] = (category, amount)
            }
        }

        var slices = totalsByCategoryID.values
            .map {
                ReconciliationCategorySpendSlice(
                    id: $0.category.id,
                    hexColor: $0.category.hexColor,
                    amount: $0.total
                )
            }
            .sorted { $0.amount > $1.amount }

        if slices.count > limit {
            slices = Array(slices.prefix(limit))
        }

        let total = slices.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }

        var cursor: Double = 0
        slices = slices.map { slice in
            let width = slice.amount / total
            let start = cursor
            let end = min(1.0, cursor + width)
            cursor = end
            return ReconciliationCategorySpendSlice(
                id: slice.id,
                hexColor: slice.hexColor,
                amount: slice.amount,
                start: start,
                end: end
            )
        }

        if var last = slices.last, last.end < 1.0 {
            last.end = 1.0
            slices[slices.count - 1] = last
        }

        return slices
    }

    private func gradientStops(from slices: [ReconciliationCategorySpendSlice]) -> [Gradient.Stop] {
        guard !slices.isEmpty else { return [] }

        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(slices.count * 2)

        for slice in slices {
            let color = Color(hex: slice.hexColor) ?? Color.secondary.opacity(0.35)
            stops.append(.init(color: color, location: slice.start))
            stops.append(.init(color: color, location: slice.end))
        }

        if stops.first?.location != 0 {
            let firstColor = stops.first?.color ?? Color.secondary.opacity(0.35)
            stops.insert(.init(color: firstColor, location: 0), at: 0)
        }

        if stops.last?.location != 1 {
            let lastColor = stops.last?.color ?? Color.secondary.opacity(0.35)
            stops.append(.init(color: lastColor, location: 1))
        }

        return stops
    }

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
        applyQuickRangePreset(preset)
        DispatchQueue.main.async {
            applyDraftDates()
            isApplyingQuickRange = false
        }
    }

    private func applyQuickRangePreset(_ preset: CalendarQuickRangePreset) {
        let range = preset.makeRange(now: Date(), calendar: .current)
        draftStartDate = normalizedStart(range.start)
        draftEndDate = normalizedEnd(range.end)
    }

    private func normalizedStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func normalizedEnd(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private func balanceSection(_ derived: ReconciliationDetailDerivedState) -> some View {
        Section {
            ReconciliationBalanceStatementRow(
                total: balance,
                heatMapStops: derived.heatMapStops
            )
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
        } header: {
            Text("Balance")
        } footer: {
            Text("Current outstanding reconciliation balance across all history.")
        }
    }

    private var dateRangeSection: some View {
        Section {
            ReconciliationDateFilterRow(
                draftStartDate: $draftStartDate,
                draftEndDate: $draftEndDate,
                isGoEnabled: isDateDirty && !isApplyingQuickRange,
                onTapGo: applyDraftDates,
                onSelectQuickRange: applyQuickRangePresetDeferred
            )
        } header: {
            Text("Date Range")
        }
    }

    private func categorySection(_ derived: ReconciliationDetailDerivedState) -> some View {
        Section {
            ReconciliationCategoryChipsRow(
                categories: derived.availableCategoriesForChips,
                selectedIDs: $selectedCategoryIDs
            )
        } header: {
            HStack {
                Text("Categories")
                Spacer()
                if !selectedCategoryIDs.isEmpty {
                    Button("Clear") {
                        selectedCategoryIDs.removeAll()
                    }
                    .buttonStyle(.plain)
                }
            }
        } footer: {
            Text(
                selectedCategoryIDs.isEmpty
                ? "Single-press categories to filter ledger entries."
                : "Tap selected chips to clear one at a time, or use Clear to reset all."
            )
        }
    }

    private var sortSection: some View {
        Section {
            Picker("Sort", selection: $sortMode) {
                Text("A-Z").tag(ReconciliationDetailSortMode.az)
                Text("Z-A").tag(ReconciliationDetailSortMode.za)
                Text("\(CurrencyFormatter.currencySymbol)↑").tag(ReconciliationDetailSortMode.amountAsc)
                Text("\(CurrencyFormatter.currencySymbol)↓").tag(ReconciliationDetailSortMode.amountDesc)
                Text(String(localized: "sort.dateShort.asc", defaultValue: "D↑", comment: "Compact ascending date sort label for segmented controls.")).tag(ReconciliationDetailSortMode.dateAsc)
                Text(String(localized: "sort.dateShort.desc", defaultValue: "D↓", comment: "Compact descending date sort label for segmented controls.")).tag(ReconciliationDetailSortMode.dateDesc)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Sort")
        }
    }

    private func ledgerSection(_ derived: ReconciliationDetailDerivedState) -> some View {
        Section {
            if derived.filteredLedgerRows.isEmpty {
                Text(emptyLedgerMessage)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(derived.filteredLedgerRows) { row in
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
        } header: {
            Text("Period Activity • \(derived.filteredAmountValue, format: CurrencyFormatter.currencyStyle())")
        } footer: {
            Text("Shows filtered charge activity for the selected date range and categories.")
        }
    }

    private var emptyLedgerMessage: String {
        if isSearching {
            return ReconciliationDetailEmptyState.message(
                hasHistory: hasHistory,
                isSearching: true,
                selectedCategoryCount: selectedCategoryIDs.count
            )
        }

        if !selectedCategoryIDs.isEmpty {
            return ReconciliationDetailEmptyState.message(
                hasHistory: hasHistory,
                isSearching: false,
                selectedCategoryCount: selectedCategoryIDs.count
            )
        }

        if hasHistory {
            return ReconciliationDetailEmptyState.message(
                hasHistory: true,
                isSearching: false,
                selectedCategoryCount: 0
            )
        }

        return ReconciliationDetailEmptyState.message(
            hasHistory: false,
            isSearching: false,
            selectedCategoryCount: 0
        )
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

            VStack(alignment: .trailing, spacing: 2) {
                Text(
                    CurrencyFormatter.normalizedCurrencyDisplayValue(row.amount),
                    format: CurrencyFormatter.currencyStyle()
                )
                .font(.body.weight(.semibold))

                Text(
                    CurrencyFormatter.normalizedCurrencyDisplayValue(row.runningBalance),
                    format: CurrencyFormatter.currencyStyle()
                )
                .font(.caption)
                .foregroundStyle(runningBalanceColor(for: row.runningBalance))
            }
        }
        .padding(.vertical, 2)
    }

    private func runningBalanceColor(for balance: Double) -> Color {
        if balance > 0 {
            return .red
        }

        if balance < 0 {
            return .green
        }

        return .secondary
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
            if expense.offsetSettlement?.id == settlement.id {
                expense.offsetSettlement = nil
            }
        } else if let plannedExpense = settlement.plannedExpense {
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
            expense.amount = SavingsMathService.variableGrossAmount(for: expense)

            if expense.allocation?.id == allocation.id {
                expense.allocation = nil
            }
        } else if let plannedExpense = allocation.plannedExpense {
            let grossRecordedActual = SavingsMathService.grossRecordedActualAmount(for: plannedExpense)
            if grossRecordedActual > 0 {
                plannedExpense.actualAmount = grossRecordedActual
            }

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

private struct ReconciliationDetailDerivedState {
    let availableCategoriesForChips: [Category]
    let filteredLedgerRows: [AllocationLedgerService.LedgerRow]
    let filteredAmountValue: Double
    let heatMapStops: [Gradient.Stop]
}

private enum ReconciliationDetailSortMode: String, Identifiable {
    case az
    case za
    case amountAsc
    case amountDesc
    case dateAsc
    case dateDesc

    var id: String { rawValue }

    func sorted(_ rows: [AllocationLedgerService.LedgerRow]) -> [AllocationLedgerService.LedgerRow] {
        rows.sorted(by: compare)
    }

    private func compare(_ lhs: AllocationLedgerService.LedgerRow, _ rhs: AllocationLedgerService.LedgerRow) -> Bool {
        switch self {
        case .az:
            let result = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if result != .orderedSame {
                return result == .orderedAscending
            }
            return descendingTieBreak(lhs, rhs)
        case .za:
            let result = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
            if result != .orderedSame {
                return result == .orderedDescending
            }
            return descendingTieBreak(lhs, rhs)
        case .amountAsc:
            if lhs.amount != rhs.amount {
                return lhs.amount < rhs.amount
            }
            return descendingTieBreak(lhs, rhs)
        case .amountDesc:
            if lhs.amount != rhs.amount {
                return lhs.amount > rhs.amount
            }
            return descendingTieBreak(lhs, rhs)
        case .dateAsc:
            if lhs.date != rhs.date {
                return lhs.date < rhs.date
            }
            return lhs.id < rhs.id
        case .dateDesc:
            return descendingTieBreak(lhs, rhs)
        }
    }

    private func descendingTieBreak(_ lhs: AllocationLedgerService.LedgerRow, _ rhs: AllocationLedgerService.LedgerRow) -> Bool {
        if lhs.date != rhs.date {
            return lhs.date > rhs.date
        }
        return lhs.id > rhs.id
    }
}

private struct ReconciliationCategorySpendSlice: Identifiable {
    let id: UUID
    let hexColor: String
    let amount: Double

    var start: Double = 0
    var end: Double = 0
}

private struct ReconciliationHeatMapBar: View {
    let stops: [Gradient.Stop]

    var body: some View {
        ZStack {
            if !stops.isEmpty {
                LinearGradient(
                    gradient: Gradient(stops: stops),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .saturation(1.75)
                .blur(radius: 36)
                .overlay(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.16),
                            Color.white.opacity(0.05),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReconciliationBalanceStatementRow: View {
    let total: Double
    let heatMapStops: [Gradient.Stop]

    private let cornerRadius: CGFloat = 14

    var body: some View {
        ZStack(alignment: .leading) {
            ReconciliationHeatMapBar(stops: heatMapStops)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(total, format: CurrencyFormatter.currencyStyle())
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 72)
        .contentShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Balance")
        .accessibilityValue(Text(total, format: CurrencyFormatter.currencyStyle()))
    }
}

private struct ReconciliationDateFilterRow: View {
    @Binding var draftStartDate: Date
    @Binding var draftEndDate: Date

    let isGoEnabled: Bool
    let onTapGo: () -> Void
    let onSelectQuickRange: (CalendarQuickRangePreset) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            HStack(spacing: 10) {
                PillDatePickerField(title: "Start Date", date: $draftStartDate)
                    .layoutPriority(1)

                PillDatePickerField(title: "End Date", date: $draftEndDate)
                    .layoutPriority(1)

                Button(action: onTapGo) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(
                                    isGoEnabled
                                    ? Color.accentColor.opacity(0.85)
                                    : Color.secondary.opacity(0.1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .disabled(!isGoEnabled)
                .accessibilityLabel("Apply Date Range")

                Menu {
                    CalendarQuickRangeMenuItems { preset in
                        onSelectQuickRange(preset)
                    }
                } label: {
                    Image(systemName: "calendar")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(Color.secondary.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Quick Date Ranges")
            }

            Spacer(minLength: 0)
        }
    }
}

private struct ReconciliationCategoryChipsRow: View {
    let categories: [Category]
    @Binding var selectedIDs: Set<UUID>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.id) { category in
                    ReconciliationChip(
                        title: category.name,
                        dotHex: category.hexColor,
                        isSelected: selectedIDs.contains(category.id)
                    ) {
                        toggle(category.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
}

private struct ReconciliationChip: View {
    let title: String
    let dotHex: String
    let isSelected: Bool
    let action: () -> Void

    private var baseColor: Color {
        Color(hex: dotHex) ?? Color.secondary.opacity(0.35)
    }

    private var backgroundColor: Color {
        isSelected ? baseColor.opacity(0.20) : Color.secondary.opacity(0.12)
    }

    private var foregroundColor: Color {
        isSelected ? baseColor : .primary
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(baseColor)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
            }
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
        }
        .buttonStyle(.plain)
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
            case .none:
                return String(localized: "action.none", defaultValue: "None", comment: "Action label for no reconciliation adjustment.")
            case .split:
                return String(localized: "Split", defaultValue: "Split", comment: "Shared-balance action label for splitting a linked reconciliation entry.")
            case .offset:
                return String(localized: "Offset", defaultValue: "Offset", comment: "Shared-balance action label for offsetting a linked reconciliation entry.")
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
                guard selectedAccount != nil else {
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
                expense.amount = gross
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
                allocation.preservesGrossAmount = true
                allocation.updatedAt = .now
                allocation.account = account
                allocation.workspace = workspace
                allocation.expense = expense
            } else {
                let allocation = ExpenseAllocation(
                    allocatedAmount: AllocationLedgerService.cappedAllocationAmount(amount, expenseAmount: gross),
                    preservesGrossAmount: true,
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

            expense.amount = gross
        case .offset:
            if let allocation = expense.allocation {
                expense.amount = gross
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

            expense.amount = gross
        }

        expense.transactionDate = date
        expense.workspace = workspace
    }

    private func saveLinkedPlanned(_ plannedExpense: PlannedExpense, account: AllocationAccount, amount: Double) throws {
        let plannedAmount = max(0, plannedExpense.plannedAmount)
        let grossRecordedActual = SavingsMathService.grossRecordedActualAmount(for: plannedExpense)

        switch actionMode {
        case .none:
            if let allocation = plannedExpense.allocation {
                if grossRecordedActual > 0 {
                    plannedExpense.actualAmount = grossRecordedActual
                }
                plannedExpense.allocation = nil
                modelContext.delete(allocation)
            } else if let settlement = plannedExpense.offsetSettlement {
                plannedExpense.offsetSettlement = nil
                modelContext.delete(settlement)
            }
        case .split:
            if let settlement = plannedExpense.offsetSettlement {
                plannedExpense.offsetSettlement = nil
                modelContext.delete(settlement)
            }

            if let allocation = plannedExpense.allocation {
                allocation.allocatedAmount = AllocationLedgerService.cappedAllocationAmount(amount, expenseAmount: plannedAmount)
                allocation.preservesGrossAmount = true
                allocation.updatedAt = .now
                allocation.account = account
                allocation.workspace = workspace
                allocation.expense = nil
                allocation.plannedExpense = plannedExpense
            } else {
                let allocation = ExpenseAllocation(
                    allocatedAmount: AllocationLedgerService.cappedAllocationAmount(amount, expenseAmount: plannedAmount),
                    preservesGrossAmount: true,
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

            if grossRecordedActual > 0 {
                plannedExpense.actualAmount = grossRecordedActual
            }
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

            if grossRecordedActual > 0 {
                plannedExpense.actualAmount = grossRecordedActual
            }
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
        SavingsMathService.variableGrossAmount(for: expense)
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
        try? modelContext.save()
        dismiss()
    }
}
