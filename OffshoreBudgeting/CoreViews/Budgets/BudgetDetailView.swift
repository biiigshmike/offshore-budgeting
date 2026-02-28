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
    @AppStorage("general_hideFutureVariableExpenses")
    private var hideFutureVariableExpensesDefault: Bool = false
    @AppStorage("general_excludeFutureVariableExpensesFromCalculations")
    private var excludeFutureVariableExpensesFromCalculationsDefault: Bool = false
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appCommandHub) private var commandHub
    @Environment(DetailViewSnapshotCache.self) private var detailSnapshotCache
    
    // MARK: - Budget Delete Flow
    
    @State private var showingBudgetDeleteConfirm: Bool = false
    @State private var pendingBudgetDelete: (() -> Void)? = nil
    
    @State private var showingBudgetDeleteOptionsDialog: Bool = false
    @State private var showingNothingToDeleteAlert: Bool = false

    // MARK: - Sheets

    @State private var activeModal: BudgetDetailModalRoute? = nil
    
    // MARK: - Expense Delete Flow
    
    @State private var showingExpenseDeleteConfirm: Bool = false
    @State private var pendingExpenseDelete: (() -> Void)? = nil
    
    // MARK: - UI State
    
    @State private var selectedCategoryIDs: Set<UUID> = []
    @State private var expenseScope: ExpenseScope = .unified
    @State private var sortMode: BudgetSortMode = .dateDesc
    @State private var hideFuturePlannedExpensesInView: Bool = false
    @State private var excludeFuturePlannedExpensesFromCalculationsInView: Bool = false
    @State private var hideFutureVariableExpensesInView: Bool = false
    @State private var excludeFutureVariableExpensesFromCalculationsInView: Bool = false

    private var isPhone: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }
    
    // MARK: - Search
    
    @State private var searchText: String = ""
    @State private var derivedState: BudgetDetailDerivedState = .empty
    @State private var searchRebuildTask: Task<Void, Never>? = nil
    @State private var didApplyDefaultsOnAppear: Bool = false
    @State private var hasLoadedDerivedState: Bool = false
    @State private var needsDerivedStateRefresh: Bool = false
    @State private var isVisible: Bool = false
#if DEBUG
    @State private var appearCount: Int = 0
#endif
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

    private static let tipItems: [PostBoardingTipItem] = [
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
            detail: "Tap one or more categories to filter expenses. Tap a selected category again to clear just that selection."
        ),
        PostBoardingTipItem(
            systemImage: "ellipsis",
            title: "Budget Management",
            detail: "Press the three dots and manage your budget easily. Assign cards and presets to track them for your budget period."
        )
    ]

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
    
    private struct BudgetDetailDerivedState {
        let plannedExpensesInBudget: [PlannedExpense]
        let variableExpensesInBudget: [VariableExpense]
        let categoriesInBudget: [Category]
        let plannedIncomeTotal: Double
        let actualIncomeTotal: Double
        let plannedExpensesFiltered: [PlannedExpense]
        let variableExpensesFiltered: [VariableExpense]
        let unifiedItemsFiltered: [BudgetUnifiedExpenseItem]
        let hiddenFuturePlannedExpenseCount: Int
        let hiddenFutureVariableExpenseCount: Int
        let plannedExpensesPlannedTotal: Double
        let plannedExpensesActualTotal: Double
        let plannedExpensesEffectiveTotal: Double
        let variableExpensesTotal: Double
        let maxSavings: Double
        let projectedSavings: Double
        let actualSavings: Double
        let presetBySourceID: [UUID: Preset]

        static let empty = BudgetDetailDerivedState(
            plannedExpensesInBudget: [],
            variableExpensesInBudget: [],
            categoriesInBudget: [],
            plannedIncomeTotal: 0,
            actualIncomeTotal: 0,
            plannedExpensesFiltered: [],
            variableExpensesFiltered: [],
            unifiedItemsFiltered: [],
            hiddenFuturePlannedExpenseCount: 0,
            hiddenFutureVariableExpenseCount: 0,
            plannedExpensesPlannedTotal: 0,
            plannedExpensesActualTotal: 0,
            plannedExpensesEffectiveTotal: 0,
            variableExpensesTotal: 0,
            maxSavings: 0,
            projectedSavings: 0,
            actualSavings: 0,
            presetBySourceID: [:]
        )
    }

    private struct CategoryLimitEditorInput {
        let category: Category
        let plannedContribution: Double
        let variableContribution: Double
    }

    private enum BudgetDetailModalRoute: Identifiable {
        case addExpense
        case managePresets
        case manageCards
        case editBudget
        case editExpense(VariableExpense)
        case editPlannedExpense(PlannedExpense)
        case editPreset(Preset)
        case editCategoryLimit(CategoryLimitEditorInput)
        case reviewRecordedPlannedExpenses

        var id: String {
            switch self {
            case .addExpense:
                return "add-expense"
            case .managePresets:
                return "manage-presets"
            case .manageCards:
                return "manage-cards"
            case .editBudget:
                return "edit-budget"
            case .editExpense(let expense):
                return "edit-expense-\(expense.id.uuidString)"
            case .editPlannedExpense(let expense):
                return "edit-planned-expense-\(expense.id.uuidString)"
            case .editPreset(let preset):
                return "edit-preset-\(preset.id.uuidString)"
            case .editCategoryLimit(let input):
                return "edit-category-limit-\(input.category.id.uuidString)"
            case .reviewRecordedPlannedExpenses:
                return "review-recorded-planned-expenses"
            }
        }
    }

    private func buildDerivedState() -> BudgetDetailDerivedState {
        let incomesInBudget = (workspace.incomes ?? [])
            .filter { isWithinBudget($0.date) }
            .sorted { $0.date > $1.date }

        let plannedIncomeTotal = incomesInBudget
            .filter { $0.isPlanned }
            .reduce(0) { $0 + $1.amount }
        let actualIncomeTotal = incomesInBudget
            .filter { !$0.isPlanned }
            .reduce(0) { $0 + $1.amount }

        let plannedExpensesInBudget = BudgetPlannedExpenseStore.plannedExpenses(in: workspace, for: budget)
        let variableExpensesInBudget = linkedCards
            .flatMap { $0.variableExpenses ?? [] }
            .filter { isWithinBudget($0.transactionDate) }
            .sorted { $0.transactionDate > $1.transactionDate }

        var categoriesByID: [UUID: Category] = [:]
        for category in (workspace.categories ?? []) {
            categoriesByID[category.id] = category
        }
        for category in (plannedExpensesInBudget.compactMap { $0.category } + variableExpensesInBudget.compactMap { $0.category }) {
            categoriesByID[category.id] = category
        }
        let categoriesInBudget = categoriesByID.values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let query = SearchQueryParser.parse(searchText)
        let isSearching = query.isEmpty == false

        func matchesSearch(_ planned: PlannedExpense) -> Bool {
            guard isSearching else { return true }
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

        func matchesSearch(_ variable: VariableExpense) -> Bool {
            guard isSearching else { return true }
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

        let plannedCategoryFiltered: [PlannedExpense]
        if selectedCategoryIDs.isEmpty {
            plannedCategoryFiltered = plannedExpensesInBudget
        } else {
            plannedCategoryFiltered = plannedExpensesInBudget.filter {
                guard let categoryID = $0.category?.id else { return false }
                return selectedCategoryIDs.contains(categoryID)
            }
        }
        let plannedFilteredForCurrentControls = plannedCategoryFiltered.filter { matchesSearch($0) }

        let variableCategoryFiltered: [VariableExpense]
        if selectedCategoryIDs.isEmpty {
            variableCategoryFiltered = variableExpensesInBudget
        } else {
            variableCategoryFiltered = variableExpensesInBudget.filter {
                guard let categoryID = $0.category?.id else { return false }
                return selectedCategoryIDs.contains(categoryID)
            }
        }
        let variableFilteredForCurrentControls = variableCategoryFiltered.filter { matchesSearch($0) }

        let hiddenFuturePlannedExpenseCount: Int
        if hideFuturePlannedExpensesInView {
            hiddenFuturePlannedExpenseCount = plannedFilteredForCurrentControls
                .filter { PlannedExpenseFuturePolicy.isFuturePlannedExpense($0) }
                .count
        } else {
            hiddenFuturePlannedExpenseCount = 0
        }

        let hiddenFutureVariableExpenseCount: Int
        if hideFutureVariableExpensesInView {
            hiddenFutureVariableExpenseCount = variableFilteredForCurrentControls
                .filter { VariableExpenseFuturePolicy.isFutureVariableExpense($0) }
                .count
        } else {
            hiddenFutureVariableExpenseCount = 0
        }

        let plannedVisible = PlannedExpenseFuturePolicy.filteredForVisibility(
            plannedFilteredForCurrentControls,
            hideFuture: hideFuturePlannedExpensesInView
        )
        let plannedExpensesFiltered = sortPlanned(plannedVisible)

        let plannedIncluded = PlannedExpenseFuturePolicy.filteredForCalculations(
            plannedFilteredForCurrentControls,
            excludeFuture: excludeFuturePlannedExpensesFromCalculationsInView
        )
        let plannedExpensesForCalculations = sortPlanned(plannedIncluded)

        let variableVisible = VariableExpenseFuturePolicy.filteredForVisibility(
            variableFilteredForCurrentControls,
            hideFuture: hideFutureVariableExpensesInView
        )
        let variableExpensesFiltered = sortVariable(variableVisible)

        let variableIncluded = VariableExpenseFuturePolicy.filteredForCalculations(
            variableFilteredForCurrentControls,
            excludeFuture: excludeFutureVariableExpensesFromCalculationsInView
        )
        let variableExpensesForCalculations = sortVariable(variableIncluded)

        let unifiedItemsFiltered = sortUnified(
            plannedExpensesFiltered.map { BudgetUnifiedExpenseItem.planned($0) } +
            variableExpensesFiltered.map { BudgetUnifiedExpenseItem.variable($0) }
        )

        let plannedExpensesPlannedTotal = plannedExpensesForCalculations.reduce(0) { $0 + $1.plannedAmount }
        let plannedExpensesActualTotal = plannedExpensesForCalculations.reduce(0) { $0 + max(0, $1.actualAmount) }
        let plannedExpensesEffectiveTotal = plannedExpensesForCalculations.reduce(0) {
            $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1)
        }
        let variableExpensesTotal = variableExpensesForCalculations.reduce(0) {
            $0 + SavingsMathService.variableBudgetImpactAmount(for: $1)
        }

        let maxSavings = plannedIncomeTotal - plannedExpensesEffectiveTotal
        let projectedSavings = plannedIncomeTotal - plannedExpensesPlannedTotal
        let actualSavings = actualIncomeTotal - plannedExpensesEffectiveTotal - variableExpensesTotal

        return BudgetDetailDerivedState(
            plannedExpensesInBudget: plannedExpensesInBudget,
            variableExpensesInBudget: variableExpensesInBudget,
            categoriesInBudget: categoriesInBudget,
            plannedIncomeTotal: plannedIncomeTotal,
            actualIncomeTotal: actualIncomeTotal,
            plannedExpensesFiltered: plannedExpensesFiltered,
            variableExpensesFiltered: variableExpensesFiltered,
            unifiedItemsFiltered: unifiedItemsFiltered,
            hiddenFuturePlannedExpenseCount: hiddenFuturePlannedExpenseCount,
            hiddenFutureVariableExpenseCount: hiddenFutureVariableExpenseCount,
            plannedExpensesPlannedTotal: plannedExpensesPlannedTotal,
            plannedExpensesActualTotal: plannedExpensesActualTotal,
            plannedExpensesEffectiveTotal: plannedExpensesEffectiveTotal,
            variableExpensesTotal: variableExpensesTotal,
            maxSavings: maxSavings,
            projectedSavings: projectedSavings,
            actualSavings: actualSavings,
            presetBySourceID: presetLookup(for: plannedExpensesFiltered)
        )
    }

    private func presetLookup(for plannedExpenses: [PlannedExpense]) -> [UUID: Preset] {
        let sourcePresetIDs = Set(plannedExpenses.compactMap(\.sourcePresetID))
        guard !sourcePresetIDs.isEmpty else { return [:] }

        var presetsByID: [UUID: Preset] = [:]
        for preset in workspace.presets ?? [] {
            if sourcePresetIDs.contains(preset.id) {
                presetsByID[preset.id] = preset
            }
        }
        return presetsByID
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
    
    private func expensesTitleText(_ derived: BudgetDetailDerivedState) -> Text {
        switch expenseScope {
        case .planned:
            return Text("Planned Expenses • \(derived.plannedExpensesPlannedTotal, format: CurrencyFormatter.currencyStyle())")
            
        case .unified:
            let unifiedTotal = derived.plannedExpensesEffectiveTotal + derived.variableExpensesTotal
            return Text("All Expenses • \(unifiedTotal, format: CurrencyFormatter.currencyStyle())")
            
        case .variable:
            return Text("Variable Expenses • \(derived.variableExpensesTotal, format: CurrencyFormatter.currencyStyle())")
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        mainContent
            .onAppear {
                isVisible = true
                commandHub.activate(.budgetDetail)
                updateBudgetDetailCommandAvailability()
                if !didApplyDefaultsOnAppear {
                    hideFuturePlannedExpensesInView = hideFuturePlannedExpensesDefault
                    excludeFuturePlannedExpensesFromCalculationsInView = excludeFuturePlannedExpensesFromCalculationsDefault
                    hideFutureVariableExpensesInView = hideFutureVariableExpensesDefault
                    excludeFutureVariableExpensesFromCalculationsInView = excludeFutureVariableExpensesFromCalculationsDefault
                    didApplyDefaultsOnAppear = true
                }
                if hasLoadedDerivedState == false {
                    hydrateDerivedStateFromCacheIfAvailable()
                    rebuildDerivedState(reason: "onAppearInitial")
                    hasLoadedDerivedState = true
                    needsDerivedStateRefresh = false
                } else if needsDerivedStateRefresh {
                    rebuildDerivedState(reason: "onAppearRefresh")
                    needsDerivedStateRefresh = false
                }
#if DEBUG
                appearCount += 1
                debugLog("onAppear count=\(appearCount)")
#endif
            }
            .onDisappear {
                isVisible = false
                searchFocused = false
                commandHub.deactivate(.budgetDetail)
                commandHub.setBudgetDetailCanCreateTransaction(false)
                searchRebuildTask?.cancel()
#if DEBUG
                debugLog("onDisappear")
#endif
            }
            .onChange(of: linkedCards.count) { _, _ in
                updateBudgetDetailCommandAvailability()
            }
            .onReceive(commandHub.$sequence) { _ in
                guard commandHub.surface == .budgetDetail else { return }
                handleCommand(commandHub.latestCommandID)
            }
            .onChange(of: searchText) { _, _ in
                if isVisible {
                    scheduleSearchDerivedStateRebuild()
                } else {
                    searchRebuildTask?.cancel()
                    needsDerivedStateRefresh = true
                }
            }
            .onChange(of: derivedRebuildInputs) { _, _ in
                if isVisible {
                    rebuildDerivedState(reason: "derivedRebuildInputs")
                } else {
                    needsDerivedStateRefresh = true
                }
            }
    }

    private var mainContent: some View {
        budgetDetailList(derived: derivedState)
        .postBoardingTip(
            key: "tip.budgetdetail.v1",
            title: "Budget Detail Overview",
            items: Self.tipItems
        )
        .listStyle(.insetGrouped)
        .navigationTitle(budget.name)

        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: isPhone ? .automatic : .always),
            prompt: "Search"
        )
        .searchFocused($searchFocused)

        .toolbar {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    budgetDisplayToolbarButton
                    budgetActionsToolbarButton
                }

                ToolbarSpacer(.flexible, placement: .primaryAction)

                ToolbarItemGroup(placement: .primaryAction) {
                    addTransactionToolbarButton
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    budgetDisplayToolbarButton
                    budgetActionsToolbarButton
                    addTransactionToolbarButton
                }
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
        .sheet(item: $activeModal, onDismiss: handleModalDismiss) { modal in
            switch modal {
            case .addExpense:
                NavigationStack {
                    AddExpenseView(
                        workspace: workspace,
                        allowedCards: linkedCards,
                        defaultDate: .now
                    )
                }
            case .managePresets:
                NavigationStack {
                    ManagePresetsForBudgetSheet(workspace: workspace, budget: budget)
                }
            case .manageCards:
                NavigationStack {
                    ManageCardsForBudgetSheet(workspace: workspace, budget: budget)
                }
            case .editBudget:
                NavigationStack {
                    EditBudgetView(workspace: workspace, budget: budget)
                }
            case .editExpense(let expense):
                NavigationStack {
                    EditExpenseView(workspace: workspace, expense: expense)
                }
            case .editPlannedExpense(let plannedExpense):
                NavigationStack {
                    EditPlannedExpenseView(workspace: workspace, plannedExpense: plannedExpense)
                }
            case .editPreset(let preset):
                NavigationStack {
                    EditPresetView(workspace: workspace, preset: preset)
                }
            case .editCategoryLimit(let input):
                EditCategoryLimitView(
                    budget: budget,
                    category: input.category,
                    plannedContribution: input.plannedContribution,
                    variableContribution: input.variableContribution
                )
            case .reviewRecordedPlannedExpenses:
                NavigationStack {
                    BudgetRecordedPlannedExpensesReviewView(
                        workspace: workspace,
                        budget: budget,
                        onDeleteBudget: {
                            activeModal = nil
                            deleteBudgetOnly()
                        },
                        onDone: {
                            activeModal = nil
                        }
                    )
                }
            }
        }
    }

    private var linkedVariableExpenseCount: Int {
        linkedCards.reduce(0) { partialResult, card in
            partialResult + (card.variableExpenses?.count ?? 0)
        }
    }

    private struct DerivedRebuildInputs: Equatable {
        let selectedCategoryIDs: Set<UUID>
        let expenseScope: ExpenseScope
        let sortMode: BudgetSortMode
        let hideFuturePlannedExpensesInView: Bool
        let excludeFuturePlannedExpensesFromCalculationsInView: Bool
        let hideFutureVariableExpensesInView: Bool
        let excludeFutureVariableExpensesFromCalculationsInView: Bool
        let workspaceIncomesCount: Int
        let workspacePlannedExpensesCount: Int
        let workspaceCategoriesCount: Int
        let workspacePresetsCount: Int
        let budgetPresetLinksCount: Int
        let linkedCardsCount: Int
        let linkedVariableExpenseCount: Int
        let budgetStartDate: Date
        let budgetEndDate: Date
    }

    private var derivedRebuildInputs: DerivedRebuildInputs {
        DerivedRebuildInputs(
            selectedCategoryIDs: selectedCategoryIDs,
            expenseScope: expenseScope,
            sortMode: sortMode,
            hideFuturePlannedExpensesInView: hideFuturePlannedExpensesInView,
            excludeFuturePlannedExpensesFromCalculationsInView: excludeFuturePlannedExpensesFromCalculationsInView,
            hideFutureVariableExpensesInView: hideFutureVariableExpensesInView,
            excludeFutureVariableExpensesFromCalculationsInView: excludeFutureVariableExpensesFromCalculationsInView,
            workspaceIncomesCount: workspace.incomes?.count ?? 0,
            workspacePlannedExpensesCount: workspace.plannedExpenses?.count ?? 0,
            workspaceCategoriesCount: workspace.categories?.count ?? 0,
            workspacePresetsCount: workspace.presets?.count ?? 0,
            budgetPresetLinksCount: budget.presetLinks?.count ?? 0,
            linkedCardsCount: linkedCards.count,
            linkedVariableExpenseCount: linkedVariableExpenseCount,
            budgetStartDate: budget.startDate,
            budgetEndDate: budget.endDate
        )
    }

    private func rebuildDerivedState(reason: String = "unspecified") {
        let start = DispatchTime.now().uptimeNanoseconds
        derivedState = buildDerivedState()
        detailSnapshotCache.store(derivedState, for: derivedStateCacheKey)
#if DEBUG
        let elapsedMS = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        if elapsedMS >= 8 {
            debugLog("rebuildDerivedState reason=\(reason) elapsedMS=\(elapsedMS)")
        }
#endif
    }

    private func scheduleSearchDerivedStateRebuild() {
        searchRebuildTask?.cancel()
        guard isVisible else {
            needsDerivedStateRefresh = true
            return
        }
        searchRebuildTask = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled, isVisible else { return }
            rebuildDerivedState(reason: "searchDebounced")
        }
    }

    private func handleModalDismiss() {
        if isVisible {
            rebuildDerivedState(reason: "modalDismiss")
        } else {
            needsDerivedStateRefresh = true
        }
    }

    private func hydrateDerivedStateFromCacheIfAvailable() {
        if let cached: BudgetDetailDerivedState = detailSnapshotCache.snapshot(for: derivedStateCacheKey) {
            derivedState = cached
#if DEBUG
            debugLog("cache hit key=\(derivedStateCacheKey)")
#endif
        } else {
#if DEBUG
            debugLog("cache miss key=\(derivedStateCacheKey)")
#endif
        }
    }

    private var derivedStateCacheKey: String {
        let budgetStartStamp = Int64(budget.startDate.timeIntervalSinceReferenceDate)
        let budgetEndStamp = Int64(budget.endDate.timeIntervalSinceReferenceDate)
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        parts.reserveCapacity(23)
        parts.append("budget-detail")
        parts.append(workspace.id.uuidString)
        parts.append(budget.id.uuidString)
        if selectedCategoryIDs.isEmpty {
            parts.append("none")
        } else {
            parts.append(selectedCategoryIDs.map(\.uuidString).sorted().joined(separator: ","))
        }
        parts.append(expenseScope.rawValue)
        parts.append(sortMode.rawValue)
        parts.append(hideFuturePlannedExpensesInView ? "1" : "0")
        parts.append(excludeFuturePlannedExpensesFromCalculationsInView ? "1" : "0")
        parts.append(hideFutureVariableExpensesInView ? "1" : "0")
        parts.append(excludeFutureVariableExpensesFromCalculationsInView ? "1" : "0")
        parts.append(String(budgetStartStamp))
        parts.append(String(budgetEndStamp))
        parts.append(String(workspace.incomes?.count ?? 0))
        parts.append(String(workspace.plannedExpenses?.count ?? 0))
        parts.append(String(workspace.categories?.count ?? 0))
        parts.append(String(workspace.presets?.count ?? 0))
        parts.append(String(budget.presetLinks?.count ?? 0))
        parts.append(String(linkedCards.count))
        parts.append(String(linkedVariableExpenseCount))
        parts.append(String(latestLinkedVariableExpenseStamp))
        parts.append(String(latestWorkspaceIncomeStamp))
        parts.append(String(latestWorkspacePlannedExpenseStamp))
        parts.append(trimmedSearch)
        return parts.joined(separator: "|")
    }

    private var latestLinkedVariableExpenseStamp: Int64 {
        Int64(
            linkedCards
                .flatMap { $0.variableExpenses ?? [] }
                .map(\.transactionDate.timeIntervalSinceReferenceDate)
                .max() ?? 0
        )
    }

    private var latestWorkspaceIncomeStamp: Int64 {
        Int64((workspace.incomes ?? []).map(\.date.timeIntervalSinceReferenceDate).max() ?? 0)
    }

    private var latestWorkspacePlannedExpenseStamp: Int64 {
        Int64((workspace.plannedExpenses ?? []).map(\.expenseDate.timeIntervalSinceReferenceDate).max() ?? 0)
    }

#if DEBUG
    private func debugLog(_ message: String) {
        print("[BudgetDetailView:\(budget.id.uuidString)] \(message)")
    }
#endif

    private func budgetDetailList(derived: BudgetDetailDerivedState) -> some View {
        List {
            summarySection(derived)
            categorySection(derived)
            typeAndSortSection
            expenseListSection(derived)
        }
    }

    @ViewBuilder
    private func summarySection(_ derived: BudgetDetailDerivedState) -> some View {
        Section {
            VStack(spacing: 12) {
                BudgetSummaryBucketCard(
                    title: "Income",
                    titleColor: .blue,
                    rows: [
                        .init(label: "Planned Income", value: derived.plannedIncomeTotal),
                        .init(label: "Actual Income", value: derived.actualIncomeTotal)
                    ]
                )

                BudgetSummaryBucketCard(
                    title: "Expenses",
                    titleColor: .orange,
                    rows: expenseRowsForCurrentSelection(derived)
                )

                BudgetSummaryBucketCard(
                    title: "Savings",
                    titleColor: .green,
                    rows: [
                        .init(label: "Max Savings", value: derived.maxSavings),
                        .init(label: "Projected Savings", value: derived.projectedSavings),
                        .init(label: "Actual Savings", value: derived.actualSavings)
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
    }

    @ViewBuilder
    private func categorySection(_ derived: BudgetDetailDerivedState) -> some View {
        if !derived.categoriesInBudget.isEmpty {
            Section {
                BudgetCategoryChipsRow(
                    categories: derived.categoriesInBudget,
                    selectedIDs: $selectedCategoryIDs,
                    onLongPressCategory: { category in
                        let input = CategoryLimitEditorInput(
                            category: category,
                            plannedContribution: plannedContribution(for: category, derived: derived),
                            variableContribution: variableContribution(for: category, derived: derived)
                        )
                        activeModal = .editCategoryLimit(input)
                    }
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
                Text("Single-press categories to filter expenses; tap selected chips to clear one. Long-press to edit category limits.")
            }
        }
    }

    private var typeAndSortSection: some View {
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
    }

    private func expenseListSection(_ derived: BudgetDetailDerivedState) -> some View {
        Section {
            expenseListSectionContent(derived)
        } header: {
            expensesTitleText(derived)
        } footer: {
            expenseListSectionFooter(derived)
        }
    }

    @ViewBuilder
    private func expenseListSectionContent(_ derived: BudgetDetailDerivedState) -> some View {
        switch expenseScope {
        case .planned:
            if derived.plannedExpensesFiltered.isEmpty {
                ContentUnavailableView(plannedEmptyMessage(derived), systemImage: "")
            } else {
                ForEach(derived.plannedExpensesFiltered, id: \.id) { expense in
                    plannedExpenseRow(expense, presetBySourceID: derived.presetBySourceID)
                }
            }

        case .variable:
            if derived.variableExpensesFiltered.isEmpty {
                ContentUnavailableView(variableEmptyMessage(derived), systemImage: "")
            } else {
                ForEach(derived.variableExpensesFiltered, id: \.id) { expense in
                    variableExpenseRow(expense)
                }
            }

        case .unified:
            if derived.unifiedItemsFiltered.isEmpty {
                ContentUnavailableView(unifiedEmptyMessage(derived), systemImage: "")
            } else {
                ForEach(derived.unifiedItemsFiltered) { item in
                    unifiedExpenseRow(item, presetBySourceID: derived.presetBySourceID)
                }
            }
        }
    }

    @ViewBuilder
    private func expenseListSectionFooter(_ derived: BudgetDetailDerivedState) -> some View {
        if derived.hiddenFuturePlannedExpenseCount > 0 {
            Text("\(derived.hiddenFuturePlannedExpenseCount.formatted()) future planned expenses are hidden.")
        }
        if derived.hiddenFutureVariableExpenseCount > 0 {
            Text("\(derived.hiddenFutureVariableExpenseCount.formatted()) future variable expenses are hidden.")
        }
    }

    private func plannedExpenseRow(
        _ expense: PlannedExpense,
        presetBySourceID: [UUID: Preset]
    ) -> some View {
        BudgetPlannedExpenseRow(expense: expense, showsCardName: true)
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    openEdit(expense)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                .tint(Color("AccentColor"))

                if let presetID = expense.sourcePresetID, let preset = presetBySourceID[presetID] {
                    Button {
                        openEditPreset(preset)
                    } label: {
                        Label("Edit Preset", systemImage: "list.bullet.rectangle")
                    }
                    .tint(Color("OffshoreSand"))
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

    private func variableExpenseRow(_ expense: VariableExpense) -> some View {
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

    @ViewBuilder
    private func unifiedExpenseRow(
        _ item: BudgetUnifiedExpenseItem,
        presetBySourceID: [UUID: Preset]
    ) -> some View {
        switch item {
        case .planned(let expense):
            plannedExpenseRow(expense, presetBySourceID: presetBySourceID)
        case .variable(let expense):
            variableExpenseRow(expense)
        }
    }

    @ViewBuilder
    private var addTransactionToolbarButton: some View {
        Button {
            activeModal = .addExpense
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add Expense")
        .disabled(linkedCards.isEmpty)
    }

    @ViewBuilder
    private var budgetActionsToolbarButton: some View {
        Menu {
            Button {
                activeModal = .managePresets
            } label: {
                Label("Manage Presets", systemImage: "list.bullet.rectangle")
            }

            Button {
                activeModal = .manageCards
            } label: {
                Label("Manage Cards", systemImage: "creditcard")
            }

            Divider()

            Button {
                activeModal = .editBudget
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

    @ViewBuilder
    private var budgetDisplayToolbarButton: some View {
        Menu {
            Menu {
                Toggle("Hide Future Planned Expenses", isOn: $hideFuturePlannedExpensesInView)
                Toggle(
                    "Exclude Future Planned Expenses from Totals",
                    isOn: $excludeFuturePlannedExpensesFromCalculationsInView
                )
            } label: {
                if #available(iOS 26.0, *) {
                    Label("Planned Expense Display", systemImage: "calendar.badge")
                } else {
                    Label("Planned Expense Display", systemImage: "calendar.badge.clock")
                }
            }

            Menu {
                Toggle("Hide Future Variable Expenses", isOn: $hideFutureVariableExpensesInView)
                Toggle(
                    "Exclude Future Variable Expenses from Totals",
                    isOn: $excludeFutureVariableExpensesFromCalculationsInView
                )
            } label: {
                Label("Variable Expense Display", systemImage: "chart.xyaxis.line")
            }
        } label: {
            Image(systemName: "eye")
        }
        .accessibilityLabel("Expense Display")
    }

    // MARK: - Expenses bucket rows (reactive)

    private func expenseRowsForCurrentSelection(_ derived: BudgetDetailDerivedState) -> [BudgetSummaryBucketCard.Row] {
        switch expenseScope {
        case .planned:
            return [
                .init(label: "Planned Total", value: derived.plannedExpensesPlannedTotal),
                .init(label: "Actual Total", value: derived.plannedExpensesActualTotal)
            ]

        case .variable:
            return [
                .init(label: "Variable Total", value: derived.variableExpensesTotal),
            ]

        case .unified:
            let unifiedTotal = derived.plannedExpensesEffectiveTotal + derived.variableExpensesTotal
            return [
                .init(label: "Planned Total", value: derived.plannedExpensesEffectiveTotal),
                .init(label: "Variable Total", value: derived.variableExpensesTotal),
                .init(label: "Unified Total", value: unifiedTotal)
            ]
        }
    }

    private func plannedEmptyMessage(_ derived: BudgetDetailDerivedState) -> String {
        if derived.hiddenFuturePlannedExpenseCount > 0 {
            return "No visible planned expenses"
        }
        return "No planned expenses"
    }

    private func variableEmptyMessage(_ derived: BudgetDetailDerivedState) -> String {
        if derived.hiddenFutureVariableExpenseCount > 0 {
            return "No visible variable expenses"
        }
        return "No variable expenses"
    }

    private func unifiedEmptyMessage(_ derived: BudgetDetailDerivedState) -> String {
        if derived.hiddenFuturePlannedExpenseCount > 0 || derived.hiddenFutureVariableExpenseCount > 0 {
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
            activeModal = .reviewRecordedPlannedExpenses
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
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
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
        activeModal = .editExpense(expense)
    }

    private func openEdit(_ plannedExpense: PlannedExpense) {
        activeModal = .editPlannedExpense(plannedExpense)
    }

    private func openEditPreset(_ preset: Preset) {
        activeModal = .editPreset(preset)
    }

    private func deleteVariableExpense(_ expense: VariableExpense) {
        deleteWithOptionalConfirm {
            deleteVariableExpenseRecord(expense)
        }
    }

    private func deletePlannedExpense(_ expense: PlannedExpense) {
        deleteWithOptionalConfirm {
            PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        }
    }

    private func deleteWithOptionalConfirm(_ deleteAction: @escaping () -> Void) {
        if confirmBeforeDeleting {
            pendingExpenseDelete = deleteAction
            showingExpenseDeleteConfirm = true
        } else {
            deleteAction()
        }
    }

    private func deleteVariableExpensesFiltered(at offsets: IndexSet) {
        let derived = derivedState
        let expensesToDelete = offsets.compactMap { index in
            derived.variableExpensesFiltered.indices.contains(index) ? derived.variableExpensesFiltered[index] : nil
        }

        deleteWithOptionalConfirm {
            for expense in expensesToDelete {
                deleteVariableExpenseRecord(expense)
            }
        }
    }

    private func deletePlannedExpensesFiltered(at offsets: IndexSet) {
        let derived = derivedState
        let expensesToDelete = offsets.compactMap { index in
            derived.plannedExpensesFiltered.indices.contains(index) ? derived.plannedExpensesFiltered[index] : nil
        }

        deleteWithOptionalConfirm {
            for expense in expensesToDelete {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        }
    }

    private func deleteUnifiedExpensesFiltered(at offsets: IndexSet) {
        let derived = derivedState
        let itemsToDelete = offsets.compactMap { index in
            derived.unifiedItemsFiltered.indices.contains(index) ? derived.unifiedItemsFiltered[index] : nil
        }

        deleteWithOptionalConfirm {
            for item in itemsToDelete {
                switch item {
                case .planned(let expense):
                    PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
                case .variable(let expense):
                    deleteVariableExpenseRecord(expense)
                }
            }
        }
    }

    private func deleteVariableExpenseRecord(_ expense: VariableExpense) {
        VariableExpenseDeletionService.delete(expense, modelContext: modelContext)
    }

    // MARK: - Category Limit Math

    private func plannedContribution(for category: Category, derived: BudgetDetailDerivedState) -> Double {
        derived.plannedExpensesInBudget
            .filter { $0.category?.id == category.id }
            .reduce(0) { total, expense in
                total + SavingsMathService.plannedBudgetImpactAmount(for: expense)
            }
    }

    private func variableContribution(for category: Category, derived: BudgetDetailDerivedState) -> Double {
        derived.variableExpensesInBudget
            .filter { $0.category?.id == category.id }
            .reduce(0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }
    }

    private func updateBudgetDetailCommandAvailability() {
        commandHub.setBudgetDetailCanCreateTransaction(!linkedCards.isEmpty)
    }

    private func openNewTransaction() {
        activeModal = .addExpense
    }

    private func openEditBudget() {
        activeModal = .editBudget
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
        case AppCommandID.ExpenseDisplay.toggleHideFuturePlanned:
            hideFuturePlannedExpensesInView.toggle()
        case AppCommandID.ExpenseDisplay.toggleExcludeFuturePlanned:
            excludeFuturePlannedExpensesFromCalculationsInView.toggle()
        case AppCommandID.ExpenseDisplay.toggleHideFutureVariable:
            hideFutureVariableExpensesInView.toggle()
        case AppCommandID.ExpenseDisplay.toggleExcludeFutureVariable:
            excludeFutureVariableExpensesFromCalculationsInView.toggle()
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
    @Binding var selectedIDs: Set<UUID>
    var onLongPressCategory: ((Category) -> Void)? = nil

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories, id: \.id) { category in
                    BudgetChip(
                        title: category.name,
                        dotHex: category.hexColor,
                        isSelected: selectedIDs.contains(category.id)
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
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
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
        Group {
            if #available(iOS 26.0, *) {
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
            } else {
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
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(backgroundColor)
                )
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
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

    private enum SharedBalancePresentation {
        case none
        case split
        case offset
    }

    private var amountToShow: Double {
        expense.effectiveAmount()
    }

    private var offsetAmount: Double {
        max(0, -(expense.offsetSettlement?.amount ?? 0))
    }

    private var splitAmount: Double {
        max(0, expense.allocation?.allocatedAmount ?? 0)
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
            return "arrow.trianglehead.2.clockwise"
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
            return "arrow.trianglehead.2.clockwise"
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
