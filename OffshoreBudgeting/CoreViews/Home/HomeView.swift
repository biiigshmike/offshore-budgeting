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
    let showAssistantToolbarButton: Bool
    let onOpenAssistant: () -> Void

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
    @AppStorage("general_hideFuturePlannedExpenses")
    private var hideFuturePlannedExpensesDefault: Bool = false
    @AppStorage("general_excludeFuturePlannedExpensesFromCalculations")
    private var excludeFuturePlannedExpensesFromCalculationsDefault: Bool = false

    @State private var draftStartDate: Date = Date()
    @State private var draftEndDate: Date = Date()
    @State private var hideFuturePlannedExpensesInView: Bool = false
    @State private var excludeFuturePlannedExpensesFromCalculationsInView: Bool = false

    @State private var isEditingWidgets: Bool = false

    @State private var pinnedItems: [HomePinnedItem] = []
    @State private var masonryMeasuredHeights: [String: CGFloat] = [:]

    @State private var isShowingWhatIfPlanner: Bool = false
    @State private var whatIfInitialScenarioID: UUID? = nil

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

    private var calculationPlannedExpensesForHome: [PlannedExpense] {
        PlannedExpenseFuturePolicy.filteredForCalculations(
            plannedExpensesForHome,
            excludeFuture: excludeFuturePlannedExpensesFromCalculationsInView
        )
    }

    private var visiblePlannedExpensesForHome: [PlannedExpense] {
        PlannedExpenseFuturePolicy.filteredForVisibility(
            plannedExpensesForHome,
            hideFuture: hideFuturePlannedExpensesInView
        )
    }

    // MARK: - A11y + Layout Environment

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled

    private var isPhone: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    init(
        workspace: Workspace,
        showAssistantToolbarButton: Bool = false,
        onOpenAssistant: @escaping () -> Void = { }
    ) {
        self.workspace = workspace
        self.showAssistantToolbarButton = showAssistantToolbarButton
        self.onOpenAssistant = onOpenAssistant
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
                                pinnedItemsLayout(availableWidth: proxy.size.width)
                            }
                        }

                        Spacer(minLength: 22)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, contentHorizontalPadding)
                    .padding(.bottom, 18)
                }
            }
        }
        .navigationDestination(isPresented: $isShowingWhatIfPlanner) {
            WhatIfScenarioPlannerView(
                workspace: workspace,
                categories: categories,
                incomes: incomes,
                plannedExpenses: calculationPlannedExpensesForHome,
                variableExpenses: variableExpenses,
                startDate: appliedStartDate,
                endDate: appliedEndDate,
                initialScenarioID: whatIfInitialScenarioID
            )
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
        .toolbar {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    homeActionsToolbarButton
                }

                if showAssistantToolbarButton {
                    ToolbarSpacer(.flexible, placement: .primaryAction)

                    ToolbarItemGroup(placement: .primaryAction) {
                        assistantToolbarButton
                    }
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    homeActionsToolbarButton
                }

                if showAssistantToolbarButton {
                    ToolbarItem(placement: .primaryAction) {
                        assistantToolbarButton
                    }
                }
            }
        }
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
            prunePinnedCardsIfNeeded()
            hideFuturePlannedExpensesInView = hideFuturePlannedExpensesDefault
            excludeFuturePlannedExpensesFromCalculationsInView = excludeFuturePlannedExpensesFromCalculationsDefault
        }
        .onChange(of: pinnedItems) { _, _ in
            persistPinnedItems()
        }
        .onChange(of: cardIDSet) { _, _ in
            prunePinnedCardsIfNeeded()
        }
        .onChange(of: defaultBudgetingPeriodRaw) { _, _ in
            applyDefaultBudgetingPeriodToApplied()
            lastSyncedDefaultBudgetingPeriodRaw = defaultBudgetingPeriodRaw
            syncDraftToApplied()
        }
    }

    // MARK: - Navigation

    private func openWhatIfPlanner(_ initialScenarioID: UUID?) {
        whatIfInitialScenarioID = initialScenarioID
        isShowingWhatIfPlanner = true
    }

    // MARK: - Unified tile rendering

    @ViewBuilder
    private func pinnedItemView(_ item: HomePinnedItem, displaySize: HomeTileDisplaySize) -> some View {
        switch item {
        case .widget(let widget, _):
            widgetView(for: widget, displaySize: displaySize)

        case .card(let id, _):
            if let card = cards.first(where: { $0.id == id }) {
                HomeCardSummaryTile(
                    workspace: workspace,
                    card: card,
                    startDate: appliedStartDate,
                    endDate: appliedEndDate,
                    excludeFuturePlannedExpensesFromCalculationsInView: excludeFuturePlannedExpensesFromCalculationsInView
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
    private func widgetView(for widget: HomeWidgetID, displaySize: HomeTileDisplaySize) -> some View {
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
            categoryAvailabilityWidget(
                displaySize: displaySize
            )

        case .spendTrends:
            spendTrendsWidget
        }
    }

    // MARK: - Pinned Items Layout

    private enum HomeTileDisplaySize {
        case small
        case wide
        case wideTall

        func columnSpan(for columns: Int) -> Int {
            let columns = max(1, columns)

            switch self {
            case .small:
                return 1
            case .wide, .wideTall:
                if columns >= 3 {
                    return 2
                }
                return columns
            }
        }
    }

    private struct PinnedLayoutCell: Identifiable {
        let id: String
        let item: HomePinnedItem
        let displaySize: HomeTileDisplaySize
        let span: Int
    }

    private struct MasonryPlacement: Identifiable {
        let id: String
        let item: HomePinnedItem
        let displaySize: HomeTileDisplaySize
        let sourceIndex: Int
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let estimatedHeight: CGFloat

        var maxY: CGFloat {
            y + estimatedHeight
        }
    }

    private var usesStackedAccessibilityLayout: Bool {
        voiceOverEnabled || dynamicTypeSize.isAccessibilitySize
    }

    @ViewBuilder
    private func pinnedItemsLayout(availableWidth: CGFloat) -> some View {
        if usesStackedAccessibilityLayout {
            stackedPinnedItemsLayout(availableWidth: availableWidth)
        } else {
            masonryPinnedItemsLayout(availableWidth: availableWidth)
        }
    }

    private func stackedPinnedItemsLayout(availableWidth: CGFloat) -> some View {
        let usableWidth = max(0, availableWidth - (contentHorizontalPadding * 2))
        let items = buildPinnedLayoutItems(columns: 1)

        return LazyVStack(alignment: .leading, spacing: gridSpacing) {
            ForEach(items) { cell in
                pinnedItemView(cell.item, displaySize: cell.displaySize)
                    .frame(
                        width: tileWidth(
                            span: 1,
                            columns: 1,
                            usableWidth: usableWidth
                        ),
                        alignment: .topLeading
                    )
            }
        }
    }

    private func masonryPinnedItemsLayout(availableWidth: CGFloat) -> some View {
        let usableWidth = max(0, availableWidth - (contentHorizontalPadding * 2))
        let columns = max(1, homeMaxSmallTilesPerRow(for: usableWidth))
        let items = buildPinnedLayoutItems(columns: columns)
        let placements = masonryPlacements(
            for: items,
            columns: columns,
            usableWidth: usableWidth
        )
        let totalHeight = max(0, (placements.map(\.maxY).max() ?? 0))
        let highestPriority = Double(max(0, items.count))

        return ZStack(alignment: .topLeading) {
            ForEach(placements) { placement in
                pinnedItemView(placement.item, displaySize: placement.displaySize)
                    .frame(width: placement.width, alignment: .topLeading)
                    .background(masonryHeightReader(id: placement.id))
                    .offset(x: placement.x, y: placement.y)
                    .accessibilitySortPriority(highestPriority - Double(placement.sourceIndex))
            }
        }
        .frame(height: totalHeight, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onPreferenceChange(HomeMasonryHeightPreferenceKey.self) { heights in
            var updated = masonryMeasuredHeights
            var changed = false

            for (id, value) in heights {
                guard value > 1 else { continue }
                let current = updated[id] ?? 0
                if abs(current - value) > 0.5 {
                    updated[id] = value
                    changed = true
                }
            }

            if changed {
                masonryMeasuredHeights = updated
            }
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
            plannedExpenses: calculationPlannedExpensesForHome,
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
            plannedExpenses: calculationPlannedExpensesForHome,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate,
            onOpenPlanner: openWhatIfPlanner
        )
    }

    @ViewBuilder
    private var nextPlannedExpenseWidget: some View {
        if let next = HomeNextPlannedExpenseFinder.nextExpense(
            from: visiblePlannedExpensesForHome,
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
            plannedExpenses: calculationPlannedExpensesForHome,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

    @ViewBuilder
    private func categoryAvailabilityWidget(displaySize: HomeTileDisplaySize) -> some View {
        HomeCategoryAvailabilityTile(
            workspace: workspace,
            budgets: budgets,
            categories: categories,
            plannedExpenses: calculationPlannedExpensesForHome,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate,
            layoutMode: categoryAvailabilityLayoutMode(for: displaySize)
        )
    }

    private func categoryAvailabilityLayoutMode(
        for displaySize: HomeTileDisplaySize
    ) -> HomeCategoryAvailabilityTile.LayoutMode {
        if usesStackedAccessibilityLayout {
            return .small
        }

        switch displaySize {
        case .small:
            return .small
        case .wide, .wideTall:
            return .wide
        }
    }

    private var spendTrendsWidget: some View {
        HomeSpendTrendsTile(
            workspace: workspace,
            cards: cards,
            categories: categories,
            plannedExpenses: calculationPlannedExpensesForHome,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

    // MARK: - Layout

    private var contentHorizontalPadding: CGFloat { 16 }

    private var gridSpacing: CGFloat { 12 }

    private func homeMaxSmallTilesPerRow(for usableWidth: CGFloat) -> Int {
        if isPhone { return 1 }
        if voiceOverEnabled { return 1 }
        if dynamicTypeSize.isAccessibilitySize { return 1 }

        let minTileWidth: CGFloat = (dynamicTypeSize >= .xxLarge) ? 420 : 330
        let fit = Int((usableWidth + gridSpacing) / (minTileWidth + gridSpacing))
        return max(1, min(fit, 3))
    }

    private func buildPinnedLayoutItems(columns: Int) -> [PinnedLayoutCell] {
        let columns = max(1, columns)
        var result: [PinnedLayoutCell] = []

        for (index, item) in pinnedItems.enumerated() {
            let displaySize = effectiveTileDisplaySize(for: item, columns: columns)
            let span = max(1, min(displaySize.columnSpan(for: columns), columns))
            result.append(
                PinnedLayoutCell(
                    id: "\(item.id)-\(index)",
                    item: item,
                    displaySize: displaySize,
                    span: span
                )
            )
        }

        return result
    }

    private func masonryPlacements(
        for items: [PinnedLayoutCell],
        columns: Int,
        usableWidth: CGFloat
    ) -> [MasonryPlacement] {
        let columns = max(1, columns)
        var placements: [MasonryPlacement] = []
        var columnBottoms = Array(repeating: CGFloat(0), count: columns)

        for (index, cell) in items.enumerated() {
            let span = max(1, min(cell.span, columns))
            let column = bestMasonryStartColumn(
                columnBottoms: columnBottoms,
                columns: columns,
                span: span
            )

            let width = tileWidth(span: span, columns: columns, usableWidth: usableWidth)
            let height = resolvedMasonryHeight(
                for: cell.id,
                item: cell.item,
                displaySize: cell.displaySize
            )
            let y = masonryYOrigin(
                columnBottoms: columnBottoms,
                startColumn: column,
                span: span
            )

            let placement = MasonryPlacement(
                id: cell.id,
                item: cell.item,
                displaySize: cell.displaySize,
                sourceIndex: index,
                x: xOrigin(
                    forColumn: column,
                    columns: columns,
                    usableWidth: usableWidth
                ),
                y: y,
                width: width,
                estimatedHeight: height
            )

            placements.append(placement)

            let newBottom = placement.maxY + gridSpacing
            for c in column..<(column + span) {
                columnBottoms[c] = newBottom
            }
        }

        return placements
    }

    private func bestMasonryStartColumn(
        columnBottoms: [CGFloat],
        columns: Int,
        span: Int
    ) -> Int {
        let maxStart = max(0, columns - span)
        var bestColumn = 0
        var bestValue = CGFloat.greatestFiniteMagnitude

        for start in 0...maxStart {
            let value = masonryYOrigin(columnBottoms: columnBottoms, startColumn: start, span: span)
            if value < bestValue {
                bestValue = value
                bestColumn = start
            }
        }

        return bestColumn
    }

    private func masonryYOrigin(columnBottoms: [CGFloat], startColumn: Int, span: Int) -> CGFloat {
        let end = min(columnBottoms.count, startColumn + span)
        return columnBottoms[startColumn..<end].max() ?? 0
    }

    private func tileWidth(span: Int, columns: Int, usableWidth: CGFloat) -> CGFloat {
        let columns = max(1, columns)
        let span = max(1, min(span, columns))
        let totalSpacing = CGFloat(columns - 1) * gridSpacing
        let columnWidth = max(0, (usableWidth - totalSpacing) / CGFloat(columns))
        return (columnWidth * CGFloat(span)) + (CGFloat(span - 1) * gridSpacing)
    }

    private func xOrigin(forColumn column: Int, columns: Int, usableWidth: CGFloat) -> CGFloat {
        let unitWidth = tileWidth(span: 1, columns: columns, usableWidth: usableWidth)
        return CGFloat(max(0, column)) * (unitWidth + gridSpacing)
    }

    private func resolvedMasonryHeight(
        for id: String,
        item: HomePinnedItem,
        displaySize: HomeTileDisplaySize
    ) -> CGFloat {
        if let measured = masonryMeasuredHeights[id], measured > 1 {
            return measured
        }
        return estimatedMasonryHeight(for: item, displaySize: displaySize)
    }

    private func estimatedMasonryHeight(
        for item: HomePinnedItem,
        displaySize: HomeTileDisplaySize
    ) -> CGFloat {
        if case .widget(.categoryAvailability, _) = item {
            switch displaySize {
            case .small:
                return 620
            case .wide:
                return 390
            case .wideTall:
                return 620
            }
        }

        switch displaySize {
        case .small:
            return 220
        case .wide:
            return 240
        case .wideTall:
            return 460
        }
    }

    private func masonryHeightReader(id: String) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: HomeMasonryHeightPreferenceKey.self,
                value: [id: proxy.size.height]
            )
        }
    }

    private func effectiveTileDisplaySize(for item: HomePinnedItem, columns: Int) -> HomeTileDisplaySize {
        guard columns >= 3 else { return baseDisplaySize(for: item.tileSize) }
        guard isPhone == false else { return baseDisplaySize(for: item.tileSize) }
        guard voiceOverEnabled == false else { return baseDisplaySize(for: item.tileSize) }
        guard dynamicTypeSize.isAccessibilitySize == false else { return baseDisplaySize(for: item.tileSize) }

        return baseDisplaySize(for: item.tileSize)
    }

    private func baseDisplaySize(for size: HomeTileSize) -> HomeTileDisplaySize {
        switch size {
        case .small:
            return .small
        case .wide:
            return .wide
        }
    }

    // MARK: - Widgets Header

    private var homeActionsToolbarButton: some View {
        Menu {
            Toggle("Hide Future Planned Expenses", isOn: $hideFuturePlannedExpensesInView)
            Toggle(
                "Exclude Future Planned Expenses from Totals",
                isOn: $excludeFuturePlannedExpensesFromCalculationsInView
            )
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("Home Actions")
    }

    private var assistantToolbarButton: some View {
        Button(action: onOpenAssistant) {
            Image(systemName: "figure.wave")
        }
        .accessibilityLabel("Open Assistant")
    }

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

    // MARK: - Pin fixups

    private var cardIDSet: Set<UUID> {
        Set(cards.map(\.id))
    }

    private func prunePinnedCardsIfNeeded() {
        let existingCardIDs = cardIDSet

        let pruned = pinnedItems.filter { item in
            switch item {
            case .widget:
                return true
            case .card(let id, _):
                return existingCardIDs.contains(id)
            }
        }

        guard pruned != pinnedItems else { return }
        pinnedItems = pruned
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

private struct HomeMasonryHeightPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]

    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
