//
//  AppRootView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSection: AppSection = .home
    @State private var homePath = NavigationPath()
    @State private var budgetsPath = NavigationPath()
    @State private var incomePath = NavigationPath()
    @State private var cardsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()

    var body: some View {
        if horizontalSizeClass == .compact {
            phoneTabs
        } else {
            splitView
        }
    }

    private var selectedSectionForSidebar: Binding<AppSection?> {
        Binding(
            get: { selectedSection },
            set: { newValue in
                guard let newValue else { return }
                selectedSection = newValue
            }
        )
    }

    // MARK: - iPhone

    private var phoneTabs: some View {
        TabView(selection: $selectedSection) {

            NavigationStack {
                HomeView(workspace: workspace)
            }
            .tabItem { Label(AppSection.home.rawValue, systemImage: AppSection.home.systemImage) }
            .tag(AppSection.home)

            NavigationStack {
                BudgetsView(workspace: workspace)
            }
            .tabItem { Label(AppSection.budgets.rawValue, systemImage: AppSection.budgets.systemImage) }
            .tag(AppSection.budgets)

            NavigationStack {
                IncomeView(workspace: workspace)
            }
            .tabItem { Label(AppSection.income.rawValue, systemImage: AppSection.income.systemImage) }
            .tag(AppSection.income)

            NavigationStack {
                CardsView(workspace: workspace)
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
        NavigationSplitView {
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

    // MARK: - Detail Root

    @ViewBuilder
    private var sectionRootView: some View {
        switch selectedSection {
        case .home:
            HomeView(workspace: workspace)
        case .budgets:
            BudgetsView(workspace: workspace)
        case .income:
            IncomeView(workspace: workspace)
        case .cards:
            CardsView(workspace: workspace)
        case .settings:
            SettingsView(workspace: workspace, selectedWorkspaceID: $selectedWorkspaceID)
        }
    }
}
