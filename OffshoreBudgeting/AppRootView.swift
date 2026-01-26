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

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("app_selectedSection") private var storedSelectedSectionRaw: String = AppSection.home.rawValue
    @AppStorage("app_splitViewVisibility") private var storedSplitViewVisibilityRaw: String = "all"

    @State private var selectedSection: AppSection = .home
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all
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

    var body: some View {
        Group {
            if isPhone {
                phoneTabs
            } else if horizontalSizeClass == .compact {
                phoneTabs
            } else {
                splitView
            }
        }
        .onAppear {
            selectedSection = AppSection(rawValue: storedSelectedSectionRaw) ?? .home
            splitViewVisibility = splitViewVisibilityFromRaw(storedSplitViewVisibilityRaw)
        }
        .onChange(of: selectedSection) { _, newValue in
            storedSelectedSectionRaw = newValue.rawValue
        }
        .onChange(of: splitViewVisibility) { _, newValue in
            storedSplitViewVisibilityRaw = rawFromSplitViewVisibility(newValue)
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
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
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
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if splitViewVisibility == .detailOnly {
                        Picker("Section", selection: $selectedSection) {
                            ForEach(AppSection.allCases) { section in
                                Text(section.rawValue)
                                    .tag(section)
                            }
                        }
                        #if os(iOS)
                        .pickerStyle(.segmented)
                        #endif
                    }
                }
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
