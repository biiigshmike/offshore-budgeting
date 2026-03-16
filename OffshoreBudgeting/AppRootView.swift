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

enum AppTabActivationPhase: String, Equatable {
    case inactive
    case activating
    case active
}

struct AppTabActivationContext: Equatable {
    let sectionRawValue: String
    let phase: AppTabActivationPhase
    let token: Int

    var isVisible: Bool {
        phase != .inactive
    }

    var isSettled: Bool {
        phase == .active
    }

    static let inactive = AppTabActivationContext(
        sectionRawValue: "",
        phase: .inactive,
        token: 0
    )
}

private struct AppTabActivationContextKey: EnvironmentKey {
    static let defaultValue: AppTabActivationContext = .inactive
}

extension EnvironmentValues {
    var appTabActivationContext: AppTabActivationContext {
        get { self[AppTabActivationContextKey.self] }
        set { self[AppTabActivationContextKey.self] = newValue }
    }
}

struct AppRootView: View {

    let workspace: Workspace
    @Binding var selectedWorkspaceID: String
    let initialSectionOverride: AppSection?
    let onTabInteraction: ((AppSection) -> Void)?

    init(
        workspace: Workspace,
        selectedWorkspaceID: Binding<String>,
        initialSectionOverride: AppSection? = nil,
        onTabInteraction: ((AppSection) -> Void)? = nil
    ) {
        self.workspace = workspace
        self._selectedWorkspaceID = selectedWorkspaceID
        self.initialSectionOverride = initialSectionOverride
        self.onTabInteraction = onTabInteraction
    }

    @AppStorage(AppShortcutNavigationStore.pendingSectionKey) private var pendingShortcutSectionRaw: String = ""

    @SceneStorage("AppRootView.selectedSection")
    private var persistedSelectedSectionRaw: String = AppSection.home.rawValue

    @State private var selectedSectionRaw: String = AppSection.home.rawValue

    @State private var homePath = NavigationPath()
    @State private var budgetsPath = NavigationPath()
    @State private var incomePath = NavigationPath()
    @State private var cardsPath = NavigationPath()
    @State private var settingsPath = NavigationPath()
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .automatic

    @State private var didApplyInitialSection: Bool = false
    @State private var showingHelpSheet: Bool = false
    @State private var detailSnapshotCache = DetailViewSnapshotCache()
    @State private var loadedPhoneSections: Set<AppSection> = []
    @State private var mountedPhoneSections: Set<AppSection> = []
    @State private var stagingPhoneSections: Set<AppSection> = []
    @State private var activePhoneSection: AppSection? = nil
    @State private var activatingPhoneSections: Set<AppSection> = []
    @State private var activationTokens: [AppSection: Int] = [:]
    @State private var settledActivationTokens: [AppSection: Int] = [:]
    @State private var lastEligibilitySignatures: [AppSection: String] = [:]
    @State private var pendingSharedInvalidationSources: Set<String> = []
    @State private var sharedInvalidationWaveScheduled: Bool = false

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
            set: { newValue in
                let currentValue = selectedSectionRaw
                let metadata = shellMetadata().merging(
                    [
                        "fromTab": currentValue,
                        "toTab": newValue.rawValue
                    ],
                    uniquingKeysWith: { _, new in new }
                )
                TabFlickerDiagnostics.markEvent("tabSelectionBindingSetRequested", metadata: metadata)

                guard currentValue != newValue.rawValue else {
                    TabFlickerDiagnostics.markEvent("tabSelectionBindingSetIgnored", metadata: metadata)
                    return
                }

                selectedSectionRaw = newValue.rawValue
                TabFlickerDiagnostics.markEvent("tabSelectionBindingSetApplied", metadata: metadata)
            }
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
            let resolvedSection = resolveInitialSection()
            selectedSectionRaw = resolvedSection.rawValue
            persistedSelectedSectionRaw = resolvedSection.rawValue
            preparePhoneSection(resolvedSection, preferImmediateMount: true)
            preparePhoneSectionActivation(resolvedSection, preferImmediateActivation: true)
            TabFlickerDiagnostics.markEvent(
                "launchSelectionResolved",
                metadata: [
                    "selectedTab": resolvedSection.rawValue,
                    "persistedSelection": persistedSelectedSectionRaw
                ]
            )
            TabFlickerDiagnostics.markEvent(
                "appRootInitialSection",
                metadata: ["selectedTab": resolvedSection.rawValue]
            )
            clearPendingShortcutSection()

            if shouldSyncActiveSectionToCommandHub {
                commandHub.setActiveSectionRaw(selectedSectionRaw)
            }
        }
        .onChange(of: persistedSelectedSectionRaw) { _, newValue in
            guard didApplyInitialSection else { return }
            guard AppSection.fromStorageRaw(newValue) == selectedSection else { return }
            TabFlickerDiagnostics.markEvent(
                "persistedSelectionApplied",
                metadata: ["selectedTab": newValue]
            )
        }
        .onChange(of: pendingShortcutSectionRaw) { _, _ in
            consumePendingShortcutSectionIfNeeded()
        }
        .onReceive(commandHub.$sequence) { _ in
            handleCommand(commandHub.latestCommandID)
        }
        .onChange(of: selectedSectionRaw) { oldValue, newValue in
            guard didApplyInitialSection else { return }
            recordSharedRootInputChange("selectedSectionRaw")
            traceTabSelection(from: oldValue, to: newValue)
            if let section = AppSection.fromStorageRaw(newValue) {
                onTabInteraction?(section)
                preparePhoneSection(section)
                preparePhoneSectionActivation(section)
                persistedSelectedSectionRaw = section.rawValue
            }
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
        .onChange(of: persistedSelectedSectionRaw) { _, _ in
            recordSharedRootInputChange("persistedSelectedSectionRaw")
        }
        .onChange(of: loadedPhoneSections) { _, _ in
            recordSharedRootInputChange("loadedPhoneSections")
            auditPhoneSectionEligibilityChanges(reason: "loadedPhoneSectionsChanged")
        }
        .onChange(of: mountedPhoneSections) { _, _ in
            recordSharedRootInputChange("mountedPhoneSections")
            auditPhoneSectionEligibilityChanges(reason: "mountedPhoneSectionsChanged")
        }
        .onChange(of: activePhoneSection) { _, _ in
            recordSharedRootInputChange("activePhoneSection")
            auditPhoneSectionEligibilityChanges(reason: "activePhoneSectionChanged")
        }
        .onChange(of: activatingPhoneSections) { _, _ in
            recordSharedRootInputChange("activatingPhoneSections")
            auditPhoneSectionEligibilityChanges(reason: "activatingPhoneSectionsChanged")
        }
        .onChange(of: activationTokens) { _, _ in
            recordSharedRootInputChange("activationTokens")
        }
        .onChange(of: commandHub.surface) { _, _ in
            recordSharedRootInputChange("appCommandHub.surface")
        }
        .onChange(of: commandHub.sequence) { _, _ in
            recordSharedRootInputChange("appCommandHub.sequence")
        }
    }

    // MARK: - iPhone

    private var phoneTabs: some View {
        TabView(selection: selectedSectionBinding) {

            NavigationStack(path: $homePath) {
                phoneSectionContent(.home) {
                    homeRootView
                }
            }
            .tabItem { Label(AppSection.home.title, systemImage: AppSection.home.systemImage) }
            .tag(AppSection.home)

            NavigationStack(path: $budgetsPath) {
                phoneSectionContent(.budgets) {
                    BudgetsView(workspace: workspace)
                }
            }
            .tabItem { Label(AppSection.budgets.title, systemImage: AppSection.budgets.systemImage) }
            .tag(AppSection.budgets)

            NavigationStack(path: $incomePath) {
                phoneSectionContent(.income) {
                    IncomeWorkspaceView(workspace: workspace)
                }
            }
            .tabItem { Label(AppSection.income.title, systemImage: AppSection.income.systemImage) }
            .tag(AppSection.income)

            NavigationStack(path: $cardsPath) {
                phoneSectionContent(.cards) {
                    AccountsView(workspace: workspace)
                }
            }
            .tabItem { Label(AppSection.cards.title, systemImage: AppSection.cards.systemImage) }
            .tag(AppSection.cards)

            NavigationStack(path: $settingsPath) {
                phoneSectionContent(.settings) {
                    SettingsView(workspace: workspace, selectedWorkspaceID: $selectedWorkspaceID)
                }
            }
            .tabItem { Label(AppSection.settings.title, systemImage: AppSection.settings.systemImage) }
            .tag(AppSection.settings)
        }
        .tabShellBodyReporter(
            shell: "phoneTabs",
            signature: tabShellSignature,
            metadata: shellMetadata()
        )
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
            let context = AppTabActivationContext(
                sectionRawValue: selectedSection.rawValue,
                phase: .active,
                token: activationTokens[selectedSection] ?? 0
            )
            NavigationStack(path: selectedSectionPath) {
                sectionRootView
            }
            .rootActivationBodyReporter(root: selectedSection.rawValue.lowercased(), context: context)
            .environment(\.postBoardingTipPresenterIsActive, true)
            .environment(\.appTabActivationContext, context)
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

    @ViewBuilder
    private func phoneSectionContent<Content: View>(
        _ section: AppSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if loadedPhoneSections.contains(section), mountedPhoneSections.contains(section) {
            let context = activationContext(for: section)
            AppTabRootActivationReporter(section: section) {
                content()
            }
                .rootActivationBodyReporter(root: section.rawValue.lowercased(), context: context)
                .environment(\.postBoardingTipPresenterIsActive, section == selectedSection)
                .environment(\.appTabActivationContext, context)
        } else {
            Color.clear
                .accessibilityHidden(true)
        }
    }

    private func preparePhoneSection(_ section: AppSection, preferImmediateMount: Bool = false) {
        guard isPhone else { return }
        loadedPhoneSections.insert(section)
        guard mountedPhoneSections.contains(section) == false else { return }
        guard stagingPhoneSections.contains(section) == false else { return }

        if preferImmediateMount {
            mountedPhoneSections.insert(section)
            return
        }

        stagingPhoneSections.insert(section)
        TabFlickerDiagnostics.markEvent(
            "tabRootMountScheduled",
            metadata: ["tab": section.rawValue]
        )
        TabFlickerDiagnostics.markEvent(
            "tabRootMountDispatchQueued",
            metadata: shellMetadata().merging(["tab": section.rawValue], uniquingKeysWith: { _, new in new })
        )
        DispatchQueue.main.async {
            mountedPhoneSections.insert(section)
            stagingPhoneSections.remove(section)
            TabFlickerDiagnostics.markEvent(
                "tabRootMountActivated",
                metadata: ["tab": section.rawValue]
            )
            TabFlickerDiagnostics.markEvent(
                "tabRootMountDispatchExecuted",
                metadata: shellMetadata().merging(["tab": section.rawValue], uniquingKeysWith: { _, new in new })
            )
        }
    }

    private func preparePhoneSectionActivation(
        _ section: AppSection,
        preferImmediateActivation: Bool = false
    ) {
        guard isPhone else { return }

        let previousActiveSection = activePhoneSection
        activePhoneSection = section
        let nextToken = (activationTokens[section] ?? 0) + 1
        activationTokens[section] = nextToken

        if let previousActiveSection,
           previousActiveSection != section,
           activatingPhoneSections.contains(previousActiveSection) {
            activatingPhoneSections.remove(previousActiveSection)
            TabFlickerDiagnostics.markEvent(
                "tabActivationCancelled",
                metadata: ["tab": previousActiveSection.rawValue]
            )
        }

        if preferImmediateActivation {
            activatingPhoneSections.remove(section)
            markActivationSettled(section: section, token: nextToken)
            return
        }

        activatingPhoneSections.insert(section)
        TabFlickerDiagnostics.markEvent(
            "tabActivationBegan",
            metadata: [
                "tab": section.rawValue,
                "token": String(nextToken)
            ]
        )
        TabFlickerDiagnostics.markEvent(
            "tabActivationDispatchQueued",
            metadata: shellMetadata().merging(
                [
                    "tab": section.rawValue,
                    "token": String(nextToken)
                ],
                uniquingKeysWith: { _, new in new }
            )
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            guard activePhoneSection == section else { return }
            guard activationTokens[section] == nextToken else { return }
            activatingPhoneSections.remove(section)
            TabFlickerDiagnostics.markEvent(
                "tabActivationDispatchExecuted",
                metadata: shellMetadata().merging(
                    [
                        "tab": section.rawValue,
                        "token": String(nextToken)
                    ],
                    uniquingKeysWith: { _, new in new }
                )
            )
            markActivationSettled(section: section, token: nextToken)
        }
    }

    private func activationContext(for section: AppSection) -> AppTabActivationContext {
        guard isPhone else {
            return AppTabActivationContext(
                sectionRawValue: section.rawValue,
                phase: .active,
                token: activationTokens[section] ?? 0
            )
        }

        guard activePhoneSection == section else {
            return AppTabActivationContext(
                sectionRawValue: section.rawValue,
                phase: .inactive,
                token: activationTokens[section] ?? 0
            )
        }

        let phase: AppTabActivationPhase = activatingPhoneSections.contains(section) ? .activating : .active
        return AppTabActivationContext(
            sectionRawValue: section.rawValue,
            phase: phase,
            token: activationTokens[section] ?? 0
        )
    }

    private func resolveInitialSection() -> AppSection {
        if let initialSectionOverride {
            return initialSectionOverride
        }

        let pending = pendingShortcutSectionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pendingSection = AppSection.fromStorageRaw(pending) {
            return pendingSection
        }

        if isPhone == false,
           let persistedSection = AppSection.fromStorageRaw(persistedSelectedSectionRaw) {
            return persistedSection
        }

        return .home
    }

    private func consumePendingShortcutSectionIfNeeded() {
        let pending = pendingShortcutSectionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pending.isEmpty else { return }

        if let section = AppSection.fromStorageRaw(pending) {
            selectedSectionRaw = section.rawValue
            preparePhoneSection(section)
            preparePhoneSectionActivation(section)
            persistedSelectedSectionRaw = section.rawValue
        }

        clearPendingShortcutSection()
    }

    private func clearPendingShortcutSection() {
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

    private func traceTabSelection(from oldValue: String, to newValue: String) {
        #if DEBUG
        let metadata = [
            "fromTab": oldValue,
            "toTab": newValue,
            "loadedPhoneSections": loadedPhoneSections.map(\.rawValue).sorted().joined(separator: ","),
            "mountedPhoneSections": mountedPhoneSections.map(\.rawValue).sorted().joined(separator: ",")
        ]

        TabFlickerDiagnostics.beginWatch(
            reason: "tabSelection",
            metadata: metadata,
            duration: 1.0
        )
        TabFlickerDiagnostics.markEvent("tabSelectionChanged", metadata: metadata)

        guard UserDefaults.standard.bool(forKey: "debug_resumeTraceEnabled") else { return }
        print("[ResumeTrace] tabSelection changed from=\(oldValue) to=\(newValue)")
        #endif
    }

    private var tabShellSignature: String {
        [
            selectedSectionRaw,
            activePhoneSection?.rawValue ?? "none",
            loadedPhoneSections.map(\.rawValue).sorted().joined(separator: ","),
            mountedPhoneSections.map(\.rawValue).sorted().joined(separator: ","),
            activatingPhoneSections.map(\.rawValue).sorted().joined(separator: ","),
            AppSection.allCases.map { "\($0.rawValue):\(activationTokens[$0] ?? 0)" }.joined(separator: ",")
        ].joined(separator: "|")
    }

    private func shellMetadata() -> [String: String] {
        [
            "selectedTab": selectedSectionRaw,
            "activePhoneSection": activePhoneSection?.rawValue ?? "none",
            "loadedPhoneSections": loadedPhoneSections.map(\.rawValue).sorted().joined(separator: ","),
            "mountedPhoneSections": mountedPhoneSections.map(\.rawValue).sorted().joined(separator: ","),
            "activatingPhoneSections": activatingPhoneSections.map(\.rawValue).sorted().joined(separator: ",")
        ]
    }

    private func markActivationSettled(section: AppSection, token: Int) {
        if settledActivationTokens[section] == token {
            TabFlickerDiagnostics.markEvent(
                "duplicateTabActivationSettledPrevented",
                metadata: [
                    "tab": section.rawValue,
                    "token": String(token)
                ]
            )
            return
        }

        settledActivationTokens[section] = token
        TabFlickerDiagnostics.markEvent(
            "tabActivationSettled",
            metadata: [
                "tab": section.rawValue,
                "token": String(token)
            ]
        )
    }

    private func auditPhoneSectionEligibilityChanges(reason: String) {
        for section in AppSection.allCases {
            let signature = [
                loadedPhoneSections.contains(section) ? "loaded" : "notLoaded",
                mountedPhoneSections.contains(section) ? "mounted" : "notMounted",
                activePhoneSection == section ? "active" : "inactive",
                activatingPhoneSections.contains(section) ? "activating" : "notActivating"
            ].joined(separator: "|")

            if lastEligibilitySignatures[section] == signature {
                continue
            }

            lastEligibilitySignatures[section] = signature
            TabFlickerDiagnostics.markEvent(
                "tabSectionEligibilityChanged",
                metadata: [
                    "tab": section.rawValue,
                    "reason": reason,
                    "eligibility": signature
                ]
            )
        }
    }

    private func recordSharedRootInputChange(_ source: String) {
        pendingSharedInvalidationSources.insert(source)
        TabFlickerDiagnostics.markEvent(
            "sharedRootInputChanged",
            metadata: shellMetadata().merging(["source": source], uniquingKeysWith: { _, new in new })
        )

        guard sharedInvalidationWaveScheduled == false else { return }
        sharedInvalidationWaveScheduled = true
        DispatchQueue.main.async {
            let sources = pendingSharedInvalidationSources.sorted()
            pendingSharedInvalidationSources.removeAll()
            sharedInvalidationWaveScheduled = false
            TabFlickerDiagnostics.markEvent(
                "sharedInvalidationWave",
                metadata: shellMetadata().merging(
                    ["sources": sources.joined(separator: ",")],
                    uniquingKeysWith: { _, new in new }
                )
            )
        }
    }

}

private struct AppTabRootActivationReporter<Content: View>: View {
    let section: AppSection
    let content: Content

    @Environment(\.appTabActivationContext) private var tabActivationContext
    @State private var lastStartedToken: Int? = nil
    @State private var lastFinishedToken: Int? = nil

    init(section: AppSection, @ViewBuilder content: () -> Content) {
        self.section = section
        self.content = content()
    }

    var body: some View {
        content
            .onAppear {
                markActivationIfNeeded(for: tabActivationContext)
            }
            .onChange(of: tabActivationContext) { _, newValue in
                markActivationIfNeeded(for: newValue)
            }
    }

    private func markActivationIfNeeded(for context: AppTabActivationContext) {
        guard context.sectionRawValue == section.rawValue else { return }

        if context.phase == .activating, lastStartedToken != context.token {
            lastStartedToken = context.token
            TabFlickerDiagnostics.markEvent(
                "tabRootActivationStarted",
                metadata: [
                    "tab": section.rawValue,
                    "token": String(context.token)
                ]
            )
        } else if context.phase == .activating, lastStartedToken == context.token {
            TabFlickerDiagnostics.markEvent(
                "duplicateTabActivationStartedPrevented",
                metadata: [
                    "tab": section.rawValue,
                    "token": String(context.token)
                ]
            )
        }

        if context.phase == .active {
            guard lastFinishedToken != context.token else {
                TabFlickerDiagnostics.markEvent(
                    "duplicateTabActivationFinishedPrevented",
                    metadata: [
                        "tab": section.rawValue,
                        "token": String(context.token)
                    ]
                )
                return
            }
            lastFinishedToken = context.token
            TabFlickerDiagnostics.markEvent(
                "tabRootActivationFinished",
                metadata: [
                    "tab": section.rawValue,
                    "token": String(context.token)
                ]
            )
        }
    }
}

private struct TabShellBodyReporter: ViewModifier {
    let shell: String
    let signature: String
    let metadata: [String: String]

    @State private var renderCount: Int = 0

    func body(content: Content) -> some View {
        content
            .onAppear {
                emit(reason: "appear")
            }
            .onChange(of: signature) { _, _ in
                emit(reason: "signatureChanged")
            }
    }

    private func emit(reason: String) {
        renderCount += 1
        let eventMetadata = metadata.merging(
            [
                "shell": shell,
                "reason": reason,
                "renderCount": String(renderCount),
                "signature": signature
            ],
            uniquingKeysWith: { _, new in new }
        )
        TabFlickerDiagnostics.markEvent("tabShellBodyStarted", metadata: eventMetadata)
        DispatchQueue.main.async {
            TabFlickerDiagnostics.markEvent("tabShellBodyFinished", metadata: eventMetadata)
        }
    }
}

private extension View {
    func tabShellBodyReporter(
        shell: String,
        signature: String,
        metadata: [String: String]
    ) -> some View {
        modifier(TabShellBodyReporter(shell: shell, signature: signature, metadata: metadata))
    }
}
