import SwiftUI
import SwiftData

struct CategoryDetailView: View, Equatable {
    let workspace: Workspace
    let category: Category
    private let workspaceID: UUID
    private let categoryID: UUID

    // Keep parent list refreshes from replacing the destination's query configuration.
    // Its own state, model observations, and queries continue to update normally.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.workspaceID == rhs.workspaceID && lhs.categoryID == rhs.categoryID
    }

    @Environment(\.modelContext) private var modelContext
    @Query private var plannedExpenses: [PlannedExpense]
    @Query private var variableExpenses: [VariableExpense]
    @Query private var workspacePresets: [Preset]

    @AppStorage("general_defaultBudgetingPeriod") private var defaultBudgetingPeriodRaw = BudgetingPeriod.monthly.rawValue
    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting = true
    @AppStorage("general_hideFuturePlannedExpenses") private var hideFuturePlannedDefault = false
    @AppStorage("general_excludeFuturePlannedExpensesFromCalculations") private var excludeFuturePlannedDefault = false
    @AppStorage("general_hideFutureVariableExpenses") private var hideFutureVariableDefault = false
    @AppStorage("general_excludeFutureVariableExpensesFromCalculations") private var excludeFutureVariableDefault = false

    @State private var searchText = ""
    @State private var scope: ExpenseScope = .unified
    @State private var sortMode: CategoryDetailSortMode = .dateDesc
    @State private var startDate = Date.now
    @State private var endDate = Date.now
    @State private var didInitialize = false
    @State private var isApplyingQuickRange = false
    @State private var hideFuturePlanned = false
    @State private var excludeFuturePlanned = false
    @State private var hideFutureVariable = false
    @State private var excludeFutureVariable = false
    @State private var modal: ModalRoute?
    @State private var pendingDeletion: CategoryDetailExpenseItem?
    @State private var showingDeleteConfirm = false

    init(workspace: Workspace, category: Category) {
        self.workspace = workspace
        self.category = category
        let workspaceID = workspace.id
        let categoryID = category.id
        self.workspaceID = workspaceID
        self.categoryID = categoryID
        _plannedExpenses = Query(
            filter: #Predicate<PlannedExpense> {
                $0.workspace?.id == workspaceID && $0.category?.id == categoryID
            },
            sort: [SortDescriptor(\PlannedExpense.expenseDate, order: .reverse)]
        )
        _variableExpenses = Query(
            filter: #Predicate<VariableExpense> {
                $0.workspace?.id == workspaceID && $0.category?.id == categoryID
            },
            sort: [SortDescriptor(\VariableExpense.transactionDate, order: .reverse)]
        )
        _workspacePresets = Query(filter: #Predicate<Preset> { $0.workspace?.id == workspaceID })
    }

    private enum ModalRoute: Identifiable {
        case editVariable(VariableExpense)
        case editPlanned(PlannedExpense)
        case editPreset(Preset)
        case calculationHelp

        var id: String {
            switch self {
            case .editVariable(let expense): "variable-\(expense.id)"
            case .editPlanned(let expense): "planned-\(expense.id)"
            case .editPreset(let preset): "preset-\(preset.id)"
            case .calculationHelp: "calculation-help"
            }
        }
    }

    private var result: CategoryDetailCalculator.Result {
        CategoryDetailCalculator.calculate(
            workspaceID: workspaceID, categoryID: categoryID,
            plannedExpenses: plannedExpenses, variableExpenses: variableExpenses,
            startDate: startDate, endDate: endDate, searchText: searchText,
            scope: scope, sortMode: sortMode,
            hideFuturePlanned: hideFuturePlanned, excludeFuturePlanned: excludeFuturePlanned,
            hideFutureVariable: hideFutureVariable, excludeFutureVariable: excludeFutureVariable
        )
    }

    var body: some View {
        let derived = result
        List {
            totalSection(derived)
            sortSection
            expensesSection(derived)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(category.name)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                DateRangeToolbarControls(
                    startDate: startDate, endDate: endDate,
                    isEnabled: !isApplyingQuickRange,
                    onApply: applyDates,
                    onSelectQuickRange: applyQuickRange
                )
                displayMenu
            }
        }
        .appSheet(item: $modal) { route in
            switch route {
            case .editVariable(let expense):
                NavigationStack { EditExpenseView(workspace: workspace, expense: expense) }
            case .editPlanned(let expense):
                NavigationStack { EditPlannedExpenseView(workspace: workspace, plannedExpense: expense) }
            case .editPreset(let preset):
                NavigationStack { EditPresetView(workspace: workspace, preset: preset) }
            case .calculationHelp:
                FinancialCalculationHelpView(
                    sections: calculationSections(result),
                    dateRange: "\(AppDateFormat.abbreviatedDate(startDate)) – \(AppDateFormat.abbreviatedDate(endDate))"
                )
            }
        }
        .blocksAutomaticExpenseReview(while: showingDeleteConfirm)
        .alert("Delete Expense?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                if let pendingDeletion { delete(pendingDeletion) }
                pendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
        }
        .onAppear {
            guard !didInitialize else { return }
            applyDefaultPeriod()
            hideFuturePlanned = hideFuturePlannedDefault
            excludeFuturePlanned = excludeFuturePlannedDefault
            hideFutureVariable = hideFutureVariableDefault
            excludeFutureVariable = excludeFutureVariableDefault
            didInitialize = true
        }
        .onChange(of: defaultBudgetingPeriodRaw) { _, _ in applyDefaultPeriod() }
    }

    private func totalSection(_ derived: CategoryDetailCalculator.Result) -> some View {
        Section {
            let color = Color(hex: category.hexColor) ?? .secondary
            TotalSpentStatementRow(total: derived.displayTotal, heatMapStops: [
                .init(color: color, location: 0), .init(color: color, location: 1)
            ])
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .accessibilityIdentifier("categoryDetail.total")
        } header: {
            Text("Total Spent")
        } footer: {
            VStack(alignment: .leading, spacing: 8) {
                Button("How is this calculated?", systemImage: "info.circle") { modal = .calculationHelp }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .font(.subheadline)
                    .padding(.vertical, 4)
                Text("Total Spent shows planned expenses and debit purchases for this category in the selected view. Credits and adjustments remain in history and do not contribute to this gross spending total.")
            }
        }
    }

    private var sortSection: some View {
        Section {
            Picker("Scope", selection: $scope) {
                Text("Planned").tag(ExpenseScope.planned)
                Text("Combined").tag(ExpenseScope.unified)
                Text("Variable").tag(ExpenseScope.variable)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("categoryDetail.scope")

            Picker("Sort", selection: $sortMode) {
                Text("A–Z").tag(CategoryDetailSortMode.az)
                Text("Z–A").tag(CategoryDetailSortMode.za)
                Text("\(CurrencyFormatter.currencySymbol)↑").tag(CategoryDetailSortMode.amountAsc)
                Text("\(CurrencyFormatter.currencySymbol)↓").tag(CategoryDetailSortMode.amountDesc)
                Text(String(localized: "sort.dateShort.asc", defaultValue: "D↑", comment: "Compact ascending date sort label for segmented controls."))
                    .tag(CategoryDetailSortMode.dateAsc)
                Text(String(localized: "sort.dateShort.desc", defaultValue: "D↓", comment: "Compact descending date sort label for segmented controls."))
                    .tag(CategoryDetailSortMode.dateDesc)
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("categoryDetail.sort")
        } header: {
            Text("Sort")
        }
    }

    private func expensesSection(_ derived: CategoryDetailCalculator.Result) -> some View {
        Section {
            if derived.items.isEmpty {
                Text(emptyMessage(derived))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(derived.items) { item in
                    expenseRow(item)
                        .accessibilityIdentifier("categoryDetail.expense.\(item.id)")
                }
            }
        } header: {
            Text("\(expenseListTitle) • \(derived.displayTotal, format: CurrencyFormatter.currencyStyle())")
        } footer: {
            if scope != .variable && derived.hiddenFuturePlannedCount > 0 {
                Text("\(derived.hiddenFuturePlannedCount.formatted()) future planned expenses are hidden.")
            }
            if scope != .planned && derived.hiddenFutureVariableCount > 0 {
                Text("\(derived.hiddenFutureVariableCount.formatted()) future variable expenses are hidden.")
            }
        }
    }

    private var expenseListTitle: String {
        switch scope {
        case .planned: String(localized: "Planned Expenses")
        case .variable: String(localized: "Variable Expenses")
        case .unified: String(localized: "All Expenses")
        }
    }

    @ViewBuilder
    private func expenseRow(_ item: CategoryDetailExpenseItem) -> some View {
        switch item {
        case .planned(let expense):
            SharedPlannedExpenseRow(expense: expense, showsCardName: true)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    Button("Edit", systemImage: "pencil") { modal = .editPlanned(expense) }
                        .offshoreAccentTint()
                    if let presetID = expense.sourcePresetID,
                       let preset = workspacePresets.first(where: { $0.id == presetID }) {
                        Button("Edit Preset", systemImage: "list.bullet.rectangle") { modal = .editPreset(preset) }
                            .tint(Color("OffshoreSand"))
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteButton(item) }
        case .variable(let expense):
            Button { modal = .editVariable(expense) } label: {
                SharedVariableExpenseRow(expense: expense, showsCardName: true)
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button("Edit", systemImage: "pencil") { modal = .editVariable(expense) }
                    .offshoreAccentTint()
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteButton(item) }
        }
    }

    private func deleteButton(_ item: CategoryDetailExpenseItem) -> some View {
        Button("Delete", systemImage: "trash", role: .destructive) {
            if confirmBeforeDeleting {
                pendingDeletion = item
                showingDeleteConfirm = true
            } else {
                delete(item)
            }
        }
        .tint(Color("OffshoreDepth"))
    }

    private var displayMenu: some View {
        Menu("Expense Display", systemImage: "eye") {
            Menu("Planned Expense Display", systemImage: "calendar.badge.clock") {
                Toggle("Hide Future Planned Expenses", isOn: $hideFuturePlanned)
                Toggle("Exclude Future Planned Expenses from Totals", isOn: $excludeFuturePlanned)
            }
            Menu("Variable Expense Display", systemImage: "chart.xyaxis.line") {
                Toggle("Hide Future Variable Expenses", isOn: $hideFutureVariable)
                Toggle("Exclude Future Variable Expenses from Totals", isOn: $excludeFutureVariable)
            }
        }
        .labelStyle(.iconOnly)
    }

    private func emptyMessage(_ derived: CategoryDetailCalculator.Result) -> String {
        if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "No expenses match your search in this date range.")
        }
        let hiddenPlanned = scope != .variable && derived.hiddenFuturePlannedCount > 0
        let hiddenVariable = scope != .planned && derived.hiddenFutureVariableCount > 0
        if hiddenPlanned && hiddenVariable {
            return String(localized: "No visible expenses. Future planned and variable expenses are hidden.")
        }
        if hiddenPlanned { return String(localized: "No visible expenses. Future planned expenses are hidden.") }
        if hiddenVariable { return String(localized: "No visible expenses. Future variable expenses are hidden.") }
        return String(localized: "No expenses for this category in this date range.")
    }

    private func applyDefaultPeriod() {
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let range = period.defaultRange(containing: .now, calendar: .current)
        applyDates(range.start, range.end)
    }

    private func applyDates(_ start: Date, _ end: Date) {
        startDate = Calendar.current.startOfDay(for: start)
        endDate = Calendar.current.startOfDay(for: end)
    }

    private func applyQuickRange(_ preset: CalendarQuickRangePreset) {
        isApplyingQuickRange = true
        let range = preset.makeRange(now: .now, calendar: .current)
        DispatchQueue.main.async {
            applyDates(range.start, range.end)
            isApplyingQuickRange = false
        }
    }

    private func delete(_ item: CategoryDetailExpenseItem) {
        switch item {
        case .planned(let expense): PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        case .variable(let expense): VariableExpenseDeletionService.delete(expense, modelContext: modelContext)
        }
    }

    private func calculationSections(_ derived: CategoryDetailCalculator.Result) -> [FinancialCalculationSection] {
        [FinancialCalculationSection(
            id: "category-spending", title: "Category Spending",
            explanation: "Planned expenses plus variable debit purchases for this category across all cards, using the current dates, search, and calculation settings.",
            rows: [
                .init(id: "planned", title: "Planned", amount: derived.plannedTotal),
                .init(id: "variable", title: "Variable", amount: derived.variableTotal),
                .init(id: "combined", title: "Combined Total", amount: derived.plannedTotal + derived.variableTotal, isTotal: true)
            ],
            notes: [
                "Planned expenses use their actual amount when greater than zero; otherwise, they use the planned amount.",
                "Credits and adjustments remain in history and do not contribute to this gross spending total.",
                "Shared splits and Pay From Savings affect budget impact elsewhere; they do not reduce this category’s gross spending total.",
                "Hiding future expenses changes the list. Excluding future expenses from totals changes this calculation."
            ]
        ), FinancialCalculationSection(
            id: "current-view", title: "Current View",
            explanation: "Total Spent follows the selected Planned, Combined, or Variable expense scope.",
            rows: [.init(id: "displayed", title: "Total Spent", amount: derived.displayTotal, isTotal: true)]
        )]
    }
}

#Preview("Category Detail") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { workspace in
        NavigationStack {
            if let category = workspace.categories?.first {
                CategoryDetailView(workspace: workspace, category: category)
                    .equatable()
            }
        }
    }
}
