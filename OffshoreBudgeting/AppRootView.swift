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

    var title: String {
        switch self {
        case .home:
            return String(
                localized: "app.section.home",
                defaultValue: "Home",
                comment: "Main tab title for the Home section."
            )
        case .budgets:
            return String(
                localized: "app.section.budgets",
                defaultValue: "Budgets",
                comment: "Main tab title for the Budgets section."
            )
        case .income:
            return String(
                localized: "app.section.income",
                defaultValue: "Income",
                comment: "Main tab title for the Income section."
            )
        case .cards:
            return String(
                localized: "app.section.cards",
                defaultValue: "Accounts",
                comment: "Main tab title for the Accounts section."
            )
        case .settings:
            return String(
                localized: "app.section.settings",
                defaultValue: "Settings",
                comment: "Main tab title for the Settings section."
            )
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .budgets: return "chart.pie"
        case .income: return "calendar"
        case .cards: return "creditcard"
        case .settings: return "gear"
        }
    }

    static func fromStorageRaw(_ raw: String) -> AppSection? {
        if let section = AppSection(rawValue: raw) {
            return section
        }

        if raw == "Accounts" {
            return .cards
        }

        return nil
    }
}

struct AppRootView: View {

    let workspace: Workspace
    @Binding var selectedWorkspaceID: String
    let initialSectionOverride: AppSection?

    init(
        workspace: Workspace,
        selectedWorkspaceID: Binding<String>,
        initialSectionOverride: AppSection? = nil
    ) {
        self.workspace = workspace
        self._selectedWorkspaceID = selectedWorkspaceID
        self.initialSectionOverride = initialSectionOverride
    }

    @AppStorage("general_rememberTabSelection") private var rememberTabSelection: Bool = false
    @AppStorage(AppShortcutNavigationStore.pendingSectionKey) private var pendingShortcutSectionRaw: String = ""

    @SceneStorage("AppRootView.selectedSection")
    private var selectedSectionRaw: String = AppSection.home.rawValue

    @State private var homePath = NavigationPath()
    @State private var budgetsPath = NavigationPath()
    @State private var incomePath = NavigationPath()
    @State private var cardsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .automatic

    @State private var didApplyInitialSection: Bool = false
    @State private var showingHelpSheet: Bool = false
    @State private var detailSnapshotCache = DetailViewSnapshotCache()
    @State private var postBoardingTipActivationCycle: Int = 0

    @Environment(\.appCommandHub) private var commandHub

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private var selectedSection: AppSection {
        AppSection.fromStorageRaw(selectedSectionRaw) ?? .home
    }

    private var shouldSyncActiveSectionToCommandHub: Bool {
        isPhone == false
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

    var body: some View {
        Group {
            if isPhone {
                phoneTabs
            } else {
                splitView
            }
        }
        .environment(detailSnapshotCache)
        .whatsNewForCurrentRelease()
        .onAppear {
            guard didApplyInitialSection == false else { return }
            didApplyInitialSection = true
            if let initialSectionOverride {
                selectedSectionRaw = initialSectionOverride.rawValue
            } else {
                consumePendingShortcutSectionIfNeeded()

                guard rememberTabSelection == false else { return }
                selectedSectionRaw = AppSection.home.rawValue
            }

            if shouldSyncActiveSectionToCommandHub {
                commandHub.setActiveSectionRaw(selectedSectionRaw)
            }
        }
        .onChange(of: rememberTabSelection) { _, newValue in
            guard newValue == false else { return }
            selectedSectionRaw = AppSection.home.rawValue
        }
        .onChange(of: pendingShortcutSectionRaw) { _, _ in
            consumePendingShortcutSectionIfNeeded()
        }
        .onReceive(commandHub.$sequence) { _ in
            handleCommand(commandHub.latestCommandID)
        }
        .onChange(of: selectedSectionRaw) { _, newValue in
            postBoardingTipActivationCycle &+= 1
            if shouldSyncActiveSectionToCommandHub {
                commandHub.setActiveSectionRaw(newValue)
            }
        }
        .sheet(isPresented: $showingHelpSheet) {
            NavigationStack {
                SettingsHelpView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(
                                String(
                                    localized: "common.done",
                                    defaultValue: "Done",
                                    comment: "Generic action label to finish and close a sheet."
                                )
                            ) {
                                showingHelpSheet = false
                            }
                        }
                    }
            }
        }
    }

    // MARK: - iPhone

    private var phoneTabs: some View {
        TabView(selection: selectedSectionBinding) {

            NavigationStack(path: $homePath) {
                homeRootView
            }
            .environment(\.postBoardingTipPresenterIsActive, selectedSection == .home)
            .environment(\.postBoardingTipActivationCycle, postBoardingTipActivationCycle)
            .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.systemImage) }
            .tag(AppSection.home)

            NavigationStack(path: $budgetsPath) {
                BudgetsView(workspace: workspace)
            }
            .environment(\.postBoardingTipPresenterIsActive, selectedSection == .budgets)
            .environment(\.postBoardingTipActivationCycle, postBoardingTipActivationCycle)
            .tabItem { Label(AppSection.budgets.title, systemImage: AppSection.budgets.systemImage) }
            .tag(AppSection.budgets)

            NavigationStack(path: $incomePath) {
                IncomeWorkspaceView(workspace: workspace)
            }
            .environment(\.postBoardingTipPresenterIsActive, selectedSection == .income)
            .environment(\.postBoardingTipActivationCycle, postBoardingTipActivationCycle)
            .tabItem { Label(AppSection.income.title, systemImage: AppSection.income.systemImage) }
            .tag(AppSection.income)

            NavigationStack(path: $cardsPath) {
                AccountsView(workspace: workspace)
            }
            .environment(\.postBoardingTipPresenterIsActive, selectedSection == .cards)
            .environment(\.postBoardingTipActivationCycle, postBoardingTipActivationCycle)
            .tabItem { Label(AppSection.cards.title, systemImage: AppSection.cards.systemImage) }
            .tag(AppSection.cards)

            NavigationStack(path: $settingsPath) {
                SettingsView(workspace: workspace, selectedWorkspaceID: $selectedWorkspaceID)
            }
            .environment(\.postBoardingTipPresenterIsActive, selectedSection == .settings)
            .environment(\.postBoardingTipActivationCycle, postBoardingTipActivationCycle)
            .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage) }
            .tag(AppSection.settings)
        }
    }

    // MARK: - iPad + Mac

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $splitViewVisibility) {
            List(selection: selectedSectionForSidebar) {
                ForEach(AppSection.allCases) { section in
                    Label(section.title, systemImage: section.systemImage)
                        .tag(section)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(workspace.name)
        } detail: {
            NavigationStack(path: selectedSectionPath) {
                sectionRootView
            }
            .environment(\.postBoardingTipPresenterIsActive, true)
            .environment(\.postBoardingTipActivationCycle, postBoardingTipActivationCycle)
            .id(selectedSection)
        }
        .homeAssistantHost(
            workspace: workspace,
            isEnabled: selectedSection == .home
        )
        .background {
            MacWindowSceneTitleHost(title: macWindowSceneTitle)
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

    private func consumePendingShortcutSectionIfNeeded() {
        let pending = pendingShortcutSectionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty else { return }

        if let section = AppSection.fromStorageRaw(pending) {
            selectedSectionRaw = section.rawValue
        }

        pendingShortcutSectionRaw = ""
    }

    private func handleCommand(_ commandID: String) {
        if commandID == AppCommandID.Help.openHelp {
            showingHelpSheet = true
        }
    }

    private var macWindowSceneTitle: String {
        selectedSection.title
    }

    // MARK: - Detail Root

    @ViewBuilder
    private var sectionRootView: some View {
        switch selectedSection {
        case .home:
            homeRootView
        case .budgets:
            BudgetsView(workspace: workspace)
        case .income:
            IncomeWorkspaceView(workspace: workspace)
        case .cards:
            AccountsView(workspace: workspace)
        case .settings:
            SettingsView(workspace: workspace, selectedWorkspaceID: $selectedWorkspaceID)
        }
    }

    private var homeRootView: some View {
        HomeView(workspace: workspace)
    }

}
