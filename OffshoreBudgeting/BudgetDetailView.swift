//
//  BudgetDetailView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData
import Foundation

struct BudgetDetailView: View {
    let workspace: Workspace
    let budget: Budget
    
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingBudgetDeleteConfirm: Bool = false
    @State private var pendingBudgetDelete: (() -> Void)? = nil

    @State private var showingExpenseDeleteConfirm: Bool = false
    @State private var pendingExpenseDelete: (() -> Void)? = nil

    @State private var showingManageCardsSheet: Bool = false
    @State private var showingManagePresetsSheet: Bool = false
    @State private var showingAddExpenseSheet: Bool = false

    // MARK: - Edit Budget

    @State private var showingEditBudgetSheet: Bool = false

    // MARK: - Edit Expense (added, matches CardDetailView behavior)

    @State private var expenseToEdit: ExpenseToEdit? = nil
    @State private var plannedExpenseToEdit: PlannedExpenseToEdit? = nil
    @State private var presetToEdit: PresetToEdit? = nil

    // MARK: - Category Limits

    @State private var limitEditorCategory: Category? = nil

    // MARK: - UI State

    @State private var selectedCategoryID: UUID? = nil
    @State private var expenseScope: ExpenseScope = .unified
    @State private var sortMode: BudgetSortMode = .dateDesc

    // MARK: - Search

    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    // MARK: - Budget Window

    private func isWithinBudget(_ date: Date) -> Bool {
        let cal = Calendar.current

        let start = cal.startOfDay(for: budget.startDate)
        let endStart = cal.startOfDay(for: budget.endDate)
        let end = cal.date(byAdding: DateComponents(day: 1, second: -1), to: endStart) ?? budget.endDate

        return date >= start && date <= end
    }

    private var budgetDateRangeLabel: String {
        let start = budget.startDate.formatted(date: .abbreviated, time: .omitted)
        let end = budget.endDate.formatted(date: .abbreviated, time: .omitted)
        return "\(start) – \(end)"
    }

    // MARK: - Linked Cards

    private var linkedCards: [Card] {
        (budget.cardLinks ?? [])
            .compactMap { $0.card }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Income (within budget window)

    private var incomesInBudget: [Income] {
        (workspace.incomes ?? [])
            .filter { isWithinBudget($0.date) }
            .sorted { $0.date > $1.date }
    }

    private var plannedIncomeTotal: Double {
        incomesInBudget
            .filter { $0.isPlanned }
            .reduce(0) { $0 + $1.amount }
    }

    private var actualIncomeTotal: Double {
        incomesInBudget
            .filter { !$0.isPlanned }
            .reduce(0) { $0 + $1.amount }
    }

    // MARK: - Expenses aggregated from linked cards (within budget window)

    private var plannedExpensesInBudget: [PlannedExpense] {
        linkedCards
            .flatMap { $0.plannedExpenses ?? [] }
            .filter { isWithinBudget($0.expenseDate) }
            .sorted { $0.expenseDate > $1.expenseDate }
    }

    private var variableExpensesInBudget: [VariableExpense] {
        linkedCards
            .flatMap { $0.variableExpenses ?? [] }
            .filter { isWithinBudget($0.transactionDate) }
            .sorted { $0.transactionDate > $1.transactionDate }
    }

    // MARK: - Categories (chips)

    private var categoriesInBudget: [Category] {
        var seen = Set<UUID>()
        let all = (plannedExpensesInBudget.compactMap { $0.category } + variableExpensesInBudget.compactMap { $0.category })

        let uniques = all.filter { cat in
            guard !seen.contains(cat.id) else { return false }
            seen.insert(cat.id)
            return true
        }

        return uniques.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Search helpers

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matchesSearch(_ planned: PlannedExpense) -> Bool {
        let q = trimmedSearch
        guard !q.isEmpty else { return true }

        if planned.title.localizedCaseInsensitiveContains(q) { return true }
        if let categoryName = planned.category?.name, categoryName.localizedCaseInsensitiveContains(q) { return true }
        if let cardName = planned.card?.name, cardName.localizedCaseInsensitiveContains(q) { return true }

        return false
    }

    private func matchesSearch(_ variable: VariableExpense) -> Bool {
        let q = trimmedSearch
        guard !q.isEmpty else { return true }

        if variable.descriptionText.localizedCaseInsensitiveContains(q) { return true }
        if let categoryName = variable.category?.name, categoryName.localizedCaseInsensitiveContains(q) { return true }
        if let cardName = variable.card?.name, cardName.localizedCaseInsensitiveContains(q) { return true }

        return false
    }

    // MARK: - Filtering

    private var plannedExpensesFiltered: [PlannedExpense] {
        let base = plannedExpensesInBudget

        let categoryFiltered: [PlannedExpense]
        if let selectedCategoryID {
            categoryFiltered = base.filter { $0.category?.id == selectedCategoryID }
        } else {
            categoryFiltered = base
        }

        let searched: [PlannedExpense]
        if trimmedSearch.isEmpty {
            searched = categoryFiltered
        } else {
            searched = categoryFiltered.filter { matchesSearch($0) }
        }

        return sortPlanned(searched)
    }

    private var variableExpensesFiltered: [VariableExpense] {
        let base = variableExpensesInBudget

        let categoryFiltered: [VariableExpense]
        if let selectedCategoryID {
            categoryFiltered = base.filter { $0.category?.id == selectedCategoryID }
        } else {
            categoryFiltered = base
        }

        let searched: [VariableExpense]
        if trimmedSearch.isEmpty {
            searched = categoryFiltered
        } else {
            searched = categoryFiltered.filter { matchesSearch($0) }
        }

        return sortVariable(searched)
    }

    private var unifiedItemsFiltered: [BudgetUnifiedExpenseItem] {
        let planned = plannedExpensesFiltered.map { BudgetUnifiedExpenseItem.planned($0) }
        let variable = variableExpensesFiltered.map { BudgetUnifiedExpenseItem.variable($0) }
        return sortUnified(planned + variable)
    }

    // MARK: - Totals that react to Type + Category filter

    private var plannedExpensesPlannedTotal: Double {
        plannedExpensesFiltered.reduce(0) { $0 + $1.plannedAmount }
    }

    private var plannedExpensesActualTotal: Double {
        plannedExpensesFiltered.reduce(0) { $0 + max(0, $1.actualAmount) }
    }

    private var variableExpensesTotal: Double {
        variableExpensesFiltered.reduce(0) { $0 + $1.amount }
    }

    // MARK: - Savings math (reacts to category + type)

    private var maxSavings: Double {
        plannedIncomeTotal - plannedExpensesPlannedTotal
    }

    private var projectedSavings: Double {
        plannedIncomeTotal - plannedExpensesPlannedTotal - variableExpensesTotal
    }

    private var actualSavings: Double {
        actualIncomeTotal - plannedExpensesActualTotal - variableExpensesTotal
    }

    // MARK: - Sort

    private func sortPlanned(_ items: [PlannedExpense]) -> [PlannedExpense] {
        switch sortMode {
        case .az:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .amountAsc:
            return items.sorted { plannedAmountForSort($0) < plannedAmountForSort($1) }
        case .amountDesc:
            return items.sorted { plannedAmountForSort($0) > plannedAmountForSort($1) }
        case .dateAsc:
            return items.sorted { $0.expenseDate < $1.expenseDate }
        case .dateDesc:
            return items.sorted { $0.expenseDate > $1.expenseDate }
        }
    }

    private func sortVariable(_ items: [VariableExpense]) -> [VariableExpense] {
        switch sortMode {
        case .az:
            return items.sorted { $0.descriptionText.localizedCaseInsensitiveCompare($1.descriptionText) == .orderedAscending }
        case .amountAsc:
            return items.sorted { $0.amount < $1.amount }
        case .amountDesc:
            return items.sorted { $0.amount > $1.amount }
        case .dateAsc:
            return items.sorted { $0.transactionDate < $1.transactionDate }
        case .dateDesc:
            return items.sorted { $0.transactionDate > $1.transactionDate }
        }
    }

    private func sortUnified(_ items: [BudgetUnifiedExpenseItem]) -> [BudgetUnifiedExpenseItem] {
        switch sortMode {
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

    private func plannedAmountForSort(_ expense: PlannedExpense) -> Double {
        expense.actualAmount > 0 ? expense.actualAmount : expense.plannedAmount
    }

    // MARK: - List title (reacts to type)

    private var expensesTitleText: Text {
        switch expenseScope {
        case .planned:
            return Text("Planned Expenses • \(plannedExpensesPlannedTotal, format: CurrencyFormatter.currencyStyle())")

        case .unified:
            let unifiedTotal = plannedExpensesPlannedTotal + variableExpensesTotal
            return Text("All Expenses • \(unifiedTotal, format: CurrencyFormatter.currencyStyle())")

        case .variable:
            return Text("Variable Expenses • \(variableExpensesTotal, format: CurrencyFormatter.currencyStyle())")
        }
    }

    // MARK: - Body

    var body: some View {
        List {
            // MARK: - Summary (3 equal-height rows)

            Section {
                VStack(spacing: 12) {

                    BudgetSummaryBucketCard(
                        title: "Income",
                        titleColor: .blue,
                        rows: [
                            .init(label: "Planned Income", value: plannedIncomeTotal),
                            .init(label: "Actual Income", value: actualIncomeTotal)
                        ]
                    )

                    BudgetSummaryBucketCard(
                        title: "Expenses",
                        titleColor: .orange,
                        rows: expenseRowsForCurrentSelection()
                    )

                    BudgetSummaryBucketCard(
                        title: "Savings",
                        titleColor: .green,
                        rows: [
                            .init(label: "Max Savings", value: maxSavings),
                            .init(label: "Projected Savings", value: projectedSavings),
                            .init(label: "Actual Savings", value: actualSavings)
                        ]
                    )
                }
                .padding(.vertical, 4)
            } header: {
                Text("Overview • \(budgetDateRangeLabel)")
            }

            // MARK: - Category Chips

            if !categoriesInBudget.isEmpty {
                Section {
                    BudgetCategoryChipsRow(
                        categories: categoriesInBudget,
                        selectedID: $selectedCategoryID,
                        onLongPressCategory: { category in
                            limitEditorCategory = category
                        }
                    )
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Single-press a category to filter expenses. Long-press a category to edit its spending limit for this budget.")
                }
            }

            // MARK: - Type + Sort

            Section {
                Picker("Type", selection: $expenseScope) {
                    Text("Planned").tag(ExpenseScope.planned)
                    Text("Unified").tag(ExpenseScope.unified)
                    Text("Variable").tag(ExpenseScope.variable)
                }
                .pickerStyle(.segmented)

                Picker("Sort", selection: $sortMode) {
                    Text("A–Z").tag(BudgetSortMode.az)
                    Text("$↓").tag(BudgetSortMode.amountDesc)
                    Text("$↑").tag(BudgetSortMode.amountAsc)
                    Text("Date ↑").tag(BudgetSortMode.dateAsc)
                    Text("Date ↓").tag(BudgetSortMode.dateDesc)
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Sort")
            }

            // MARK: - Expense List (swipe behavior added)

            Section {
                switch expenseScope {

                case .planned:
                    if plannedExpensesFiltered.isEmpty {
                        ContentUnavailableView("No planned expenses", systemImage: "")
                    } else {
                        ForEach(plannedExpensesFiltered, id: \.id) { expense in
                            BudgetPlannedExpenseRow(expense: expense, showsCardName: true)
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
                        ContentUnavailableView("No variable expenses", systemImage: "")
                    } else {
                        ForEach(variableExpensesFiltered, id: \.id) { expense in
                            Button {
                                openEdit(expense)
                            } label: {
                                BudgetVariableExpenseRow(expense: expense, showsCardName: true)
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
                    if unifiedItemsFiltered.isEmpty {
                        ContentUnavailableView("No expenses", systemImage: "")
                    } else {
                        ForEach(unifiedItemsFiltered) { item in
                            switch item {
                            case .planned(let expense):
                                BudgetPlannedExpenseRow(expense: expense, showsCardName: true)
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
                                    BudgetVariableExpenseRow(expense: expense, showsCardName: true)
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
        .listStyle(.insetGrouped)
        .navigationTitle(budget.name)

        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .searchFocused($searchFocused)

        .toolbar {

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddExpenseSheet = true
                }
                label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Transaction")
                .disabled(linkedCards.isEmpty)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showingManagePresetsSheet = true
                    } label: {
                        Label("Manage Presets", systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        showingManageCardsSheet = true
                    } label: {
                        Label("Manage Cards", systemImage: "link")
                    }

                    Divider()

                    Button {
                        showingEditBudgetSheet = true
                    } label: {
                        Label("Edit Budget", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        if confirmBeforeDeleting {
                            pendingBudgetDelete = {
                                deleteBudget()
                            }
                            showingBudgetDeleteConfirm = true
                        } else {
                            deleteBudget()
                        }
                    } label: {
                        Label("Delete Budget", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Budget Actions")
            }
        }
        .sheet(isPresented: $showingEditBudgetSheet) {
            NavigationStack {
                EditBudgetView(workspace: workspace, budget: budget)
            }
        }
        .sheet(isPresented: $showingAddExpenseSheet) {
            NavigationStack {
                AddExpenseView(
                    workspace: workspace,
                    allowedCards: linkedCards,
                    defaultDate: .now
                )
            }
        }
        .sheet(isPresented: $showingManageCardsSheet) {
            NavigationStack {
                ManageCardsForBudgetSheet(workspace: workspace, budget: budget)
            }
        }
        .sheet(isPresented: $showingManagePresetsSheet) {
            NavigationStack {
                ManagePresetsForBudgetSheet(workspace: workspace, budget: budget)
            }
        }
        .sheet(item: $expenseToEdit) { item in
            NavigationStack {
                EditExpenseView(workspace: workspace, expense: item.expense)
            }
        }
        .sheet(item: $plannedExpenseToEdit) { item in
            NavigationStack {
                EditPlannedExpenseView(workspace: workspace, plannedExpense: item.plannedExpense)
            }
        }
        .sheet(item: $presetToEdit) { item in
            NavigationStack {
                EditPresetView(workspace: workspace, preset: item.preset)
            }
        }
        .sheet(item: $limitEditorCategory) { category in
            EditCategoryLimitView(
                budget: budget,
                category: category,
                plannedContribution: plannedContribution(for: category),
                variableContribution: variableContribution(for: category)
            )
        }
        .alert("Delete?", isPresented: $showingBudgetDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingBudgetDelete?()
                pendingBudgetDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingBudgetDelete = nil
            }
        }
        .alert("Delete?", isPresented: $showingExpenseDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingExpenseDelete?()
                pendingExpenseDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingExpenseDelete = nil
            }
        }
    }

    // MARK: - Expenses bucket rows (reactive)

    private func expenseRowsForCurrentSelection() -> [BudgetSummaryBucketCard.Row] {
        switch expenseScope {
        case .planned:
            return [
                .init(label: "Planned Total", value: plannedExpensesPlannedTotal),
                .init(label: "Actual Total", value: plannedExpensesActualTotal)
            ]

        case .variable:
            return [
                .init(label: "Spent", value: variableExpensesTotal),
            ]

        case .unified:
            let unifiedTotal = plannedExpensesPlannedTotal + variableExpensesTotal
            return [
                .init(label: "Planned Total", value: plannedExpensesPlannedTotal),
                .init(label: "Variable Total", value: variableExpensesTotal),
                .init(label: "Unified Total", value: unifiedTotal)
            ]
        }
    }

    // MARK: - Actions

    private func deleteBudget() {
        modelContext.delete(budget)
        dismiss()
    }

    // MARK: - Edit + Preset lookup (added, matches CardDetailView)

    private func openEdit(_ expense: VariableExpense) {
        expenseToEdit = ExpenseToEdit(expense: expense)
    }

    private func openEdit(_ plannedExpense: PlannedExpense) {
        plannedExpenseToEdit = PlannedExpenseToEdit(plannedExpense: plannedExpense)
    }

    private func openEditPreset(_ preset: Preset) {
        presetToEdit = PresetToEdit(preset: preset)
    }

    private func presetForPlannedExpense(_ expense: PlannedExpense) -> Preset? {
        guard let presetID = expense.sourcePresetID else { return nil }

        let desc = FetchDescriptor<Preset>(
            predicate: #Predicate<Preset> { $0.id == presetID }
        )

        return (try? modelContext.fetch(desc))?.first
    }

    private func deleteVariableExpensesFiltered(at offsets: IndexSet) {
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
        let itemsToDelete = offsets.compactMap { index in
            unifiedItemsFiltered.indices.contains(index) ? unifiedItemsFiltered[index] : nil
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

    // MARK: - Category Limit Math

    private func plannedContribution(for category: Category) -> Double {
        plannedExpensesInBudget
            .filter { $0.category?.id == category.id }
            .reduce(0) { total, expense in
                total + (expense.actualAmount > 0 ? expense.actualAmount : expense.plannedAmount)
            }
    }

    private func variableContribution(for category: Category) -> Double {
        variableExpensesInBudget
            .filter { $0.category?.id == category.id }
            .reduce(0) { $0 + $1.amount }
    }
}


// MARK: - Budget Sort Mode

enum BudgetSortMode: String, Identifiable {
    case az
    case amountAsc
    case amountDesc
    case dateAsc
    case dateDesc

    var id: String { rawValue }
}

// MARK: - Unified Item (budget-local)

private enum BudgetUnifiedExpenseItem: Identifiable {
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

    var cardName: String? {
        switch self {
        case .planned(let e): return e.card?.name
        case .variable(let e): return e.card?.name
        }
    }
}

// MARK: - Swipe/Edit supporting types (added, matches CardDetailView)

private struct ExpenseToEdit: Identifiable {
    let id: UUID
    let expense: VariableExpense

    init(expense: VariableExpense) {
        self.id = expense.id
        self.expense = expense
    }
}

private struct PlannedExpenseToEdit: Identifiable {
    let id: UUID
    let plannedExpense: PlannedExpense

    init(plannedExpense: PlannedExpense) {
        self.id = plannedExpense.id
        self.plannedExpense = plannedExpense
    }
}

private struct PresetToEdit: Identifiable {
    let id: UUID
    let preset: Preset

    init(preset: Preset) {
        self.id = preset.id
        self.preset = preset
    }
}

// MARK: - Summary Bucket Card

private struct BudgetSummaryBucketCard: View {

    struct Row: Identifiable {
        let id = UUID()
        let label: String
        let value: Double?
        let valueText: String?

        init(label: String, value: Double) {
            self.label = label
            self.value = value
            self.valueText = nil
        }

        init(label: String, valueText: String) {
            self.label = label
            self.value = nil
            self.valueText = valueText
        }
    }

    let title: String
    let titleColor: Color
    let rows: [Row]

    private let cornerRadius: CGFloat = 14
    private let fixedHeight: CGFloat = 104

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(titleColor)

            ForEach(rows) { row in
                HStack {
                    Text(row.label)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    if let value = row.value {
                        Text(value, format: CurrencyFormatter.currencyStyle())
                            .font(.subheadline.weight(.semibold))
                    } else if let valueText = row.valueText {
                        Text(valueText)
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: fixedHeight)
        .background(.clear, in: RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Category Chips

private struct BudgetCategoryChipsRow: View {
    let categories: [Category]
    @Binding var selectedID: UUID?
    var onLongPressCategory: ((Category) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.id) { category in
                    BudgetChip(
                        title: category.name,
                        dotHex: category.hexColor,
                        isSelected: selectedID == category.id
                    ) {
                        toggle(category.id)
                    } onLongPress: {
                        onLongPressCategory?(category)
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

private struct BudgetChip: View {
    let title: String
    let dotHex: String?
    let isSelected: Bool
    let action: () -> Void
    var onLongPress: (() -> Void)? = nil

    private var baseColor: Color {
        if let dotHex, let color = Color(hex: dotHex) {
            return color
        }
        return Color.secondary.opacity(0.60)
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
        .contentShape(Capsule())
        .onTapGesture {
            action()
        }
        .onLongPressGesture(minimumDuration: 0.45) {
            onLongPress?()
        }
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Rows

private struct BudgetPlannedExpenseRow: View {
    let expense: PlannedExpense
    let showsCardName: Bool

    private var amountToShow: Double {
        expense.actualAmount > 0 ? expense.actualAmount : expense.plannedAmount
    }

    private var amountLabel: String {
        expense.actualAmount > 0 ? "Actual" : "Planned"
    }

    private var categoryColor: Color {
        if let hex = expense.category?.hexColor, let color = Color(hex: hex) {
            return color
        }
        return Color.secondary.opacity(0.40)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(categoryColor)
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(expense.expenseDate.formatted(date: .abbreviated, time: .omitted))
                    Text("•")
                    Text("\(amountLabel): \(amountToShow, format: CurrencyFormatter.currencyStyle())")

                    if showsCardName, let cardName = expense.card?.name {
                        Text("•")
                        Text(cardName)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct BudgetVariableExpenseRow: View {
    let expense: VariableExpense
    let showsCardName: Bool

    private var categoryColor: Color {
        if let hex = expense.category?.hexColor, let color = Color(hex: hex) {
            return color
        }
        return Color.secondary.opacity(0.40)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(categoryColor)
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(expense.descriptionText)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(expense.transactionDate.formatted(date: .abbreviated, time: .omitted))
                    Text("•")
                    Text(expense.amount, format: CurrencyFormatter.currencyStyle())

                    if showsCardName, let cardName = expense.card?.name {
                        Text("•")
                        Text(cardName)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }
}

private struct EditPlannedExpenseView: View {

    let workspace: Workspace
    let plannedExpense: PlannedExpense

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]
    @Query private var categories: [Category]

    // MARK: - Form State

    @State private var title: String = ""
    @State private var plannedAmountText: String = ""
    @State private var actualAmountText: String = ""
    @State private var expenseDate: Date = .now
    @State private var selectedCardID: UUID? = nil
    @State private var selectedCategoryID: UUID? = nil

    // MARK: - Alerts

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false

    init(workspace: Workspace, plannedExpense: PlannedExpense) {
        self.workspace = workspace
        self.plannedExpense = plannedExpense

        let workspaceID = workspace.id
        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )
    }

    private var canSave: Bool {
        let trimmedTitle = PresetFormView.trimmedTitle(title)
        guard !trimmedTitle.isEmpty else { return false }

        guard let plannedAmount = PresetFormView.parsePlannedAmount(plannedAmountText),
              plannedAmount > 0
        else { return false }

        // actual can be blank or 0
        if !actualAmountText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let actual = PresetFormView.parsePlannedAmount(actualAmountText),
                  actual >= 0
            else { return false }
        }

        guard selectedCardID != nil else { return false }
        return true
    }

    var body: some View {
        List {
            Section("Details") {
                TextField("Title", text: $title)

                TextField("Planned Amount", text: $plannedAmountText)
                    .keyboardType(.decimalPad)

                TextField("Actual Amount (optional)", text: $actualAmountText)
                    .keyboardType(.decimalPad)

                HStack {
                    Text("Date")
                    Spacer()
                    PillDatePickerField(title: "Date", date: $expenseDate)
                }
            }

            Section("Card") {
                Picker("Card", selection: $selectedCardID) {
                    Text("Select").tag(UUID?.none)
                    ForEach(cards) { card in
                        Text(card.name).tag(UUID?.some(card.id))
                    }
                }
            }

            Section("Category") {
                Picker("Category", selection: $selectedCategoryID) {
                    Text("None").tag(UUID?.none)
                    ForEach(categories) { category in
                        Text(category.name).tag(UUID?.some(category.id))
                    }
                }
            }
        }
        .navigationTitle("Edit Planned Expense")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .alert("Invalid Amount", isPresented: $showingInvalidAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter a planned amount greater than 0, and an actual amount that is 0 or greater.")
        }
        .alert("Select a Card", isPresented: $showingMissingCardAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Choose a card for this planned expense.")
        }
        .onAppear {
            title = plannedExpense.title
            plannedAmountText = CurrencyFormatter.editingString(from: plannedExpense.plannedAmount)
            actualAmountText = plannedExpense.actualAmount > 0 ? CurrencyFormatter.editingString(from: plannedExpense.actualAmount) : ""
            expenseDate = plannedExpense.expenseDate
            selectedCardID = plannedExpense.card?.id
            selectedCategoryID = plannedExpense.category?.id
        }
    }

    private func save() {
        let trimmedTitle = PresetFormView.trimmedTitle(title)
        guard !trimmedTitle.isEmpty else { return }

        guard let planned = PresetFormView.parsePlannedAmount(plannedAmountText), planned > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        let actual: Double
        let actualTrimmed = actualAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if actualTrimmed.isEmpty {
            actual = 0
        } else {
            guard let parsed = PresetFormView.parsePlannedAmount(actualAmountText), parsed >= 0 else {
                showingInvalidAmountAlert = true
                return
            }
            actual = parsed
        }

        guard let selectedCard = cards.first(where: { $0.id == selectedCardID }) else {
            showingMissingCardAlert = true
            return
        }

        let selectedCategory = categories.first(where: { $0.id == selectedCategoryID })

        plannedExpense.title = trimmedTitle
        plannedExpense.plannedAmount = planned
        plannedExpense.actualAmount = actual
        plannedExpense.expenseDate = expenseDate
        plannedExpense.workspace = workspace
        plannedExpense.card = selectedCard
        plannedExpense.category = selectedCategory

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Preview

private struct BudgetDetailPreview: View {
    let workspace: Workspace
    var body: some View {
        if let budget = (workspace.budgets ?? []).first {
            BudgetDetailView(workspace: workspace, budget: budget)
        } else {
            ContentUnavailableView(
                "No Budget Seeded",
                systemImage: "chart.pie",
                description: Text("PreviewSeed.seedBasicData(in:) didn't create a Budget.")
            )
        }
    }
}

#Preview("Budget Detail") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            BudgetDetailPreview(workspace: ws)
        }
    }
}
