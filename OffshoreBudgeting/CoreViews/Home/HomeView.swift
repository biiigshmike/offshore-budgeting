//
//  HomeView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct HomeView: View {

    let workspace: Workspace

    @Query private var budgets: [Budget]
    @Query private var cards: [Card]
    @Query private var plannedExpenses: [PlannedExpense]
    @Query private var incomes: [Income]
    @Query private var categories: [Category]
    @Query private var variableExpenses: [VariableExpense]

    // MARK: - Date Range Storage (per workspace)

    private static func appliedStartKey(workspaceID: UUID) -> String {
        "home_appliedStartTimestamp_\(workspaceID.uuidString)"
    }

    private static func appliedEndKey(workspaceID: UUID) -> String {
        "home_appliedEndTimestamp_\(workspaceID.uuidString)"
    }

    private static func lastSyncedDefaultBudgetingPeriodKey(workspaceID: UUID) -> String {
        "home_lastSyncedDefaultBudgetingPeriod_\(workspaceID.uuidString)"
    }

    private static let legacyAppliedStartKey = "home_appliedStartTimestamp"
    private static let legacyAppliedEndKey = "home_appliedEndTimestamp"

    @AppStorage private var appliedStartTimestamp: Double
    @AppStorage private var appliedEndTimestamp: Double
    @AppStorage private var lastSyncedDefaultBudgetingPeriodRaw: String

    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

    @State private var draftStartDate: Date = Date()
    @State private var draftEndDate: Date = Date()

    @State private var isEditingWidgets: Bool = false

    @State private var pinnedItems: [HomePinnedItem] = []

    // MARK: - Data Fixups

    private var plannedExpensesForHome: [PlannedExpense] {
        // I filter out budget-generated planned expenses whose source budget no longer exists,
        // because deleting a budget can leave orphan planned expenses behind.
        let existingBudgetIDs = Set(budgets.map(\.id))

        return plannedExpenses.filter { expense in
            guard let sourceBudgetID = expense.sourceBudgetID else {
                return true
            }
            return existingBudgetIDs.contains(sourceBudgetID)
        }
    }

    // MARK: - A11y + Layout Environment

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _appliedStartTimestamp = AppStorage(wrappedValue: 0, Self.appliedStartKey(workspaceID: workspaceID))
        _appliedEndTimestamp = AppStorage(wrappedValue: 0, Self.appliedEndKey(workspaceID: workspaceID))
        _lastSyncedDefaultBudgetingPeriodRaw = AppStorage(
            wrappedValue: "",
            Self.lastSyncedDefaultBudgetingPeriodKey(workspaceID: workspaceID)
        )

        _budgets = Query(
            filter: #Predicate<Budget> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Budget.startDate, order: .reverse)]
        )

        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _plannedExpenses = Query(
            filter: #Predicate<PlannedExpense> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\PlannedExpense.expenseDate, order: .forward)]
        )

        _incomes = Query(
            filter: #Predicate<Income> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Income.date, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )

        _variableExpenses = Query(
            filter: #Predicate<VariableExpense> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\VariableExpense.transactionDate, order: .forward)]
        )
    }

	    var body: some View {
	        ZStack {
	            HomeBackgroundView()

	            GeometryReader { proxy in
	                ScrollView {
	                    VStack(alignment: .leading, spacing: 14) {

                        HomeDateRangeBar(
                            draftStartDate: $draftStartDate,
                            draftEndDate: $draftEndDate,
                            isApplyEnabled: isDateRangeDirty,
                            onApply: applyDraftRange
                        )
                        .padding(.top, 8)

                        widgetsHeader

                        VStack(spacing: 12) {

                            if pinnedItems.isEmpty {
                                HomeTileContainer(
                                    title: "Home",
                                    subtitle: dateRangeSubtitle,
                                    accent: .primary,
                                    showsChevron: false
                                ) {
                                    Text("Tap Edit to pin widgets and cards to Home.")
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            } else {

                                let columnCount = homeColumnCount(for: proxy.size.width)

                                if columnCount <= 1 {
                                    VStack(spacing: gridSpacing) {
                                        ForEach(pinnedItems) { item in
                                            pinnedItemView(item)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                    }
                                } else {
                                    let rows = pinnedGridRows(columnCount: columnCount)

                                    Grid(horizontalSpacing: gridSpacing, verticalSpacing: gridSpacing) {
                                        ForEach(rows.indices, id: \.self) { rowIndex in
                                            GridRow {
                                                ForEach(rows[rowIndex].cells.indices, id: \.self) { cellIndex in
                                                    pinnedItemView(rows[rowIndex].cells[cellIndex].item)
                                                        .frame(maxWidth: .infinity, alignment: .leading)
                                                        .gridCellColumns(rows[rowIndex].cells[cellIndex].span)
                                                }

                                                if rows[rowIndex].remainingColumns > 0 {
                                                    Color.clear
                                                        .frame(height: 0)
                                                        .gridCellColumns(rows[rowIndex].remainingColumns)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

	                        Spacer(minLength: 22)
	                    }
	                    .padding(.horizontal, contentHorizontalPadding)
	                    .padding(.bottom, 18)
	                    .frame(maxWidth: .infinity, alignment: .leading)
	                }
	            }
	        }
	        .postBoardingTip(
            key: "tip.home.v1",
            title: "Home",
            items: [
                PostBoardingTipItem(
                    systemImage: "house.fill",
                    title: "Dashboard",
                    detail: "Home is your landing page. This is the first screen you see when opening the app."
                ),
                PostBoardingTipItem(
                    systemImage: "rectangle.grid.2x2",
                    title: "Widgets",
                    detail: "Tap any widget to open deeper metrics. Use Edit to pin, reorder, or remove widgets."
                ),
                PostBoardingTipItem(
                    systemImage: "calendar",
                    title: "Date Range",
                    detail: "Use the date controls at the top to change the time period shown across all widgets."
                )
            ]
        )
        .navigationTitle("Home")
        .sheet(isPresented: $isEditingWidgets) {
            HomeEditPinnedCardsView(
                cards: cards,
                workspaceID: workspace.id,
                pinnedItems: $pinnedItems
            )
            .onDisappear {
                persistPinnedItems()
            }
        }
        .onAppear {
            bootstrapAppliedDatesIfNeeded()
            applyDefaultBudgetingPeriodIfSettingsChanged()
            syncDraftToApplied()
            loadPinnedItemsIfNeeded()
        }
        .onChange(of: pinnedItems) { _, _ in
            persistPinnedItems()
        }
        .onChange(of: defaultBudgetingPeriodRaw) { _, _ in
            applyDefaultBudgetingPeriodToApplied()
            lastSyncedDefaultBudgetingPeriodRaw = defaultBudgetingPeriodRaw
            syncDraftToApplied()
        }
    }

    // MARK: - Unified tile rendering

    @ViewBuilder
    private func pinnedItemView(_ item: HomePinnedItem) -> some View {
        switch item {
        case .widget(let widget, _):
            widgetView(for: widget)

        case .card(let id, _):
            if let card = cards.first(where: { $0.id == id }) {
                HomeCardSummaryTile(
                    workspace: workspace,
                    card: card,
                    startDate: appliedStartDate,
                    endDate: appliedEndDate
                )
                .accessibilityElement(children: .combine)
            } else {
                HomeTileContainer(
                    title: "Missing Card",
                    subtitle: dateRangeSubtitle,
                    accent: .secondary,
                    showsChevron: false
                ) {
                    Text("This pinned card no longer exists.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder
    private func widgetView(for widget: HomeWidgetID) -> some View {
        switch widget {
        case .income:
            incomeWidget

        case .savingsOutlook:
            savingsOutlookWidget

        case .whatIf:
            whatIfWidget

        case .nextPlannedExpense:
            nextPlannedExpenseWidget

        case .categorySpotlight:
            categorySpotlightWidget

        case .categoryAvailability:
            categoryAvailabilityWidget

        case .spendTrends:
            spendTrendsWidget
        }
    }

    // MARK: - Widget views

    private var incomeWidget: some View {
        HomeIncomeTile(
            workspace: workspace,
            incomes: incomes,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

    private var savingsOutlookWidget: some View {
        HomeSavingsOutlookTile(
            workspace: workspace,
            incomes: incomes,
            plannedExpenses: plannedExpensesForHome,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

    private var whatIfWidget: some View {
        HomeWhatIfTile(
            workspace: workspace,
            categories: categories,
            incomes: incomes,
            plannedExpenses: plannedExpensesForHome,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

    @ViewBuilder
    private var nextPlannedExpenseWidget: some View {
        if let next = HomeNextPlannedExpenseFinder.nextExpense(
            from: plannedExpensesForHome,
            in: appliedStartDate,
            to: appliedEndDate
        ) {
            HomeNextPlannedExpenseTile(
                workspace: workspace,
                expense: next,
                startDate: appliedStartDate,
                endDate: appliedEndDate
            )
        } else {
            HomeTileContainer(
                title: "Next Planned Expense",
                subtitle: dateRangeSubtitle,
                accent: .orange,
                showsChevron: false
            ) {
                Text("No planned expenses coming up in this range.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var categorySpotlightWidget: some View {
        HomeCategorySpotlightTile(
            workspace: workspace,
            categories: categories,
            plannedExpenses: plannedExpensesForHome,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate,
            topN: 4
        )
    }

    @ViewBuilder
    private var categoryAvailabilityWidget: some View {
        HomeCategoryAvailabilityTile(
            workspace: workspace,
            budgets: budgets,
            categories: categories,
            plannedExpenses: plannedExpensesForHome,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

    private var spendTrendsWidget: some View {
        HomeSpendTrendsTile(
            workspace: workspace,
            cards: cards,
            categories: categories,
            plannedExpenses: plannedExpensesForHome,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

	    // MARK: - Layout
	
	    private var contentHorizontalPadding: CGFloat { 16 }

	    private var gridSpacing: CGFloat { 12 }

    private struct PinnedGridCell {
        let item: HomePinnedItem
        let span: Int
    }

    private struct PinnedGridRowModel {
        let cells: [PinnedGridCell]
        let remainingColumns: Int
    }

	    private func homeColumnCount(for width: CGFloat) -> Int {
	        if voiceOverEnabled { return 1 }
	        if dynamicTypeSize.isAccessibilitySize { return 1 }

	        let minTileWidth: CGFloat = (dynamicTypeSize >= .xxLarge) ? 420 : 330
	        let usable = max(0, width - (contentHorizontalPadding * 2))
	        let columns = Int((usable + gridSpacing) / (minTileWidth + gridSpacing))

	        return max(1, min(columns, 4))
	    }

    private func pinnedGridRows(columnCount: Int) -> [PinnedGridRowModel] {
        let columnCount = max(1, columnCount)

        var rows: [PinnedGridRowModel] = []
        var current: [PinnedGridCell] = []
        var used = 0

        func flush() {
            guard !current.isEmpty else { return }
            rows.append(.init(cells: current, remainingColumns: max(0, columnCount - used)))
            current = []
            used = 0
        }

        for item in pinnedItems {
            let desiredSpan = (item.tileSize == .wide) ? columnCount : 1
            let clampedSpan = max(1, min(desiredSpan, columnCount))

            if used + clampedSpan > columnCount {
                flush()
            }

            current.append(.init(item: item, span: clampedSpan))
            used += clampedSpan

            if used == columnCount {
                flush()
            }
        }

        flush()
        return rows
    }

    private func homeGridColumns(for width: CGFloat) -> [GridItem] {
        let count = homeColumnCount(for: width)
        return Array(
            repeating: GridItem(.flexible(minimum: 0), spacing: gridSpacing, alignment: .top),
            count: count
        )
    }

    // MARK: - Widgets Header

    private var widgetsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Widgets")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                isEditingWidgets = true
            } label: {
                Text("Edit")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    // MARK: - Date Range

    private var isDateRangeDirty: Bool {
        draftStartDate != appliedStartDate || draftEndDate != appliedEndDate
    }

    private var appliedStartDate: Date {
        Date(timeIntervalSince1970: appliedStartTimestamp)
    }

    private var appliedEndDate: Date {
        Date(timeIntervalSince1970: appliedEndTimestamp)
    }

    private var dateRangeSubtitle: String {
        "\(formattedDate(appliedStartDate)) - \(formattedDate(appliedEndDate))"
    }

    private func syncDraftToApplied() {
        draftStartDate = appliedStartDate
        draftEndDate = appliedEndDate
    }

    private func bootstrapAppliedDatesIfNeeded() {
        guard isAppliedRangeInitialized == false else { return }

        if migrateLegacyAppliedRangeIfNeeded() {
            lastSyncedDefaultBudgetingPeriodRaw = defaultBudgetingPeriodRaw
            return
        }

        applyDefaultBudgetingPeriodToApplied()
        lastSyncedDefaultBudgetingPeriodRaw = defaultBudgetingPeriodRaw
    }

    private var isAppliedRangeInitialized: Bool {
        appliedStartTimestamp > 0 && appliedEndTimestamp > 0
    }

    @discardableResult
    private func migrateLegacyAppliedRangeIfNeeded() -> Bool {
        let defaults = UserDefaults.standard

        let legacyStart = defaults.double(forKey: Self.legacyAppliedStartKey)
        let legacyEnd = defaults.double(forKey: Self.legacyAppliedEndKey)

        guard legacyStart > 0, legacyEnd > 0 else { return false }

        appliedStartTimestamp = legacyStart
        appliedEndTimestamp = legacyEnd
        return true
    }

    private func applyDefaultBudgetingPeriodToApplied() {
        let now = Date()
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let range = period.defaultRange(containing: now, calendar: .current)

        setAppliedRange(start: range.start, end: range.end)
    }

    private func applyDefaultBudgetingPeriodIfSettingsChanged() {
        guard lastSyncedDefaultBudgetingPeriodRaw != defaultBudgetingPeriodRaw else { return }
        applyDefaultBudgetingPeriodToApplied()
        lastSyncedDefaultBudgetingPeriodRaw = defaultBudgetingPeriodRaw
    }

    private func setAppliedRange(start: Date, end: Date) {
        let clampedEnd = max(end, start)
        appliedStartTimestamp = start.timeIntervalSince1970
        appliedEndTimestamp = clampedEnd.timeIntervalSince1970
    }

    private func applyDraftRange() {
        let start = draftStartDate
        let end = draftEndDate

        if end < start {
            draftEndDate = start
            setAppliedRange(start: start, end: start)
            return
        }

        setAppliedRange(start: start, end: end)
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    // MARK: - Persistence: Unified pins + Migration

    private func loadPinnedItemsIfNeeded() {
        if pinnedItems.isEmpty {
            let itemsStore = HomePinnedItemsStore(workspaceID: workspace.id)
            let loaded = itemsStore.load()

            if !loaded.isEmpty {
                pinnedItems = loaded
                return
            }

            let widgetsStore = HomePinnedWidgetsStore(workspaceID: workspace.id)
            let cardsStore = HomePinnedCardsStore(workspaceID: workspace.id)

            let migratedWidgets = widgetsStore.load().map { HomePinnedItem.widget($0, .small) }

            var migratedCardIDs = cardsStore.load()
            if migratedCardIDs.isEmpty {
                migratedCardIDs = cards.map { $0.id }
            }
            let migratedCards = migratedCardIDs.map { HomePinnedItem.card($0, .small) }

            let migrated = migratedWidgets + migratedCards
            pinnedItems = migrated
            itemsStore.save(migrated)
        }
    }

    private func persistPinnedItems() {
        let store = HomePinnedItemsStore(workspaceID: workspace.id)
        store.save(pinnedItems)
    }
}

// MARK: Preview

#Preview("Home") {
    let container = PreviewSeed.makeContainer()

    PreviewHost(container: container) { ws in
        NavigationStack {
            HomeView(workspace: ws)
        }
    }
}
