//
//  HomeView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData
import Foundation

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
    @AppStorage("general_hideFuturePlannedExpenses")
    private var hideFuturePlannedExpensesDefault: Bool = false
    @AppStorage("general_excludeFuturePlannedExpensesFromCalculations")
    private var excludeFuturePlannedExpensesFromCalculationsDefault: Bool = false
    @AppStorage("general_hideFutureVariableExpenses")
    private var hideFutureVariableExpensesDefault: Bool = false
    @AppStorage("general_excludeFutureVariableExpensesFromCalculations")
    private var excludeFutureVariableExpensesFromCalculationsDefault: Bool = false

    @State private var draftStartDate: Date
    @State private var draftEndDate: Date
    @State private var hideFuturePlannedExpensesInView: Bool
    @State private var excludeFuturePlannedExpensesFromCalculationsInView: Bool
    @State private var hideFutureVariableExpensesInView: Bool
    @State private var excludeFutureVariableExpensesFromCalculationsInView: Bool

    @State private var isEditingWidgets: Bool = false

    @State private var pinnedItems: [HomePinnedItem]
    @State private var dashboardSnapshot: HomeDashboardSnapshot = .empty
    @State private var hasLoadedDashboardSnapshot: Bool = false
    @State private var needsDashboardSnapshotRefresh: Bool = false
    @State private var dashboardSnapshotRefreshTask: Task<Void, Never>? = nil
    @State private var postSettleHousekeepingTask: Task<Void, Never>? = nil
    @State private var activationEnrichmentTask: Task<Void, Never>? = nil
    @State private var masonryMeasuredHeights: [String: CGFloat] = [:]
    @State private var lastMeasuredUsableWidth: CGFloat = 0

    @State private var isShowingWhatIfPlanner: Bool = false
    @State private var whatIfInitialScenarioID: UUID? = nil
    @State private var isShowingAssistantPanel: Bool = false

    // MARK: - Data Fixups

    private struct HomeDashboardSnapshot {
        let plannedExpensesForHome: [PlannedExpense]
        let calculationPlannedExpensesForHome: [PlannedExpense]
        let calculationVariableExpensesForHome: [VariableExpense]
        let nextPlannedExpense: PlannedExpense?

        static let empty = HomeDashboardSnapshot(
            plannedExpensesForHome: [],
            calculationPlannedExpensesForHome: [],
            calculationVariableExpensesForHome: [],
            nextPlannedExpense: nil
        )
    }

    private func computePlannedExpensesForHome() -> [PlannedExpense] {
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

    private var plannedExpensesForHome: [PlannedExpense] {
        if hasLoadedDashboardSnapshot {
            return dashboardSnapshot.plannedExpensesForHome
        }
        return computePlannedExpensesForHome()
    }

    private var calculationPlannedExpensesForHome: [PlannedExpense] {
        if hasLoadedDashboardSnapshot {
            return dashboardSnapshot.calculationPlannedExpensesForHome
        }
        return PlannedExpenseFuturePolicy.filteredForCalculations(
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

    private var calculationVariableExpensesForHome: [VariableExpense] {
        if hasLoadedDashboardSnapshot {
            return dashboardSnapshot.calculationVariableExpensesForHome
        }
        return VariableExpenseFuturePolicy.filteredForCalculations(
            variableExpenses,
            excludeFuture: excludeFutureVariableExpensesFromCalculationsInView
        )
    }

    private var visibleVariableExpensesForHome: [VariableExpense] {
        VariableExpenseFuturePolicy.filteredForVisibility(
            variableExpenses,
            hideFuture: hideFutureVariableExpensesInView
        )
    }

    // MARK: - A11y + Layout Environment

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.homeAssistantToolbarContext) private var assistantToolbarContext
    @Environment(\.appTabActivationContext) private var tabActivationContext
    @Environment(\.appCommandHub) private var commandHub
    @Environment(\.modelContext) private var modelContext
    @Environment(DetailViewSnapshotCache.self) private var detailSnapshotCache

    private var isPhone: Bool {
        #if canImport(UIKit)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
    }

    private var shouldSyncCommandSurface: Bool {
        isPhone == false
    }

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id
        let defaults = UserDefaults.standard
        let defaultBudgetingPeriodRaw = defaults.string(forKey: "general_defaultBudgetingPeriod")
            ?? BudgetingPeriod.monthly.rawValue
        let initialPinnedItems = HomeViewBootstrap.initialPinnedItems(
            workspaceID: workspaceID,
            fallbackCardIDs: (workspace.cards ?? []).map(\.id),
            defaults: defaults
        )
        let appliedRangeSeed = HomeViewBootstrap.initialAppliedRangeSeed(
            workspaceID: workspaceID,
            defaultBudgetingPeriodRaw: defaultBudgetingPeriodRaw,
            defaults: defaults
        )

        _appliedStartTimestamp = AppStorage(
            wrappedValue: appliedRangeSeed.start.timeIntervalSince1970,
            Self.appliedStartKey(workspaceID: workspaceID)
        )
        _appliedEndTimestamp = AppStorage(
            wrappedValue: appliedRangeSeed.end.timeIntervalSince1970,
            Self.appliedEndKey(workspaceID: workspaceID)
        )
        _lastSyncedDefaultBudgetingPeriodRaw = AppStorage(
            wrappedValue: appliedRangeSeed.lastSyncedDefaultBudgetingPeriodRaw,
            Self.lastSyncedDefaultBudgetingPeriodKey(workspaceID: workspaceID)
        )
        _draftStartDate = State(initialValue: appliedRangeSeed.start)
        _draftEndDate = State(initialValue: appliedRangeSeed.end)
        _hideFuturePlannedExpensesInView = State(
            initialValue: defaults.bool(forKey: "general_hideFuturePlannedExpenses")
        )
        _excludeFuturePlannedExpensesFromCalculationsInView = State(
            initialValue: defaults.bool(forKey: "general_excludeFuturePlannedExpensesFromCalculations")
        )
        _hideFutureVariableExpensesInView = State(
            initialValue: defaults.bool(forKey: "general_hideFutureVariableExpenses")
        )
        _excludeFutureVariableExpensesFromCalculationsInView = State(
            initialValue: defaults.bool(forKey: "general_excludeFutureVariableExpensesFromCalculations")
        )
        _pinnedItems = State(initialValue: initialPinnedItems)

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
                                    title: String(localized: "app.section.home", defaultValue: "Home", comment: "Main tab title for the Home section."),
                                    subtitle: dateRangeSubtitle,
                                    accent: .primary,
                                    showsChevron: false
                                ) {
                                    Text(String(localized: "home.emptyPinned.message", defaultValue: "Tap Edit to pin widgets and cards to Home.", comment: "Message when no home items are pinned."))
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
                .onAppear {
                    updateMeasuredUsableWidth(totalWidth: proxy.size.width)
                }
                .onChange(of: proxy.size.width) { _, newWidth in
                    updateMeasuredUsableWidth(totalWidth: newWidth)
                }
            }
        }
        .navigationDestination(isPresented: $isShowingWhatIfPlanner) {
            WhatIfScenarioPlannerView(
                workspace: workspace,
                budgets: budgets,
                categories: categories,
                incomes: incomes,
                plannedExpenses: calculationPlannedExpensesForHome,
                variableExpenses: calculationVariableExpensesForHome,
                startDate: appliedStartDate,
                endDate: appliedEndDate,
                initialScenarioID: whatIfInitialScenarioID
            )
        }
        .fullScreenCover(isPresented: $isShowingAssistantPanel, onDismiss: dismissAssistantPanel) {
            HomeAssistantPanelView(
                workspace: workspace,
                onDismiss: dismissAssistantPanel,
                shouldUseLargeMinimumSize: false
            )
        }
        .postBoardingTip(
            key: "tip.home.v1",
            title: String(localized: "app.section.home", defaultValue: "Home", comment: "Main tab title for the Home section."),
            items: [
                PostBoardingTipItem(
                    systemImage: "house.fill",
                    title: String(localized: "home.tip.dashboard.title", defaultValue: "Dashboard", comment: "Home tip title for dashboard overview."),
                    detail: String(localized: "home.tip.dashboard.detail", defaultValue: "Home is your landing page. This is the first screen you see when opening the app.", comment: "Home tip detail for dashboard overview.")
                ),
                PostBoardingTipItem(
                    systemImage: "rectangle.grid.2x2",
                    title: String(localized: "home.widgets.header", defaultValue: "Widgets", comment: "Header title for home widgets section."),
                    detail: String(localized: "home.tip.widgets.detail", defaultValue: "Tap any widget to open deeper metrics. Use Edit to pin, reorder, or remove widgets.", comment: "Home tip detail for widgets usage.")
                ),
                PostBoardingTipItem(
                    systemImage: "calendar",
                    title: String(localized: "home.tip.dateRange.title", defaultValue: "Date Range", comment: "Home tip title for date range controls."),
                    detail: String(localized: "home.tip.dateRange.detail", defaultValue: "Use the date controls at the top to change the time period shown across all widgets.", comment: "Home tip detail for date range controls.")
                )
            ]
        )
        .navigationTitle(String(localized: "app.section.home", defaultValue: "Home", comment: "Main tab title for the Home section."))
        .toolbar {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    homeActionsToolbarButton
                }

                if showsAssistantToolbarButton {
                    ToolbarSpacer(.flexible, placement: .primaryAction)

                    ToolbarItemGroup(placement: .primaryAction) {
                        assistantToolbarButtoniOS26
                    }
                }
            } else {
                ToolbarItemGroup(placement: .primaryAction) {
                    homeActionsToolbarButton
                }

                if showsAssistantToolbarButton {
                    ToolbarItem(placement: .primaryAction) {
                        assistantToolbarButtonLegacy
                    }
                }
            }
        }
        .sheet(isPresented: $isEditingWidgets) {
            HomeEditPinnedCardsView(
                cards: cards,
                workspaceID: workspace.id,
                showsTileSizePicker: showsTileSizePicker,
                pinnedItems: $pinnedItems
            )
            .onDisappear {
                persistPinnedItems()
            }
        }
        .onAppear {
            if shouldSyncCommandSurface {
                commandHub.activate(.home)
            }
            bootstrapAppliedDatesIfNeeded()
            applyDefaultBudgetingPeriodIfSettingsChanged()
            syncDraftToAppliedIfNeeded()
            if hasLoadedDashboardSnapshot == false {
                hydrateDashboardSnapshotIfAvailable()
                if hasLoadedDashboardSnapshot == false {
                    rebuildDashboardSnapshot(reason: "onAppearInitial")
                    hasLoadedDashboardSnapshot = true
                }
                needsDashboardSnapshotRefresh = false
            } else if needsDashboardSnapshotRefresh {
                scheduleDashboardSnapshotRefresh(reason: "onAppearRefresh")
            }
            schedulePostSettleHousekeeping(reason: "onAppear")
            scheduleActivationEnrichment(reason: "onAppear")
        }
        .onDisappear {
            dismissAssistantPanel()
            cancelDashboardSnapshotRefresh(reason: "onDisappear")
            cancelPostSettleHousekeeping()
            cancelActivationEnrichment()
            if shouldSyncCommandSurface {
                commandHub.deactivate(.home)
            }
        }
        .onReceive(commandHub.$sequence) { _ in
            guard commandHub.surface == .home else { return }
            handleCommand(commandHub.latestCommandID)
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
            syncDraftToAppliedIfNeeded()
        }
        .onChange(of: hideFuturePlannedExpensesDefault) { _, newValue in
            guard hideFuturePlannedExpensesInView != newValue else { return }
            hideFuturePlannedExpensesInView = newValue
        }
        .onChange(of: excludeFuturePlannedExpensesFromCalculationsDefault) { _, newValue in
            guard excludeFuturePlannedExpensesFromCalculationsInView != newValue else { return }
            excludeFuturePlannedExpensesFromCalculationsInView = newValue
        }
        .onChange(of: hideFutureVariableExpensesDefault) { _, newValue in
            guard hideFutureVariableExpensesInView != newValue else { return }
            hideFutureVariableExpensesInView = newValue
        }
        .onChange(of: excludeFutureVariableExpensesFromCalculationsDefault) { _, newValue in
            guard excludeFutureVariableExpensesFromCalculationsInView != newValue else { return }
            excludeFutureVariableExpensesFromCalculationsInView = newValue
        }
        .onChange(of: tabActivationContext) { _, newValue in
            guard newValue.sectionRawValue == AppSection.home.rawValue else { return }
            if newValue.phase == .active, needsDashboardSnapshotRefresh {
                scheduleDashboardSnapshotRefresh(reason: "tabActivationSettled")
                schedulePostSettleHousekeeping(reason: "tabActivationSettled")
                scheduleActivationEnrichment(reason: "tabActivationSettled")
            } else if newValue.phase != .active {
                cancelDashboardSnapshotRefresh(reason: "tabPhaseChanged")
                cancelPostSettleHousekeeping()
                cancelActivationEnrichment()
            }
        }
        .onChange(of: dashboardSnapshotInputs) { _, _ in
            if tabActivationContext.phase == .active {
                scheduleDashboardSnapshotRefresh(reason: "inputsChanged")
            } else {
                needsDashboardSnapshotRefresh = true
            }
        }
    }

    // MARK: - Navigation

    private func openWhatIfPlanner(_ initialScenarioID: UUID?) {
        whatIfInitialScenarioID = initialScenarioID
        isShowingWhatIfPlanner = true
    }

    private func presentAssistantPanel() {
        if isPhone {
            isShowingAssistantPanel = true
        } else {
            assistantToolbarContext.openAssistant()
        }
    }

    private func dismissAssistantPanel() {
        isShowingAssistantPanel = false
    }

    private func handleCommand(_ commandID: String) {
        switch commandID {
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
                    excludeFuturePlannedExpensesFromCalculationsInView: excludeFuturePlannedExpensesFromCalculationsInView,
                    excludeFutureVariableExpensesFromCalculationsInView: excludeFutureVariableExpensesFromCalculationsInView
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
        let usableWidth = effectivePinnedLayoutWidth(
            defaultUsableWidth: max(0, availableWidth - (contentHorizontalPadding * 2))
        )
        if shouldUseMasonry(for: usableWidth) {
            masonryPinnedItemsLayout(usableWidth: usableWidth)
        } else {
            stackedPinnedItemsLayout(usableWidth: usableWidth)
        }
    }

    private func stackedPinnedItemsLayout(usableWidth: CGFloat) -> some View {
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

    @ViewBuilder
    private func masonryPinnedItemsLayout(usableWidth: CGFloat) -> some View {
        let columns = masonryColumnCount(for: usableWidth)
        if columns < 2 {
            stackedPinnedItemsLayout(usableWidth: usableWidth)
        } else {
            let items = buildPinnedLayoutItems(columns: columns)
            let placements = masonryPlacements(
                for: items,
                columns: columns,
                usableWidth: usableWidth
            )
            let totalHeight = max(0, (placements.map(\.maxY).max() ?? 0))
            let highestPriority = Double(max(0, items.count))

            ZStack(alignment: .topLeading) {
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
                guard tabActivationContext.phase == .active else { return }
                let filteredHeights = heights.filter { $0.value > 1 }
                guard filteredHeights.isEmpty == false else { return }

                DispatchQueue.main.async {
                    var updated = masonryMeasuredHeights
                    var changed = false

                    for (id, value) in filteredHeights {
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
            variableExpenses: calculationVariableExpensesForHome,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

    private var whatIfWidget: some View {
        HomeWhatIfTile(
            workspace: workspace,
            budgets: budgets,
            categories: categories,
            incomes: incomes,
            plannedExpenses: calculationPlannedExpensesForHome,
            variableExpenses: calculationVariableExpensesForHome,
            startDate: appliedStartDate,
            endDate: appliedEndDate,
            onOpenPlanner: openWhatIfPlanner
        )
    }

    @ViewBuilder
    private var nextPlannedExpenseWidget: some View {
        if let next = nextPlannedExpenseForHome {
            HomeNextPlannedExpenseTile(
                workspace: workspace,
                expense: next,
                startDate: appliedStartDate,
                endDate: appliedEndDate
            )
        } else {
            HomeTileContainer(
                title: String(localized: "Next Planned Expense", defaultValue: "Next Planned Expense", comment: "Home tile title for the next planned expense widget."),
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
            variableExpenses: calculationVariableExpensesForHome,
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
            variableExpenses: calculationVariableExpensesForHome,
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
            variableExpenses: calculationVariableExpensesForHome,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

    // MARK: - Layout

    private var contentHorizontalPadding: CGFloat { 16 }

    private var gridSpacing: CGFloat { 12 }

    private func masonryColumnCount(for usableWidth: CGFloat) -> Int {
        HomeLayoutCapabilities.masonryColumnCount(
            usableWidth: usableWidth,
            dynamicTypeSize: dynamicTypeSize,
            gridSpacing: gridSpacing
        )
    }

    private func shouldUseMasonry(for usableWidth: CGFloat) -> Bool {
        HomeLayoutCapabilities.supportsMultiColumnLayout(
            usableWidth: usableWidth,
            isPhone: isPhone,
            voiceOverEnabled: voiceOverEnabled,
            dynamicTypeSize: dynamicTypeSize,
            gridSpacing: gridSpacing
        )
    }

    private var showsTileSizePicker: Bool {
        HomeLayoutCapabilities.supportsTileSizeControl(
            usableWidth: lastMeasuredUsableWidth,
            isPhone: isPhone,
            voiceOverEnabled: voiceOverEnabled,
            dynamicTypeSize: dynamicTypeSize,
            gridSpacing: gridSpacing
        )
    }

    private func updateMeasuredUsableWidth(totalWidth: CGFloat) {
        let next = max(0, totalWidth - (contentHorizontalPadding * 2))
        if tabActivationContext.phase != .active, lastMeasuredUsableWidth > 0 {
            return
        }
        guard abs(next - lastMeasuredUsableWidth) > 0.5 else { return }
        lastMeasuredUsableWidth = next
    }

    private func effectivePinnedLayoutWidth(defaultUsableWidth: CGFloat) -> CGFloat {
        if tabActivationContext.phase != .active, lastMeasuredUsableWidth > 0 {
            return lastMeasuredUsableWidth
        }
        return defaultUsableWidth
    }

    private struct DashboardSnapshotInputs: Equatable {
        let appliedStartTimestamp: Double
        let appliedEndTimestamp: Double
        let excludeFuturePlannedExpensesFromCalculationsInView: Bool
        let excludeFutureVariableExpensesFromCalculationsInView: Bool
        let budgetsSignature: Int
        let plannedExpensesSignature: Int
        let variableExpensesSignature: Int
    }

    private var dashboardSnapshotInputs: DashboardSnapshotInputs {
        DashboardSnapshotInputs(
            appliedStartTimestamp: appliedStartTimestamp,
            appliedEndTimestamp: appliedEndTimestamp,
            excludeFuturePlannedExpensesFromCalculationsInView: excludeFuturePlannedExpensesFromCalculationsInView,
            excludeFutureVariableExpensesFromCalculationsInView: excludeFutureVariableExpensesFromCalculationsInView,
            budgetsSignature: SnapshotContentSignature.budgets(budgets),
            plannedExpensesSignature: SnapshotContentSignature.plannedExpenses(plannedExpenses),
            variableExpensesSignature: SnapshotContentSignature.variableExpenses(variableExpenses)
        )
    }

    private var nextPlannedExpenseForHome: PlannedExpense? {
        if hasLoadedDashboardSnapshot {
            return dashboardSnapshot.nextPlannedExpense
        }

        return HomeNextPlannedExpenseFinder.nextExpense(
            from: plannedExpensesForHome,
            in: appliedStartDate,
            to: appliedEndDate
        )
    }

    private var dashboardSnapshotCacheKey: String {
        [
            "home-dashboard",
            workspace.id.uuidString,
            String(Int64(appliedStartTimestamp)),
            String(Int64(appliedEndTimestamp)),
            excludeFuturePlannedExpensesFromCalculationsInView ? "1" : "0",
            excludeFutureVariableExpensesFromCalculationsInView ? "1" : "0",
            String(SnapshotContentSignature.budgets(budgets)),
            String(SnapshotContentSignature.plannedExpenses(plannedExpenses)),
            String(SnapshotContentSignature.variableExpenses(variableExpenses))
        ].joined(separator: "|")
    }

    private func buildDashboardSnapshot() -> HomeDashboardSnapshot {
        RootActivationDiagnostics.measure(
            "homeRootDerived",
            metadata: [
                "phase": tabActivationContext.phase.rawValue,
                "token": String(tabActivationContext.token)
            ]
        ) {
            let plannedExpensesForHome = computePlannedExpensesForHome()
            let calculationPlannedExpensesForHome = PlannedExpenseFuturePolicy.filteredForCalculations(
                plannedExpensesForHome,
                excludeFuture: excludeFuturePlannedExpensesFromCalculationsInView
            )
            let calculationVariableExpensesForHome = VariableExpenseFuturePolicy.filteredForCalculations(
                variableExpenses,
                excludeFuture: excludeFutureVariableExpensesFromCalculationsInView
            )
            let nextPlannedExpense = HomeNextPlannedExpenseFinder.nextExpense(
                from: plannedExpensesForHome,
                in: appliedStartDate,
                to: appliedEndDate
            )

            return HomeDashboardSnapshot(
                plannedExpensesForHome: plannedExpensesForHome,
                calculationPlannedExpensesForHome: calculationPlannedExpensesForHome,
                calculationVariableExpensesForHome: calculationVariableExpensesForHome,
                nextPlannedExpense: nextPlannedExpense
            )
        }
    }

    private func rebuildDashboardSnapshot(reason: String) {
        let start = DispatchTime.now().uptimeNanoseconds
        dashboardSnapshot = buildDashboardSnapshot()
        detailSnapshotCache.store(dashboardSnapshot, for: dashboardSnapshotCacheKey)
        let elapsedMillis = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        TabFlickerDiagnostics.markEvent(
            "homeDashboardSnapshotFinished",
            metadata: [
                "reason": reason,
                "elapsedMs": String(format: "%.1f", elapsedMillis)
            ]
        )
    }

    private func hydrateDashboardSnapshotIfAvailable() {
        guard let cached: HomeDashboardSnapshot = detailSnapshotCache.snapshot(for: dashboardSnapshotCacheKey) else {
            return
        }

        dashboardSnapshot = cached
        hasLoadedDashboardSnapshot = true
        TabFlickerDiagnostics.markEvent("homeDashboardSnapshotHydrated")
    }

    private func scheduleDashboardSnapshotRefresh(reason: String) {
        cancelDashboardSnapshotRefresh(reason: "reschedule")
        let activationToken = tabActivationContext.token
        let activationPhase = tabActivationContext.phase
        TabFlickerDiagnostics.markEvent(
            "homeDashboardSnapshotScheduled",
            metadata: [
                "reason": reason,
                "phase": activationPhase.rawValue,
                "token": String(activationToken)
            ]
        )

        if activationPhase == .active {
            rebuildDashboardSnapshot(reason: reason)
            hasLoadedDashboardSnapshot = true
            needsDashboardSnapshotRefresh = false
            return
        }

        needsDashboardSnapshotRefresh = true
        dashboardSnapshotRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                guard tabActivationContext.sectionRawValue == AppSection.home.rawValue,
                      tabActivationContext.phase == .active,
                      tabActivationContext.token == activationToken else {
                    TabFlickerDiagnostics.markEvent(
                        "homeDashboardSnapshotCancelled",
                        metadata: [
                            "reason": reason,
                            "cancel": "activationChanged"
                        ]
                    )
                    return
                }

                rebuildDashboardSnapshot(reason: reason)
                hasLoadedDashboardSnapshot = true
                needsDashboardSnapshotRefresh = false
            }
        }
    }

    private func cancelDashboardSnapshotRefresh(reason: String) {
        guard dashboardSnapshotRefreshTask != nil else { return }
        dashboardSnapshotRefreshTask?.cancel()
        dashboardSnapshotRefreshTask = nil
        TabFlickerDiagnostics.markEvent(
            "homeDashboardSnapshotCancelled",
            metadata: ["reason": reason]
        )
    }

    private func schedulePostSettleHousekeeping(reason: String) {
        cancelPostSettleHousekeeping()
        let activationToken = tabActivationContext.token

        postSettleHousekeepingTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                guard tabActivationContext.sectionRawValue == AppSection.home.rawValue,
                      tabActivationContext.phase == .active,
                      tabActivationContext.token == activationToken else {
                    return
                }

                persistPinnedItemsMigrationIfNeeded()
                prunePinnedCardsIfNeeded()
                TabFlickerDiagnostics.markEvent(
                    "homePostSettleHousekeepingFinished",
                    metadata: ["reason": reason]
                )
            }
        }
    }

    private func cancelPostSettleHousekeeping() {
        postSettleHousekeepingTask?.cancel()
        postSettleHousekeepingTask = nil
    }

    private func scheduleActivationEnrichment(reason: String) {
        cancelActivationEnrichment()
        let activationToken = tabActivationContext.token

        activationEnrichmentTask = Task {
            try? await Task.sleep(nanoseconds: 170_000_000)
            guard Task.isCancelled == false else { return }

            await MainActor.run {
                guard tabActivationContext.sectionRawValue == AppSection.home.rawValue,
                      tabActivationContext.phase == .active,
                      tabActivationContext.token == activationToken else {
                    return
                }

                if needsDashboardSnapshotRefresh {
                    scheduleDashboardSnapshotRefresh(reason: "postSettleEnrichment")
                }

                TabFlickerDiagnostics.markEvent(
                    "homeActivationEnrichmentFinished",
                    metadata: ["reason": reason]
                )
            }
        }
    }

    private func cancelActivationEnrichment() {
        activationEnrichmentTask?.cancel()
        activationEnrichmentTask = nil
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
            Menu {
                Toggle(String(localized: "expenseDisplay.hideFuturePlanned", defaultValue: "Hide Future Planned Expenses", comment: "Toggle label to hide future planned expenses."), isOn: $hideFuturePlannedExpensesInView)
                Toggle(
                    String(localized: "expenseDisplay.excludeFuturePlanned", defaultValue: "Exclude Future Planned Expenses from Totals", comment: "Toggle label to exclude future planned expenses from totals."),
                    isOn: $excludeFuturePlannedExpensesFromCalculationsInView
                )
            } label: {
                if #available(iOS 26.0, *) {
                    Label(String(localized: "expenseDisplay.planned.title", defaultValue: "Planned Expense Display", comment: "Menu label for planned expense display options."), systemImage: "calendar.badge")
                } else {
                    Label(String(localized: "expenseDisplay.planned.title", defaultValue: "Planned Expense Display", comment: "Menu label for planned expense display options."), systemImage: "calendar.badge.clock")
                }
            }

            Menu {
                Toggle(String(localized: "expenseDisplay.hideFutureVariable", defaultValue: "Hide Future Variable Expenses", comment: "Toggle label to hide future variable expenses."), isOn: $hideFutureVariableExpensesInView)
                Toggle(
                    String(localized: "expenseDisplay.excludeFutureVariable", defaultValue: "Exclude Future Variable Expenses from Totals", comment: "Toggle label to exclude future variable expenses from totals."),
                    isOn: $excludeFutureVariableExpensesFromCalculationsInView
                )
            } label: {
                Label(String(localized: "expenseDisplay.variable.title", defaultValue: "Variable Expense Display", comment: "Menu label for variable expense display options."), systemImage: "chart.xyaxis.line")
            }
        } label: {
            Image(systemName: "eye")
        }
        .accessibilityLabel(String(localized: "home.actions", defaultValue: "Home Actions", comment: "Accessibility label for home actions menu."))
    }

    private var showsAssistantToolbarButton: Bool {
        if isPhone {
            return true
        }

        return assistantToolbarContext.isToolbarButtonVisible
    }

    @available(iOS 26.0, macCatalyst 26.0, *)
    private var assistantToolbarButtoniOS26: some View {
        Button(action: presentAssistantPanel) {
            Image(systemName: "figure.wave")
        }
        .buttonStyle(.glassProminent)
        .accessibilityLabel(String(localized: "assistant.open", defaultValue: "Open Assistant", comment: "Accessibility label for opening assistant."))
    }

    private var assistantToolbarButtonLegacy: some View {
        Button(action: presentAssistantPanel) {
            Image(systemName: "figure.wave")
        }
        .buttonStyle(.borderedProminent)
        .tint(Color("AccentColor"))
        .accessibilityLabel(String(localized: "assistant.open", defaultValue: "Open Assistant", comment: "Accessibility label for opening assistant."))
    }

    private var widgetsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(localized: "home.widgets.header", defaultValue: "Widgets", comment: "Header title for home widgets section."))
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button {
                isEditingWidgets = true
            } label: {
                Text(String(localized: "common.edit", defaultValue: "Edit", comment: "Edit action label."))
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

    private func syncDraftToAppliedIfNeeded() {
        guard draftStartDate != appliedStartDate || draftEndDate != appliedEndDate else { return }
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
        AppDateFormat.abbreviatedDate(date)
    }

    // MARK: - Persistence: Unified pins + Migration

    private func persistPinnedItems() {
        let store = HomePinnedItemsStore(workspaceID: workspace.id)
        store.save(pinnedItems)
    }

    private func persistPinnedItemsMigrationIfNeeded() {
        let store = HomePinnedItemsStore(workspaceID: workspace.id)
        guard store.load().isEmpty else { return }
        guard pinnedItems.isEmpty == false else { return }
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

// MARK: - Layout Capabilities

enum HomeLayoutCapabilities {

    static func masonryColumnCount(
        usableWidth: CGFloat,
        dynamicTypeSize: DynamicTypeSize,
        gridSpacing: CGFloat
    ) -> Int {
        let minTileWidth: CGFloat = (dynamicTypeSize >= .xxLarge) ? 420 : 330
        let fit = Int((usableWidth + gridSpacing) / (minTileWidth + gridSpacing))
        return max(1, min(fit, 3))
    }

    static func supportsMultiColumnLayout(
        usableWidth: CGFloat,
        isPhone: Bool,
        voiceOverEnabled: Bool,
        dynamicTypeSize: DynamicTypeSize,
        gridSpacing: CGFloat
    ) -> Bool {
        guard isPhone == false else { return false }
        guard voiceOverEnabled == false else { return false }
        guard dynamicTypeSize.isAccessibilitySize == false else { return false }
        return masonryColumnCount(
            usableWidth: usableWidth,
            dynamicTypeSize: dynamicTypeSize,
            gridSpacing: gridSpacing
        ) >= 2
    }

    static func supportsTileSizeControl(
        usableWidth: CGFloat,
        isPhone: Bool,
        voiceOverEnabled: Bool,
        dynamicTypeSize: DynamicTypeSize,
        gridSpacing: CGFloat
    ) -> Bool {
        supportsMultiColumnLayout(
            usableWidth: usableWidth,
            isPhone: isPhone,
            voiceOverEnabled: voiceOverEnabled,
            dynamicTypeSize: dynamicTypeSize,
            gridSpacing: gridSpacing
        )
    }
}
