//
//  BudgetsView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct BudgetsView: View {

    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCommandHub) private var commandHub

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true
    @AppStorage("sort.budgets.mode") private var sortModeRaw: String = BudgetsListSortMode.dateDesc.rawValue

    @Query private var budgets: [Budget]

    private enum SheetRoute: Identifiable {
        case add
        case edit(Budget)

        var id: String {
            switch self {
            case .add:
                return "add"
            case .edit(let budget):
                return "edit-\(budget.id.uuidString)"
            }
        }
    }

    // MARK: - UI State

    @State private var upcomingExpanded: Bool = true
    @State private var activeExpanded: Bool = true
    @State private var pastExpanded: Bool = false

    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    @State private var sheetRoute: SheetRoute? = nil
    @State private var showingDeleteConfirm: Bool = false
    @State private var pendingDelete: (() -> Void)? = nil

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _budgets = Query(
            filter: #Predicate<Budget> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Budget.startDate, order: .reverse)]
        )
    }

    private var isPhone: Bool {
        #if canImport(UIKit)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var shouldSyncCommandSurface: Bool {
        isPhone == false
    }

    // MARK: - Date Buckets

    private var todayStartOfDay: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private func isActive(_ budget: Budget) -> Bool {
        let t = todayStartOfDay
        return budget.startDate <= t && t <= budget.endDate
    }

    private func isUpcoming(_ budget: Budget) -> Bool {
        let t = todayStartOfDay
        return budget.startDate > t
    }

    private func isPast(_ budget: Budget) -> Bool {
        let t = todayStartOfDay
        return budget.endDate < t
    }

    private var filteredBudgets: [Budget] {
        let query = SearchQueryParser.parse(searchText)
        guard !query.isEmpty else { return budgets }

        return budgets.filter { budget in
            if !SearchMatch.matchesTextTerms(query, in: [budget.name]) { return false }
            if !SearchMatch.matchesDateRange(query, startDate: budget.startDate, endDate: budget.endDate) { return false }
            return true
        }
    }

    private var upcomingBudgets: [Budget] {
        sortBudgets(filteredBudgets.filter { isUpcoming($0) })
    }

    private var activeBudgets: [Budget] {
        sortBudgets(filteredBudgets.filter { isActive($0) })
    }

    private var pastBudgets: [Budget] {
        sortBudgets(filteredBudgets.filter { isPast($0) })
    }

    // MARK: - View

    var body: some View {
        List {
            if budgets.isEmpty {
                ContentUnavailableView(
                    String(localized: "budgets.empty.title", defaultValue: "No Budgets Yet", comment: "Empty state title when no budgets exist."),
                    systemImage: "chart.pie",
                    description: Text(String(localized: "budgets.empty.message", defaultValue: "Create a budget to start planning spending.", comment: "Empty state message when no budgets exist."))
                )
            } else if filteredBudgets.isEmpty {
                ContentUnavailableView(
                    String(localized: "common.noResults", defaultValue: "No Results", comment: "Empty state title for no search results."),
                    systemImage: "magnifyingglass",
                    description: Text(String(localized: "common.tryDifferentSearch", defaultValue: "Try a different search.", comment: "Prompt to try a different search query."))
                )
            } else {

                // Order: Active → Upcoming → Past

                if !activeBudgets.isEmpty {
                    Section {
                        BucketDisclosureRow(
                            title: bucketTitle(
                                key: "budgets.bucket.active",
                                defaultValue: "Active Budgets (%@)",
                                count: activeBudgets.count
                            ),
                            isExpanded: $activeExpanded
                        )

                        if activeExpanded {
                            ForEach(activeBudgets) { budget in
                                budgetRow(budget)
                            }
                        }
                    }
                }

                if !upcomingBudgets.isEmpty {
                    Section {
                        BucketDisclosureRow(
                            title: bucketTitle(
                                key: "budgets.bucket.upcoming",
                                defaultValue: "Upcoming Budgets (%@)",
                                count: upcomingBudgets.count
                            ),
                            isExpanded: $upcomingExpanded
                        )

                        if upcomingExpanded {
                            ForEach(upcomingBudgets) { budget in
                                budgetRow(budget)
                            }
                        }
                    }
                }

                if !pastBudgets.isEmpty {
                    Section {
                        BucketDisclosureRow(
                            title: bucketTitle(
                                key: "budgets.bucket.past",
                                defaultValue: "Past Budgets (%@)",
                                count: pastBudgets.count
                            ),
                            isExpanded: $pastExpanded
                        )

                        if pastExpanded {
                            ForEach(pastBudgets) { budget in
                                budgetRow(budget)
                            }
                        }
                    }
                }
            }
        }
        .postBoardingTip(
            key: "tip.budgets.v1",
            title: String(localized: "app.section.budgets", defaultValue: "Budgets", comment: "Main tab title for the Budgets section."),
            items: [
                PostBoardingTipItem(
                    systemImage: "chart.pie.fill",
                    title: String(localized: "app.section.budgets", defaultValue: "Budgets", comment: "Main tab title for the Budgets section."),
                    detail: String(localized: "budgets.tip.overview.detail", defaultValue: "Create and view your budgets here. Press a budget and you will be taken to its detail view.", comment: "Tip text describing budgets overview.")
                ),
                PostBoardingTipItem(
                    systemImage: "list.triangle",
                    title: String(localized: "budgets.tip.viewSort.title", defaultValue: "View & Sort", comment: "Tip title for viewing and sorting budgets."),
                    detail: String(localized: "budgets.tip.viewSort.detail", defaultValue: "Active • happening now\nUpcoming • starts later\nPast • ended", comment: "Tip detail explaining budget buckets.")
                ),
                PostBoardingTipItem(
                    systemImage: "magnifyingglass",
                    title: String(localized: "common.search", defaultValue: "Search", comment: "Label for search actions."),
                    detail: String(localized: "budgets.tip.search.detail", defaultValue: "Use the search bar to search budgets by title or date.", comment: "Tip detail for searching budgets.")
                )
            ]
        )
        .navigationTitle(String(localized: "app.section.budgets", defaultValue: "Budgets", comment: "Main tab title for the Budgets section."))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: String(localized: "common.search", defaultValue: "Search", comment: "Label for search actions.")
        )
        .searchFocused($searchFocused)
        .toolbar {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                ToolbarItemGroup(placement: .primaryAction) {
                    sortToolbarButton
                }

                ToolbarSpacer(.flexible, placement: .primaryAction)

                ToolbarItemGroup(placement: .primaryAction) {
                    addToolbarButton
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    addToolbarButton
                }

                ToolbarItem(placement: .primaryAction) {
                    sortToolbarButton
                }
            }
        }
        .sheet(item: $sheetRoute) { route in
            switch route {
            case .add:
                NavigationStack {
                    AddBudgetView(workspace: workspace)
                }
            case .edit(let budget):
                NavigationStack {
                    EditBudgetView(workspace: workspace, budget: budget)
                }
            }
        }
        .alert("Delete Budget?", isPresented: $showingDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingDelete?()
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        }
        .onAppear {
            if shouldSyncCommandSurface {
                commandHub.activate(.budgets)
            }
        }
        .onDisappear {
            if shouldSyncCommandSurface {
                commandHub.deactivate(.budgets)
            }
        }
        .onReceive(commandHub.$sequence) { _ in
            guard commandHub.surface == .budgets else { return }
            handleCommand(commandHub.latestCommandID)
        }
    }

    private var sortMode: BudgetsListSortMode {
        BudgetsListSortMode(rawValue: sortModeRaw) ?? .dateDesc
    }

    private func setSortMode(_ mode: BudgetsListSortMode) {
        sortModeRaw = mode.rawValue
    }

    @ViewBuilder
    private var addToolbarButton: some View {
        Button {
            sheetRoute = .add
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel(String(localized: "budgets.add", defaultValue: "Add Budget", comment: "Accessibility label for adding a budget."))
    }

    @ViewBuilder
    private var sortToolbarButton: some View {
        Menu {
            sortMenuButton(title: "A–Z", mode: .az)
            sortMenuButton(title: "Z–A", mode: .za)
            sortMenuButton(title: "Date ↑", mode: .dateAsc)
            sortMenuButton(title: "Date ↓", mode: .dateDesc)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel(String(localized: "common.sort", defaultValue: "Sort", comment: "Accessibility label for sort actions."))
    }

    private func sortMenuButton(title: String, mode: BudgetsListSortMode) -> some View {
        Button {
            setSortMode(mode)
        } label: {
            HStack {
                Text(title)
                if sortMode == mode {
                    Spacer()
                    Image(systemName: "checkmark")
                }
            }
        }
    }

    private func sortBudgets(_ source: [Budget]) -> [Budget] {
        switch sortMode {
        case .az:
            return source.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        case .za:
            return source.sorted { lhs, rhs in
                lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
            }
        case .dateAsc:
            return source.sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.startDate < rhs.startDate
            }
        case .dateDesc:
            return source.sorted { lhs, rhs in
                if lhs.startDate == rhs.startDate {
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
                return lhs.startDate > rhs.startDate
            }
        }
    }

    private func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }

    private func bucketTitle(key: String, defaultValue: String, count: Int) -> String {
        let format = Bundle.main.localizedString(forKey: key, value: defaultValue, table: nil)
        return String(format: format, locale: Locale.current, localizedInt(count))
    }

    private func openNewBudget() {
        sheetRoute = .add
    }

    private func handleCommand(_ commandID: String) {
        if commandID == AppCommandID.Budgets.newBudget {
            openNewBudget()
            return
        }

        switch commandID {
        case AppCommandID.Budgets.sortAZ:
            setSortMode(.az)
        case AppCommandID.Budgets.sortZA:
            setSortMode(.za)
        case AppCommandID.Budgets.sortDateAsc:
            setSortMode(.dateAsc)
        case AppCommandID.Budgets.sortDateDesc:
            setSortMode(.dateDesc)
        default:
            break
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func budgetRow(_ budget: Budget) -> some View {
        NavigationLink {
            BudgetDetailView(workspace: workspace, budget: budget)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(budget.name)
                    .font(.headline)

                Text(formattedDateRange(start: budget.startDate, end: budget.endDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                sheetRoute = .edit(budget)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Color("AccentColor"))
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteBudgetWithOptionalConfirm(budget)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .tint(Color("OffshoreDepth"))
        }
    }

    private func formattedDateRange(start: Date, end: Date) -> String {
        let formatter = DateIntervalFormatter()
        formatter.calendar = .autoupdatingCurrent
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: start, to: end)
    }

    private func deleteBudgetWithOptionalConfirm(_ budget: Budget) {
        if confirmBeforeDeleting {
            pendingDelete = {
                deleteBudgetAndGeneratedPlannedExpenses(budget)
            }
            showingDeleteConfirm = true
        } else {
            deleteBudgetAndGeneratedPlannedExpenses(budget)
        }
    }

    private func deleteBudgetAndGeneratedPlannedExpenses(_ budget: Budget) {
        let budgetID: UUID? = budget.id
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID
            }
        )

        if let expenses = try? modelContext.fetch(descriptor) {
            for expense in expenses {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        }

        modelContext.delete(budget)
    }
}

private enum BudgetsListSortMode: String {
    case az
    case za
    case dateAsc
    case dateDesc
}

private struct BucketDisclosureRow: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Text(title)
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .animation(.easeInOut(duration: 0.18), value: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

#Preview("Budgets") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            BudgetsView(workspace: ws)
        }
    }
}
