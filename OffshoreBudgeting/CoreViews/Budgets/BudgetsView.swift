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

    @Query private var budgets: [Budget]

    // MARK: - UI State

    @State private var upcomingExpanded: Bool = true
    @State private var activeExpanded: Bool = true
    @State private var pastExpanded: Bool = false

    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

    @State private var showingAddBudget: Bool = false

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _budgets = Query(
            filter: #Predicate<Budget> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Budget.startDate, order: .reverse)]
        )
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
        filteredBudgets
            .filter { isUpcoming($0) }
            .sorted { $0.startDate < $1.startDate } // soonest first
    }

    private var activeBudgets: [Budget] {
        filteredBudgets
            .filter { isActive($0) }
            .sorted { $0.startDate > $1.startDate } // most recent first
    }

    private var pastBudgets: [Budget] {
        filteredBudgets
            .filter { isPast($0) }
            .sorted { $0.startDate > $1.startDate } // most recent first
    }

    // MARK: - View

    var body: some View {
        List {
            if budgets.isEmpty {
                ContentUnavailableView(
                    "No Budgets Yet",
                    systemImage: "chart.pie",
                    description: Text("Create a budget to start planning spending.")
                )
            } else if filteredBudgets.isEmpty {
                ContentUnavailableView(
                    "No Results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search.")
                )
            } else {

                // Order: Active → Upcoming → Past

                if !activeBudgets.isEmpty {
                    Section {
                        BucketDisclosureRow(
                            title: "Active Budgets (\(activeBudgets.count))",
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
                            title: "Upcoming Budgets (\(upcomingBudgets.count))",
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
                            title: "Past Budgets (\(pastBudgets.count))",
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
            title: "Budgets",
            items: [
                PostBoardingTipItem(
                    systemImage: "chart.pie.fill",
                    title: "Budgets",
                    detail: "Create and view your budgets here. Press a budget and you will be taken to it's detail view."
                ),
                PostBoardingTipItem(
                    systemImage: "list.triangle",
                    title: "View & Sort",
                    detail: "Active • happening now\nUpcoming • starts later\nPast • ended"
                ),
                PostBoardingTipItem(
                    systemImage: "magnifyingglass",
                    title: "Search",
                    detail: "Use the search bar to search budgets by title or date."
                )
            ]
        )
        .navigationTitle("Budgets")
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search"
        )
        .searchFocused($searchFocused)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingAddBudget = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Budget")
            }
        }
        .sheet(isPresented: $showingAddBudget) {
            NavigationStack {
                AddBudgetView(workspace: workspace)
            }
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

                Text("\(budget.startDate.formatted(date: .abbreviated, time: .omitted)) to \(budget.endDate.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
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
