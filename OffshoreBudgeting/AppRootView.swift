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

    @AppStorage("general_rememberTabSelection") private var rememberTabSelection: Bool = false

    @SceneStorage("AppRootView.selectedSection")
    private var selectedSectionRaw: String = AppSection.home.rawValue

    @State private var homePath = NavigationPath()
    @State private var budgetsPath = NavigationPath()
    @State private var incomePath = NavigationPath()
    @State private var cardsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .automatic

    @State private var didApplyInitialSection: Bool = false
    @State private var assistantRoute: AssistantPresentationRoute? = nil
    @State private var containerWidth: CGFloat = 0

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private enum AssistantPresentationRoute: Equatable {
        case inspector
        case sheet
        case fullScreen
    }

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

    var body: some View {
        Group {
            if isPhone {
                phoneTabs
            } else {
                splitView
            }
        }
        .sheet(
            isPresented: assistantSheetPresentedBinding,
            onDismiss: dismissAssistant
        ) {
            HomeAssistantPanelView(
                workspace: workspace,
                onDismiss: dismissAssistant,
                shouldUseLargeMinimumSize: assistantPresentationPlan.usesExpandedPanelSizing
            )
            .presentationDetents(assistantPresentationPlan.detents)
            .presentationDragIndicator(.visible)
        }
        .applyAssistantInspectorIfNeeded(
            isEnabled: shouldMountInspectorPresenter,
            isPresented: assistantInspectorPresentedBinding
        ) {
            HomeAssistantPanelView(
                workspace: workspace,
                onDismiss: dismissAssistant,
                shouldUseLargeMinimumSize: false
            )
            .inspectorColumnWidth(min: 340, ideal: 420, max: 520)
        }
        .fullScreenCover(
            isPresented: assistantFullScreenPresentedBinding,
            onDismiss: dismissAssistant
        ) {
            HomeAssistantPanelView(
                workspace: workspace,
                onDismiss: dismissAssistant,
                shouldUseLargeMinimumSize: false
            )
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        updateContainerWidth(proxy.size.width)
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        updateContainerWidth(newWidth)
                    }
            }
        }
        .onAppear {
            guard didApplyInitialSection == false else { return }
            didApplyInitialSection = true

            guard rememberTabSelection == false else { return }
            selectedSectionRaw = AppSection.home.rawValue
        }
        .onChange(of: rememberTabSelection) { _, newValue in
            guard newValue == false else { return }
            selectedSectionRaw = AppSection.home.rawValue
        }
    }

    // MARK: - iPhone

    private var phoneTabs: some View {
        TabView(selection: selectedSectionBinding) {

            NavigationStack {
                HomeView(workspace: workspace)
            }
            .toolbar { assistantToolbarContent }
            .safeAreaInset(edge: .bottom) {
                if shouldShowBottomLauncher {
                    HomeAssistantLauncherBar(onTap: presentAssistant)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
            .tabItem { Label(AppSection.home.rawValue, systemImage: AppSection.home.systemImage) }
            .tag(AppSection.home)

            NavigationStack {
                BudgetsView(workspace: workspace)
            }
            .toolbar { assistantToolbarContent }
            .tabItem { Label(AppSection.budgets.rawValue, systemImage: AppSection.budgets.systemImage) }
            .tag(AppSection.budgets)

            NavigationStack {
                IncomeView(workspace: workspace)
            }
            .toolbar { assistantToolbarContent }
            .tabItem { Label(AppSection.income.rawValue, systemImage: AppSection.income.systemImage) }
            .tag(AppSection.income)

            NavigationStack {
                CardsView(workspace: workspace)
            }
            .toolbar { assistantToolbarContent }
            .tabItem { Label(AppSection.cards.rawValue, systemImage: AppSection.cards.systemImage) }
            .tag(AppSection.cards)

            NavigationStack {
                SettingsView(workspace: workspace, selectedWorkspaceID: $selectedWorkspaceID)
            }
            .toolbar { assistantToolbarContent }
            .tabItem { Label(AppSection.settings.rawValue, systemImage: AppSection.settings.systemImage) }
            .tag(AppSection.settings)
        }
        .overlay(alignment: .bottomTrailing) {
            if shouldShowCompactLandscapeLauncher {
                compactLandscapeAssistantButton
                    .padding(.trailing, 24)
                    .padding(.bottom, 8)
            }
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
            .toolbar { assistantToolbarContent }
            .id(selectedSection)
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

    // MARK: - Assistant

    @ToolbarContentBuilder
    private var assistantToolbarContent: some ToolbarContent {
        if shouldShowToolbarButton {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentAssistant()
                } label: {
                    Image(systemName: "message")
                }
                .accessibilityLabel("Open Assistant")
            }
        }
    }

    private var assistantSheetPresentedBinding: Binding<Bool> {
        Binding(
            get: { assistantRoute == .sheet },
            set: { isPresented in
                assistantRoute = isPresented ? .sheet : nil
            }
        )
    }

    private var assistantInspectorPresentedBinding: Binding<Bool> {
        Binding(
            get: { assistantRoute == .inspector },
            set: { isPresented in
                assistantRoute = isPresented ? .inspector : nil
            }
        )
    }

    private var assistantFullScreenPresentedBinding: Binding<Bool> {
        Binding(
            get: { assistantRoute == .fullScreen },
            set: { isPresented in
                assistantRoute = isPresented ? .fullScreen : nil
            }
        )
    }

    private func presentAssistant() {
        if supportsInlineInspector {
            splitViewVisibility = .detailOnly
        }
        assistantRoute = route(for: assistantPresentationPlan.mode)
    }

    private func dismissAssistant() {
        assistantRoute = nil
    }

    private func route(for mode: HomeAssistantPresentationMode) -> AssistantPresentationRoute {
        switch mode {
        case .inspector:
            return .inspector
        case .sheet:
            return .sheet
        case .fullScreen:
            return .fullScreen
        }
    }

    private var assistantPresentationPlan: HomeAssistantPresentationPlan {
        let basePlan = HomeAssistantPresentationResolver.resolve(
            containerWidth: containerWidth,
            supportsInlineInspector: supportsInlineInspector,
            dynamicTypeSize: dynamicTypeSize,
            voiceOverEnabled: voiceOverEnabled
        )

        guard usesCompactPhoneHeight == false else {
            return HomeAssistantPresentationPlan(
                mode: basePlan.mode,
                showsBottomLauncher: false,
                showsToolbarButton: true,
                detents: basePlan.detents,
                usesExpandedPanelSizing: basePlan.usesExpandedPanelSizing,
                prefersInlineInspectorWhenAvailable: basePlan.prefersInlineInspectorWhenAvailable
            )
        }

        return basePlan
    }

    private var supportsInlineInspector: Bool {
        isPhone == false && horizontalSizeClass != .compact
    }

    private var usesCompactPhoneHeight: Bool {
        #if os(iOS)
        isPhone && verticalSizeClass == .compact
        #else
        false
        #endif
    }

    private var shouldShowBottomLauncher: Bool {
        selectedSection == .home &&
        assistantRoute == nil &&
        assistantPresentationPlan.showsBottomLauncher
    }

    private var shouldShowToolbarButton: Bool {
        selectedSection == .home &&
        assistantRoute == nil &&
        assistantPresentationPlan.showsToolbarButton
    }

    private var shouldShowCompactLandscapeLauncher: Bool {
        selectedSection == .home &&
        assistantRoute == nil &&
        usesCompactPhoneHeight
    }

    @ViewBuilder
    private var compactLandscapeAssistantButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: presentAssistant) {
                Image(systemName: "message")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("Open Assistant")
        } else {
            Button(action: presentAssistant) {
                Image(systemName: "message")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .accessibilityLabel("Open Assistant")
        }
    }

    private var shouldMountInspectorPresenter: Bool {
        supportsInlineInspector && (
            assistantRoute == .inspector ||
            assistantPresentationPlan.mode == .inspector
        )
    }

    private func updateContainerWidth(_ rawWidth: CGFloat) {
        let width = max(0, rawWidth)
        let previousBand = widthBand(for: containerWidth)
        let nextBand = widthBand(for: width)

        if containerWidth == 0 || previousBand != nextBand {
            containerWidth = width
        }
    }

    private func widthBand(for width: CGFloat) -> Int {
        if width < 540 { return 0 }
        if width < 900 { return 1 }
        return 2
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

private extension View {
    @ViewBuilder
    func applyAssistantInspectorIfNeeded<InspectorContent: View>(
        isEnabled: Bool,
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> InspectorContent
    ) -> some View {
        if isEnabled {
            self.inspector(isPresented: isPresented, content: content)
        } else {
            self
        }
    }
}
