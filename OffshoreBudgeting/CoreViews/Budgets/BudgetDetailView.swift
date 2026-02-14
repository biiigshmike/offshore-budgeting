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
    @AppStorage("general_hideFuturePlannedExpenses")
    private var hideFuturePlannedExpensesDefault: Bool = false
    @AppStorage("general_excludeFuturePlannedExpensesFromCalculations")
    private var excludeFuturePlannedExpensesFromCalculationsDefault: Bool = false
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCommandHub) private var commandHub
    
    // MARK: - Budget Delete Flow
    
    @State private var showingBudgetDeleteConfirm: Bool = false
    @State private var pendingBudgetDelete: (() -> Void)? = nil
    
    @State private var showingBudgetDeleteOptionsDialog: Bool = false
    @State private var showingNothingToDeleteAlert: Bool = false
    
    @State private var showingReviewRecordedBudgetPlannedExpenses: Bool = false

    // MARK: - Sheets

    @State private var showingAddExpenseSheet: Bool = false
    @State private var showingManagePresetsSheet: Bool = false
    @State private var showingManageCardsSheet: Bool = false
    @State private var showingEditBudgetSheet: Bool = false

    @State private var showingEditExpenseSheet: Bool = false
    @State private var editingExpense: VariableExpense? = nil

    @State private var showingEditPlannedExpenseSheet: Bool = false
    @State private var editingPlannedExpense: PlannedExpense? = nil

    @State private var showingEditPresetSheet: Bool = false
    @State private var editingPreset: Preset? = nil

    @State private var showingEditCategoryLimitSheet: Bool = false
    @State private var editingCategoryLimitCategory: Category? = nil
    @State private var editingCategoryLimitPlannedContribution: Double = 0
    @State private var editingCategoryLimitVariableContribution: Double = 0
    
    // MARK: - Expense Delete Flow
    
    @State private var showingExpenseDeleteConfirm: Bool = false
    @State private var pendingExpenseDelete: (() -> Void)? = nil
    
    // MARK: - UI State
    
    @State private var selectedCategoryID: UUID? = nil
    @State private var expenseScope: ExpenseScope = .unified
    @State private var sortMode: BudgetSortMode = .dateDesc
    @State private var hideFuturePlannedExpensesInView: Bool = false
    @State private var excludeFuturePlannedExpensesFromCalculationsInView: Bool = false
    
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
        let start = AppDateFormat.abbreviatedDate(budget.startDate)
        let end = AppDateFormat.abbreviatedDate(budget.endDate)
        return "\(start) – \(end)"
    }
    
    // MARK: - Linked Cards
    
    private var linkedCards: [Card] {
        (budget.cardLinks ?? [])
            .compactMap { $0.card }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Linked Presets (for edge-case messaging)
    
    private var linkedPresetsCount: Int {
        (budget.presetLinks ?? []).compactMap { $0.preset }.count
    }
    
    private var presetRequiresCardFootnote: String? {
        guard linkedPresetsCount > 0 else { return nil }
        guard linkedCards.isEmpty else { return nil }
        
        let hasAnyCardsInSystem = (workspace.cards ?? []).isEmpty == false
        return hasAnyCardsInSystem ? "Card Unassigned" : "No Cards Available"
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
    
    // MARK: - Planned expenses (generated for this budget)

    private var plannedExpensesInBudget: [PlannedExpense] {
        BudgetPlannedExpenseStore.plannedExpenses(in: workspace, for: budget)
    }

    // MARK: - Variable expenses aggregated from linked cards (within budget window)
    
    private var variableExpensesInBudget: [VariableExpense] {
        linkedCards
            .flatMap { $0.variableExpenses ?? [] }
            .filter { isWithinBudget($0.transactionDate) }
            .sorted { $0.transactionDate > $1.transactionDate }
    }
    
    // MARK: - Categories (chips)
    
    private var categoriesInBudget: [Category] {
        var categoriesByID: [UUID: Category] = [:]

        for category in (workspace.categories ?? []) {
            categoriesByID[category.id] = category
        }

        for category in (plannedExpensesInBudget.compactMap { $0.category } + variableExpensesInBudget.compactMap { $0.category }) {
            categoriesByID[category.id] = category
        }

        return categoriesByID.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    // MARK: - Search helpers
    
    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func matchesSearch(_ planned: PlannedExpense) -> Bool {
        let query = SearchQueryParser.parse(searchText)
        guard !query.isEmpty else { return true }
        
        if !SearchMatch.matchesDateRange(query, date: planned.expenseDate) { return false }
        
        let textFields: [String?] = [
            planned.title,
            planned.category?.name,
            planned.card?.name
        ]
        if !SearchMatch.matchesTextTerms(query, in: textFields) { return false }
        
        let amounts: [Double] = [
            planned.plannedAmount,
            planned.actualAmount,
            plannedAmountForSort(planned)
        ]
        if !SearchMatch.matchesAmountDigitTerms(query, amounts: amounts) { return false }
        
        return true
    }
    
    private func matchesSearch(_ variable: VariableExpense) -> Bool {
        let query = SearchQueryParser.parse(searchText)
        guard !query.isEmpty else { return true }
        
        if !SearchMatch.matchesDateRange(query, date: variable.transactionDate) { return false }
        
        let textFields: [String?] = [
            variable.descriptionText,
            variable.category?.name,
            variable.card?.name
        ]
        if !SearchMatch.matchesTextTerms(query, in: textFields) { return false }
        
        if !SearchMatch.matchesAmountDigitTerms(query, amounts: [variable.amount]) { return false }
        
        return true
    }
    
    // MARK: - Filtering
    
    private var plannedExpensesFilteredForCurrentControls: [PlannedExpense] {
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
        
        return searched
    }

    private var hiddenFuturePlannedExpenseCount: Int {
        guard hideFuturePlannedExpensesInView else { return 0 }
        return plannedExpensesFilteredForCurrentControls
            .filter { PlannedExpenseFuturePolicy.isFuturePlannedExpense($0) }
            .count
    }

    private var plannedExpensesFiltered: [PlannedExpense] {
        let visible = PlannedExpenseFuturePolicy.filteredForVisibility(
            plannedExpensesFilteredForCurrentControls,
            hideFuture: hideFuturePlannedExpensesInView
        )
        return sortPlanned(visible)
    }

    private var plannedExpensesForCalculations: [PlannedExpense] {
        let included = PlannedExpenseFuturePolicy.filteredForCalculations(
            plannedExpensesFilteredForCurrentControls,
            excludeFuture: excludeFuturePlannedExpensesFromCalculationsInView
        )
        return sortPlanned(included)
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
        plannedExpensesForCalculations.reduce(0) { $0 + $1.plannedAmount }
    }
    
    private var plannedExpensesActualTotal: Double {
        plannedExpensesForCalculations.reduce(0) { $0 + max(0, $1.actualAmount) }
    }

    private var plannedExpensesEffectiveTotal: Double {
        plannedExpensesForCalculations.reduce(0) { $0 + $1.effectiveAmount() }
    }

    private var variableExpensesTotal: Double {
        variableExpensesFiltered.reduce(0) { $0 + $1.amount }
    }
    
    // MARK: - Savings math (reacts to category + type)
    
    private var maxSavings: Double {
        plannedIncomeTotal - plannedExpensesEffectiveTotal
    }
    
    private var projectedSavings: Double {
        plannedIncomeTotal - plannedExpensesPlannedTotal
    }
    
    private var actualSavings: Double {
        actualIncomeTotal - plannedExpensesEffectiveTotal - variableExpensesTotal
    }
    
    // MARK: - Sort
    
    private func sortPlanned(_ items: [PlannedExpense]) -> [PlannedExpense] {
        switch sortMode {
        case .az:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .za:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
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
        case .za:
            return items.sorted { $0.descriptionText.localizedCaseInsensitiveCompare($1.descriptionText) == .orderedDescending }
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
        case .za:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedDescending }
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
        expense.effectiveAmount()
    }

    // MARK: - List title (reacts to type)
    
    private var expensesTitleText: Text {
        switch expenseScope {
        case .planned:
            return Text("Planned Expenses • \(plannedExpensesPlannedTotal, format: CurrencyFormatter.currencyStyle())")
            
        case .unified:
            let unifiedTotal = plannedExpensesEffectiveTotal + variableExpensesTotal
            return Text("All Expenses • \(unifiedTotal, format: CurrencyFormatter.currencyStyle())")
            
        case .variable:
            return Text("Variable Expenses • \(variableExpensesTotal, format: CurrencyFormatter.currencyStyle())")
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        mainContent
            .onAppear {
                commandHub.activate(.budgetDetail)
                updateBudgetDetailCommandAvailability()
                hideFuturePlannedExpensesInView = hideFuturePlannedExpensesDefault
                excludeFuturePlannedExpensesFromCalculationsInView = excludeFuturePlannedExpensesFromCalculationsDefault
            }
            .onDisappear {
                commandHub.deactivate(.budgetDetail)
                commandHub.setBudgetDetailCanCreateTransaction(false)
            }
            .onChange(of: linkedCards.count) { _, _ in
                updateBudgetDetailCommandAvailability()
            }
            .onReceive(commandHub.$sequence) { _ in
                guard commandHub.surface == .budgetDetail else { return }
                handleCommand(commandHub.latestCommandID)
            }
    }

    private var mainContent: some View {
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
            } footer: {
                if let footnote = presetRequiresCardFootnote {
                    Text(footnote)
                }
            }

            // MARK: - Category Chips

            if !categoriesInBudget.isEmpty {
                Section {
                    BudgetCategoryChipsRow(
                        categories: categoriesInBudget,
                        selectedID: $selectedCategoryID,
                        onLongPressCategory: { category in
                            editingCategoryLimitCategory = category
                            editingCategoryLimitPlannedContribution = plannedContribution(for: category)
                            editingCategoryLimitVariableContribution = variableContribution(for: category)
                            showingEditCategoryLimitSheet = true
                        }
                    )
                } header: {
                    Text("Categories")
                } footer: {
                    Text("Single-press a category to filter expenses by that category alone, then tap the same category again to clear your selection. Long-press a category to edit its spending limit for this budget.")
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
                    Text("Z–A").tag(BudgetSortMode.za)
                    Text("\(CurrencyFormatter.currencySymbol)↑").tag(BudgetSortMode.amountAsc)
                    Text("\(CurrencyFormatter.currencySymbol)↓").tag(BudgetSortMode.amountDesc)
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
                        ContentUnavailableView(plannedEmptyMessage, systemImage: "")
                    } else {
                        ForEach(plannedExpensesFiltered, id: \.id) { expense in
                            BudgetPlannedExpenseRow(expense: expense, showsCardName: true)
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    Button {
                                        openEdit(expense)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(Color("AccentColor"))

                                    if let preset = presetForPlannedExpense(expense) {
                                        Button {
                                            openEditPreset(preset)
                                        } label: {
                                            Label("Edit Preset", systemImage: "list.bullet.rectangle")
                                        }
                                        .tint(.orange)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        deletePlannedExpense(expense)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(Color("OffshoreDepth"))
                                }
                        }
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
                                .tint(Color("AccentColor"))
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button {
                                    deleteVariableExpense(expense)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(Color("OffshoreDepth"))
                            }
                        }
                    }

                case .unified:
                    if unifiedItemsFiltered.isEmpty {
                        ContentUnavailableView(unifiedEmptyMessage, systemImage: "")
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
                                        .tint(Color("AccentColor"))

                                        if let preset = presetForPlannedExpense(expense) {
                                            Button {
                                                openEditPreset(preset)
                                            } label: {
                                                Label("Edit Preset", systemImage: "list.bullet.rectangle")
                                            }
                                            .tint(.orange)
                                        }
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button {
                                            deletePlannedExpense(expense)
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                        .tint(Color("OffshoreDepth"))
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
                                    .tint(Color("AccentColor"))
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button {
                                        deleteVariableExpense(expense)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    .tint(Color("OffshoreDepth"))
                                }
                            }
                        }
                    }
                }
            } header: {
                expensesTitleText
            } footer: {
                if hiddenFuturePlannedExpenseCount > 0 {
                    Text("\(hiddenFuturePlannedExpenseCount.formatted()) future planned expenses are hidden.")
                }
            }
        }
        .postBoardingTip(
            key: "tip.budgetdetail.v1",
            title: "Budget Detail Overview",
            items: [
                PostBoardingTipItem(
                    systemImage: "chart.bar.xaxis",
                    title: "Detailed Overview",
                    detail: "View income, expenses, and savings summaries for the budget period."
                ),
                PostBoardingTipItem(
                    systemImage: "magnifyingglass",
                    title: "Search for Expenses",
                    detail: "Search by name, category, card, date, or amount using the search bar."
                ),
                PostBoardingTipItem(
                    systemImage: "tag",
                    title: "Categories",
                    detail: "Tap a category to filter expenses by that category alone, then tap the same category again to clear your selection."
                ),
                PostBoardingTipItem(
                    systemImage: "ellipsis",
                    title: "Budget Management",
                    detail: "Press the three dots and manage your budget easily. Assign cards and presets to track them for your budget period."
                )
            ]
        )
        .listStyle(.insetGrouped)
        .navigationTitle(budget.name)

        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search"
        )
        .searchFocused($searchFocused)

        .toolbar {

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddExpenseSheet = true
                } label: {
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
                        Label("Manage Cards", systemImage: "creditcard")
                    }

                    Menu {
                        Toggle("Hide Future Planned Expenses", isOn: $hideFuturePlannedExpensesInView)
                        Toggle(
                            "Exclude Future Planned Expenses from Totals",
                            isOn: $excludeFuturePlannedExpensesFromCalculationsInView
                        )
                    } label: {
                        Label("Planned Expense Display", systemImage: "gearshape")
                    }

                    Divider()

                    Button {
                        showingEditBudgetSheet = true
                    } label: {
                        Label("Edit Budget", systemImage: "pencil")
                    }
                    .tint(Color("AccentColor"))
                    Button(role: .destructive) {
                        handleDeleteBudgetTapped()
                    } label: {
                        Label("Delete Budget", systemImage: "trash")
                    }
                    .tint(Color("OffshoreDepth"))
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("Budget Actions")
            }
        }

        // MARK: - Deletion UI

        .alert(
            "Delete Budget?",
            isPresented: $showingBudgetDeleteOptionsDialog
        ) {
            Button("Keep All Expenses") {
                deleteBudgetOnly()
            }

            Button("Delete Budget-Planned Expenses", role: .destructive) {
                deleteBudgetAndHandleGeneratedPlannedExpenses()
            }

            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This budget created planned expenses on your cards. What should Offshore do with them?")
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

        .alert("Nothing to delete", isPresented: $showingNothingToDeleteAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("These planned expenses have actual spending recorded.")
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

        .sheet(isPresented: $showingAddExpenseSheet) {
            NavigationStack {
                AddExpenseView(
                    workspace: workspace,
                    allowedCards: linkedCards,
                    defaultDate: .now
                )
            }
        }

        .sheet(isPresented: $showingManagePresetsSheet) {
            NavigationStack {
                ManagePresetsForBudgetSheet(workspace: workspace, budget: budget)
            }
        }

        .sheet(isPresented: $showingManageCardsSheet) {
            NavigationStack {
                ManageCardsForBudgetSheet(workspace: workspace, budget: budget)
            }
        }

        .sheet(isPresented: $showingEditBudgetSheet) {
            NavigationStack {
                EditBudgetView(workspace: workspace, budget: budget)
            }
        }

        .sheet(isPresented: $showingEditExpenseSheet, onDismiss: { editingExpense = nil }) {
            NavigationStack {
                if let editingExpense {
                    EditExpenseView(workspace: workspace, expense: editingExpense)
                } else {
                    EmptyView()
                }
            }
        }

        .sheet(isPresented: $showingEditPlannedExpenseSheet, onDismiss: { editingPlannedExpense = nil }) {
            NavigationStack {
                if let editingPlannedExpense {
                    EditPlannedExpenseView(workspace: workspace, plannedExpense: editingPlannedExpense)
                } else {
                    EmptyView()
                }
            }
        }

        .sheet(isPresented: $showingEditPresetSheet, onDismiss: { editingPreset = nil }) {
            NavigationStack {
                if let editingPreset {
                    EditPresetView(workspace: workspace, preset: editingPreset)
                } else {
                    EmptyView()
                }
            }
        }

        .sheet(isPresented: $showingEditCategoryLimitSheet, onDismiss: {
            editingCategoryLimitCategory = nil
            editingCategoryLimitPlannedContribution = 0
            editingCategoryLimitVariableContribution = 0
        }) {
            if let editingCategoryLimitCategory {
                EditCategoryLimitView(
                    budget: budget,
                    category: editingCategoryLimitCategory,
                    plannedContribution: editingCategoryLimitPlannedContribution,
                    variableContribution: editingCategoryLimitVariableContribution
                )
            } else {
                EmptyView()
            }
        }

        .sheet(isPresented: $showingReviewRecordedBudgetPlannedExpenses) {
            NavigationStack {
                BudgetRecordedPlannedExpensesReviewView(
                    workspace: workspace,
                    budget: budget,
                    onDeleteBudget: {
                        showingReviewRecordedBudgetPlannedExpenses = false
                        deleteBudgetOnly()
                    },
                    onDone: {
                        showingReviewRecordedBudgetPlannedExpenses = false
                    }
                )
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
                .init(label: "Variable Total", value: variableExpensesTotal),
            ]

        case .unified:
            let unifiedTotal = plannedExpensesEffectiveTotal + variableExpensesTotal
            return [
                .init(label: "Planned Total", value: plannedExpensesEffectiveTotal),
                .init(label: "Variable Total", value: variableExpensesTotal),
                .init(label: "Unified Total", value: unifiedTotal)
            ]
        }
    }

    private var plannedEmptyMessage: String {
        if hiddenFuturePlannedExpenseCount > 0 {
            return "No visible planned expenses"
        }
        return "No planned expenses"
    }

    private var unifiedEmptyMessage: String {
        if hiddenFuturePlannedExpenseCount > 0 {
            return "No visible expenses"
        }
        return "No expenses"
    }

    // MARK: - Budget Deletion (Policy A)

    private func handleDeleteBudgetTapped() {
        if budgetHasAnyGeneratedPlannedExpenses() {
            showingBudgetDeleteOptionsDialog = true
            return
        }

        // No generated planned expenses, normal behavior
        if confirmBeforeDeleting {
            pendingBudgetDelete = { deleteBudgetOnly() }
            showingBudgetDeleteConfirm = true
        } else {
            deleteBudgetOnly()
        }
    }

    private func budgetHasAnyGeneratedPlannedExpenses() -> Bool {
        let budgetID: UUID? = budget.id

        var descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID
            }
        )
        descriptor.fetchLimit = 1

        do {
            let matches = try modelContext.fetch(descriptor)
            return !matches.isEmpty
        } catch {
            return false
        }
    }

    private func deleteBudgetOnly() {
        modelContext.delete(budget)
        dismiss()
    }

    /// New flow:
    /// - Deletes unspent generated planned expenses (actualAmount == 0).
    /// - If recorded generated planned expenses exist (actualAmount > 0), opens the review screen.
    /// - Otherwise deletes the budget immediately.
    private func deleteBudgetAndHandleGeneratedPlannedExpenses() {
        let deletedUnspentCount = deleteUnspentGeneratedPlannedExpensesForBudget()
        let recordedCount = countRecordedGeneratedPlannedExpensesForBudget()

        if recordedCount > 0 {
            // If everything is recorded (deletedUnspentCount == 0), still route the user to review
            // instead of showing "Nothing to delete", because there *is* something to consider.
            showingReviewRecordedBudgetPlannedExpenses = true
            return
        }

        if deletedUnspentCount == 0 {
            showingNothingToDeleteAlert = true
            return
        }

        modelContext.delete(budget)
        dismiss()
    }

    private func deleteUnspentGeneratedPlannedExpensesForBudget() -> Int {
        let budgetID: UUID? = budget.id

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID &&
                expense.actualAmount == 0
            }
        )

        do {
            let matches = try modelContext.fetch(descriptor)
            for expense in matches {
                modelContext.delete(expense)
            }
            return matches.count
        } catch {
            return 0
        }
    }

    private func countRecordedGeneratedPlannedExpensesForBudget() -> Int {
        let budgetID: UUID? = budget.id

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID &&
                expense.actualAmount > 0
            }
        )

        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    // MARK: - Edit + Preset lookup (added, matches CardDetailView)

    private func openEdit(_ expense: VariableExpense) {
        editingExpense = expense
        showingEditExpenseSheet = true
    }

    private func openEdit(_ plannedExpense: PlannedExpense) {
        editingPlannedExpense = plannedExpense
        showingEditPlannedExpenseSheet = true
    }

    private func openEditPreset(_ preset: Preset) {
        editingPreset = preset
        showingEditPresetSheet = true
    }

    private func presetForPlannedExpense(_ expense: PlannedExpense) -> Preset? {
        guard let presetID = expense.sourcePresetID else { return nil }

        let desc = FetchDescriptor<Preset>(
            predicate: #Predicate<Preset> { $0.id == presetID }
        )

        return (try? modelContext.fetch(desc))?.first
    }

    private func deleteVariableExpense(_ expense: VariableExpense) {
        guard let index = variableExpensesFiltered.firstIndex(where: { $0.id == expense.id }) else { return }
        deleteVariableExpensesFiltered(at: IndexSet(integer: index))
    }

    private func deletePlannedExpense(_ expense: PlannedExpense) {
        guard let index = plannedExpensesFiltered.firstIndex(where: { $0.id == expense.id }) else { return }
        deletePlannedExpensesFiltered(at: IndexSet(integer: index))
    }

    private func deleteVariableExpensesFiltered(at offsets: IndexSet) {
        let expensesToDelete = offsets.compactMap { index in
            variableExpensesFiltered.indices.contains(index) ? variableExpensesFiltered[index] : nil
        }

        if confirmBeforeDeleting {
            pendingExpenseDelete = {
                for expense in expensesToDelete {
                    deleteVariableExpenseRecord(expense)
                }
            }
            showingExpenseDeleteConfirm = true
        } else {
            for expense in expensesToDelete {
                deleteVariableExpenseRecord(expense)
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
                        deleteVariableExpenseRecord(expense)
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
                    deleteVariableExpenseRecord(expense)
                }
            }
        }
    }

    private func deleteVariableExpenseRecord(_ expense: VariableExpense) {
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

    // MARK: - Category Limit Math

    private func plannedContribution(for category: Category) -> Double {
        plannedExpensesInBudget
            .filter { $0.category?.id == category.id }
            .reduce(0) { total, expense in
                total + expense.effectiveAmount()
            }
    }

    private func variableContribution(for category: Category) -> Double {
        variableExpensesInBudget
            .filter { $0.category?.id == category.id }
            .reduce(0) { $0 + $1.amount }
    }

    private func updateBudgetDetailCommandAvailability() {
        commandHub.setBudgetDetailCanCreateTransaction(!linkedCards.isEmpty)
    }

    private func openNewTransaction() {
        showingAddExpenseSheet = true
    }

    private func openEditBudget() {
        showingEditBudgetSheet = true
    }

    private func deleteBudget() {
        handleDeleteBudgetTapped()
    }

    private func handleCommand(_ commandID: String) {
        switch commandID {
        case AppCommandID.BudgetDetail.newTransaction:
            openNewTransaction()
        case AppCommandID.BudgetDetail.editBudget:
            openEditBudget()
        case AppCommandID.BudgetDetail.deleteBudget:
            deleteBudget()
        case AppCommandID.BudgetDetail.sortAZ:
            sortMode = .az
        case AppCommandID.BudgetDetail.sortZA:
            sortMode = .za
        case AppCommandID.BudgetDetail.sortAmountAsc:
            sortMode = .amountAsc
        case AppCommandID.BudgetDetail.sortAmountDesc:
            sortMode = .amountDesc
        case AppCommandID.BudgetDetail.sortDateAsc:
            sortMode = .dateAsc
        case AppCommandID.BudgetDetail.sortDateDesc:
            sortMode = .dateDesc
        default:
            break
        }
    }
}


// MARK: - Budget Sort Mode

enum BudgetSortMode: String, Identifiable {
    case az
    case za
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
        case .planned(let e): return e.effectiveAmount()
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
        expense.effectiveAmount()
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

            // LEFT SIDE
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.title)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(AppDateFormat.abbreviatedDate(expense.expenseDate))

                    if showsCardName, let cardName = expense.card?.name {
                        Text("•")
                        Text(cardName)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // RIGHT SIDE (CardDetailView styling)
            Text(amountToShow, format: CurrencyFormatter.currencyStyle())
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 4)
    }
}

private struct BudgetVariableExpenseRow: View {
    let expense: VariableExpense
    let showsCardName: Bool

    private enum SharedBalancePresentation {
        case none
        case split
        case offset
    }

    private var offsetAmount: Double {
        max(0, -(expense.offsetSettlement?.amount ?? 0))
    }

    private var splitAmount: Double {
        max(0, expense.allocation?.allocatedAmount ?? 0)
    }

    private var originalChargeAmount: Double {
        max(0, expense.amount + offsetAmount)
    }

    private var presentation: SharedBalancePresentation {
        if offsetAmount > 0 { return .offset }
        if splitAmount > 0 { return .split }
        return .none
    }

    private var indicatorSymbolName: String? {
        switch presentation {
        case .none:
            return nil
        case .split:
            return "arrow.trianglehead.branch"
        case .offset:
            return "text.append"
        }
    }

    private var indicatorAccessibilityLabel: String {
        switch presentation {
        case .none:
            return ""
        case .split:
            return "Shared balance split"
        case .offset:
            return "Shared balance offset"
        }
    }

    private var secondaryAmountSummary: String? {
        switch presentation {
        case .none:
            return nil
        case .split:
            return "Split \(CurrencyFormatter.string(from: splitAmount))"
        case .offset:
            let net = CurrencyFormatter.string(from: expense.amount)
            let offset = CurrencyFormatter.string(from: offsetAmount)
            return "Net \(net) • Offset \(offset)"
        }
    }

    private var categoryColor: Color {
        if let hex = expense.category?.hexColor, let color = Color(hex: hex) {
            return color
        }
        return Color.secondary.opacity(0.40)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            VStack(spacing: 4) {
                Circle()
                    .fill(categoryColor)
                    .frame(width: 10, height: 10)

                if let indicatorSymbolName {
                    Image(systemName: indicatorSymbolName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(indicatorAccessibilityLabel)
                }
            }
            .frame(width: 12)
            .padding(.top, 6)

            // LEFT SIDE
            VStack(alignment: .leading, spacing: 4) {
                Text(expense.descriptionText)
                    .font(.body)

                HStack(spacing: 8) {
                    Text(AppDateFormat.abbreviatedDate(expense.transactionDate))

                    if showsCardName, let cardName = expense.card?.name {
                        Text("•")
                        Text(cardName)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            // RIGHT SIDE (CardDetailView styling)
            VStack(alignment: .trailing, spacing: 2) {
                Text(originalChargeAmount, format: CurrencyFormatter.currencyStyle())
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.trailing)

                if let secondaryAmountSummary {
                    Text(secondaryAmountSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 4)
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
