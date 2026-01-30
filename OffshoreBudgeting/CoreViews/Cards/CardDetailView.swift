//
//  CardDetailView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct CardDetailView: View {
    let workspace: Workspace
    @Bindable var card: Card

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cardsSheetRoute) private var cardsSheetRoute

    @State private var showingCardDeleteConfirm: Bool = false
    @State private var pendingCardDelete: (() -> Void)? = nil

    @State private var showingExpenseDeleteConfirm: Bool = false
    @State private var pendingExpenseDelete: (() -> Void)? = nil

    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    // MARK: - Filters / UI State

    @State private var didInitializeDateRange: Bool = false
    @State private var draftStartDate: Date = .now
    @State private var draftEndDate: Date = .now
    @State private var appliedStartDate: Date = .now
    @State private var appliedEndDate: Date = .now
    @State private var isApplyingQuickRange: Bool = false

    @State private var selectedCategoryID: UUID? = nil

    @State private var expenseScope: ExpenseScope = .unified
    @State private var sortMode: SortMode = .dateDesc

    // MARK: - Derived Data

    private var variableExpensesBase: [VariableExpense] {
        card.variableExpenses ?? []
    }

    private var plannedExpensesBase: [PlannedExpense] {
        card.plannedExpenses ?? []
    }

    private var availableCategoriesForChips: [Category] {
        var byID: [UUID: Category] = [:]

        for expense in variableExpensesBase {
            if let category = expense.category {
                byID[category.id] = category
            }
        }

        for expense in plannedExpensesBase {
            if let category = expense.category {
                byID[category.id] = category
            }
        }

        return byID.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var isDateDirty: Bool {
        let cal = Calendar.current
        let s1 = cal.startOfDay(for: draftStartDate)
        let s2 = cal.startOfDay(for: appliedStartDate)
        let e1 = cal.startOfDay(for: draftEndDate)
        let e2 = cal.startOfDay(for: appliedEndDate)
        return s1 != s2 || e1 != e2
    }

    private var variableExpensesFiltered: [VariableExpense] {
        let start = normalizedStart(appliedStartDate)
        let end = normalizedEnd(appliedEndDate)

        let query = SearchQueryParser.parse(searchText)

        let dateFiltered = variableExpensesBase.filter { expense in
            let d = expense.transactionDate
            return d >= start && d <= end
        }

        let categoryFiltered: [VariableExpense]
        if let selectedCategoryID {
            categoryFiltered = dateFiltered.filter { expense in
                expense.category?.id == selectedCategoryID
            }
        } else {
            categoryFiltered = dateFiltered
        }

        let searched: [VariableExpense]
        if query.isEmpty {
            searched = categoryFiltered
        } else {
            searched = categoryFiltered.filter { expense in
                if !SearchMatch.matchesDateRange(query, date: expense.transactionDate) { return false }
                if !SearchMatch.matchesTextTerms(query, in: [expense.descriptionText, expense.category?.name]) { return false }
                return true
            }
        }

        return sortVariableExpenses(searched, by: sortMode)
    }

    private var plannedExpensesFiltered: [PlannedExpense] {
        let start = normalizedStart(appliedStartDate)
        let end = normalizedEnd(appliedEndDate)

        let query = SearchQueryParser.parse(searchText)

        let dateFiltered = plannedExpensesBase.filter { expense in
            let d = expense.expenseDate
            return d >= start && d <= end
        }

        let categoryFiltered: [PlannedExpense]
        if let selectedCategoryID {
            categoryFiltered = dateFiltered.filter { expense in
                expense.category?.id == selectedCategoryID
            }
        } else {
            categoryFiltered = dateFiltered
        }

        let searched: [PlannedExpense]
        if query.isEmpty {
            searched = categoryFiltered
        } else {
            searched = categoryFiltered.filter { expense in
                if !SearchMatch.matchesDateRange(query, date: expense.expenseDate) { return false }
                if !SearchMatch.matchesTextTerms(query, in: [expense.title, expense.category?.name]) { return false }
                return true
            }
        }

        return sortPlannedExpenses(searched, by: sortMode)
    }

    private var variableTotal: Double {
        variableExpensesFiltered.reduce(0) { $0 + $1.amount }
    }

    private var plannedTotal: Double {
        plannedExpensesFiltered.reduce(0) { $0 + plannedEffectiveAmount($1) }
    }

    private var unifiedTotal: Double {
        variableTotal + plannedTotal
    }

    private var displayTotal: Double {
        switch expenseScope {
        case .planned: return plannedTotal
        case .variable: return variableTotal
        case .unified: return unifiedTotal
        }
    }

    private var unifiedExpensesFiltered: [UnifiedExpenseItem] {
        let merged: [UnifiedExpenseItem] =
            plannedExpensesFiltered.map { .planned($0) } +
            variableExpensesFiltered.map { .variable($0) }

        return sortUnifiedExpenses(merged, by: sortMode)
    }

    // MARK: - Heat Map (Total Spent by Category)

    private var heatMapStops: [Gradient.Stop] {
        let slices = categoryHeatSlicesForCurrentView(limit: 10)
        return gradientStops(from: slices)
    }

    private func categoryHeatSlicesForCurrentView(limit: Int) -> [CategorySpendSlice] {
        // A behavior: reflect current view state (scope + date + selected category + search)
        var totalsByCategoryID: [UUID: (category: Category, total: Double)] = [:]

        func add(category: Category?, amount: Double) {
            guard amount > 0 else { return }
            guard let category else { return }

            if let existing = totalsByCategoryID[category.id] {
                totalsByCategoryID[category.id] = (existing.category, existing.total + amount)
            } else {
                totalsByCategoryID[category.id] = (category, amount)
            }
        }

        switch expenseScope {
        case .planned:
            for expense in plannedExpensesFiltered {
                add(category: expense.category, amount: plannedEffectiveAmount(expense))
            }
        case .variable:
            for expense in variableExpensesFiltered {
                add(category: expense.category, amount: expense.amount)
            }
        case .unified:
            for expense in plannedExpensesFiltered {
                add(category: expense.category, amount: plannedEffectiveAmount(expense))
            }
            for expense in variableExpensesFiltered {
                add(category: expense.category, amount: expense.amount)
            }
        }

        var slices = totalsByCategoryID.values
            .map { CategorySpendSlice(id: $0.category.id, name: $0.category.name, hexColor: $0.category.hexColor, amount: $0.total) }
            .sorted { $0.amount > $1.amount }

        if slices.count > limit {
            slices = Array(slices.prefix(limit))
        }

        let total = slices.reduce(0) { $0 + $1.amount }
        guard total > 0 else { return [] }

        // Assign positions [0...1] by weight, biggest categories get the most territory.
        var cursor: Double = 0
        slices = slices.map { slice in
            let w = slice.amount / total
            let start = cursor
            let end = min(1.0, cursor + w)
            cursor = end
            return CategorySpendSlice(
                id: slice.id,
                name: slice.name,
                hexColor: slice.hexColor,
                amount: slice.amount,
                start: start,
                end: end
            )
        }

        // If floating-point math leaves a tiny gap at the end, stretch the last slice to 1.0.
        if var last = slices.last, last.end < 1.0 {
            last.end = 1.0
            slices[slices.count - 1] = last
        }

        return slices
    }

    private func gradientStops(from slices: [CategorySpendSlice]) -> [Gradient.Stop] {
        guard !slices.isEmpty else { return [] }

        var stops: [Gradient.Stop] = []
        stops.reserveCapacity(slices.count * 2)

        for slice in slices {
            let color = Color(hex: slice.hexColor) ?? Color.secondary.opacity(0.35)

            // Two stops per slice creates a "plateau" of color territory.
            stops.append(.init(color: color, location: slice.start))
            stops.append(.init(color: color, location: slice.end))
        }

        // Ensure the first stop starts exactly at 0 for nice edge behavior.
        if stops.first?.location != 0 {
            let firstColor = stops.first?.color ?? Color.secondary.opacity(0.35)
            stops.insert(.init(color: firstColor, location: 0), at: 0)
        }

        // Ensure we end at 1.
        if stops.last?.location != 1 {
            let lastColor = stops.last?.color ?? Color.secondary.opacity(0.35)
            stops.append(.init(color: lastColor, location: 1))
        }

        return stops
    }
    
    // MARK: - List title (reacts to scope)

    private var expensesTitleText: Text {
        switch expenseScope {
        case .planned:
            return Text("Planned Expenses • \(plannedTotal, format: CurrencyFormatter.currencyStyle())")

        case .variable:
            return Text("Variable Expenses • \(variableTotal, format: CurrencyFormatter.currencyStyle())")

        case .unified:
            return Text("All Expenses • \(unifiedTotal, format: CurrencyFormatter.currencyStyle())")
        }
    }
    
    // MARK: - Body

    var body: some View {
        List {

            // MARK: - Hero Card

            Section {
                HeroCardRow(
                    title: card.name,
                    theme: cardThemeOption(from: card.theme),
                    effect: cardEffectOption(from: card.effect)
                )
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowSeparator(.hidden)
            }

            // MARK: - Date Filter Row

            Section {
                DateFilterRow(
                    draftStartDate: $draftStartDate,
                    draftEndDate: $draftEndDate,
                    isGoEnabled: isDateDirty && !isApplyingQuickRange,
                    onTapGo: { applyDraftDates() },
                    onSelectQuickRange: { applyQuickRangePresetDeferred($0) }
                )
            } header: {
                Text("Date Range")
            }

            // MARK: - Total Spent (Statement)

            Section {
                TotalSpentStatementRow(
                    total: displayTotal,
                    heatMapStops: heatMapStops
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            } header: {
                Text("Total Spent")
            }

            // MARK: - Category Chips

            if !availableCategoriesForChips.isEmpty {
                Section {
                    CategoryChipsRow(
                        categories: availableCategoriesForChips,
                        selectedID: $selectedCategoryID
                    )
                } header: {
                    Text("Categories")
                } footer: {
                    Text(selectedCategoryID == nil ? "Single-press a category to filter expenses." : "Make another selection or tap the selected chip again to clear.")
                }
            }

            // MARK: - Sort

            Section {
                
                Picker("Scope", selection: $expenseScope) {
                    Text("Planned").tag(ExpenseScope.planned)
                    Text("Unified").tag(ExpenseScope.unified)
                    Text("Variable").tag(ExpenseScope.variable)
                }
                .pickerStyle(.segmented)
                
                Picker("Sort", selection: $sortMode) {
                    Text("A–Z").tag(SortMode.az)
                    Text("$↓").tag(SortMode.amountDesc)
                    Text("$↑").tag(SortMode.amountAsc)
                    Text("Date ↑").tag(SortMode.dateAsc)
                    Text("Date ↓").tag(SortMode.dateDesc)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Sort")
            }
            // MARK: - Expenses

            Section {
                switch expenseScope {

                case .planned:
                    if plannedExpensesFiltered.isEmpty {
                        Text(emptyMessage())
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(plannedExpensesFiltered, id: \.id) { expense in
                            PlannedExpenseRow(expense: expense)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        openEdit(expense)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)

                                    if let preset = presetForPlannedExpense(expense) {
                                        Button {
                                            openEditPreset(preset)
                                        } label: {
                                            Label("Edit Preset", systemImage: "list.bullet.rectangle")
                                        }
                                        .tint(.indigo)
                                    }
                                }
                        }
                        .onDelete(perform: deletePlannedExpensesFiltered)
                    }

                case .variable:
                    if variableExpensesFiltered.isEmpty {
                        Text(emptyMessage())
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(variableExpensesFiltered, id: \.id) { expense in
                            Button {
                                openEdit(expense)
                            } label: {
                                VariableExpenseRow(expense: expense)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    openEdit(expense)
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                        }
                        .onDelete(perform: deleteVariableExpensesFiltered)
                    }

                case .unified:
                    if unifiedExpensesFiltered.isEmpty {
                        Text(emptyMessage())
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(unifiedExpensesFiltered, id: \.id) { item in
                            switch item {
                            case .planned(let expense):
                                PlannedExpenseRow(expense: expense)
                                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                        Button {
                                            openEdit(expense)
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(.blue)

                                        if let preset = presetForPlannedExpense(expense) {
                                            Button {
                                                openEditPreset(preset)
                                            } label: {
                                                Label("Edit Preset", systemImage: "list.bullet.rectangle")
                                            }
                                            .tint(.indigo)
                                        }
                                    }

                            case .variable(let expense):
                                Button {
                                    openEdit(expense)
                                } label: {
                                    VariableExpenseRow(expense: expense)
                                }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        openEdit(expense)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                        .onDelete(perform: deleteUnifiedExpensesFiltered)
                    }
                }
            } header: {
                expensesTitleText
            }
        }
        .postBoardingTip(
            key: "tip.carddetail.v1",
            title: "Card Detail Overview",
            items: [
                PostBoardingTipItem(
                    systemImage: "list.bullet.below.rectangle",
                    title: "Detailed Overview",
                    detail: "Review expenses with advanced filtering."
                ),
                PostBoardingTipItem(
                    systemImage: "magnifyingglass",
                    title: "Search for Expenses",
                    detail: "Search by name, category, or date using the search bar."
                ),
                PostBoardingTipItem(
                    systemImage: "tag",
                    title: "Categories",
                    detail: "Tap a category to filter expenses by that category alone, then tap the same category again to clear your selection."
                ),
                PostBoardingTipItem(
                    systemImage: "tray.and.arrow.down.fill",
                    title: "Import Expenses",
                    detail: "Using the plus button in the top right, choose Import Expenses (.csv) and import expenses easily to your card."
                )
            ]
        )
        .listStyle(.insetGrouped)
        .navigationTitle(card.name)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search"
        )
        .searchFocused($searchFocused)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {

                Menu {
                    Button {
                        cardsSheetRoute.wrappedValue = .addExpense(defaultCard: card)
                    } label: {
                        Label("Add Transaction", systemImage: "plus")
                    }

                    Button {
                        cardsSheetRoute.wrappedValue = .importExpenses(card: card)
                    } label: {
                        Label("Import Expenses (.csv)", systemImage: "tray.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
                
                Menu {
                    Button {
                        cardsSheetRoute.wrappedValue = .editCard(card)
                    } label: {
                        Label("Edit Card", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        if confirmBeforeDeleting {
                            pendingCardDelete = {
                                deleteCard()
                            }
                            showingCardDeleteConfirm = true
                        } else {
                            deleteCard()
                        }
                    } label: {
                        Label("Delete Card", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Card Actions")
            }
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
        .alert("Delete Expense?", isPresented: $showingExpenseDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingExpenseDelete?()
                pendingExpenseDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingExpenseDelete = nil
            }
        }
        .onAppear {
            initializeDateRangeIfNeeded()
        }
        .onChange(of: defaultBudgetingPeriodRaw) { _, _ in
            applyDefaultPeriodRange()
        }
    }

    // MARK: - Empty State

    private func emptyMessage() -> String {
        if selectedCategoryID != nil {
            return "No expenses match the selected category in this date range."
        }
        return "No expenses yet for this date range."
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

    private func applyQuickRangePreset(_ preset: QuickRangePreset) {
        switch preset {
        case .today:
            applyQuickRange(.today())
        case .thisWeek:
            applyQuickRange(.thisWeek())
        case .thisMonth:
            applyQuickRange(.thisMonth())
        case .thisQuarter:
            applyQuickRange(.thisQuarter())
        case .thisYear:
            applyQuickRange(.thisYear())
        }
    }

    private func applyQuickRangePresetDeferred(_ preset: QuickRangePreset) {
        // Update draft immediately so the UI reflects the selection,
        // then apply on the next run loop, so the menu can dismiss cleanly.
        isApplyingQuickRange = true
        applyQuickRangePreset(preset)
        DispatchQueue.main.async {
            applyDraftDates()
            isApplyingQuickRange = false
        }
    }

    private func applyQuickRange(_ range: DateRange) {
        draftStartDate = normalizedStart(range.start)
        draftEndDate = normalizedEnd(range.end)
        // Do not apply here, applyQuickRangePresetDeferred handles it.
    }

    private func normalizedStart(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func normalizedEnd(_ date: Date) -> Date {
        let start = Calendar.current.startOfDay(for: date)
        return Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
    
    private func refreshDateRangeIfSafe() {
        // If the user has manually adjusted the range, do not fight them.
        guard !isDateDirty else { return }

        let variableDates = (card.variableExpenses ?? []).map(\.transactionDate)
        let plannedDates = (card.plannedExpenses ?? []).map(\.expenseDate)
        let allDates = variableDates + plannedDates

        guard let minDate = allDates.min(), let maxDate = allDates.max() else { return }

        let start = normalizedStart(minDate)
        let end = normalizedEnd(maxDate)

        draftStartDate = start
        draftEndDate = end
        appliedStartDate = start
        appliedEndDate = end
    }


    // MARK: - DateRange helper (local)

    private struct DateRange {
        let start: Date
        let end: Date

        static func today() -> DateRange {
            let cal = Calendar.current
            let start = cal.startOfDay(for: Date())
            let end = cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? start
            return DateRange(start: start, end: end)
        }

        static func thisWeek() -> DateRange {
            let cal = Calendar.current
            let now = Date()

            // Start of week based on user’s locale settings
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: DateComponents(day: 7, second: -1), to: start) ?? now
            return DateRange(start: start, end: end)
        }

        static func thisMonth() -> DateRange {
            let cal = Calendar.current
            let now = Date()

            let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
            return DateRange(start: start, end: end)
        }

        static func thisQuarter() -> DateRange {
            let cal = Calendar.current
            let now = Date()

            let comps = cal.dateComponents([.year, .month], from: now)
            let year = comps.year ?? cal.component(.year, from: now)
            let month = comps.month ?? cal.component(.month, from: now)

            let quarterStartMonth: Int
            switch month {
            case 1...3: quarterStartMonth = 1
            case 4...6: quarterStartMonth = 4
            case 7...9: quarterStartMonth = 7
            default: quarterStartMonth = 10
            }

            let start = cal.date(from: DateComponents(year: year, month: quarterStartMonth, day: 1)) ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: DateComponents(month: 3, day: -1), to: start) ?? now
            return DateRange(start: start, end: end)
        }

        static func thisYear() -> DateRange {
            let cal = Calendar.current
            let now = Date()

            let year = cal.component(.year, from: now)
            let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? now
            return DateRange(start: start, end: end)
        }
    }

    // MARK: - Sorting

    private func sortVariableExpenses(_ expenses: [VariableExpense], by mode: SortMode) -> [VariableExpense] {
        switch mode {
        case .az:
            return expenses.sorted { $0.descriptionText.localizedCaseInsensitiveCompare($1.descriptionText) == .orderedAscending }
        case .amountAsc:
            return expenses.sorted { $0.amount < $1.amount }
        case .amountDesc:
            return expenses.sorted { $0.amount > $1.amount }
        case .dateAsc:
            return expenses.sorted { $0.transactionDate < $1.transactionDate }
        case .dateDesc:
            return expenses.sorted { $0.transactionDate > $1.transactionDate }
        }
    }

    private func plannedEffectiveAmount(_ expense: PlannedExpense) -> Double {
        expense.actualAmount > 0 ? expense.actualAmount : expense.plannedAmount
    }

    private func sortPlannedExpenses(_ expenses: [PlannedExpense], by mode: SortMode) -> [PlannedExpense] {
        switch mode {
        case .az:
            return expenses.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .amountAsc:
            return expenses.sorted { plannedEffectiveAmount($0) < plannedEffectiveAmount($1) }
        case .amountDesc:
            return expenses.sorted { plannedEffectiveAmount($0) > plannedEffectiveAmount($1) }
        case .dateAsc:
            return expenses.sorted { $0.expenseDate < $1.expenseDate }
        case .dateDesc:
            return expenses.sorted { $0.expenseDate > $1.expenseDate }
        }
    }

    private func sortUnifiedExpenses(_ items: [UnifiedExpenseItem], by mode: SortMode) -> [UnifiedExpenseItem] {
        switch mode {
        case .az:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .amountAsc:
            return items.sorted { $0.amount < $1.amount }
        case .amountDesc:
            return items.sorted { $0.amount > $1.amount }
        case .dateAsc:
            return items.sorted { $0.date < $1.date }
        case .dateDesc:
            return items.sorted { $0.date > $1.date }
        }
    }

    // MARK: - Card Theme / Effect Mapping

    private func cardThemeOption(from raw: String) -> CardThemeOption {
        if let option = CardThemeOption(rawValue: raw) {
            return option
        }
        return .graphite
    }

    private func cardEffectOption(from raw: String) -> CardEffectOption {
        if let option = CardEffectOption(rawValue: raw) {
            return option
        }
        return .plastic
    }

    // MARK: - Actions

    private func openEdit(_ expense: VariableExpense) {
        cardsSheetRoute.wrappedValue = .editExpense(expense)
    }

    private func openEdit(_ plannedExpense: PlannedExpense) {
        cardsSheetRoute.wrappedValue = .editPlannedExpense(plannedExpense)
    }

    private func openEditPreset(_ preset: Preset) {
        cardsSheetRoute.wrappedValue = .editPreset(preset)
    }

    private func presetForPlannedExpense(_ expense: PlannedExpense) -> Preset? {
        guard let presetID = expense.sourcePresetID else { return nil }

        let desc = FetchDescriptor<Preset>(
            predicate: #Predicate<Preset> { $0.id == presetID }
        )

        return (try? modelContext.fetch(desc))?.first
    }

    private func deleteCard() {

        // I prefer being explicit here even though SwiftData delete rules are set to cascade.
        // This keeps behavior predictable if those rules ever change.
        if let planned = card.plannedExpenses {
            for expense in planned {
                modelContext.delete(expense)
            }
        }

        if let variable = card.variableExpenses {
            for expense in variable {
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
        dismiss()
    }


    private func deleteVariableExpensesFiltered(at offsets: IndexSet) {
        // IMPORTANT: offsets are for the filtered/sorted list
        let expensesToDelete = offsets.compactMap { index in
            variableExpensesFiltered.indices.contains(index) ? variableExpensesFiltered[index] : nil
        }

        if confirmBeforeDeleting {
            pendingExpenseDelete = {
                for expense in expensesToDelete {
                    modelContext.delete(expense)
                }
            }
            showingExpenseDeleteConfirm = true
        } else {
            for expense in expensesToDelete {
                modelContext.delete(expense)
            }
        }
    }

    private func deletePlannedExpensesFiltered(at offsets: IndexSet) {
        // IMPORTANT: offsets are for the filtered/sorted list
        let expensesToDelete = offsets.compactMap { index in
            plannedExpensesFiltered.indices.contains(index) ? plannedExpensesFiltered[index] : nil
        }

        if confirmBeforeDeleting {
            pendingExpenseDelete = {
                for expense in expensesToDelete {
                    modelContext.delete(expense)
                }
            }
            showingExpenseDeleteConfirm = true
        } else {
            for expense in expensesToDelete {
                modelContext.delete(expense)
            }
        }
    }

    private func deleteUnifiedExpensesFiltered(at offsets: IndexSet) {
        // IMPORTANT: offsets are for the unified filtered/sorted list
        let itemsToDelete = offsets.compactMap { index in
            unifiedExpensesFiltered.indices.contains(index) ? unifiedExpensesFiltered[index] : nil
        }

        if confirmBeforeDeleting {
            pendingExpenseDelete = {
                for item in itemsToDelete {
                    switch item {
                    case .planned(let expense):
                        modelContext.delete(expense)
                    case .variable(let expense):
                        modelContext.delete(expense)
                    }
                }
            }
            showingExpenseDeleteConfirm = true
        } else {
            for item in itemsToDelete {
                switch item {
                case .planned(let expense):
                    modelContext.delete(expense)
                case .variable(let expense):
                    modelContext.delete(expense)
                }
            }
        }
    }
}

// MARK: - Supporting Types
private enum SortMode: String, Identifiable {
    case az
    case amountAsc
    case amountDesc
    case dateAsc
    case dateDesc

    var id: String { rawValue }
}

private enum QuickRangePreset {
    case today
    case thisWeek
    case thisMonth
    case thisQuarter
    case thisYear
}

private enum UnifiedExpenseItem: Identifiable {
    case planned(PlannedExpense)
    case variable(VariableExpense)

    var id: UUID {
        switch self {
        case .planned(let e): return e.id
        case .variable(let e): return e.id
        }
    }

    var title: String {
        switch self {
        case .planned(let e): return e.title
        case .variable(let e): return e.descriptionText
        }
    }

    var amount: Double {
        switch self {
        case .planned(let e): return e.actualAmount > 0 ? e.actualAmount : e.plannedAmount
        case .variable(let e): return e.amount
        }
    }

    var date: Date {
        switch self {
        case .planned(let e): return e.expenseDate
        case .variable(let e): return e.transactionDate
        }
    }

    var category: Category? {
        switch self {
        case .planned(let e): return e.category
        case .variable(let e): return e.category
        }
    }

    var kindLabel: String {
        switch self {
        case .planned: return "Planned"
        case .variable: return "Variable"
        }
    }
}

// MARK: - Heat Map Support

private struct CategorySpendSlice: Identifiable {
    let id: UUID
    let name: String
    let hexColor: String
    let amount: Double

    var start: Double = 0
    var end: Double = 0
}

private struct HeatMapSpendingBar: View {
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

private struct TotalSpentStatementRow: View {
    let total: Double
    let heatMapStops: [Gradient.Stop]

    private let cornerRadius: CGFloat = 14

    var body: some View {
        ZStack(alignment: .leading) {

            // Background that fills the entire row
            HeatMapSpendingBar(stops: heatMapStops)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .accessibilityHidden(true)

            // Foreground content
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
        .accessibilityLabel("Total Spent")
        .accessibilityValue(Text(total, format: CurrencyFormatter.currencyStyle()))
    }
}

// MARK: - Hero Card Row

private struct HeroCardRow: View {
    let title: String
    let theme: CardThemeOption
    let effect: CardEffectOption

    private let maxHeroWidth: CGFloat = 520

    var body: some View {
        HStack {
            Spacer(minLength: 0)

            CardVisualView(title: title, theme: theme, effect: effect)
                .frame(maxWidth: maxHeroWidth)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Date Filter Row

private struct DateFilterRow: View {
    @Binding var draftStartDate: Date
    @Binding var draftEndDate: Date

    let isGoEnabled: Bool
    let onTapGo: () -> Void
    let onSelectQuickRange: (QuickRangePreset) -> Void

    var body: some View {
        HStack(spacing: 12) {

            PillDatePickerField(title: "Start Date", date: $draftStartDate)
            PillDatePickerField(title: "End Date", date: $draftEndDate)

            IconCircleButton(systemName: "arrow.right", isEnabled: isGoEnabled, action: onTapGo)
                .accessibilityLabel("Apply Date Range")

            Menu {
                Button("Today") { onSelectQuickRange(.today) }
                Button("This Week") { onSelectQuickRange(.thisWeek) }
                Button("This Month") { onSelectQuickRange(.thisMonth) }
                Button("This Quarter") { onSelectQuickRange(.thisQuarter) }
                Button("This Year") { onSelectQuickRange(.thisYear) }
            } label: {
                IconCircleLabel(systemName: "calendar")
            }
            .accessibilityLabel("Quick Date Ranges")
        }
    }
}

// MARK: - Date Pill Button

private struct DatePillButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(Color.secondary.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Icon Circle Button

private struct IconCircleButton: View {
    let systemName: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isEnabled ? Color.accentColor.opacity(0.85) : Color.secondary.opacity(0.1))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

// MARK: - Icon Circle Label (for Menu)

private struct IconCircleLabel: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .tint(.primary)
            .frame(width: 44, height: 44)
            .background(.thinMaterial, in: Circle())
    }
}

// MARK: - Category Chips Row

private struct CategoryChipsRow: View {
    let categories: [Category]
    @Binding var selectedID: UUID?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.id) { category in
                    Chip(
                        title: category.name,
                        dotHex: category.hexColor,
                        isSelected: selectedID == category.id
                    ) {
                        toggle(category.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func toggle(_ id: UUID) {
        if selectedID == id {
            selectedID = nil
        } else {
            selectedID = id
        }
    }
}

private struct Chip: View {
    let title: String
    let dotHex: String
    let isSelected: Bool
    let action: () -> Void

    private var baseColor: Color {
        Color(hex: dotHex) ?? Color.secondary.opacity(0.35)
    }

    private var backgroundColor: Color {
        if isSelected {
            baseColor.opacity(0.20)
        } else {
            Color.secondary.opacity(0.12)
        }
    }

    private var foregroundColor: Color {
        if isSelected {
            baseColor
        } else {
            Color.primary
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(baseColor)
                    .frame(width: 8, height: 8)

                Text(title)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(foregroundColor)
            }
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

// MARK: - Planned Expense Row

private struct PlannedExpenseRow: View {
    let expense: PlannedExpense

    private var amountToShow: Double {
        expense.actualAmount > 0 ? expense.actualAmount : expense.plannedAmount
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            CategoryDotView(category: expense.category)
                .padding(.top, 6)

            // LEFT SIDE
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.body)

                HStack(spacing: 6) {
                    Text(
                        expense.expenseDate.formatted(
                            date: .abbreviated,
                            time: .omitted
                        )
                    )
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // RIGHT SIDE
            Text(amountToShow, format: CurrencyFormatter.currencyStyle())
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Variable Expense Row

private struct VariableExpenseRow: View {
    let expense: VariableExpense

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            CategoryDotView(category: expense.category)
                .padding(.top, 6)

            // LEFT SIDE
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.descriptionText)
                    .font(.body)

                Text(
                    expense.transactionDate.formatted(
                        date: .abbreviated,
                        time: .omitted
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // RIGHT SIDE
            Text(expense.amount, format: CurrencyFormatter.currencyStyle())
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}


// MARK: - Category Dot

private struct CategoryDotView: View {
    let category: Category?

    private var dotColor: Color {
        guard let hex = category?.hexColor, let color = Color(hex: hex) else {
            return Color.secondary.opacity(0.35)
        }
        return color
    }

    var body: some View {
        Circle()
            .fill(dotColor)
            .frame(width: 10, height: 10)
    }
}

// MARK: - Preview

private struct CardDetailPreview: View {
    let workspace: Workspace

    @Query private var cards: [Card]

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )
    }

    var body: some View {
        if let card = cards.first {
            CardDetailView(workspace: workspace, card: card)
        } else {
            ContentUnavailableView(
                "No Card Seeded",
                systemImage: "creditcard",
                description: Text("PreviewSeed.seedBasicData(in:) didn’t create a Card.")
            )
        }
    }
}

#Preview("Card Detail") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            CardDetailPreview(workspace: ws)
        }
    }
}
