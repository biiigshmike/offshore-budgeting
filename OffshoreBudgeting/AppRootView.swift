//
//  AppRootView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

enum AppSection: String, CaseIterable, Identifiable {
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

    @State private var tabStackIDs: [AppSection: UUID] = Dictionary(
        uniqueKeysWithValues: AppSection.allCases.map { ($0, UUID()) }
    )

    // Changing this forces the iPad/Mac NavigationSplitView subtree to be recreated,
    // which reliably clears any pushed (nested) navigation state.
    @State private var splitViewID = UUID()

    var body: some View {
        if horizontalSizeClass == .compact {
            phoneTabs
        } else {
            splitView
        }
    }

    // MARK: - iPhone

    private var phoneTabs: some View {
        TabView(selection: $selectedSection) {

            NavigationStack {
                HomeView(workspace: workspace)
            }
            .id(tabStackIDs[.home]!)
            .tabItem { Label(AppSection.home.rawValue, systemImage: AppSection.home.systemImage) }
            .tag(AppSection.home)

            NavigationStack {
                BudgetsView(workspace: workspace)
            }
            .id(tabStackIDs[.budgets]!)
            .tabItem { Label(AppSection.budgets.rawValue, systemImage: AppSection.budgets.systemImage) }
            .tag(AppSection.budgets)

            NavigationStack {
                IncomeView(workspace: workspace)
            }
            .id(tabStackIDs[.income]!)
            .tabItem { Label(AppSection.income.rawValue, systemImage: AppSection.income.systemImage) }
            .tag(AppSection.income)

            NavigationStack {
                CardsView(workspace: workspace)
            }
            .id(tabStackIDs[.cards]!)
            .tabItem { Label(AppSection.cards.rawValue, systemImage: AppSection.cards.systemImage) }
            .tag(AppSection.cards)

            NavigationStack {
                SettingsView(workspace: workspace, selectedWorkspaceID: $selectedWorkspaceID)
            }
            .id(tabStackIDs[.settings]!)
            .tabItem { Label(AppSection.settings.rawValue, systemImage: AppSection.settings.systemImage) }
            .tag(AppSection.settings)
        }
    }

    // MARK: - iPad + Mac

    private var splitView: some View {
        NavigationSplitView {
            List {
                ForEach(AppSection.allCases) { section in
                    Button {
                        selectedSection = section
                        DispatchQueue.main.async {
                            resetDetailColumn()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.systemImage)
                            Text(section.rawValue)
                            Spacer()
                            if selectedSection == section {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(workspace.name)
        } detail: {
            sectionRootView
        }
        .id(splitViewID)
    }

    // MARK: - Detail Reset

    private func resetDetailColumn() {
        splitViewID = UUID()
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
