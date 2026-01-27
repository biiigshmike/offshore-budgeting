//
//  AppRootView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home = "Home"
    case budgets = "Budgets"
    case income = "Income"
    case cards = "Cards"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .budgets: return "chart.pie"
        case .income: return "calendar"
        case .cards: return "creditcard"
        case .settings: return "gear"
        }
    }
}

struct AppRootView: View {

    let workspace: Workspace
    @Binding var selectedWorkspaceID: String

    @SceneStorage("AppRootView.selectedSection")
    private var selectedSectionRaw: String = AppSection.home.rawValue

    @SceneStorage("AppRootView.splitViewVisibility")
    private var splitViewVisibilityRaw: String = "all"

    @State private var budgetsSheetRoute: BudgetsSheetRoute? = nil
    @State private var cardsSheetRoute: CardsSheetRoute? = nil
    @State private var incomeSheetRoute: IncomeSheetRoute? = nil

    @State private var homePath = NavigationPath()
    @State private var budgetsPath = NavigationPath()
    @State private var incomePath = NavigationPath()
    @State private var cardsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var selectedSection: AppSection {
        AppSection(rawValue: selectedSectionRaw) ?? .home
    }

    private var selectedSectionBinding: Binding<AppSection> {
        Binding(
            get: { selectedSection },
            set: { selectedSectionRaw = $0.rawValue }
        )
    }

    private var selectedSectionForSidebar: Binding<AppSection?> {
        Binding(
            get: { selectedSection },
            set: { newValue in
                guard let newValue else { return }
                selectedSectionRaw = newValue.rawValue
            }
        )
    }

    private var splitViewVisibility: NavigationSplitViewVisibility {
        splitViewVisibilityFromRaw(splitViewVisibilityRaw)
    }

    private var splitViewVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { splitViewVisibility },
            set: { splitViewVisibilityRaw = rawFromSplitViewVisibility($0) }
        )
    }

    private enum AppRootSheetRoute: Identifiable {
        case budgets(BudgetsSheetRoute)
        case cards(CardsSheetRoute)
        case income(IncomeSheetRoute)

        var id: String {
            switch self {
            case .budgets(let route):
                return "budgets-\(route.id)"
            case .cards(let route):
                return "cards-\(route.id)"
            case .income(let route):
                return "income-\(route.id)"
            }
        }
    }

    private var appRootSheetRouteBinding: Binding<AppRootSheetRoute?> {
        Binding(
            get: {
                if let budgetsSheetRoute { return .budgets(budgetsSheetRoute) }
                if let cardsSheetRoute { return .cards(cardsSheetRoute) }
                if let incomeSheetRoute { return .income(incomeSheetRoute) }
                return nil
            },
            set: { newValue in
                budgetsSheetRoute = nil
                cardsSheetRoute = nil
                incomeSheetRoute = nil

                switch newValue {
                case .budgets(let route):
                    budgetsSheetRoute = route
                case .cards(let route):
                    cardsSheetRoute = route
                case .income(let route):
                    incomeSheetRoute = route
                case nil:
                    break
                }
            }
        )
    }

    var body: some View {
        Group {
            if isPhone {
                phoneTabs
            } else {
                splitView
            }
        }
        .environment(\.budgetsSheetRoute, $budgetsSheetRoute)
        .environment(\.cardsSheetRoute, $cardsSheetRoute)
        .environment(\.incomeSheetRoute, $incomeSheetRoute)
        .sheet(item: appRootSheetRouteBinding) { route in
            switch route {
            case .budgets(let budgetsRoute):
                switch budgetsRoute {
                case .addBudget:
                    NavigationStack {
                        AddBudgetView(workspace: workspace)
                    }
                case .editBudget(let budget):
                    NavigationStack {
                        EditBudgetView(workspace: workspace, budget: budget)
                    }
                case .addExpense(let budget):
                    NavigationStack {
                        AddExpenseView(
                            workspace: workspace,
                            allowedCards: linkedCards(for: budget),
                            defaultDate: .now
                        )
                    }
                case .manageCards(let budget):
                    NavigationStack {
                        ManageCardsForBudgetSheet(workspace: workspace, budget: budget)
                    }
                case .managePresets(let budget):
                    NavigationStack {
                        ManagePresetsForBudgetSheet(workspace: workspace, budget: budget)
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
                case .editCategoryLimit(let budget, let category, let plannedContribution, let variableContribution):
                    EditCategoryLimitView(
                        budget: budget,
                        category: category,
                        plannedContribution: plannedContribution,
                        variableContribution: variableContribution
                    )
                }

            case .cards(let cardsRoute):
                switch cardsRoute {
                case .addCard:
                    NavigationStack {
                        AddCardView(workspace: workspace)
                    }
                case .editCard(let card):
                    NavigationStack {
                        EditCardView(workspace: workspace, card: card)
                    }
                case .addExpense(let card):
                    NavigationStack {
                        AddExpenseView(workspace: workspace, defaultCard: card)
                    }
                case .importExpenses(let card):
                    NavigationStack {
                        ExpenseCSVImportFlowView(workspace: workspace, card: card)
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
                }

            case .income(let incomeRoute):
                switch incomeRoute {
                case .add(let initialDate):
                    NavigationStack {
                        AddIncomeView(workspace: workspace, initialDate: initialDate)
                    }
                case .edit(let income):
                    NavigationStack {
                        EditIncomeView(workspace: workspace, income: income)
                    }
                }
            }
        }
    }

    private func linkedCards(for budget: Budget) -> [Card] {
        (budget.cardLinks ?? [])
            .compactMap { $0.card }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - iPhone

    private var phoneTabs: some View {
        TabView(selection: selectedSectionBinding) {

            NavigationStack {
                HomeView(workspace: workspace)
            }
            .tabItem { Label(AppSection.home.rawValue, systemImage: AppSection.home.systemImage) }
            .tag(AppSection.home)

            NavigationStack {
                BudgetsView(workspace: workspace, sheetRoute: $budgetsSheetRoute)
            }
            .tabItem { Label(AppSection.budgets.rawValue, systemImage: AppSection.budgets.systemImage) }
            .tag(AppSection.budgets)

            NavigationStack {
                IncomeView(workspace: workspace, sheetRoute: $incomeSheetRoute)
            }
            .tabItem { Label(AppSection.income.rawValue, systemImage: AppSection.income.systemImage) }
            .tag(AppSection.income)

            NavigationStack {
                CardsView(workspace: workspace, sheetRoute: $cardsSheetRoute)
            }
            .tabItem { Label(AppSection.cards.rawValue, systemImage: AppSection.cards.systemImage) }
            .tag(AppSection.cards)

            NavigationStack {
                SettingsView(workspace: workspace, selectedWorkspaceID: $selectedWorkspaceID)
            }
            .tabItem { Label(AppSection.settings.rawValue, systemImage: AppSection.settings.systemImage) }
            .tag(AppSection.settings)
        }
    }

    // MARK: - iPad + Mac

    private var splitView: some View {
        NavigationSplitView(columnVisibility: splitViewVisibilityBinding) {
            List(selection: selectedSectionForSidebar) {
                ForEach(AppSection.allCases) { section in
                    Label(section.rawValue, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(workspace.name)
        } detail: {
            NavigationStack(path: selectedSectionPath) {
                sectionRootView
            }
        }
    }

    private var selectedSectionPath: Binding<NavigationPath> {
        switch selectedSection {
        case .home:
            return $homePath
        case .budgets:
            return $budgetsPath
        case .income:
            return $incomePath
        case .cards:
            return $cardsPath
        case .settings:
            return $settingsPath
        }
    }

    private func splitViewVisibilityFromRaw(_ raw: String) -> NavigationSplitViewVisibility {
        switch raw {
        case "automatic":
            return .automatic
        case "detailOnly":
            return .detailOnly
        default:
            return .all
        }
    }

    private func rawFromSplitViewVisibility(_ visibility: NavigationSplitViewVisibility) -> String {
        switch visibility {
        case .automatic:
            return "automatic"
        case .detailOnly:
            return "detailOnly"
        case .all:
            return "all"
        default:
            return "all"
        }
    }

    // MARK: - Detail Root

    @ViewBuilder
    private var sectionRootView: some View {
        switch selectedSection {
        case .home:
            HomeView(workspace: workspace)
        case .budgets:
            BudgetsView(workspace: workspace, sheetRoute: $budgetsSheetRoute)
        case .income:
            IncomeView(workspace: workspace, sheetRoute: $incomeSheetRoute)
        case .cards:
            CardsView(workspace: workspace, sheetRoute: $cardsSheetRoute)
        case .settings:
            SettingsView(workspace: workspace, selectedWorkspaceID: $selectedWorkspaceID)
        }
    }
}
