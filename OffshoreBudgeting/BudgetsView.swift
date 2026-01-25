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

    @State private var showingAddBudgetSheet: Bool = false

    @State private var upcomingExpanded: Bool = true
    @State private var activeExpanded: Bool = true
    @State private var pastExpanded: Bool = false

    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool

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
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return budgets }

        return budgets.filter { budget in
            budget.name.localizedCaseInsensitiveContains(trimmed)
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
                        DisclosureGroup(isExpanded: $activeExpanded) {
                            ForEach(activeBudgets) { budget in
                                budgetRow(budget)
                            }
                        } label: {
                            Text("Active Budgets (\(activeBudgets.count))")
                        }
                    }
                }

                if !upcomingBudgets.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $upcomingExpanded) {
                            ForEach(upcomingBudgets) { budget in
                                budgetRow(budget)
                            }
                        } label: {
                            Text("Upcoming Budgets (\(upcomingBudgets.count))")
                        }
                    }
                }

                if !pastBudgets.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $pastExpanded) {
                            ForEach(pastBudgets) { budget in
                                budgetRow(budget)
                            }
                        } label: {
                            Text("Past Budgets (\(pastBudgets.count))")
                        }
                    }
                }
            }
        }
        .navigationTitle("Budgets")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .searchFocused($searchFocused)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showingAddBudgetSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Budget")
            }
        }
        .sheet(isPresented: $showingAddBudgetSheet) {
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

#Preview("Budgets") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            BudgetsView(workspace: ws)
        }
    }
}
