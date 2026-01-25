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

    @AppStorage("home_appliedStartTimestamp")
    private var appliedStartTimestamp: Double = 0

    @AppStorage("home_appliedEndTimestamp")
    private var appliedEndTimestamp: Double = 0

    @State private var draftStartDate: Date = Date()
    @State private var draftEndDate: Date = Date()

    @State private var isEditingWidgets: Bool = false
    @State private var pinnedCardIDs: [UUID] = []

    // ✅ New: ordered widget list
    @State private var pinnedWidgets: [HomeWidgetID] = []

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

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
                            onApply: applyDraftRange
                        )
                        .padding(.top, 8)

                        widgetsHeader

                        VStack(spacing: 12) {
                            let pinnedCards = pinnedCardIDs.compactMap { id in
                                cards.first(where: { $0.id == id })
                            }

                            if pinnedCards.isEmpty {
                                HomeTileContainer(
                                    title: "Card Summary",
                                    subtitle: dateRangeSubtitle,
                                    accent: .primary,
                                    showsChevron: false
                                ) {
                                    Text("Tap Edit to pin cards to Home.")
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            } else {
                                LazyVGrid(columns: homeGridColumns, alignment: .leading, spacing: 12) {

                                    // ✅ Render widgets in persisted order
                                    ForEach(pinnedWidgets) { widget in
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
                                        }
                                    }

                                    // Cards after widgets (like your current layout)
                                    ForEach(pinnedCards) { card in
                                        HomeCardSummaryTile(
                                            workspace: workspace,
                                            card: card,
                                            startDate: appliedStartDate,
                                            endDate: appliedEndDate
                                        )
                                        .accessibilityElement(children: .combine)
                                    }
                                }
                            }
                        }

                        Spacer(minLength: 22)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                    .frame(width: proxy.size.width, alignment: .leading)
                }
            }
        }
        .navigationTitle("Home")
        .sheet(isPresented: $isEditingWidgets) {
            HomeEditPinnedCardsView(
                cards: cards,
                workspaceID: workspace.id,
                pinnedIDs: $pinnedCardIDs,
                pinnedWidgets: $pinnedWidgets
            )
            .onDisappear {
                persistPinnedCards()
                persistPinnedWidgets()
            }
        }
        .onAppear {
            bootstrapDatesIfNeeded()
            loadPinnedCardsIfNeeded()
            loadPinnedWidgetsIfNeeded()
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
            plannedExpenses: plannedExpenses,
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
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

    @ViewBuilder
    private var nextPlannedExpenseWidget: some View {
        if let next = HomeNextPlannedExpenseFinder.nextExpense(
            from: plannedExpenses,
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
        }
    }

    private var categorySpotlightWidget: some View {
        HomeCategorySpotlightTile(
            workspace: workspace,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate,
            topN: 4
        )
    }

    /// Phase 2 validation tile (simple, not final UI)
    @ViewBuilder
    private var categoryAvailabilityWidget: some View {
        HomeCategoryAvailabilityTile(
            workspace: workspace,
            budgets: budgets,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            startDate: appliedStartDate,
            endDate: appliedEndDate
        )
    }

    // MARK: - Layout

    private var homeGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 330), spacing: 12, alignment: .top)]
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

    private var appliedStartDate: Date {
        Date(timeIntervalSince1970: appliedStartTimestamp)
    }

    private var appliedEndDate: Date {
        Date(timeIntervalSince1970: appliedEndTimestamp)
    }

    private var dateRangeSubtitle: String {
        "\(formattedDate(appliedStartDate)) - \(formattedDate(appliedEndDate))"
    }

    private func bootstrapDatesIfNeeded() {
        if appliedStartTimestamp == 0 || appliedEndTimestamp == 0 {
            let calendar = Calendar.current
            let now = Date()
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now

            appliedStartTimestamp = start.timeIntervalSince1970
            appliedEndTimestamp = end.timeIntervalSince1970
        }

        draftStartDate = appliedStartDate
        draftEndDate = appliedEndDate
    }

    private func applyDraftRange() {
        let start = draftStartDate
        var end = draftEndDate

        if end < start {
            end = start
            draftEndDate = start
        }

        appliedStartTimestamp = start.timeIntervalSince1970
        appliedEndTimestamp = end.timeIntervalSince1970
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    // MARK: - Persistence: Cards

    private func loadPinnedCardsIfNeeded() {
        if pinnedCardIDs.isEmpty {
            let store = HomePinnedCardsStore(workspaceID: workspace.id)
            let loaded = store.load()

            if loaded.isEmpty {
                pinnedCardIDs = cards.map { $0.id }
                store.save(pinnedCardIDs)
            } else {
                pinnedCardIDs = loaded
            }
        }
    }

    private func persistPinnedCards() {
        let store = HomePinnedCardsStore(workspaceID: workspace.id)
        store.save(pinnedCardIDs)
    }

    // MARK: - Persistence: Widgets (new)

    private func loadPinnedWidgetsIfNeeded() {
        if pinnedWidgets.isEmpty {
            let store = HomePinnedWidgetsStore(workspaceID: workspace.id)
            pinnedWidgets = store.load()
        }
    }

    private func persistPinnedWidgets() {
        let store = HomePinnedWidgetsStore(workspaceID: workspace.id)
        store.save(pinnedWidgets)
    }
}

#Preview("Home") {
    let container = PreviewSeed.makeContainer()

    PreviewHost(container: container) { ws in
        NavigationStack {
            HomeView(workspace: ws)
        }
    }
}
