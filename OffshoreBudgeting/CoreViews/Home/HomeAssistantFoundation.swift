//
//  HomeAssistantFoundation.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import SwiftUI
import SwiftData

// MARK: - Assistant State

enum HomeAssistantState: Equatable {
    case collapsed
    case presented
}

private enum HomeAssistantPlanResolutionSource: String {
    case parser
    case contextual
    case entityAware
}

// MARK: - Launcher Bar (iPhone)

struct HomeAssistantLauncherBar: View {
    let onTap: () -> Void

    var body: some View {
        if #available(iOS 26.0, *) {
            Button(action: onTap) {
                launcherLabel
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.capsule)
        } else {
            Button(action: onTap) {
                launcherLabel
                    .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(Color(uiColor: .separator).opacity(0.2), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var launcherLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "figure.wave")
                .font(.subheadline.weight(.semibold))

            Text("Marina")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            Image(systemName: "chevron.up")
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Presented Panel

struct HomeAssistantPanelView: View {
    private enum ScrollTarget {
        static let bottomAnchor = "assistant-bottom-anchor"
    }

    private enum HomeAssistantCreateEntityKind {
        case budget
        case income
        case card
        case preset
        case category
    }

    private enum HomeAssistantBudgetCreationStep {
        case cardsChoice
        case cardsSelection
        case presetsChoice
        case presetsSelection
    }

    private enum HomeAssistantCardStyleStep {
        case offer
        case themeSelection
        case effectSelection
    }

    private struct AssistantSubtitlePresentation {
        let narrative: String?
        let sources: String?
    }

    private enum EmptySuggestionGroup: String, CaseIterable, Identifiable {
        case budget
        case income
        case card
        case preset
        case category
        case trends

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .budget:
                return "chart.pie.fill"
            case .income:
                return "calendar"
            case .card:
                return "creditcard"
            case .preset:
                return "list.bullet.rectangle"
            case .category:
                return "tag.fill"
            case .trends:
                return "chart.line.uptrend.xyaxis"
            }
        }

        var title: String {
            switch self {
            case .budget:
                return "Budget Prompt Suggestions"
            case .income:
                return "Income Prompt Suggestions"
            case .card:
                return "Card Prompt Suggestions"
            case .preset:
                return "Preset Prompt Suggestions"
            case .category:
                return "Category Prompt Suggestions"
            case .trends:
                return "Trend Prompt Suggestions"
            }
        }
    }

    let workspace: Workspace
    let onDismiss: () -> Void
    let shouldUseLargeMinimumSize: Bool

    @Query private var categories: [Category]
    @Query private var cards: [Card]
    @Query private var presets: [Preset]
    @Query private var incomes: [Income]
    @Query private var assistantAliasRules: [AssistantAliasRule]
    @Query private var plannedExpenses: [PlannedExpense]
    @Query private var variableExpenses: [VariableExpense]

    @State private var answers: [HomeAnswer] = []
    @State private var promptText = ""
    @State private var pendingUserPromptForNextAnswer: String? = nil
    @State private var quickButtonsVisible = false
    @State private var followUpsCollapsed = false
    @State private var hasLoadedConversation = false
    private let selectedPersonaID: HomeAssistantPersonaID = .marina
    @State private var isShowingClearConversationAlert = false
    @State private var sessionContext = HomeAssistantSessionContext()
    @State private var clarificationSuggestions: [HomeAssistantSuggestion] = []
    @State private var lastClarificationReasons: [HomeAssistantClarificationReason] = []
    @State private var selectedEmptySuggestionGroup: EmptySuggestionGroup?
    @State private var personaSessionSeed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)
    @State private var personaCooldownSessionID: String = UUID().uuidString
    @State private var pendingExpenseCardPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingExpenseCardOptions: [Card] = []
    @State private var pendingPresetCardPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingIncomeKindPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingExpenseDisambiguationPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingIncomeDisambiguationPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingExpenseCandidates: [VariableExpense] = []
    @State private var pendingIncomeCandidates: [Income] = []
    @State private var pendingDeleteExpense: VariableExpense? = nil
    @State private var pendingDeleteIncome: Income? = nil
    @State private var pendingBudgetCreationPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingBudgetCreationStep: HomeAssistantBudgetCreationStep? = nil
    @State private var pendingBudgetSelectedCardIDs: Set<UUID> = []
    @State private var pendingBudgetSelectedPresetIDs: Set<UUID> = []
    @State private var pendingBudgetMatchingPresets: [Preset] = []
    @State private var pendingCategoryColorPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingCategoryColorHex: String? = nil
    @State private var pendingCategoryColorName: String? = nil
    @State private var pendingCardStyleCardName: String? = nil
    @State private var pendingCardStyleStep: HomeAssistantCardStyleStep? = nil
    @State private var pendingCardStyleTheme: CardThemeOption? = nil
    @State private var pendingPlannedExpenseAmountPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingPlannedExpenseAmountExpense: PlannedExpense? = nil
    @State private var pendingPlannedExpenseCandidates: [PlannedExpense] = []
    @FocusState private var isPromptFieldFocused: Bool
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue
    @AppStorage("general_confirmBeforeDeleting")
    private var confirmBeforeDeleting: Bool = true

    @Environment(\.modelContext) private var modelContext
    private let engine = HomeQueryEngine()
    private let parser = HomeAssistantTextParser()
    private let commandParser = HomeAssistantCommandParser()
    private let conversationStore = HomeAssistantConversationStore()
    private let telemetryStore = HomeAssistantTelemetryStore()
    private let entityMatcher = HomeAssistantEntityMatcher()
    private let aliasMatcher = HomeAssistantAliasMatcher()
    private let mutationService = HomeAssistantMutationService()

    private var personaFormatter: HomeAssistantPersonaFormatter {
        HomeAssistantPersonaFormatter(
            sessionSeed: personaSessionSeed,
            responseRules: .marina,
            cooldownSessionID: personaCooldownSessionID
        )
    }

    private var defaultQueryPeriodUnit: HomeQueryPeriodUnit {
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        return period.queryPeriodUnit
    }

    init(
        workspace: Workspace,
        onDismiss: @escaping () -> Void,
        shouldUseLargeMinimumSize: Bool
    ) {
        self.workspace = workspace
        self.onDismiss = onDismiss
        self.shouldUseLargeMinimumSize = shouldUseLargeMinimumSize

        let workspaceID = workspace.id

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )

        _plannedExpenses = Query(
            filter: #Predicate<PlannedExpense> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\PlannedExpense.expenseDate, order: .forward)]
        )

        _variableExpenses = Query(
            filter: #Predicate<VariableExpense> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\VariableExpense.transactionDate, order: .forward)]
        )

        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _presets = Query(
            filter: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Preset.title, order: .forward)]
        )

        _incomes = Query(
            filter: #Predicate<Income> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Income.date, order: .forward)]
        )

        _assistantAliasRules = Query(
            filter: #Predicate<AssistantAliasRule> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\AssistantAliasRule.updatedAt, order: .reverse)]
        )
    }

    var body: some View {
        let content = NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if answers.isEmpty {
                            ContentUnavailableView(
                                selectedPersonaProfile.displayName,
                                systemImage: "figure.wave",
                                description: Text(personaTransitionDescription)
                            )
                        } else {
                            answersSection
                        }

                        Color.clear
                            .frame(height: 1)
                            .id(ScrollTarget.bottomAnchor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(20)
                    .padding(.bottom, isPromptFieldFocused ? 170 : 96)
                }
                .scrollDismissesKeyboard(.interactively)
                .onTapGesture {
                    dismissEmptySuggestionDrawer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .navigationTitle("Marina")
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        bottomSuggestionRail
                        inputSection
                    }
                }
                .onChange(of: answers.count) { _, _ in
                    scrollToLatestMessage(using: proxy, animated: true)
                }
                .onChange(of: isPromptFieldFocused) { _, isFocused in
                    if isFocused {
                        dismissEmptySuggestionDrawer()
                        withAnimation(.easeOut(duration: 0.18)) {
                            quickButtonsVisible = true
                        }
                        scrollToLatestMessage(using: proxy, animated: true)
                    } else {
                        dismissEmptySuggestionDrawer()
                        withAnimation(.easeIn(duration: 0.16)) {
                            quickButtonsVisible = false
                        }
                    }
                }
                .onAppear {
                    quickButtonsVisible = isPromptFieldFocused
                    scrollToLatestMessage(using: proxy, animated: false)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Assistant")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingClearConversationAlert = true
                    } label: {
                        Text("Clear")
                            .padding()
                    }
                    .buttonStyle(.plain)
                    .disabled(answers.isEmpty)
                    .accessibilityLabel("Clear Chat")
                }
            }
        }
        .background {
            conversationBackdrop
                .ignoresSafeArea(.container, edges: .top)
        }
        .tint(Color("AccentColor"))
        .toolbarBackground(panelHeaderBackgroundStyle, for: .navigationBar)
        .toolbarBackground(navigationBarVisibility, for: .navigationBar)
        .alert("Are you sure you want to clear your chat history?", isPresented: $isShowingClearConversationAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearConversation()
            }
        }
        .onAppear {
            loadConversationIfNeeded()
        }

        if shouldUseLargeMinimumSize {
            content.frame(minWidth: 700, minHeight: 520)
        } else {
            content
        }
    }

    private var inputSection: some View {
        HStack(spacing: 8) {
            Menu {
                Section("Create New") {
                    Button {
                        handleCreateMenuSelection(.budget)
                    } label: {
                        Label("Budget", systemImage: "chart.pie.fill")
                    }

                    Button {
                        handleCreateMenuSelection(.income)
                    } label: {
                        Label("Income", systemImage: "calendar")
                    }

                    Button {
                        handleCreateMenuSelection(.card)
                    } label: {
                        Label("Card", systemImage: "creditcard")
                    }

                    Button {
                        handleCreateMenuSelection(.preset)
                    } label: {
                        Label("Preset", systemImage: "list.bullet.rectangle")
                    }

                    Button {
                        handleCreateMenuSelection(.category)
                    } label: {
                        Label("Category", systemImage: "tag.fill")
                    }
                }
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 33, height: 33)
            }
            .modifier(AssistantIconButtonModifier())
            .accessibilityLabel("Create New")

            promptTextField

            Button {
                submitPrompt()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 33, height: 33)
            }
            .modifier(AssistantIconButtonModifier())
            .disabled(trimmedPromptText.isEmpty)
            .accessibilityLabel("Submit Question")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func handleCreateMenuSelection(_ kind: HomeAssistantCreateEntityKind) {
        let guidance = creationGuidance(for: kind)
        appendMutationMessage(
            title: guidance.title,
            subtitle: guidance.subtitle,
            rows: guidance.rows
        )
        isPromptFieldFocused = true
    }

    private func creationGuidance(
        for kind: HomeAssistantCreateEntityKind
    ) -> (title: String, subtitle: String, rows: [HomeAnswerRow]) {
        switch kind {
        case .budget:
            return (
                title: "Create New Budget",
                subtitle: "Tell me the budget range (or month) and optional name. I will also help link cards and presets.",
                rows: [
                    HomeAnswerRow(title: "Example 1", value: "create budget for March 2026"),
                    HomeAnswerRow(title: "Example 2", value: "create budget named Spring Plan from 3/1/2026 to 3/31/2026 with all cards")
                ]
            )
        case .income:
            return (
                title: "Create New Income",
                subtitle: "Tell me amount, source, and whether it is planned or actual.",
                rows: [
                    HomeAnswerRow(title: "Example 1", value: "log income $1250 from Paycheck actual"),
                    HomeAnswerRow(title: "Example 2", value: "add planned income $800 for Freelance on 2/15/2026")
                ]
            )
        case .card:
            return (
                title: "Create New Card",
                subtitle: "Tell me the card name. You can also include theme and effect.",
                rows: [
                    HomeAnswerRow(title: "Example 1", value: "create card named Apple Card"),
                    HomeAnswerRow(title: "Example 2", value: "create card named Travel Card theme periwinkle effect glass")
                ]
            )
        case .preset:
            return (
                title: "Create New Preset",
                subtitle: "Tell me title, amount, and card (category optional).",
                rows: [
                    HomeAnswerRow(title: "Example 1", value: "create preset rent 1500 on Apple Card"),
                    HomeAnswerRow(title: "Example 2", value: "create preset named Internet $65 on Apple Card category Utilities")
                ]
            )
        case .category:
            return (
                title: "Create New Category",
                subtitle: "Tell me the category name and optional color.",
                rows: [
                    HomeAnswerRow(title: "Example 1", value: "add category groceries color forest green"),
                    HomeAnswerRow(title: "Example 2", value: "create category cafes color mauve")
                ]
            )
        }
    }

    @ViewBuilder
    private var promptTextField: some View {
        if #available(iOS 26.0, *) {
            TextField("Message Marina", text: $promptText)
                .textFieldStyle(.plain)
                .focused($isPromptFieldFocused)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(Color.white.opacity(0.28), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                }
                .onSubmit {
                    submitPrompt()
                }
        } else {
            TextField("Message Marina", text: $promptText)
                .textFieldStyle(.roundedBorder)
                .focused($isPromptFieldFocused)
                .frame(minHeight: 44)
                .onSubmit {
                    submitPrompt()
                }
        }
    }

    @ViewBuilder
    private var bottomSuggestionRail: some View {
        if isPromptFieldFocused || quickButtonsVisible {
            emptyStateSuggestionRail
        }
    }

    private var emptyStateSuggestionRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedGroup = selectedEmptySuggestionGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text(selectedGroup.title)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(emptyStateSuggestions(for: selectedGroup)) { suggestion in
                                Button {
                                    selectedEmptySuggestionGroup = nil
                                    runQuery(suggestion.query, userPrompt: suggestion.title)
                                } label: {
                                    Text(suggestion.title)
                                        .lineLimit(1)
                                        .padding(.horizontal, 12)
                                        .frame(height: 33)
                                }
                                .modifier(AssistantChipButtonModifier())
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(spacing: 0) {
                let groups = Array(EmptySuggestionGroup.allCases.enumerated())
                let maxIndex = max(0, groups.count - 1)

                ForEach(groups, id: \.element.id) { index, group in
                    Button {
                        selectedEmptySuggestionGroup = selectedEmptySuggestionGroup == group ? nil : group
                    } label: {
                        Image(systemName: group.iconName)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 33, height: 33)
                    }
                    .modifier(AssistantIconButtonModifier())
                    .opacity(quickButtonsVisible ? 1 : 0)
                    .scaleEffect(quickButtonsVisible ? 1 : 0.94, anchor: .leading)
                    .offset(x: quickButtonsVisible ? 0 : -CGFloat((maxIndex - index) * 6))
                    .animation(quickButtonAccordionAnimation(for: index), value: quickButtonsVisible)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(group.title)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
        }
        .padding(.top, 10)
        .animation(.easeInOut(duration: 0.2), value: selectedEmptySuggestionGroup)
    }

    private func inlineConversationSuggestions(for answer: HomeAnswer) -> [HomeAssistantSuggestion] {
        if clarificationSuggestions.isEmpty == false {
            return clarificationSuggestions
        }

        let followUps = personaFormatter.followUpSuggestions(
            after: answer,
            personaID: selectedPersonaID
        )
        if followUps.isEmpty == false {
            return followUps
        }

        return []
    }

    private func emptyStateSuggestions(for group: EmptySuggestionGroup) -> [HomeAssistantSuggestion] {
        switch group {
        case .budget:
            return [
                HomeAssistantSuggestion(title: "How am I doing this month?", query: HomeQuery(intent: .periodOverview)),
                HomeAssistantSuggestion(title: "Spend this month", query: HomeQuery(intent: .spendThisMonth)),
                HomeAssistantSuggestion(title: "Compare with last month", query: HomeQuery(intent: .compareThisMonthToPreviousMonth)),
                HomeAssistantSuggestion(title: "How am I doing with savings?", query: HomeQuery(intent: .savingsStatus))
            ]
        case .income:
            return [
                HomeAssistantSuggestion(title: "Average actual income this year", query: HomeQuery(intent: .incomeAverageActual)),
                HomeAssistantSuggestion(title: "Income share by source this month", query: HomeQuery(intent: .incomeSourceShare)),
                HomeAssistantSuggestion(title: "Income share trend (last 4 months)", query: HomeQuery(intent: .incomeSourceShareTrend, resultLimit: 4, periodUnit: .month)),
                HomeAssistantSuggestion(title: "Savings average (last 4 periods)", query: HomeQuery(intent: .savingsAverageRecentPeriods, resultLimit: 4, periodUnit: defaultQueryPeriodUnit))
            ]
        case .card:
            return [
                HomeAssistantSuggestion(title: "Card spend total this month", query: HomeQuery(intent: .cardSpendTotal)),
                HomeAssistantSuggestion(title: "Variable spending habits by card", query: HomeQuery(intent: .cardVariableSpendingHabits)),
                HomeAssistantSuggestion(title: "Largest recent transactions", query: HomeQuery(intent: .largestRecentTransactions)),
                HomeAssistantSuggestion(title: "Spend this month", query: HomeQuery(intent: .spendThisMonth))
            ]
        case .preset:
            return [
                HomeAssistantSuggestion(title: "Do I have presets due soon?", query: HomeQuery(intent: .presetDueSoon)),
                HomeAssistantSuggestion(title: "Most expensive preset", query: HomeQuery(intent: .presetHighestCost)),
                HomeAssistantSuggestion(title: "Top preset category", query: HomeQuery(intent: .presetTopCategory)),
                HomeAssistantSuggestion(title: "Preset spend by category", query: HomeQuery(intent: .presetCategorySpend))
            ]
        case .category:
            return [
                HomeAssistantSuggestion(title: "Top categories this month", query: HomeQuery(intent: .topCategoriesThisMonth)),
                HomeAssistantSuggestion(title: "Category spend share this month", query: HomeQuery(intent: .categorySpendShare)),
                HomeAssistantSuggestion(title: "Potential savings by category", query: HomeQuery(intent: .categoryPotentialSavings)),
                HomeAssistantSuggestion(title: "Category reallocation guidance", query: HomeQuery(intent: .categoryReallocationGuidance))
            ]
        case .trends:
            return [
                HomeAssistantSuggestion(title: "Compare with last month", query: HomeQuery(intent: .compareThisMonthToPreviousMonth)),
                HomeAssistantSuggestion(title: "Income share trend (last 4 months)", query: HomeQuery(intent: .incomeSourceShareTrend, resultLimit: 4, periodUnit: .month)),
                HomeAssistantSuggestion(title: "Category share trend (last 4 months)", query: HomeQuery(intent: .categorySpendShareTrend, resultLimit: 4, periodUnit: .month)),
                HomeAssistantSuggestion(title: "Savings average (last 6 periods)", query: HomeQuery(intent: .savingsAverageRecentPeriods, resultLimit: 6, periodUnit: defaultQueryPeriodUnit))
            ]
        }
    }

    private var activeSuggestionHeaderTitle: String {
        if clarificationSuggestions.isEmpty == false {
            return lastClarificationReasons.isEmpty
                ? "Clarify"
                : "Clarify (\(lastClarificationReasons.count))"
        }

        if answers.isEmpty {
            return "Suggested Questions"
        }

        return "Follow-Up Suggestions"
    }

    private var selectedPersonaProfile: HomeAssistantPersonaProfile {
        HomeAssistantPersonaCatalog.profile(for: selectedPersonaID)
    }

    private var emptyStatePersonaIntroduction: String {
        personaTransitionDescription
    }

    private var personaTransitionDescription: String {
        "I’ll help you stay encouraged and grounded with quick, practical reads on your spending and trends."
    }

    private func dismissEmptySuggestionDrawer() {
        guard selectedEmptySuggestionGroup != nil else { return }
        selectedEmptySuggestionGroup = nil
    }

    private var answersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(answers.enumerated()), id: \.element.id) { index, answer in
                VStack(alignment: .leading, spacing: 10) {
                    if let userPrompt = answer.userPrompt, userPrompt.isEmpty == false {
                        userMessageBubble(text: userPrompt, generatedAt: answer.generatedAt)
                    }

                    assistantMessageBubble(for: answer)

                    if index == answers.count - 1, selectedEmptySuggestionGroup == nil {
                        let followUps = inlineConversationSuggestions(for: answer)
                        if followUps.isEmpty == false {
                            assistantFollowUpRail(suggestions: followUps)
                        }
                    }
                }
            }
        }
    }

    private func assistantFollowUpRail(suggestions: [HomeAssistantSuggestion]) -> some View {
        let isClarificationRail = clarificationSuggestions.isEmpty == false

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(activeSuggestionHeaderTitle)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if isClarificationRail == false {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            followUpsCollapsed.toggle()
                        }
                    } label: {
                        Image(systemName: followUpsCollapsed ? "ellipsis.message.fill" : "xmark")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    }
                    .accessibilityLabel(followUpsCollapsed ? "Show follow-up suggestions" : "Hide follow-up suggestions")
                }
            }

            if isClarificationRail || followUpsCollapsed == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(suggestions) { suggestion in
                            Button {
                                runQuery(suggestion.query, userPrompt: suggestion.title)
                            } label: {
                                Text(suggestion.title)
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .frame(height: 33)
                            }
                            .modifier(AssistantChipButtonModifier())
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
    }

    private func userMessageBubble(text: String, generatedAt: Date) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack {
                Spacer(minLength: 24)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            Text(timestampText(for: generatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func assistantMessageBubble(for answer: HomeAnswer) -> some View {
        let subtitlePresentation = assistantSubtitlePresentation(for: answer.subtitle)

        return VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 8) {
                Text(answer.title)
                    .font(.subheadline.weight(.semibold))

                if let primaryValue = answer.primaryValue {
                    Text(primaryValue)
                        .font(.title2.weight(.bold))
                }

                if let narrative = subtitlePresentation.narrative {
                    Text(narrative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if answer.rows.isEmpty == false {
                    ForEach(answer.rows) { row in
                        HStack {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(row.value)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let sources = subtitlePresentation.sources {
                    Divider()
                        .padding(.top, 2)
                    Text("Sources: \(sources)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(assistantBubbleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(assistantBubbleStroke, lineWidth: 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timestampText(for: answer.generatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func assistantSubtitlePresentation(for subtitle: String?) -> AssistantSubtitlePresentation {
        guard let subtitle else {
            return AssistantSubtitlePresentation(narrative: nil, sources: nil)
        }

        let bodyWithoutTechnicalFooter = subtitle
            .components(separatedBy: "\n\n---\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard bodyWithoutTechnicalFooter.isEmpty == false else {
            return AssistantSubtitlePresentation(narrative: nil, sources: nil)
        }

        guard let sourcesRange = bodyWithoutTechnicalFooter.range(of: "Sources:", options: .backwards) else {
            return AssistantSubtitlePresentation(
                narrative: bodyWithoutTechnicalFooter,
                sources: nil
            )
        }

        let narrative = String(bodyWithoutTechnicalFooter[..<sourcesRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sources = String(bodyWithoutTechnicalFooter[sourcesRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return AssistantSubtitlePresentation(
            narrative: narrative.isEmpty ? nil : narrative,
            sources: sources.isEmpty ? nil : sources
        )
    }

    private func runQuery(
        _ query: HomeQuery,
        userPrompt: String?,
        confidenceBand: HomeQueryConfidenceBand = .high
    ) {
        clarificationSuggestions = []
        lastClarificationReasons = []

        let baseAnswer = engine.execute(
            query: query,
            categories: categories,
            presets: presets,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            incomes: incomes
        )

        let rawAnswer = applyConfidenceTone(to: baseAnswer, confidenceBand: confidenceBand)
        let titledAnswer = applyPromptAwareTitle(
            to: rawAnswer,
            query: query,
            userPrompt: userPrompt
        )

        let answer = personaFormatter.styledAnswer(
            from: titledAnswer,
            userPrompt: userPrompt,
            personaID: selectedPersonaID,
            seedContext: personaSeedContext(for: query),
            footerContext: personaFooterContext(for: [query]),
            echoContext: personaEchoContext(for: query)
        )

        updateSessionContext(after: query)
        appendAnswer(answer)
    }

    private func submitPrompt() {
        let prompt = trimmedPromptText
        guard prompt.isEmpty == false else { return }
        pendingUserPromptForNextAnswer = prompt

        defer { promptText = "" }

        if resolvePendingMutationTurn(with: prompt) {
            return
        }

        if let explainPrompt = planExplainPrompt(from: prompt) {
            appendAnswer(planExplanationAnswer(for: explainPrompt))
            return
        }

        if handleConversationalPrompt(prompt) {
            return
        }

        if handleUnsupportedPrompt(prompt) {
            return
        }

        if commandParser.isCardCrudPrompt(prompt) {
            appendMutationMessage(
                title: "Card CRUD is not in this phase",
                subtitle: "For now, I can perform expense and income CRUD from Home. Card edits/deletes still run through Cards.",
                rows: []
            )
            return
        }

        if let command = commandParser.parse(prompt, defaultPeriodUnit: defaultQueryPeriodUnit) {
            handleCommandPlan(command, rawPrompt: prompt)
            return
        }

        if let resolved = resolvedPlan(for: prompt) {
            handleResolvedPlan(
                resolved.plan,
                rawPrompt: prompt,
                allowsBroadBundle: resolved.source == .parser,
                source: resolved.source
            )
            return
        }

        clarificationSuggestions = []
        lastClarificationReasons = []
        recordTelemetry(
            for: prompt,
            outcome: .unresolved,
            source: nil,
            plan: nil,
            notes: "no_plan_resolved"
        )
        appendAnswer(personaFormatter.unresolvedPromptAnswer(for: prompt, personaID: selectedPersonaID))
    }

    private func handleConversationalPrompt(_ prompt: String) -> Bool {
        let normalized = normalizedPrompt(prompt)
        let tokens = normalized.split(separator: " ").map(String.init)
        let firstToken = tokens.first ?? ""
        let greetingTokens: Set<String> = ["hi", "hello", "hey"]
        let greetingPhrases = [
            "how are you",
            "how s it going",
            "how are you doing",
            "what s up",
            "whats up",
            "good morning",
            "good afternoon",
            "good evening"
        ]

        let isDirectGreeting = greetingTokens.contains(firstToken) && tokens.count <= 3
        if isDirectGreeting || greetingPhrases.contains(where: { normalized.contains($0) }) {
            appendAnswer(personaFormatter.greetingAnswer(for: selectedPersonaID))
            return true
        }
        return false
    }

    private func handleUnsupportedPrompt(_ prompt: String) -> Bool {
        let normalized = normalizedPrompt(prompt)
        if normalized.contains("archive") && normalized.contains("budget") {
            appendMutationMessage(
                title: "Archive isn't available yet",
                subtitle: "Do you want to delete that budget instead?",
                rows: []
            )
            return true
        }

        if normalized.contains("split") && normalized.contains("expense") && normalized.contains("category") {
            appendMutationMessage(
                title: "Split expense isn't available yet",
                subtitle: "I can still move the expense to one category. Tell me the expense details and target category.",
                rows: []
            )
            return true
        }

        return false
    }

    private func handleCommandPlan(
        _ command: HomeAssistantCommandPlan,
        rawPrompt: String
    ) {
        clarificationSuggestions = []
        lastClarificationReasons = []

        switch command.intent {
        case .addExpense:
            handleAddExpenseCommand(command)
        case .addIncome:
            handleAddIncomeCommand(command)
        case .addBudget:
            handleAddBudgetCommand(command)
        case .addCard:
            handleAddCardCommand(command)
        case .addPreset:
            handleAddPresetCommand(command)
        case .addCategory:
            handleAddCategoryCommand(command)
        case .editExpense:
            handleEditExpenseCommand(command)
        case .deleteExpense:
            handleDeleteExpenseCommand(command)
        case .editIncome:
            handleEditIncomeCommand(command)
        case .deleteIncome:
            handleDeleteIncomeCommand(command)
        case .markIncomeReceived:
            handleMarkIncomeReceivedCommand(command)
        case .moveExpenseCategory:
            handleMoveExpenseCategoryCommand(command)
        case .updatePlannedExpenseAmount:
            handleUpdatePlannedExpenseAmountCommand(command)
        case .deleteLastExpense:
            handleDeleteLastExpenseCommand(command)
        case .deleteLastIncome:
            handleDeleteLastIncomeCommand(command)
        }

        recordTelemetry(
            for: rawPrompt,
            outcome: .resolved,
            source: nil,
            plan: nil,
            notes: "mutation_\(command.intent.rawValue)"
        )
    }

    private func resolvePendingMutationTurn(with prompt: String) -> Bool {
        if pendingCategoryColorPlan != nil {
            resolveCategoryColorConfirmation(with: prompt)
            return true
        }

        if pendingCardStyleStep != nil {
            resolveCardStyleSelection(with: prompt)
            return true
        }

        if pendingBudgetCreationPlan != nil {
            resolveBudgetCreationStep(with: prompt)
            return true
        }

        if pendingDeleteExpense != nil || pendingDeleteIncome != nil {
            resolveDeleteConfirmation(with: prompt)
            return true
        }

        if pendingExpenseCandidates.isEmpty == false {
            resolveExpenseDisambiguation(with: prompt)
            return true
        }

        if pendingPlannedExpenseCandidates.isEmpty == false {
            resolvePlannedExpenseDisambiguation(with: prompt)
            return true
        }

        if pendingIncomeCandidates.isEmpty == false {
            resolveIncomeDisambiguation(with: prompt)
            return true
        }

        if pendingExpenseCardPlan != nil {
            resolveExpenseCardSelection(with: prompt)
            return true
        }

        if pendingPresetCardPlan != nil {
            resolvePresetCardSelection(with: prompt)
            return true
        }

        if pendingIncomeKindPlan != nil {
            resolveIncomeKindSelection(with: prompt)
            return true
        }

        if pendingPlannedExpenseAmountPlan != nil && pendingPlannedExpenseAmountExpense != nil {
            resolvePlannedExpenseAmountTarget(with: prompt)
            return true
        }

        return false
    }

    private func handleAddExpenseCommand(_ command: HomeAssistantCommandPlan) {
        guard let amount = command.amount, amount > 0 else {
            appendMutationMessage(
                title: "Need expense amount",
                subtitle: "Tell me the amount to log, like: log $25 for Starbucks.",
                rows: []
            )
            return
        }

        let notes = (command.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard notes.isEmpty == false else {
            appendMutationMessage(
                title: "Need expense description",
                subtitle: "Tell me where or what this expense is for.",
                rows: []
            )
            return
        }

        if let cardName = command.cardName,
           resolveCard(from: cardName) != nil {
            executeAddExpense(command)
            return
        }

        pendingExpenseCardPlan = command
        pendingExpenseCardOptions = cards
        presentCardSelectionPrompt(for: command)
    }

    private func handleAddIncomeCommand(_ command: HomeAssistantCommandPlan) {
        guard let amount = command.amount, amount > 0 else {
            appendMutationMessage(
                title: "Need income amount",
                subtitle: "Tell me the amount to log, like: log income $1,250.",
                rows: []
            )
            return
        }

        let source = (command.source ?? command.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.isEmpty == false else {
            appendMutationMessage(
                title: "Need income source",
                subtitle: "Tell me where this income came from.",
                rows: []
            )
            return
        }

        guard command.isPlannedIncome != nil else {
            pendingIncomeKindPlan = command
            appendMutationMessage(
                title: "Quick clarification",
                subtitle: "Should I log this income as planned or actual?",
                rows: [
                    HomeAnswerRow(title: "1", value: "Planned"),
                    HomeAnswerRow(title: "2", value: "Actual")
                ]
            )
            return
        }

        executeAddIncome(command)
    }

    private func handleAddBudgetCommand(_ command: HomeAssistantCommandPlan) {
        pendingBudgetCreationPlan = command
        pendingBudgetSelectedCardIDs = []
        pendingBudgetSelectedPresetIDs = []
        pendingBudgetMatchingPresets = matchingPresets(for: command)

        if let attachAllCards = command.attachAllCards {
            pendingBudgetSelectedCardIDs = attachAllCards ? Set(cards.map(\.id)) : []
            if let attachAllPresets = command.attachAllPresets {
                pendingBudgetSelectedPresetIDs = attachAllPresets ? Set(pendingBudgetMatchingPresets.map(\.id)) : []
                executePendingBudgetCreation(plan: command)
                return
            }
            pendingBudgetCreationStep = .presetsChoice
            presentBudgetPresetsChoicePrompt()
            return
        }

        pendingBudgetCreationStep = .cardsChoice
        presentBudgetCardsChoicePrompt()
    }

    private func handleAddCardCommand(_ command: HomeAssistantCommandPlan) {
        let name = (command.entityName ?? command.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            appendMutationMessage(
                title: "Need card name",
                subtitle: "Tell me the card name to create.",
                rows: []
            )
            return
        }

        do {
            let result = try mutationService.addCard(
                name: name,
                themeRaw: command.cardThemeRaw,
                effectRaw: command.cardEffectRaw,
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)

            if command.cardThemeRaw == nil || command.cardEffectRaw == nil {
                pendingCardStyleCardName = name
                pendingCardStyleStep = .offer
                appendMutationMessage(
                    title: "Want to style this card?",
                    subtitle: "Reply yes and I can show themes and effects, or no to keep defaults.",
                    rows: []
                )
            }
        } catch {
            appendMutationMessage(
                title: "Could not create card",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func handleAddPresetCommand(_ command: HomeAssistantCommandPlan) {
        guard let amount = command.amount, amount > 0 else {
            appendMutationMessage(
                title: "Need preset amount",
                subtitle: "Tell me the planned amount for this preset.",
                rows: []
            )
            return
        }

        let title = (command.entityName ?? command.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else {
            appendMutationMessage(
                title: "Need preset title",
                subtitle: "Tell me the preset title to create.",
                rows: []
            )
            return
        }

        if let cardName = command.cardName,
           resolveCard(from: cardName) != nil {
            executeAddPreset(command)
            return
        }

        pendingPresetCardPlan = command
        presentPresetCardSelectionPrompt()
    }

    private func handleAddCategoryCommand(_ command: HomeAssistantCommandPlan) {
        let name = (command.entityName ?? command.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            appendMutationMessage(
                title: "Need category name",
                subtitle: "Tell me the category name to create.",
                rows: []
            )
            return
        }

        let colorResolution = MarinaColorResolver.resolve(
            rawPrompt: command.rawPrompt,
            parserHex: command.categoryColorHex,
            parserName: command.categoryColorName
        )

        if colorResolution.requiresConfirmation {
            pendingCategoryColorPlan = command
            pendingCategoryColorHex = colorResolution.hex
            pendingCategoryColorName = colorResolution.name
            appendMutationMessage(
                title: "Quick clarification",
                subtitle: "I mapped that color to \(colorResolution.name) (\(colorResolution.hex)). Reply yes to use it or no to keep default blue.",
                rows: []
            )
            return
        }

        do {
            let result = try mutationService.addCategory(
                name: name,
                colorHex: colorResolution.hex,
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not create category",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func handleEditExpenseCommand(_ command: HomeAssistantCommandPlan) {
        guard command.amount != nil || command.date != nil || command.notes != nil else {
            appendMutationMessage(
                title: "Need edit details",
                subtitle: "Tell me what to change for the expense, like amount or date.",
                rows: []
            )
            return
        }

        let matches = mutationService.matchedExpenses(for: command, expenses: variableExpenses)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching expense found",
                subtitle: "Try adding a date, amount, or description so I can find the right entry.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingExpenseDisambiguationPlan = command
            pendingExpenseCandidates = Array(matches.prefix(3))
            presentExpenseDisambiguationPrompt()
            return
        }

        executeExpenseEdit(matches[0], using: command)
    }

    private func handleDeleteExpenseCommand(_ command: HomeAssistantCommandPlan) {
        let matches = mutationService.matchedExpenses(for: command, expenses: variableExpenses)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching expense found",
                subtitle: "Try adding a date, amount, or description so I can find the right entry.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingExpenseDisambiguationPlan = command
            pendingExpenseCandidates = Array(matches.prefix(3))
            presentExpenseDisambiguationPrompt()
            return
        }

        executeExpenseDelete(matches[0])
    }

    private func handleEditIncomeCommand(_ command: HomeAssistantCommandPlan) {
        guard command.amount != nil || command.date != nil || command.source != nil else {
            appendMutationMessage(
                title: "Need edit details",
                subtitle: "Tell me what to change for the income entry, like amount or date.",
                rows: []
            )
            return
        }

        let matches = mutationService.matchedIncomes(for: command, incomes: incomes)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching income found",
                subtitle: "Try adding a date, amount, or source so I can find the right entry.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingIncomeDisambiguationPlan = command
            pendingIncomeCandidates = Array(matches.prefix(3))
            presentIncomeDisambiguationPrompt()
            return
        }

        executeIncomeEdit(matches[0], using: command)
    }

    private func handleDeleteIncomeCommand(_ command: HomeAssistantCommandPlan) {
        let matches = mutationService.matchedIncomes(for: command, incomes: incomes)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching income found",
                subtitle: "Try adding a date, amount, or source so I can find the right entry.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingIncomeDisambiguationPlan = command
            pendingIncomeCandidates = Array(matches.prefix(3))
            presentIncomeDisambiguationPrompt()
            return
        }

        executeIncomeDelete(matches[0])
    }

    private func handleMarkIncomeReceivedCommand(_ command: HomeAssistantCommandPlan) {
        let matches = mutationService
            .matchedIncomes(for: command, incomes: incomes)
            .filter(\.isPlanned)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No planned income found",
                subtitle: "Try adding a source or date so I can find the planned income entry.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingIncomeDisambiguationPlan = command
            pendingIncomeCandidates = Array(matches.prefix(3))
            presentIncomeDisambiguationPrompt()
            return
        }

        executeMarkIncomeReceived(matches[0])
    }

    private func handleMoveExpenseCategoryCommand(_ command: HomeAssistantCommandPlan) {
        guard let categoryName = command.categoryName,
              let category = resolveCategory(from: categoryName) else {
            appendMutationMessage(
                title: "Need target category",
                subtitle: "Tell me which category this expense should move to.",
                rows: []
            )
            return
        }

        let matches = mutationService.matchedExpenses(for: command, expenses: variableExpenses)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching expense found",
                subtitle: "Add a date, amount, or description so I can find the expense to move.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingExpenseDisambiguationPlan = command
            pendingExpenseCandidates = Array(matches.prefix(3))
            presentExpenseDisambiguationPrompt()
            return
        }

        executeMoveExpenseCategory(matches[0], category: category)
    }

    private func handleUpdatePlannedExpenseAmountCommand(_ command: HomeAssistantCommandPlan) {
        guard let amount = command.amount, amount > 0 else {
            appendMutationMessage(
                title: "Need planned expense amount",
                subtitle: "Tell me the amount to update, like: update rent to $1,450.",
                rows: []
            )
            return
        }

        let matches = mutationService.matchedPlannedExpenses(for: command, plannedExpenses: plannedExpenses)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching planned expense found",
                subtitle: "Try adding the title or date so I can find the planned expense.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingPlannedExpenseAmountPlan = command
            pendingPlannedExpenseCandidates = Array(matches.prefix(3))
            presentPlannedExpenseDisambiguationPrompt()
            return
        }

        guard let target = command.plannedExpenseAmountTarget else {
            pendingPlannedExpenseAmountPlan = command
            pendingPlannedExpenseAmountExpense = matches[0]
            presentPlannedExpenseAmountTargetPrompt()
            return
        }

        executePlannedExpenseAmountUpdate(matches[0], amount: amount, target: target)
    }

    private func handleDeleteLastExpenseCommand(_ command: HomeAssistantCommandPlan) {
        let candidates = Array(variableExpenses.sorted(by: { $0.transactionDate > $1.transactionDate }).prefix(3))
        guard candidates.isEmpty == false else {
            appendMutationMessage(
                title: "No expenses to delete",
                subtitle: "You don't have any expenses yet.",
                rows: []
            )
            return
        }

        pendingExpenseDisambiguationPlan = command
        pendingExpenseCandidates = candidates
        appendMutationMessage(
            title: "Quick clarification",
            subtitle: "Pick the expense to delete.",
            rows: candidates.enumerated().map { index, expense in
                HomeAnswerRow(title: "\(index + 1)", value: expenseDisplayLabel(expense))
            }
        )
    }

    private func handleDeleteLastIncomeCommand(_ command: HomeAssistantCommandPlan) {
        let candidates = Array(incomes.sorted(by: { $0.date > $1.date }).prefix(3))
        guard candidates.isEmpty == false else {
            appendMutationMessage(
                title: "No income entries to delete",
                subtitle: "You don't have any income entries yet.",
                rows: []
            )
            return
        }

        pendingIncomeDisambiguationPlan = command
        pendingIncomeCandidates = candidates
        appendMutationMessage(
            title: "Quick clarification",
            subtitle: "Pick the income entry to delete.",
            rows: candidates.enumerated().map { index, income in
                HomeAnswerRow(title: "\(index + 1)", value: incomeDisplayLabel(income))
            }
        )
    }

    private func executeAddExpense(_ command: HomeAssistantCommandPlan) {
        guard
            let amount = command.amount,
            let notes = command.notes,
            let selectedCard = resolveCard(from: command.cardName)
        else {
            appendMutationMessage(
                title: "Need a card to log this expense",
                subtitle: "Pick one of your cards and I will finish logging it.",
                rows: []
            )
            return
        }

        let date = calendarStartOfDay(command.date ?? Date())
        let category = resolveCategory(from: command.categoryName)

        do {
            let result = try mutationService.addExpense(
                amount: amount,
                notes: notes,
                date: date,
                card: selectedCard,
                category: category,
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not log expense",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func executeAddIncome(_ command: HomeAssistantCommandPlan) {
        guard let amount = command.amount else {
            appendMutationMessage(
                title: "Need income amount",
                subtitle: "Tell me how much income to log.",
                rows: []
            )
            return
        }

        let source = (command.source ?? command.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard source.isEmpty == false else {
            appendMutationMessage(
                title: "Need income source",
                subtitle: "Tell me where this income came from.",
                rows: []
            )
            return
        }

        guard let isPlanned = command.isPlannedIncome else {
            appendMutationMessage(
                title: "Need income type",
                subtitle: "Tell me if this should be planned or actual.",
                rows: []
            )
            return
        }

        let date = calendarStartOfDay(command.date ?? Date())

        do {
            let result = try mutationService.addIncome(
                amount: amount,
                source: source,
                date: date,
                isPlanned: isPlanned,
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not log income",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func executeAddPreset(_ command: HomeAssistantCommandPlan) {
        guard let amount = command.amount, amount > 0 else {
            appendMutationMessage(
                title: "Need preset amount",
                subtitle: "Tell me the planned amount for this preset.",
                rows: []
            )
            return
        }

        let title = (command.entityName ?? command.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else {
            appendMutationMessage(
                title: "Need preset title",
                subtitle: "Tell me the preset title.",
                rows: []
            )
            return
        }

        guard let card = resolveCard(from: command.cardName) else {
            appendMutationMessage(
                title: "Need a card for this preset",
                subtitle: "Pick which card should be the default.",
                rows: []
            )
            return
        }

        let category = resolveCategory(from: command.categoryName)

        do {
            let result = try mutationService.addPreset(
                title: title,
                plannedAmount: amount,
                card: card,
                category: category,
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not create preset",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func executeExpenseEdit(_ expense: VariableExpense, using command: HomeAssistantCommandPlan) {
        do {
            let result = try mutationService.editExpense(
                expense,
                command: command,
                card: resolveCard(from: command.cardName),
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not edit expense",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func executeIncomeEdit(_ income: Income, using command: HomeAssistantCommandPlan) {
        do {
            let result = try mutationService.editIncome(
                income,
                command: command,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not edit income",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func executeExpenseDelete(_ expense: VariableExpense) {
        if confirmBeforeDeleting {
            pendingDeleteExpense = expense
            appendMutationMessage(
                title: "Confirm delete",
                subtitle: "Delete this expense? Reply with yes to confirm or no to cancel.",
                rows: [HomeAnswerRow(title: "Expense", value: expenseDisplayLabel(expense))]
            )
            return
        }

        do {
            let result = try mutationService.deleteExpense(expense, modelContext: modelContext)
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not delete expense", subtitle: error.localizedDescription, rows: [])
        }
    }

    private func executeIncomeDelete(_ income: Income) {
        if confirmBeforeDeleting {
            pendingDeleteIncome = income
            appendMutationMessage(
                title: "Confirm delete",
                subtitle: "Delete this income entry? Reply with yes to confirm or no to cancel.",
                rows: [HomeAnswerRow(title: "Income", value: incomeDisplayLabel(income))]
            )
            return
        }

        do {
            let result = try mutationService.deleteIncome(income, modelContext: modelContext)
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not delete income", subtitle: error.localizedDescription, rows: [])
        }
    }

    private func executeMarkIncomeReceived(_ income: Income) {
        guard income.isPlanned else {
            appendMutationMessage(
                title: "Income already actual",
                subtitle: "That income entry is already marked as actual.",
                rows: []
            )
            return
        }

        do {
            let result = try mutationService.addIncome(
                amount: income.amount,
                source: income.source,
                date: income.date,
                isPlanned: false,
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(
                title: "Income marked as received",
                subtitle: result.subtitle,
                rows: result.rows
            )
        } catch {
            appendMutationMessage(
                title: "Could not mark income as received",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func executeMoveExpenseCategory(_ expense: VariableExpense, category: Category) {
        do {
            let result = try mutationService.moveExpenseCategory(
                expense: expense,
                category: category,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not move expense category",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func executePlannedExpenseAmountUpdate(
        _ expense: PlannedExpense,
        amount: Double,
        target: HomeAssistantPlannedExpenseAmountTarget
    ) {
        do {
            let result = try mutationService.updatePlannedExpenseAmount(
                expense: expense,
                amount: amount,
                target: target,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not update planned expense",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func presentPlannedExpenseAmountTargetPrompt() {
        appendMutationMessage(
            title: "Quick clarification",
            subtitle: "Should I update the planned amount or the actual amount?",
            rows: [
                HomeAnswerRow(title: "1", value: "Planned amount"),
                HomeAnswerRow(title: "2", value: "Actual amount")
            ]
        )
    }

    private func resolveExpenseCardSelection(with prompt: String) {
        guard var plan = pendingExpenseCardPlan else { return }
        guard pendingExpenseCardOptions.isEmpty == false else {
            clearMutationPendingState()
            appendMutationMessage(title: "No cards available", subtitle: "Add a card first, then try this again.", rows: [])
            return
        }

        let selected: Card?
        if let index = Int(prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
           index >= 1,
           index <= pendingExpenseCardOptions.count {
            selected = pendingExpenseCardOptions[index - 1]
        } else if let match = entityMatcher.bestCardMatch(in: prompt, cards: pendingExpenseCardOptions) {
            selected = pendingExpenseCardOptions.first { $0.name == match }
        } else {
            selected = nil
        }

        guard let selected else {
            presentCardSelectionPrompt(for: plan)
            return
        }

        plan = HomeAssistantCommandPlan(
            intent: plan.intent,
            confidenceBand: plan.confidenceBand,
            rawPrompt: plan.rawPrompt,
            amount: plan.amount,
            originalAmount: plan.originalAmount,
            date: plan.date,
            dateRange: plan.dateRange,
            notes: plan.notes,
            source: plan.source,
            cardName: selected.name,
            categoryName: plan.categoryName,
            entityName: plan.entityName,
            isPlannedIncome: plan.isPlannedIncome
        )

        pendingExpenseCardPlan = nil
        pendingExpenseCardOptions = []
        executeAddExpense(plan)
    }

    private func resolveIncomeKindSelection(with prompt: String) {
        guard var plan = pendingIncomeKindPlan else { return }

        let normalized = prompt.lowercased()
        let resolved: Bool?
        if normalized.contains("planned") || normalized == "1" {
            resolved = true
        } else if normalized.contains("actual") || normalized == "2" {
            resolved = false
        } else {
            resolved = nil
        }

        guard let resolved else {
            appendMutationMessage(
                title: "Quick clarification",
                subtitle: "Reply planned or actual.",
                rows: [
                    HomeAnswerRow(title: "1", value: "Planned"),
                    HomeAnswerRow(title: "2", value: "Actual")
                ]
            )
            return
        }

        plan = HomeAssistantCommandPlan(
            intent: plan.intent,
            confidenceBand: plan.confidenceBand,
            rawPrompt: plan.rawPrompt,
            amount: plan.amount,
            originalAmount: plan.originalAmount,
            date: plan.date,
            dateRange: plan.dateRange,
            notes: plan.notes,
            source: plan.source,
            cardName: plan.cardName,
            categoryName: plan.categoryName,
            entityName: plan.entityName,
            isPlannedIncome: resolved
        )

        pendingIncomeKindPlan = nil
        executeAddIncome(plan)
    }

    private func resolvePresetCardSelection(with prompt: String) {
        guard var plan = pendingPresetCardPlan else { return }
        guard cards.isEmpty == false else {
            clearMutationPendingState()
            appendMutationMessage(title: "No cards available", subtitle: "Add a card first, then create presets.", rows: [])
            return
        }

        let selected: Card?
        if let index = Int(prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
           index >= 1,
           index <= cards.count {
            selected = cards[index - 1]
        } else if let match = entityMatcher.bestCardMatch(in: prompt, cards: cards) {
            selected = cards.first { $0.name == match }
        } else {
            selected = nil
        }

        guard let selected else {
            presentPresetCardSelectionPrompt()
            return
        }

        plan = HomeAssistantCommandPlan(
            intent: plan.intent,
            confidenceBand: plan.confidenceBand,
            rawPrompt: plan.rawPrompt,
            amount: plan.amount,
            originalAmount: plan.originalAmount,
            date: plan.date,
            dateRange: plan.dateRange,
            notes: plan.notes,
            source: plan.source,
            cardName: selected.name,
            categoryName: plan.categoryName,
            entityName: plan.entityName,
            isPlannedIncome: plan.isPlannedIncome
        )

        pendingPresetCardPlan = nil
        executeAddPreset(plan)
    }

    private func resolveCategoryColorConfirmation(with prompt: String) {
        guard let plan = pendingCategoryColorPlan else { return }

        let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let confirms = ["yes", "y", "use it", "confirm"].contains(normalized)
        let rejects = ["no", "n", "default", "skip"].contains(normalized)

        guard confirms || rejects else {
            appendMutationMessage(
                title: "Quick clarification",
                subtitle: "Reply yes to use \(pendingCategoryColorName ?? "that color"), or no to use default blue.",
                rows: []
            )
            return
        }

        let name = (plan.entityName ?? plan.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.isEmpty == false else {
            clearMutationPendingState()
            appendMutationMessage(title: "Need category name", subtitle: "Tell me the category name to create.", rows: [])
            return
        }

        do {
            let result = try mutationService.addCategory(
                name: name,
                colorHex: confirms ? pendingCategoryColorHex : nil,
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not create category",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func resolveCardStyleSelection(with prompt: String) {
        guard let step = pendingCardStyleStep else { return }
        guard let cardName = pendingCardStyleCardName else {
            clearMutationPendingState()
            return
        }

        switch step {
        case .offer:
            let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if ["yes", "y", "style"].contains(normalized) {
                pendingCardStyleStep = .themeSelection
                presentCardThemeSelectionPrompt()
                return
            }
            if ["no", "n", "skip"].contains(normalized) {
                pendingCardStyleCardName = nil
                pendingCardStyleStep = nil
                pendingCardStyleTheme = nil
                appendMutationMessage(title: "Card style kept", subtitle: "Keeping default theme and effect.", rows: [])
                return
            }
            appendMutationMessage(
                title: "Quick clarification",
                subtitle: "Reply yes to style this card, or no to keep defaults.",
                rows: []
            )
        case .themeSelection:
            guard let theme = selectedCardTheme(from: prompt) else {
                presentCardThemeSelectionPrompt()
                return
            }
            pendingCardStyleTheme = theme
            pendingCardStyleStep = .effectSelection
            presentCardEffectSelectionPrompt()
        case .effectSelection:
            guard let effect = selectedCardEffect(from: prompt) else {
                presentCardEffectSelectionPrompt()
                return
            }
            guard let theme = pendingCardStyleTheme else {
                pendingCardStyleStep = .themeSelection
                presentCardThemeSelectionPrompt()
                return
            }

            do {
                let result = try mutationService.updateCardStyle(
                    cardName: cardName,
                    workspace: workspace,
                    themeRaw: theme.rawValue,
                    effectRaw: effect.rawValue,
                    modelContext: modelContext
                )
                pendingCardStyleCardName = nil
                pendingCardStyleStep = nil
                pendingCardStyleTheme = nil
                appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
            } catch {
                appendMutationMessage(
                    title: "Could not update card style",
                    subtitle: error.localizedDescription,
                    rows: []
                )
            }
        }
    }

    private func resolveBudgetCreationStep(with prompt: String) {
        guard let plan = pendingBudgetCreationPlan,
              let step = pendingBudgetCreationStep else { return }

        switch step {
        case .cardsChoice:
            guard let selection = triChoice(prompt) else {
                presentBudgetCardsChoicePrompt()
                return
            }
            switch selection {
            case .all:
                pendingBudgetSelectedCardIDs = Set(cards.map(\.id))
                pendingBudgetCreationStep = .presetsChoice
                presentBudgetPresetsChoicePrompt()
            case .choose:
                guard cards.isEmpty == false else {
                    pendingBudgetSelectedCardIDs = []
                    pendingBudgetCreationStep = .presetsChoice
                    presentBudgetPresetsChoicePrompt()
                    return
                }
                pendingBudgetCreationStep = .cardsSelection
                presentBudgetCardsSelectionPrompt()
            case .skip:
                pendingBudgetSelectedCardIDs = []
                pendingBudgetCreationStep = .presetsChoice
                presentBudgetPresetsChoicePrompt()
            }
        case .cardsSelection:
            let selected = selectedCards(from: prompt)
            guard selected.isEmpty == false else {
                presentBudgetCardsSelectionPrompt()
                return
            }
            pendingBudgetSelectedCardIDs = Set(selected.map(\.id))
            pendingBudgetCreationStep = .presetsChoice
            presentBudgetPresetsChoicePrompt()
        case .presetsChoice:
            if let attachAllPresets = plan.attachAllPresets {
                pendingBudgetSelectedPresetIDs = attachAllPresets ? Set(pendingBudgetMatchingPresets.map(\.id)) : []
                executePendingBudgetCreation(plan: plan)
                return
            }
            guard let selection = triChoice(prompt) else {
                presentBudgetPresetsChoicePrompt()
                return
            }
            switch selection {
            case .all:
                pendingBudgetSelectedPresetIDs = Set(pendingBudgetMatchingPresets.map(\.id))
                executePendingBudgetCreation(plan: plan)
            case .choose:
                guard pendingBudgetMatchingPresets.isEmpty == false else {
                    pendingBudgetSelectedPresetIDs = []
                    executePendingBudgetCreation(plan: plan)
                    return
                }
                pendingBudgetCreationStep = .presetsSelection
                presentBudgetPresetsSelectionPrompt()
            case .skip:
                pendingBudgetSelectedPresetIDs = []
                executePendingBudgetCreation(plan: plan)
            }
        case .presetsSelection:
            let selected = selectedPresets(from: prompt, candidates: pendingBudgetMatchingPresets)
            guard selected.isEmpty == false else {
                presentBudgetPresetsSelectionPrompt()
                return
            }
            pendingBudgetSelectedPresetIDs = Set(selected.map(\.id))
            executePendingBudgetCreation(plan: plan)
        }
    }

    private func executePendingBudgetCreation(plan: HomeAssistantCommandPlan) {
        let range = plan.dateRange ?? monthRange(containing: Date())
        var budgetName = (plan.entityName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if budgetName.hasPrefix("for ") {
            budgetName = ""
        }
        let resolvedName = budgetName.isEmpty
            ? BudgetNameSuggestion.suggestedName(start: range.startDate, end: range.endDate, calendar: .current)
            : budgetName

        let selectedCards = cards.filter { pendingBudgetSelectedCardIDs.contains($0.id) }
        let selectedPresets = presets.filter { pendingBudgetSelectedPresetIDs.contains($0.id) }

        do {
            let result = try mutationService.addBudget(
                name: resolvedName,
                dateRange: range,
                cards: selectedCards,
                presets: selectedPresets,
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not create budget",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func presentBudgetCardsChoicePrompt() {
        appendMutationMessage(
            title: "Attach cards to this budget?",
            subtitle: "Choose how Marina should link cards.",
            rows: [
                HomeAnswerRow(title: "1", value: "Attach all cards"),
                HomeAnswerRow(title: "2", value: "Choose specific cards"),
                HomeAnswerRow(title: "3", value: "Skip cards for now")
            ]
        )
    }

    private func presentBudgetCardsSelectionPrompt() {
        let rows = cards.enumerated().map { index, card in
            HomeAnswerRow(title: "\(index + 1)", value: card.name)
        }
        appendMutationMessage(
            title: "Choose cards",
            subtitle: "Reply with numbers (comma-separated) or card names.",
            rows: rows
        )
    }

    private func presentBudgetPresetsChoicePrompt() {
        let matchingCount = pendingBudgetMatchingPresets.count
        appendMutationMessage(
            title: "Attach presets to this budget?",
            subtitle: "I found \(matchingCount) preset\(matchingCount == 1 ? "" : "s") matching this budget range.",
            rows: [
                HomeAnswerRow(title: "1", value: "Attach all matching presets"),
                HomeAnswerRow(title: "2", value: "Choose specific presets"),
                HomeAnswerRow(title: "3", value: "Skip presets for now")
            ]
        )
    }

    private func presentBudgetPresetsSelectionPrompt() {
        let rows = pendingBudgetMatchingPresets.enumerated().map { index, preset in
            HomeAnswerRow(title: "\(index + 1)", value: preset.title)
        }
        appendMutationMessage(
            title: "Choose presets",
            subtitle: "Reply with numbers (comma-separated) or preset names.",
            rows: rows
        )
    }

    private func presentCardThemeSelectionPrompt() {
        let rows = CardThemeOption.allCases.enumerated().map { index, option in
            HomeAnswerRow(title: "\(index + 1)", value: option.displayName)
        }
        appendMutationMessage(
            title: "Choose card theme",
            subtitle: "Reply with a number or theme name.",
            rows: rows
        )
    }

    private func presentCardEffectSelectionPrompt() {
        let rows = CardEffectOption.allCases.enumerated().map { index, option in
            HomeAnswerRow(title: "\(index + 1)", value: option.displayName)
        }
        appendMutationMessage(
            title: "Choose card effect",
            subtitle: "Reply with a number or effect name.",
            rows: rows
        )
    }

    private enum TriChoice {
        case all
        case choose
        case skip
    }

    private func triChoice(_ prompt: String) -> TriChoice? {
        let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "1" || normalized.contains("all") {
            return .all
        }
        if normalized == "2" || normalized.contains("choose") || normalized.contains("specific") {
            return .choose
        }
        if normalized == "3" || normalized.contains("skip") || normalized.contains("no") {
            return .skip
        }
        return nil
    }

    private func selectedCards(from prompt: String) -> [Card] {
        let indexes = selectedIndexes(from: prompt, max: cards.count)
        if indexes.isEmpty == false {
            return indexes.map { cards[$0] }
        }
        if let match = entityMatcher.bestCardMatch(in: prompt, cards: cards) {
            return cards.filter { $0.name == match }
        }
        return []
    }

    private func selectedPresets(from prompt: String, candidates: [Preset]) -> [Preset] {
        let indexes = selectedIndexes(from: prompt, max: candidates.count)
        if indexes.isEmpty == false {
            return indexes.map { candidates[$0] }
        }
        let names = candidates.map(\.title)
        if let match = entityMatcher.bestMatch(in: prompt, candidateNames: names) {
            return candidates.filter { $0.title == match }
        }
        return []
    }

    private func selectedIndexes(from prompt: String, max: Int) -> [Int] {
        let parts = prompt
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let indexes = parts.compactMap { Int($0) }.filter { $0 >= 1 && $0 <= max }.map { $0 - 1 }
        return Array(Set(indexes)).sorted()
    }

    private func selectedCardTheme(from prompt: String) -> CardThemeOption? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = Int(trimmed), index >= 1, index <= CardThemeOption.allCases.count {
            return CardThemeOption.allCases[index - 1]
        }
        let normalized = prompt.lowercased()
        return CardThemeOption.allCases.first(where: { normalized.contains($0.rawValue) })
    }

    private func selectedCardEffect(from prompt: String) -> CardEffectOption? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let index = Int(trimmed), index >= 1, index <= CardEffectOption.allCases.count {
            return CardEffectOption.allCases[index - 1]
        }
        let normalized = prompt.lowercased()
        return CardEffectOption.allCases.first(where: { normalized.contains($0.rawValue) })
    }

    private func matchingPresets(for command: HomeAssistantCommandPlan) -> [Preset] {
        let range = command.dateRange ?? monthRange(containing: Date())
        let probe = Budget(
            name: "Marina Probe",
            startDate: range.startDate,
            endDate: range.endDate
        )

        return presets.filter { preset in
            guard preset.isArchived == false else { return false }
            return PresetScheduleEngine.occurrences(for: preset, in: probe).isEmpty == false
        }
    }

    private func resolveExpenseDisambiguation(with prompt: String) {
        guard pendingExpenseCandidates.isEmpty == false else { return }
        guard let command = pendingExpenseDisambiguationPlan else { return }

        let selected = selectedExpenseCandidate(from: prompt, candidates: pendingExpenseCandidates)
        guard let selected else {
            presentExpenseDisambiguationPrompt()
            return
        }

        if command.intent == .deleteExpense || command.intent == .deleteLastExpense {
            executeExpenseDelete(selected)
        } else if command.intent == .moveExpenseCategory {
            guard let categoryName = command.categoryName,
                  let category = resolveCategory(from: categoryName) else {
                appendMutationMessage(
                    title: "Need target category",
                    subtitle: "Tell me which category this expense should move to.",
                    rows: []
                )
                return
            }
            executeMoveExpenseCategory(selected, category: category)
        } else {
            executeExpenseEdit(selected, using: command)
        }
    }

    private func resolvePlannedExpenseDisambiguation(with prompt: String) {
        guard pendingPlannedExpenseCandidates.isEmpty == false else { return }
        guard let command = pendingPlannedExpenseAmountPlan else { return }
        guard let amount = command.amount, amount > 0 else { return }

        let selected = selectedPlannedExpenseCandidate(
            from: prompt,
            candidates: pendingPlannedExpenseCandidates
        )
        guard let selected else {
            presentPlannedExpenseDisambiguationPrompt()
            return
        }

        pendingPlannedExpenseCandidates = []
        pendingPlannedExpenseAmountExpense = selected

        guard let target = command.plannedExpenseAmountTarget else {
            presentPlannedExpenseAmountTargetPrompt()
            return
        }

        executePlannedExpenseAmountUpdate(selected, amount: amount, target: target)
    }

    private func resolvePlannedExpenseAmountTarget(with prompt: String) {
        guard let plan = pendingPlannedExpenseAmountPlan,
              let expense = pendingPlannedExpenseAmountExpense,
              let amount = plan.amount,
              amount > 0 else { return }

        let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let target: HomeAssistantPlannedExpenseAmountTarget?
        if normalized.contains("planned") || normalized == "1" {
            target = .planned
        } else if normalized.contains("actual") || normalized.contains("effective") || normalized == "2" {
            target = .actual
        } else {
            target = nil
        }

        guard let target else {
            presentPlannedExpenseAmountTargetPrompt()
            return
        }

        executePlannedExpenseAmountUpdate(expense, amount: amount, target: target)
    }

    private func resolveIncomeDisambiguation(with prompt: String) {
        guard pendingIncomeCandidates.isEmpty == false else { return }
        guard let command = pendingIncomeDisambiguationPlan else { return }

        let selected = selectedIncomeCandidate(from: prompt, candidates: pendingIncomeCandidates)
        guard let selected else {
            presentIncomeDisambiguationPrompt()
            return
        }

        if command.intent == .deleteIncome || command.intent == .deleteLastIncome {
            executeIncomeDelete(selected)
        } else if command.intent == .markIncomeReceived {
            executeMarkIncomeReceived(selected)
        } else {
            executeIncomeEdit(selected, using: command)
        }
    }

    private func resolveDeleteConfirmation(with prompt: String) {
        let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let confirms = ["yes", "y", "delete", "confirm", "proceed"].contains(normalized)
        let cancels = ["no", "n", "cancel", "stop"].contains(normalized)

        if confirms {
            if let expense = pendingDeleteExpense {
                pendingDeleteExpense = nil
                do {
                    let result = try mutationService.deleteExpense(expense, modelContext: modelContext)
                    clearMutationPendingState()
                    appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
                } catch {
                    appendMutationMessage(title: "Could not delete expense", subtitle: error.localizedDescription, rows: [])
                }
                return
            }

            if let income = pendingDeleteIncome {
                pendingDeleteIncome = nil
                do {
                    let result = try mutationService.deleteIncome(income, modelContext: modelContext)
                    clearMutationPendingState()
                    appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
                } catch {
                    appendMutationMessage(title: "Could not delete income", subtitle: error.localizedDescription, rows: [])
                }
                return
            }
        }

        if cancels {
            clearMutationPendingState()
            appendMutationMessage(title: "Delete canceled", subtitle: "Nothing was removed.", rows: [])
            return
        }

        appendMutationMessage(
            title: "Confirm delete",
            subtitle: "Reply yes to confirm or no to cancel.",
            rows: []
        )
    }

    private func presentCardSelectionPrompt(for command: HomeAssistantCommandPlan) {
        let rows = pendingExpenseCardOptions.enumerated().prefix(5).map { index, card in
            HomeAnswerRow(title: "\(index + 1)", value: card.name)
        }

        appendMutationMessage(
            title: "Quick clarification",
            subtitle: "Which card should I use for this expense?",
            rows: rows
        )
        pendingExpenseCardPlan = command
    }

    private func presentExpenseDisambiguationPrompt() {
        let rows = pendingExpenseCandidates.enumerated().map { index, expense in
            HomeAnswerRow(title: "\(index + 1)", value: expenseDisplayLabel(expense))
        }
        appendMutationMessage(
            title: "Quick clarification",
            subtitle: "I found multiple matching expenses. Pick one by number.",
            rows: rows
        )
    }

    private func presentPlannedExpenseDisambiguationPrompt() {
        let rows = pendingPlannedExpenseCandidates.enumerated().map { index, expense in
            HomeAnswerRow(
                title: "\(index + 1)",
                value: "\(expense.title) • \(CurrencyFormatter.string(from: expense.plannedAmount)) • \(shortDate(expense.expenseDate))"
            )
        }
        appendMutationMessage(
            title: "Quick clarification",
            subtitle: "I found multiple matching planned expenses. Pick one by number.",
            rows: rows
        )
    }

    private func presentPresetCardSelectionPrompt() {
        let rows = cards.enumerated().prefix(5).map { index, card in
            HomeAnswerRow(title: "\(index + 1)", value: card.name)
        }
        appendMutationMessage(
            title: "Quick clarification",
            subtitle: "Which card should be the default for this preset?",
            rows: rows
        )
    }

    private func presentIncomeDisambiguationPrompt() {
        let rows = pendingIncomeCandidates.enumerated().map { index, income in
            HomeAnswerRow(title: "\(index + 1)", value: incomeDisplayLabel(income))
        }
        appendMutationMessage(
            title: "Quick clarification",
            subtitle: "I found multiple matching income entries. Pick one by number.",
            rows: rows
        )
    }

    private func selectedExpenseCandidate(
        from prompt: String,
        candidates: [VariableExpense]
    ) -> VariableExpense? {
        if let index = Int(prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
           index >= 1,
           index <= candidates.count {
            return candidates[index - 1]
        }

        if let match = entityMatcher.bestMatch(
            in: prompt,
            candidateNames: candidates.map(\.descriptionText)
        ) {
            return candidates.first { $0.descriptionText == match }
        }

        return nil
    }

    private func selectedIncomeCandidate(
        from prompt: String,
        candidates: [Income]
    ) -> Income? {
        if let index = Int(prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
           index >= 1,
           index <= candidates.count {
            return candidates[index - 1]
        }

        if let match = entityMatcher.bestMatch(
            in: prompt,
            candidateNames: candidates.map(\.source)
        ) {
            return candidates.first { $0.source == match }
        }

        return nil
    }

    private func selectedPlannedExpenseCandidate(
        from prompt: String,
        candidates: [PlannedExpense]
    ) -> PlannedExpense? {
        if let index = Int(prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
           index >= 1,
           index <= candidates.count {
            return candidates[index - 1]
        }

        if let match = entityMatcher.bestMatch(
            in: prompt,
            candidateNames: candidates.map(\.title)
        ) {
            return candidates.first { $0.title == match }
        }

        return nil
    }

    private func appendMutationMessage(
        title: String,
        subtitle: String?,
        rows: [HomeAnswerRow]
    ) {
        appendAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                userPrompt: nil,
                title: title,
                subtitle: subtitle,
                rows: rows
            )
        )
    }

    private func clearMutationPendingState() {
        pendingExpenseCardPlan = nil
        pendingExpenseCardOptions = []
        pendingPresetCardPlan = nil
        pendingIncomeKindPlan = nil
        pendingExpenseDisambiguationPlan = nil
        pendingIncomeDisambiguationPlan = nil
        pendingExpenseCandidates = []
        pendingPlannedExpenseAmountPlan = nil
        pendingPlannedExpenseAmountExpense = nil
        pendingPlannedExpenseCandidates = []
        pendingIncomeCandidates = []
        pendingDeleteExpense = nil
        pendingDeleteIncome = nil
        pendingBudgetCreationPlan = nil
        pendingBudgetCreationStep = nil
        pendingBudgetSelectedCardIDs = []
        pendingBudgetSelectedPresetIDs = []
        pendingBudgetMatchingPresets = []
        pendingCategoryColorPlan = nil
        pendingCategoryColorHex = nil
        pendingCategoryColorName = nil
        pendingCardStyleCardName = nil
        pendingCardStyleStep = nil
        pendingCardStyleTheme = nil
    }

    private func resolveCard(from cardName: String?) -> Card? {
        let trimmed = (cardName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        if let match = entityMatcher.bestCardMatch(in: trimmed, cards: cards) {
            return cards.first { $0.name == match }
        }
        return nil
    }

    private func resolveCategory(from categoryName: String?) -> Category? {
        let trimmed = (categoryName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        if let match = entityMatcher.bestCategoryMatch(in: trimmed, categories: categories) {
            return categories.first { $0.name == match }
        }
        return nil
    }

    private func expenseDisplayLabel(_ expense: VariableExpense) -> String {
        "\(CurrencyFormatter.string(from: expense.amount)) • \(expense.descriptionText) • \(shortDate(expense.transactionDate))"
    }

    private func incomeDisplayLabel(_ income: Income) -> String {
        let label = income.isPlanned ? "Planned" : "Actual"
        return "\(CurrencyFormatter.string(from: income.amount)) • \(income.source) • \(shortDate(income.date)) • \(label)"
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func calendarStartOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func resolvedPlan(
        for prompt: String
    ) -> (plan: HomeQueryPlan, source: HomeAssistantPlanResolutionSource)? {
        if let plan = parser.parsePlan(prompt, defaultPeriodUnit: defaultQueryPeriodUnit) {
            return (enrichPlanWithEntities(plan, rawPrompt: prompt), .parser)
        }

        if let contextualPlan = contextualPlan(for: prompt) {
            return (contextualPlan, .contextual)
        }

        if let entityPlan = entityAwarePlan(for: prompt) {
            return (entityPlan, .entityAware)
        }

        return nil
    }

    private func planExplainPrompt(from prompt: String) -> String? {
        let normalized = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let explainPrefixes = ["/explain", "explain:"]

        for prefix in explainPrefixes {
            if normalized.lowercased().hasPrefix(prefix) {
                let remaining = normalized.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                return remaining.isEmpty ? nil : remaining
            }
        }

        return nil
    }

    private func planExplanationAnswer(for prompt: String) -> HomeAnswer {
        let normalized = normalizedPrompt(prompt)
        let aliasCard = aliasTarget(in: prompt, entityType: .card)
        let aliasCategory = aliasTarget(in: prompt, entityType: .category)
        let aliasIncome = aliasTarget(in: prompt, entityType: .incomeSource)
        let aliasPreset = aliasTarget(in: prompt, entityType: .preset)
        let matchedCard = entityMatcher.bestCardMatch(in: prompt, cards: cards)
        let matchedCategory = entityMatcher.bestCategoryMatch(in: prompt, categories: categories)
        let matchedIncome = entityMatcher.bestIncomeSourceMatch(in: prompt, incomes: incomes)
        let matchedPreset = entityMatcher.bestPresetMatch(in: prompt, presets: presets)

        guard let resolved = resolvedPlan(for: prompt) else {
            return HomeAnswer(
                queryID: UUID(),
                kind: .message,
                userPrompt: prompt,
                title: "Plan Explain",
                subtitle: "No plan resolved from this prompt.",
                rows: [
                    HomeAnswerRow(title: "Normalized", value: normalized),
                    HomeAnswerRow(title: "Matched Card", value: matchedCard ?? "None"),
                    HomeAnswerRow(title: "Alias Card", value: aliasCard ?? "None"),
                    HomeAnswerRow(title: "Matched Category", value: matchedCategory ?? "None"),
                    HomeAnswerRow(title: "Alias Category", value: aliasCategory ?? "None"),
                    HomeAnswerRow(title: "Matched Income", value: matchedIncome ?? "None"),
                    HomeAnswerRow(title: "Alias Income", value: aliasIncome ?? "None"),
                    HomeAnswerRow(title: "Matched Preset", value: matchedPreset ?? "None"),
                    HomeAnswerRow(title: "Alias Preset", value: aliasPreset ?? "None")
                ]
            )
        }

        let plan = resolved.plan
        let clarification = clarificationPlan(for: plan, rawPrompt: prompt)

        return HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: prompt,
            title: "Plan Explain",
            subtitle: "Resolved via \(resolved.source.rawValue).",
            rows: [
                HomeAnswerRow(title: "Normalized", value: normalized),
                HomeAnswerRow(title: "Intent", value: plan.metric.intent.rawValue),
                HomeAnswerRow(title: "Metric", value: plan.metric.rawValue),
                HomeAnswerRow(title: "Confidence", value: plan.confidenceBand.rawValue),
                HomeAnswerRow(title: "Target", value: plan.targetName ?? "None"),
                HomeAnswerRow(title: "Date Range", value: debugDateRangeLabel(plan.dateRange)),
                HomeAnswerRow(title: "Limit", value: plan.resultLimit.map(String.init) ?? "Default"),
                HomeAnswerRow(title: "Period Unit", value: plan.periodUnit?.rawValue ?? defaultQueryPeriodUnit.rawValue),
                HomeAnswerRow(title: "Matched Card", value: matchedCard ?? "None"),
                HomeAnswerRow(title: "Alias Card", value: aliasCard ?? "None"),
                HomeAnswerRow(title: "Matched Category", value: matchedCategory ?? "None"),
                HomeAnswerRow(title: "Alias Category", value: aliasCategory ?? "None"),
                HomeAnswerRow(title: "Matched Income", value: matchedIncome ?? "None"),
                HomeAnswerRow(title: "Alias Income", value: aliasIncome ?? "None"),
                HomeAnswerRow(title: "Matched Preset", value: matchedPreset ?? "None"),
                HomeAnswerRow(title: "Alias Preset", value: aliasPreset ?? "None"),
                HomeAnswerRow(
                    title: "Clarification",
                    value: clarification.map { $0.shouldRunBestEffort ? "Best-effort + chips" : "Blocked until clarified" } ?? "None"
                )
            ]
        )
    }

    private func debugDateRangeLabel(_ range: HomeQueryDateRange?) -> String {
        guard let range else { return "None" }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none

        return "\(formatter.string(from: range.startDate)) - \(formatter.string(from: range.endDate))"
    }

    private func aliasTarget(
        in prompt: String,
        entityType: HomeAssistantAliasEntityType
    ) -> String? {
        aliasMatcher.matchedTarget(
            in: prompt,
            entityType: entityType,
            rules: assistantAliasRules
        )
    }

    private func recordTelemetry(
        for prompt: String,
        outcome: HomeAssistantTelemetryOutcome,
        source: HomeAssistantPlanResolutionSource?,
        plan: HomeQueryPlan?,
        notes: String?
    ) {
        let event = HomeAssistantTelemetryEvent(
            prompt: prompt,
            normalizedPrompt: normalizedPrompt(prompt),
            outcome: outcome,
            source: source?.rawValue,
            intentRawValue: plan?.metric.intent.rawValue,
            confidenceRawValue: plan?.confidenceBand.rawValue,
            targetName: plan?.targetName,
            notes: notes
        )
        telemetryStore.appendEvent(event, workspaceID: workspace.id)
    }

    private func appendAnswer(_ answer: HomeAnswer) {
        let resolvedUserPrompt: String?
        if let existingPrompt = answer.userPrompt, existingPrompt.isEmpty == false {
            resolvedUserPrompt = existingPrompt
        } else {
            resolvedUserPrompt = pendingUserPromptForNextAnswer
        }

        let answerToAppend = HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: resolvedUserPrompt,
            title: answer.title,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            generatedAt: answer.generatedAt
        )

        pendingUserPromptForNextAnswer = nil
        followUpsCollapsed = false
        answers.append(answerToAppend)
        conversationStore.saveAnswers(answers, workspaceID: workspace.id)
    }

    private func quickButtonAccordionAnimation(for index: Int) -> Animation {
        let count = EmptySuggestionGroup.allCases.count
        let order = quickButtonsVisible ? index : max(0, count - 1 - index)
        let base = quickButtonsVisible
            ? Animation.easeOut(duration: 0.18)
            : Animation.easeIn(duration: 0.16)
        return base.delay(Double(order) * 0.018)
    }

    private func scrollToLatestMessage(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        let action = {
            proxy.scrollTo(ScrollTarget.bottomAnchor, anchor: .bottom)
        }

        // I defer to the next run loop so layout has settled before scrolling.
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    action()
                }
            } else {
                action()
            }
        }
    }

    private func loadConversationIfNeeded() {
        guard hasLoadedConversation == false else { return }
        answers = conversationStore.loadAnswers(workspaceID: workspace.id)
        hasLoadedConversation = true
    }

    private func clearConversation() {
        answers.removeAll()
        pendingUserPromptForNextAnswer = nil
        sessionContext = HomeAssistantSessionContext()
        clarificationSuggestions = []
        lastClarificationReasons = []
        clearMutationPendingState()
        conversationStore.saveAnswers([], workspaceID: workspace.id)
    }

    private func handleResolvedPlan(
        _ plan: HomeQueryPlan,
        rawPrompt: String,
        allowsBroadBundle: Bool,
        source: HomeAssistantPlanResolutionSource
    ) {
        if let entityDisambiguation = entityDisambiguationPlan(for: plan, rawPrompt: rawPrompt) {
            recordTelemetry(
                for: rawPrompt,
                outcome: .clarification,
                source: source,
                plan: plan,
                notes: "entity_disambiguation"
            )
            presentClarificationTurn(
                entityDisambiguation,
                userPrompt: rawPrompt
            )
            return
        }

        let clarificationPlan = clarificationPlan(for: plan, rawPrompt: rawPrompt)

        if let clarificationPlan, clarificationPlan.shouldRunBestEffort == false {
            recordTelemetry(
                for: rawPrompt,
                outcome: .clarification,
                source: source,
                plan: plan,
                notes: "clarification_required"
            )
            presentClarificationTurn(
                clarificationPlan,
                userPrompt: rawPrompt
            )
            return
        }

        if allowsBroadBundle && shouldRunBroadOverviewBundle(for: rawPrompt, plan: plan) {
            runBroadOverviewBundle(userPrompt: rawPrompt, basePlan: plan)
            recordTelemetry(
                for: rawPrompt,
                outcome: .resolved,
                source: source,
                plan: plan,
                notes: clarificationPlan == nil ? "broad_bundle" : "broad_bundle_with_clarification_chips"
            )
        } else {
            runQuery(plan.query, userPrompt: rawPrompt, confidenceBand: plan.confidenceBand)
            recordTelemetry(
                for: rawPrompt,
                outcome: .resolved,
                source: source,
                plan: plan,
                notes: clarificationPlan == nil ? nil : "resolved_with_clarification_chips"
            )
        }

        if let clarificationPlan {
            presentClarificationTurn(
                clarificationPlan,
                userPrompt: nil
            )
        }
    }

    private func entityDisambiguationPlan(
        for plan: HomeQueryPlan,
        rawPrompt: String
    ) -> HomeAssistantClarificationPlan? {
        guard plan.targetName == nil else { return nil }

        let normalized = normalizedPrompt(rawPrompt)

        if requiresCardTarget(plan.metric), normalized.contains("all cards") == false {
            let candidates = entityMatcher.rankedMatches(
                in: rawPrompt,
                candidateNames: cards.map(\.name),
                limit: 3
            )
            if candidates.count >= 2 {
                return disambiguationPlan(
                    for: plan,
                    reasons: [.missingCardTarget],
                    options: candidates,
                    allTitle: "All cards"
                )
            }
        }

        if requiresCategoryTarget(plan.metric), normalized.contains("all categories") == false {
            let candidates = entityMatcher.rankedMatches(
                in: rawPrompt,
                candidateNames: categories.map(\.name),
                limit: 3
            )
            if candidates.count >= 2 {
                return disambiguationPlan(
                    for: plan,
                    reasons: [.missingCategoryTarget],
                    options: candidates,
                    allTitle: "All categories"
                )
            }
        }

        if requiresIncomeTarget(plan.metric),
           normalized.contains("all sources") == false,
           normalized.contains("all income") == false
        {
            let uniqueSources = Array(Set(incomes.map(\.source))).sorted()
            let candidates = entityMatcher.rankedMatches(
                in: rawPrompt,
                candidateNames: uniqueSources,
                limit: 3
            )
            if candidates.count >= 2 {
                return disambiguationPlan(
                    for: plan,
                    reasons: [.missingIncomeSourceTarget],
                    options: candidates,
                    allTitle: "All income sources"
                )
            }
        }

        return nil
    }

    private func disambiguationPlan(
        for plan: HomeQueryPlan,
        reasons: [HomeAssistantClarificationReason],
        options: [String],
        allTitle: String
    ) -> HomeAssistantClarificationPlan {
        var suggestions: [HomeAssistantSuggestion] = options.map { option in
            HomeAssistantSuggestion(
                title: option,
                query: queryFromPlan(plan, overridingTargetName: option)
            )
        }

        suggestions.append(
            HomeAssistantSuggestion(
                title: allTitle,
                query: queryFromPlan(plan, overridingTargetName: nil)
            )
        )

        return HomeAssistantClarificationPlan(
            reasons: reasons,
            subtitle: "I found a few close matches. Pick one to continue.",
            suggestions: suggestions,
            shouldRunBestEffort: false
        )
    }

    private func clarificationPlan(
        for plan: HomeQueryPlan,
        rawPrompt: String
    ) -> HomeAssistantClarificationPlan? {
        guard plan.confidenceBand != .high else { return nil }

        let normalized = normalizedPrompt(rawPrompt)
        let reasons = clarificationReasons(for: plan, normalizedPrompt: normalized)

        // Medium confidence with no concrete ambiguity can still proceed without interruption.
        if reasons.isEmpty, plan.confidenceBand == .medium {
            return nil
        }

        let subtitle = clarificationSubtitle(for: reasons, confidenceBand: plan.confidenceBand)
        let suggestions = clarificationSuggestions(
            for: plan,
            reasons: reasons,
            normalizedPrompt: normalized
        )

        let shouldRunBestEffort = plan.confidenceBand == .medium

        return HomeAssistantClarificationPlan(
            reasons: reasons,
            subtitle: subtitle,
            suggestions: suggestions,
            shouldRunBestEffort: shouldRunBestEffort
        )
    }

    private func presentClarificationTurn(
        _ clarificationPlan: HomeAssistantClarificationPlan,
        userPrompt: String?
    ) {
        clarificationSuggestions = clarificationPlan.suggestions
        lastClarificationReasons = clarificationPlan.reasons

        let clarificationAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: userPrompt,
            title: "Quick clarification",
            subtitle: clarificationPlan.subtitle,
            primaryValue: nil,
            rows: []
        )

        appendAnswer(clarificationAnswer)
    }

    private func clarificationReasons(
        for plan: HomeQueryPlan,
        normalizedPrompt: String
    ) -> [HomeAssistantClarificationReason] {
        var reasons: [HomeAssistantClarificationReason] = []

        if plan.confidenceBand == .low {
            reasons.append(.lowConfidenceLanguage)
        }

        if plan.dateRange == nil
            && isDateExpected(for: plan.metric)
            && hasExplicitDatePhrase(in: normalizedPrompt) == false
        {
            reasons.append(.missingDate)
        }

        if plan.metric == .overview
            && plan.dateRange == nil
            && isBroadOverviewPrompt(normalizedPrompt)
        {
            reasons.append(.broadPrompt)
        }

        if plan.targetName == nil {
            if requiresCategoryTarget(plan.metric) && normalizedPrompt.contains("all categories") == false {
                reasons.append(.missingCategoryTarget)
            } else if requiresCardTarget(plan.metric) && normalizedPrompt.contains("all cards") == false {
                reasons.append(.missingCardTarget)
            } else if requiresIncomeTarget(plan.metric)
                && normalizedPrompt.contains("all income") == false
                && normalizedPrompt.contains("all sources") == false
            {
                reasons.append(.missingIncomeSourceTarget)
            }
        }

        return uniqueClarificationReasons(reasons)
    }

    private func clarificationSubtitle(
        for reasons: [HomeAssistantClarificationReason],
        confidenceBand: HomeQueryConfidenceBand
    ) -> String {
        let reasonLines = reasons.map(\.promptLine).prefix(2)
        let reasonBody = reasonLines.joined(separator: " ")

        switch confidenceBand {
        case .high:
            return "I have enough detail to run this now."
        case .medium:
            if reasonBody.isEmpty {
                return "Likely match complete. If you want it tighter, pick one option below."
            }
            return "Likely match complete. \(reasonBody)"
        case .low:
            if reasonBody.isEmpty {
                return "I need one more detail before I run this. Pick an option below."
            }
            return "I need one more detail before I run this. \(reasonBody)"
        }
    }

    private func clarificationSuggestions(
        for plan: HomeQueryPlan,
        reasons: [HomeAssistantClarificationReason],
        normalizedPrompt: String
    ) -> [HomeAssistantSuggestion] {
        var suggestions: [HomeAssistantSuggestion] = []
        let now = Date()

        if reasons.contains(.missingDate) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Use this month",
                    query: queryFromPlan(plan, overridingDateRange: monthRange(containing: now))
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Use last month",
                    query: queryFromPlan(plan, overridingDateRange: previousMonthRange(from: now))
                )
            )
        }

        if reasons.contains(.missingCategoryTarget) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "All categories",
                    query: queryFromPlan(plan, overridingTargetName: nil)
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Top categories first",
                    query: HomeQuery(
                        intent: .topCategoriesThisMonth,
                        dateRange: plan.dateRange ?? monthRange(containing: now),
                        resultLimit: 3
                    )
                )
            )
        }

        if reasons.contains(.missingCardTarget) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "All cards",
                    query: queryFromPlan(plan, overridingTargetName: nil)
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Card habits (all cards)",
                    query: HomeQuery(
                        intent: .cardVariableSpendingHabits,
                        dateRange: plan.dateRange ?? monthRange(containing: now),
                        resultLimit: 3
                    )
                )
            )
        }

        if reasons.contains(.missingIncomeSourceTarget) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "All income sources",
                    query: queryFromPlan(plan, overridingTargetName: nil)
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Average actual income",
                    query: HomeQuery(intent: .incomeAverageActual, dateRange: yearRange(containing: now))
                )
            )
        }

        if reasons.contains(.broadPrompt) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Spend this month",
                    query: HomeQuery(intent: .spendThisMonth, dateRange: monthRange(containing: now))
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Top categories this month",
                    query: HomeQuery(intent: .topCategoriesThisMonth, dateRange: monthRange(containing: now), resultLimit: 3)
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Compare with last month",
                    query: HomeQuery(intent: .compareThisMonthToPreviousMonth, dateRange: monthRange(containing: now))
                )
            )
        }

        if reasons.contains(.lowConfidenceLanguage) && suggestions.isEmpty {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "How am I doing this month?",
                    query: HomeQuery(intent: .periodOverview, dateRange: monthRange(containing: now))
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Top 3 categories this month",
                    query: HomeQuery(intent: .topCategoriesThisMonth, dateRange: monthRange(containing: now), resultLimit: 3)
                )
            )
        }

        if suggestions.isEmpty {
            suggestions = fallbackClarificationSuggestions(plan: plan, now: now, normalizedPrompt: normalizedPrompt)
        }

        var unique: [HomeAssistantSuggestion] = []
        var seenTitles: Set<String> = []
        for suggestion in suggestions {
            if seenTitles.insert(suggestion.title).inserted {
                unique.append(suggestion)
            }
            if unique.count == 4 {
                break
            }
        }

        return unique
    }

    private func fallbackClarificationSuggestions(
        plan: HomeQueryPlan,
        now: Date,
        normalizedPrompt: String
    ) -> [HomeAssistantSuggestion] {
        let range = plan.dateRange ?? monthRange(containing: now)
        let periodRange = yearRange(containing: now)

        return [
            HomeAssistantSuggestion(
                title: "Use this month",
                query: queryFromPlan(plan, overridingDateRange: range)
            ),
            HomeAssistantSuggestion(
                title: "Use this year",
                query: queryFromPlan(plan, overridingDateRange: periodRange)
            ),
            HomeAssistantSuggestion(
                title: "Spend this month",
                query: HomeQuery(intent: .spendThisMonth, dateRange: range)
            ),
            HomeAssistantSuggestion(
                title: normalizedPrompt.contains("income") ? "Income share this month" : "Top categories this month",
                query: normalizedPrompt.contains("income")
                    ? HomeQuery(intent: .incomeSourceShare, dateRange: range)
                    : HomeQuery(intent: .topCategoriesThisMonth, dateRange: range, resultLimit: 3)
            )
        ]
    }

    private func queryFromPlan(
        _ plan: HomeQueryPlan,
        overridingDateRange: HomeQueryDateRange? = nil,
        overridingTargetName: String? = nil
    ) -> HomeQuery {
        HomeQuery(
            intent: plan.metric.intent,
            dateRange: overridingDateRange ?? plan.dateRange,
            resultLimit: plan.resultLimit,
            targetName: overridingTargetName ?? plan.targetName,
            periodUnit: plan.periodUnit
        )
    }

    private func normalizedPrompt(_ rawPrompt: String) -> String {
        rawPrompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isDateExpected(for metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .presetHighestCost, .presetTopCategory, .presetCategorySpend:
            return false
        case .savingsAverageRecentPeriods, .incomeSourceShareTrend, .categorySpendShareTrend:
            return false
        case .overview, .spendTotal, .topCategories, .monthComparison, .largestTransactions, .cardSpendTotal, .cardVariableSpendingHabits, .incomeAverageActual, .savingsStatus, .incomeSourceShare, .categorySpendShare, .presetDueSoon, .categoryPotentialSavings, .categoryReallocationGuidance:
            return true
        }
    }

    private func hasExplicitDatePhrase(in normalizedPrompt: String) -> Bool {
        if normalizedPrompt.contains("today")
            || normalizedPrompt.contains("yesterday")
            || normalizedPrompt.contains("this month")
            || normalizedPrompt.contains("last month")
            || normalizedPrompt.contains("this year")
            || normalizedPrompt.contains("last year")
            || normalizedPrompt.contains("past ")
            || normalizedPrompt.contains("last ")
            || normalizedPrompt.contains("from ")
            || normalizedPrompt.contains("between ")
        {
            return true
        }

        return normalizedPrompt.range(of: "\\b\\d{4}-\\d{1,2}-\\d{1,2}\\b", options: .regularExpression) != nil
    }

    private func isBroadOverviewPrompt(_ normalizedPrompt: String) -> Bool {
        let broadOverviewPhrases = [
            "how am i doing",
            "how are we doing",
            "how did i do",
            "budget check in",
            "budget checkin",
            "overview",
            "summary",
            "snapshot"
        ]

        return broadOverviewPhrases.contains { normalizedPrompt.contains($0) }
    }

    private func requiresCategoryTarget(_ metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance, .presetCategorySpend:
            return true
        default:
            return false
        }
    }

    private func requiresCardTarget(_ metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .cardSpendTotal, .cardVariableSpendingHabits:
            return true
        default:
            return false
        }
    }

    private func requiresIncomeTarget(_ metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .incomeSourceShare, .incomeSourceShareTrend:
            return true
        default:
            return false
        }
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func previousMonthRange(from date: Date) -> HomeQueryDateRange {
        let calendar = Calendar.current
        let currentMonth = monthRange(containing: date)
        let previousDate = calendar.date(byAdding: .month, value: -1, to: currentMonth.startDate) ?? currentMonth.startDate
        return monthRange(containing: previousDate)
    }

    private func yearRange(containing date: Date) -> HomeQueryDateRange {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(year: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func uniqueClarificationReasons(
        _ reasons: [HomeAssistantClarificationReason]
    ) -> [HomeAssistantClarificationReason] {
        var unique: [HomeAssistantClarificationReason] = []
        var seen: Set<HomeAssistantClarificationReason> = []

        for reason in reasons {
            if seen.insert(reason).inserted {
                unique.append(reason)
            }
        }

        return unique
    }

    private func updateSessionContext(after query: HomeQuery) {
        sessionContext.lastMetric = query.intent.metric
        sessionContext.lastDateRange = query.dateRange
        sessionContext.lastTargetName = query.targetName
        sessionContext.lastPeriodUnit = query.periodUnit

        if query.intent == .topCategoriesThisMonth
            || query.intent == .largestRecentTransactions
            || query.intent == .savingsAverageRecentPeriods
            || query.intent == .incomeSourceShareTrend
            || query.intent == .categorySpendShareTrend
            || query.intent == .presetDueSoon
            || query.intent == .presetHighestCost
            || query.intent == .presetTopCategory
            || query.intent == .cardVariableSpendingHabits
            || query.intent == .categoryPotentialSavings
            || query.intent == .categoryReallocationGuidance
        {
            sessionContext.lastResultLimit = query.resultLimit
        } else {
            sessionContext.lastResultLimit = nil
        }
    }

    private func contextualPlan(for rawPrompt: String) -> HomeQueryPlan? {
        guard let lastMetric = sessionContext.lastMetric else { return nil }

        let normalized = rawPrompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.isEmpty == false else { return nil }

        let continuationPhrases = [
            "how about", "what about", "and last", "and this", "same", "again", "for that", "for this"
        ]
        let hasContinuationPhrase = continuationPhrases.contains { normalized.contains($0) }
        let hasDatePhrase = parser.parseDateRange(rawPrompt, defaultPeriodUnit: defaultQueryPeriodUnit) != nil

        guard hasContinuationPhrase || hasDatePhrase else { return nil }

        return HomeQueryPlan(
            metric: lastMetric,
            dateRange: parser.parseDateRange(rawPrompt, defaultPeriodUnit: defaultQueryPeriodUnit) ?? sessionContext.lastDateRange,
            resultLimit: parser.parseLimit(rawPrompt) ?? sessionContext.lastResultLimit,
            confidenceBand: .medium,
            targetName: sessionContext.lastTargetName,
            periodUnit: sessionContext.lastPeriodUnit
        )
    }

    private func enrichPlanWithEntities(_ plan: HomeQueryPlan, rawPrompt: String) -> HomeQueryPlan {
        let normalized = rawPrompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        switch plan.metric {
        case .cardSpendTotal, .cardVariableSpendingHabits:
            let isAllCards = normalized.contains("all cards")
            let card = isAllCards
                ? nil
                : (aliasTarget(
                    in: rawPrompt,
                    entityType: .card
                ) ?? entityMatcher.bestCardMatch(in: rawPrompt, cards: cards))
            return HomeQueryPlan(
                metric: plan.metric,
                dateRange: plan.dateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: card == nil ? plan.confidenceBand : .high,
                targetName: card,
                periodUnit: plan.periodUnit
            )

        case .incomeAverageActual, .incomeSourceShare, .incomeSourceShareTrend:
            let isAllSources = normalized.contains("all sources") || normalized.contains("all income")
            let source = isAllSources
                ? nil
                : (aliasTarget(
                    in: rawPrompt,
                    entityType: .incomeSource
                ) ?? entityMatcher.bestIncomeSourceMatch(in: rawPrompt, incomes: incomes))
            return HomeQueryPlan(
                metric: plan.metric,
                dateRange: plan.dateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: source == nil ? plan.confidenceBand : .high,
                targetName: source,
                periodUnit: plan.periodUnit
            )

        case .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance:
            let isAllCategories = normalized.contains("all categories")
            let category = isAllCategories
                ? nil
                : (aliasTarget(
                    in: rawPrompt,
                    entityType: .category
                ) ?? entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories) ?? {
                    if normalized.contains("this category") {
                        return sessionContext.lastTargetName
                    }
                    return nil
                }())
            return HomeQueryPlan(
                metric: plan.metric,
                dateRange: plan.dateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: category == nil ? plan.confidenceBand : .high,
                targetName: category,
                periodUnit: plan.periodUnit
            )

        case .presetCategorySpend:
            let isAllCategories = normalized.contains("all categories")
            let category = isAllCategories
                ? nil
                : (aliasTarget(
                    in: rawPrompt,
                    entityType: .category
                ) ?? entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories))
            return HomeQueryPlan(
                metric: plan.metric,
                dateRange: plan.dateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: category == nil ? plan.confidenceBand : .high,
                targetName: category,
                periodUnit: plan.periodUnit
            )

        case .overview, .spendTotal, .topCategories, .monthComparison, .largestTransactions, .savingsStatus, .savingsAverageRecentPeriods, .presetDueSoon, .presetHighestCost, .presetTopCategory:
            return plan
        }
    }

    private func entityAwarePlan(for rawPrompt: String) -> HomeQueryPlan? {
        let normalized = rawPrompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalized.isEmpty == false else { return nil }

        let range = parser.parseDateRange(rawPrompt, defaultPeriodUnit: defaultQueryPeriodUnit)

        if normalized.contains("income") && (normalized.contains("average") || normalized.contains("avg")) {
            let source = aliasTarget(
                in: rawPrompt,
                entityType: .incomeSource
            ) ?? entityMatcher.bestIncomeSourceMatch(in: rawPrompt, incomes: incomes)

            return HomeQueryPlan(
                metric: .incomeAverageActual,
                dateRange: range,
                resultLimit: nil,
                confidenceBand: source == nil ? .medium : .high,
                targetName: source
            )
        }

        if normalized.contains("income") && (normalized.contains("share") || normalized.contains("comes from") || normalized.contains("how much")) {
            let isAllSources = normalized.contains("all sources") || normalized.contains("all income")
            let source = isAllSources
                ? nil
                : (aliasTarget(
                    in: rawPrompt,
                    entityType: .incomeSource
                ) ?? entityMatcher.bestIncomeSourceMatch(in: rawPrompt, incomes: incomes))

            return HomeQueryPlan(
                metric: .incomeSourceShare,
                dateRange: range,
                resultLimit: nil,
                confidenceBand: source == nil ? .medium : .high,
                targetName: source
            )
        }

        let spendKeywords = ["spend", "spent", "spending", "total spent", "charges"]
        let aliasCard = aliasTarget(in: rawPrompt, entityType: .card)
        let mentionsCardContext = normalized.contains("card")
            || normalized.contains("cards")
            || normalized.contains("all cards")
            || aliasCard != nil
            || entityMatcher.bestCardMatch(in: rawPrompt, cards: cards) != nil

        if spendKeywords.contains(where: { normalized.contains($0) }) && mentionsCardContext {
            let cardName = normalized.contains("all cards")
                ? nil
                : (aliasCard ?? entityMatcher.bestCardMatch(in: rawPrompt, cards: cards))

            return HomeQueryPlan(
                metric: .cardSpendTotal,
                dateRange: range,
                resultLimit: nil,
                confidenceBand: cardName == nil ? .medium : .high,
                targetName: cardName
            )
        }

        if normalized.contains("card")
            && (normalized.contains("habit")
                || normalized.contains("habits")
                || normalized.contains("pattern")
                || normalized.contains("variable spending")
                || normalized.contains("trend"))
        {
            let isAllCards = normalized.contains("all cards")
            let cardName = isAllCards
                ? nil
                : (aliasCard ?? entityMatcher.bestCardMatch(in: rawPrompt, cards: cards))

            return HomeQueryPlan(
                metric: .cardVariableSpendingHabits,
                dateRange: range,
                resultLimit: parser.parseLimit(rawPrompt),
                confidenceBand: cardName == nil ? .medium : .high,
                targetName: cardName
            )
        }

        if normalized.contains("category")
            && spendKeywords.contains(where: { normalized.contains($0) })
            && (normalized.contains("share") || normalized.contains("percent") || normalized.contains("percentage") || normalized.contains("how much"))
        {
            let isAllCategories = normalized.contains("all categories")
            let category = isAllCategories
                ? nil
                : (aliasTarget(
                    in: rawPrompt,
                    entityType: .category
                ) ?? entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories))

            return HomeQueryPlan(
                metric: .categorySpendShare,
                dateRange: range,
                resultLimit: nil,
                confidenceBand: category == nil ? .medium : .high,
                targetName: category
            )
        }

        if normalized.contains("category")
            && (normalized.contains("reduce")
                || normalized.contains("lower")
                || normalized.contains("decrease")
                || normalized.contains("cut"))
            && (normalized.contains("savings") || normalized.contains("save"))
        {
            let isAllCategories = normalized.contains("all categories")
            let category = isAllCategories
                ? nil
                : (aliasTarget(
                    in: rawPrompt,
                    entityType: .category
                ) ?? entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories) ?? {
                    if normalized.contains("this category") {
                        return sessionContext.lastTargetName
                    }
                    return nil
                }())

            return HomeQueryPlan(
                metric: .categoryPotentialSavings,
                dateRange: range,
                resultLimit: parser.parseLimit(rawPrompt),
                confidenceBand: category == nil ? .medium : .high,
                targetName: category
            )
        }

        if normalized.contains("category")
            && (normalized.contains("other categories")
                || normalized.contains("reallocate")
                || normalized.contains("realistically spend")
                || normalized.contains("what could i spend")
                || normalized.contains("what can i spend"))
        {
            let isAllCategories = normalized.contains("all categories")
            let category = isAllCategories
                ? nil
                : (aliasTarget(
                    in: rawPrompt,
                    entityType: .category
                ) ?? entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories) ?? {
                    if normalized.contains("this category") {
                        return sessionContext.lastTargetName
                    }
                    return nil
                }())

            return HomeQueryPlan(
                metric: .categoryReallocationGuidance,
                dateRange: range,
                resultLimit: parser.parseLimit(rawPrompt),
                confidenceBand: category == nil ? .medium : .high,
                targetName: category
            )
        }

        if normalized.contains("preset")
            && normalized.contains("due")
        {
            return HomeQueryPlan(
                metric: .presetDueSoon,
                dateRange: range,
                resultLimit: parser.parseLimit(rawPrompt),
                confidenceBand: .high
            )
        }

        if normalized.contains("preset")
            && (normalized.contains("most expensive")
                || normalized.contains("costs me the most")
                || normalized.contains("highest cost"))
        {
            return HomeQueryPlan(
                metric: .presetHighestCost,
                dateRange: nil,
                resultLimit: parser.parseLimit(rawPrompt),
                confidenceBand: .high
            )
        }

        if normalized.contains("preset")
            && normalized.contains("category")
            && (normalized.contains("assigned") || normalized.contains("most presets"))
        {
            return HomeQueryPlan(
                metric: .presetTopCategory,
                dateRange: nil,
                resultLimit: parser.parseLimit(rawPrompt),
                confidenceBand: .high
            )
        }

        if normalized.contains("preset")
            && normalized.contains("category")
            && (normalized.contains("spend")
                || normalized.contains("cost")
                || normalized.contains("how much")
                || normalized.contains("per period"))
        {
            let isAllCategories = normalized.contains("all categories")
            let category = isAllCategories
                ? nil
                : (aliasTarget(
                    in: rawPrompt,
                    entityType: .category
                ) ?? entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories))

            return HomeQueryPlan(
                metric: .presetCategorySpend,
                dateRange: nil,
                resultLimit: nil,
                confidenceBand: category == nil ? .medium : .high,
                targetName: category
            )
        }

        return nil
    }

    private func applyConfidenceTone(
        to answer: HomeAnswer,
        confidenceBand: HomeQueryConfidenceBand
    ) -> HomeAnswer {
        switch confidenceBand {
        case .high:
            return answer
        case .medium:
            let originalSubtitle = answer.subtitle ?? ""
            let subtitle = originalSubtitle.isEmpty
                ? "Likely match for your request."
                : "Likely match. \(originalSubtitle)"

            return HomeAnswer(
                queryID: answer.queryID,
                kind: answer.kind,
                userPrompt: answer.userPrompt,
                title: answer.title,
                subtitle: subtitle,
                primaryValue: answer.primaryValue,
                rows: answer.rows,
                generatedAt: answer.generatedAt
            )
        case .low:
            let originalSubtitle = answer.subtitle ?? ""
            let subtitle = originalSubtitle.isEmpty
                ? "I made a best-effort match. Use follow-up chips to narrow it down."
                : "Best-effort match. \(originalSubtitle)"

            return HomeAnswer(
                queryID: answer.queryID,
                kind: answer.kind,
                userPrompt: answer.userPrompt,
                title: answer.title,
                subtitle: subtitle,
                primaryValue: answer.primaryValue,
                rows: answer.rows,
                generatedAt: answer.generatedAt
            )
        }
    }

    private func applyPromptAwareTitle(
        to answer: HomeAnswer,
        query: HomeQuery,
        userPrompt: String?
    ) -> HomeAnswer {
        let resolvedTitle = resolvedPromptAwareTitle(
            defaultTitle: answer.title,
            query: query,
            userPrompt: userPrompt
        )
        guard resolvedTitle != answer.title else { return answer }

        return HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: resolvedTitle,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            generatedAt: answer.generatedAt
        )
    }

    private func resolvedPromptAwareTitle(
        defaultTitle: String,
        query: HomeQuery,
        userPrompt: String?
    ) -> String {
        let normalized = normalizedPrompt(userPrompt ?? "")
        let scopeSuffix = promptTimeScopeSuffix(normalizedPrompt: normalized)

        switch query.intent {
        case .largestRecentTransactions:
            let baseTitle: String
            if normalized.contains("purchase") {
                baseTitle = "Purchases"
            } else if normalized.contains("expense") {
                baseTitle = "Expenses"
            } else if normalized.contains("transaction") || normalized.contains("charge") {
                baseTitle = "Transactions"
            } else if normalized.contains("what did i spend")
                || normalized.contains("spend my money on")
                || normalized.contains("where did my money go")
            {
                baseTitle = "Spending"
            } else {
                baseTitle = "Transactions"
            }

            if let scopeSuffix {
                return "\(baseTitle) \(scopeSuffix)"
            }
            return defaultTitle

        case .spendThisMonth:
            if let scopeSuffix {
                return "Spend \(scopeSuffix)"
            }
            return defaultTitle

        default:
            return defaultTitle
        }
    }

    private func promptTimeScopeSuffix(normalizedPrompt: String) -> String? {
        if normalizedPrompt.contains("today") {
            return "Today"
        }
        if normalizedPrompt.contains("yesterday") {
            return "Yesterday"
        }
        if normalizedPrompt.contains("last week") {
            return "Last Week"
        }
        if normalizedPrompt.contains("this week") {
            return "This Week"
        }
        if normalizedPrompt.contains("last month") {
            return "Last Month"
        }
        if normalizedPrompt.contains("this month") {
            return "This Month"
        }
        return nil
    }

    private func shouldRunBroadOverviewBundle(
        for prompt: String,
        plan: HomeQueryPlan
    ) -> Bool {
        guard plan.metric == .overview else { return false }

        let normalized = prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let broadOverviewPhrases = [
            "how am i doing",
            "how are we doing",
            "how did i do",
            "budget check in",
            "budget checkin",
            "overview",
            "summary",
            "snapshot"
        ]

        return broadOverviewPhrases.contains { normalized.contains($0) }
    }

    private func runBroadOverviewBundle(
        userPrompt: String,
        basePlan: HomeQueryPlan
    ) {
        let range = basePlan.dateRange
        let now = Date()

        let overviewQuery = HomeQuery(intent: .periodOverview, dateRange: range)
        let savingsQuery = HomeQuery(intent: .savingsStatus, dateRange: range)
        let categoriesQuery = HomeQuery(intent: .topCategoriesThisMonth, dateRange: range, resultLimit: 3)
        let cardsQuery = HomeQuery(intent: .cardVariableSpendingHabits, dateRange: range, resultLimit: 3)

        let overview = applyConfidenceTone(
            to: engine.execute(
                query: overviewQuery,
                categories: categories,
                presets: presets,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                incomes: incomes,
                now: now
            ),
            confidenceBand: basePlan.confidenceBand
        )
        let savings = applyConfidenceTone(
            to: engine.execute(
                query: savingsQuery,
                categories: categories,
                presets: presets,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                incomes: incomes,
                now: now
            ),
            confidenceBand: basePlan.confidenceBand
        )
        let categoriesAnswer = applyConfidenceTone(
            to: engine.execute(
                query: categoriesQuery,
                categories: categories,
                presets: presets,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                incomes: incomes,
                now: now
            ),
            confidenceBand: basePlan.confidenceBand
        )
        let cardsAnswer = applyConfidenceTone(
            to: engine.execute(
                query: cardsQuery,
                categories: categories,
                presets: presets,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                incomes: incomes,
                now: now
            ),
            confidenceBand: basePlan.confidenceBand
        )

        var rows: [HomeAnswerRow] = []
        var subtitle = overview.subtitle ?? savings.subtitle

        switch basePlan.confidenceBand {
        case .high:
            rows.append(contentsOf: sectionRows("Spend", from: overview, maxRows: 2))
            rows.append(contentsOf: sectionRows("Savings", from: savings, maxRows: 2))
            rows.append(contentsOf: sectionRows("Categories", from: categoriesAnswer, maxRows: 3))
            rows.append(contentsOf: sectionRows("Cards", from: cardsAnswer, maxRows: 3))

        case .medium:
            rows.append(contentsOf: sectionRows("Spend", from: overview, maxRows: 2))
            rows.append(contentsOf: sectionRows("Savings", from: savings, maxRows: 2))
            rows.append(contentsOf: sectionRows("Categories", from: categoriesAnswer, maxRows: 3))
            subtitle = mergedBundleSubtitle(
                base: subtitle,
                appended: "Likely match for your request."
            )

        case .low:
            rows.append(contentsOf: sectionRows("Spend", from: overview, maxRows: 2))
            rows.append(contentsOf: sectionRows("Categories", from: categoriesAnswer, maxRows: 2))
            subtitle = mergedBundleSubtitle(
                base: subtitle,
                appended: "Best-effort summary. Use follow-up chips to narrow this."
            )
        }

        let bundled = HomeAnswer(
            queryID: overviewQuery.id,
            kind: .list,
            userPrompt: userPrompt,
            title: "Budget Check-In",
            subtitle: subtitle,
            primaryValue: overview.primaryValue ?? savings.primaryValue,
            rows: rows
        )

        let styled = personaFormatter.styledAnswer(
            from: bundled,
            userPrompt: userPrompt,
            personaID: selectedPersonaID,
            seedContext: personaSeedContext(for: overviewQuery),
            footerContext: personaFooterContext(
                for: [
                    overviewQuery,
                    savingsQuery,
                    categoriesQuery,
                    cardsQuery
                ]
            ),
            echoContext: nil
        )

        updateSessionContext(after: overviewQuery)
        appendAnswer(styled)
    }

    private func sectionRows(_ section: String, from answer: HomeAnswer, maxRows: Int) -> [HomeAnswerRow] {
        var rows: [HomeAnswerRow] = []

        if let primaryValue = answer.primaryValue {
            rows.append(
                HomeAnswerRow(
                    title: "\(section) Summary",
                    value: primaryValue
                )
            )
        }

        rows.append(
            contentsOf: answer.rows.prefix(maxRows).map { row in
                HomeAnswerRow(
                    title: "\(section): \(row.title)",
                    value: row.value
                )
            }
        )

        return rows
    }

    private func mergedBundleSubtitle(base: String?, appended: String) -> String {
        guard let base, base.isEmpty == false else { return appended }
        return "\(base) • \(appended)"
    }

    private var trimmedPromptText: String {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func personaSeedContext(for query: HomeQuery) -> HomeAssistantPersonaSeedContext {
        let referenceDate = query.dateRange?.endDate ?? Date()
        return HomeAssistantPersonaSeedContext.from(
            actorID: workspace.id.uuidString,
            intentKey: query.intent.rawValue,
            referenceDate: referenceDate
        )
    }

    private func personaFooterContext(for queries: [HomeQuery]) -> HomeAssistantPersonaFooterContext {
        let dateRange = queries.compactMap(\.dateRange).first
        let queryLabels = queries.map { "\($0.intent.rawValue)#\(shortQueryID($0.id))" }
        return HomeAssistantPersonaFooterContext(
            dataWindow: personaDateWindowLabel(dateRange),
            sources: personaSourceLabels(),
            queries: queryLabels
        )
    }

    private func personaDateWindowLabel(_ dateRange: HomeQueryDateRange?) -> String {
        guard let dateRange else { return "Not specified" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: dateRange.startDate)
        let end = formatter.string(from: dateRange.endDate)
        return "\(start)–\(end)"
    }

    private func personaSourceLabels() -> [String] {
        var labels: [String] = []
        if categories.isEmpty == false { labels.append("Categories") }
        if presets.isEmpty == false { labels.append("Presets") }
        if plannedExpenses.isEmpty == false { labels.append("Planned expenses") }
        if variableExpenses.isEmpty == false { labels.append("Variable expenses") }
        if incomes.isEmpty == false { labels.append("Income") }

        if labels.isEmpty {
            return ["On-device budgeting data"]
        }

        return labels
    }

    private func shortQueryID(_ id: UUID) -> String {
        let raw = id.uuidString.replacingOccurrences(of: "-", with: "")
        return String(raw.prefix(8)).uppercased()
    }

    private func personaEchoContext(for query: HomeQuery) -> HomeAssistantPersonaEchoContext? {
        guard let targetName = query.targetName?.trimmingCharacters(in: .whitespacesAndNewlines), targetName.isEmpty == false else {
            return nil
        }

        switch query.intent {
        case .cardSpendTotal, .cardVariableSpendingHabits:
            return HomeAssistantPersonaEchoContext(
                cardName: targetName,
                categoryName: nil,
                incomeSourceName: nil
            )
        case .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance, .presetCategorySpend:
            return HomeAssistantPersonaEchoContext(
                cardName: nil,
                categoryName: targetName,
                incomeSourceName: nil
            )
        case .incomeAverageActual, .incomeSourceShare, .incomeSourceShareTrend:
            return HomeAssistantPersonaEchoContext(
                cardName: nil,
                categoryName: nil,
                incomeSourceName: targetName
            )
        default:
            return nil
        }
    }

    private var panelHeaderBackgroundStyle: AnyShapeStyle {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            return AnyShapeStyle(.clear)
        }
        #endif

        return AnyShapeStyle(.clear)
    }

    private var navigationBarVisibility: Visibility {
        #if os(iOS)
        if #available(iOS 26.0, *) {
            return .hidden
        }
        #endif

        return .visible
    }

    private var conversationBackdrop: some View {
        HomeBackgroundView()
            .opacity(0.3)
            .overlay {
                if #available(iOS 26.0, *) {
                    Color.black.opacity(0.02)
                } else {
                    Color(uiColor: .systemBackground).opacity(0.5)
                }
            }
    }

    private var assistantBubbleBackground: Color {
        Color(uiColor: .systemGray5)
    }

    private var assistantBubbleStroke: Color {
        Color.clear
    }

    private func timestampText(for date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

// MARK: - Mutation Service

private struct MarinaColorResolution {
    let hex: String
    let name: String
    let requiresConfirmation: Bool
}

private enum MarinaColorResolver {
    private static let aliasToHex: [String: String] = [
        "blue": "#3B82F6",
        "green": "#22C55E",
        "forest green": "#228B22",
        "red": "#EF4444",
        "orange": "#F97316",
        "yellow": "#EAB308",
        "purple": "#8B5CF6",
        "pink": "#EC4899",
        "mauve": "#B784A7",
        "periwinkle": "#8FA6FF",
        "cafe": "#6F4E37",
        "brown": "#8B5A2B",
        "teal": "#14B8A6",
        "mint": "#10B981",
        "gray": "#6B7280",
        "grey": "#6B7280",
        "black": "#111827",
        "white": "#E5E7EB"
    ]

    static func resolve(
        rawPrompt: String,
        parserHex: String?,
        parserName: String?
    ) -> MarinaColorResolution {
        if let parserHex, let parserName {
            return MarinaColorResolution(hex: parserHex, name: parserName, requiresConfirmation: false)
        }

        let fallback = MarinaColorResolution(hex: "#3B82F6", name: "blue", requiresConfirmation: false)
        guard let parserName, parserName.isEmpty == false else {
            return fallback
        }

        let normalized = parserName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let hex = aliasToHex[normalized] {
            return MarinaColorResolution(hex: hex, name: normalized, requiresConfirmation: false)
        }

        if let fuzzy = bestFuzzyMatch(for: normalized),
           let hex = aliasToHex[fuzzy] {
            return MarinaColorResolution(hex: hex, name: fuzzy, requiresConfirmation: true)
        }

        let lowered = rawPrompt.lowercased()
        if lowered.contains("green") { return MarinaColorResolution(hex: "#22C55E", name: "green", requiresConfirmation: true) }
        if lowered.contains("red") { return MarinaColorResolution(hex: "#EF4444", name: "red", requiresConfirmation: true) }
        if lowered.contains("orange") { return MarinaColorResolution(hex: "#F97316", name: "orange", requiresConfirmation: true) }
        if lowered.contains("purple") { return MarinaColorResolution(hex: "#8B5CF6", name: "purple", requiresConfirmation: true) }

        return fallback
    }

    private static func bestFuzzyMatch(for token: String) -> String? {
        let candidates = aliasToHex.keys
        var best: (String, Int)?

        for candidate in candidates {
            let distance = levenshtein(token, candidate)
            if distance <= 3 {
                if let best, distance >= best.1 { continue }
                best = (candidate, distance)
            }
        }

        return best?.0
    }

    private static func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        guard a.isEmpty == false else { return b.count }
        guard b.isEmpty == false else { return a.count }

        var costs = Array(0...b.count)

        for i in 1...a.count {
            costs[0] = i
            var corner = i - 1

            for j in 1...b.count {
                let upper = costs[j]
                if a[i - 1] == b[j - 1] {
                    costs[j] = corner
                } else {
                    costs[j] = min(corner, upper, costs[j - 1]) + 1
                }
                corner = upper
            }
        }

        return costs[b.count]
    }
}

@MainActor
private final class HomeAssistantMutationService {
    private let transactionEntryService = TransactionEntryService()

    func addBudget(
        name: String,
        dateRange: HomeQueryDateRange,
        cards: [Card],
        presets: [Preset],
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }

        let budget = Budget(
            name: trimmed,
            startDate: Calendar.current.startOfDay(for: dateRange.startDate),
            endDate: Calendar.current.startOfDay(for: dateRange.endDate),
            workspace: workspace
        )

        modelContext.insert(budget)

        for card in cards {
            modelContext.insert(BudgetCardLink(budget: budget, card: card))
        }

        for preset in presets {
            modelContext.insert(BudgetPresetLink(budget: budget, preset: preset))
        }

        materializePlannedExpenses(
            for: budget,
            selectedPresets: presets,
            selectedCardIDs: Set(cards.map(\.id)),
            workspace: workspace,
            modelContext: modelContext
        )

        try modelContext.save()

        Task {
            await LocalNotificationService.syncFromUserDefaultsIfPossible(
                modelContext: modelContext,
                workspaceID: workspace.id
            )
        }

        return HomeAssistantMutationResult(
            title: "Budget created",
            subtitle: "Saved budget \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Start", value: dateRange.startDate.formatted(date: .abbreviated, time: .omitted)),
                HomeAnswerRow(title: "End", value: dateRange.endDate.formatted(date: .abbreviated, time: .omitted)),
                HomeAnswerRow(title: "Cards", value: "\(cards.count) linked"),
                HomeAnswerRow(title: "Presets", value: "\(presets.count) linked")
            ]
        )
    }

    func addCard(
        name: String,
        themeRaw: String?,
        effectRaw: String?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }

        let theme = CardThemeOption(rawValue: themeRaw ?? "")?.rawValue ?? CardThemeOption.ruby.rawValue
        let effect = CardEffectOption(rawValue: effectRaw ?? "")?.rawValue ?? CardEffectOption.plastic.rawValue
        let card = Card(name: trimmed, theme: theme, effect: effect, workspace: workspace)
        modelContext.insert(card)
        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Card created",
            subtitle: "Saved card \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Theme", value: CardThemeOption(rawValue: theme)?.displayName ?? "Ruby"),
                HomeAnswerRow(title: "Effect", value: CardEffectOption(rawValue: effect)?.displayName ?? "Plastic")
            ]
        )
    }

    func addCategory(
        name: String,
        colorHex: String?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }

        let resolvedHex = (colorHex ?? "#3B82F6").trimmingCharacters(in: .whitespacesAndNewlines)
        let category = Category(name: trimmed, hexColor: resolvedHex, workspace: workspace)
        modelContext.insert(category)
        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Category created",
            subtitle: "Saved category \(trimmed).",
            rows: [HomeAnswerRow(title: "Color", value: resolvedHex)]
        )
    }

    func addPreset(
        title: String,
        plannedAmount: Double,
        card: Card,
        category: Category?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }

        guard plannedAmount > 0 else {
            throw TransactionEntryService.ValidationError.invalidAmount
        }

        let preset = Preset(
            title: trimmed,
            plannedAmount: plannedAmount,
            workspace: workspace,
            defaultCard: card,
            defaultCategory: category
        )
        modelContext.insert(preset)
        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Preset created",
            subtitle: "Saved preset \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: plannedAmount)),
                HomeAnswerRow(title: "Card", value: card.name)
            ]
        )
    }

    func addExpense(
        amount: Double,
        notes: String,
        date: Date,
        card: Card,
        category: Category?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        _ = try transactionEntryService.addExpense(
            notes: notes,
            amount: amount,
            date: date,
            workspace: workspace,
            card: card,
            category: category,
            modelContext: modelContext
        )

        return HomeAssistantMutationResult(
            title: "Expense logged",
            subtitle: "Saved \(CurrencyFormatter.string(from: amount)) on \(card.name).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: "Card", value: card.name),
                HomeAnswerRow(title: "Date", value: date.formatted(date: .abbreviated, time: .omitted))
            ]
        )
    }

    func addIncome(
        amount: Double,
        source: String,
        date: Date,
        isPlanned: Bool,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        _ = try transactionEntryService.addIncome(
            source: source,
            amount: amount,
            date: date,
            isPlanned: isPlanned,
            workspace: workspace,
            modelContext: modelContext
        )

        return HomeAssistantMutationResult(
            title: "Income logged",
            subtitle: "Saved \(CurrencyFormatter.string(from: amount)) as \(isPlanned ? "planned" : "actual") income.",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: "Source", value: source),
                HomeAnswerRow(title: "Date", value: date.formatted(date: .abbreviated, time: .omitted))
            ]
        )
    }

    func updateCardStyle(
        cardName: String,
        workspace: Workspace,
        themeRaw: String,
        effectRaw: String,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        let trimmed = cardName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }

        let workspaceID = workspace.id
        let descriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> {
                $0.workspace?.id == workspaceID && $0.name == trimmed
            }
        )

        guard let card = try modelContext.fetch(descriptor).first else {
            throw NSError(
                domain: "HomeAssistantMutationService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Could not find the card to update."]
            )
        }

        card.theme = CardThemeOption(rawValue: themeRaw)?.rawValue ?? CardThemeOption.ruby.rawValue
        card.effect = CardEffectOption(rawValue: effectRaw)?.rawValue ?? CardEffectOption.plastic.rawValue
        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Card style updated",
            subtitle: "Updated \(trimmed) with your selected theme and effect.",
            rows: [
                HomeAnswerRow(title: "Theme", value: CardThemeOption(rawValue: card.theme)?.displayName ?? "Ruby"),
                HomeAnswerRow(title: "Effect", value: CardEffectOption(rawValue: card.effect)?.displayName ?? "Plastic")
            ]
        )
    }

    private func materializePlannedExpenses(
        for budget: Budget,
        selectedPresets: [Preset],
        selectedCardIDs: Set<UUID>,
        workspace: Workspace,
        modelContext: ModelContext
    ) {
        for preset in selectedPresets {
            let dates = PresetScheduleEngine.occurrences(for: preset, in: budget)

            let defaultCard: Card? = {
                guard let card = preset.defaultCard else { return nil }
                return selectedCardIDs.contains(card.id) ? card : nil
            }()

            for date in dates {
                if plannedExpenseExists(
                    budgetID: budget.id,
                    presetID: preset.id,
                    date: date,
                    modelContext: modelContext
                ) {
                    continue
                }

                modelContext.insert(
                    PlannedExpense(
                        title: preset.title,
                        plannedAmount: preset.plannedAmount,
                        actualAmount: 0,
                        expenseDate: date,
                        workspace: workspace,
                        card: defaultCard,
                        category: preset.defaultCategory,
                        sourcePresetID: preset.id,
                        sourceBudgetID: budget.id
                    )
                )
            }
        }
    }

    private func plannedExpenseExists(
        budgetID: UUID,
        presetID: UUID,
        date: Date,
        modelContext: ModelContext
    ) -> Bool {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate {
                $0.sourceBudgetID == budgetID &&
                $0.sourcePresetID == presetID &&
                $0.expenseDate == day
            }
        )

        do {
            return try modelContext.fetch(descriptor).isEmpty == false
        } catch {
            return false
        }
    }

    func editExpense(
        _ expense: VariableExpense,
        command: HomeAssistantCommandPlan,
        card: Card?,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        if let amount = command.amount, amount > 0 {
            expense.amount = amount
        }
        if let date = command.date {
            expense.transactionDate = Calendar.current.startOfDay(for: date)
        }
        if let notes = command.notes, notes.isEmpty == false {
            expense.descriptionText = notes
        }
        if let card {
            expense.card = card
        }

        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Expense updated",
            subtitle: "Your expense entry was updated.",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: expense.amount)),
                HomeAnswerRow(title: "Description", value: expense.descriptionText),
                HomeAnswerRow(title: "Date", value: expense.transactionDate.formatted(date: .abbreviated, time: .omitted))
            ]
        )
    }

    func editIncome(
        _ income: Income,
        command: HomeAssistantCommandPlan,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        if let amount = command.amount, amount > 0 {
            income.amount = amount
        }
        if let date = command.date {
            income.date = Calendar.current.startOfDay(for: date)
        }
        if let source = command.source, source.isEmpty == false {
            income.source = source
        }
        if let isPlanned = command.isPlannedIncome {
            income.isPlanned = isPlanned
        }

        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Income updated",
            subtitle: "Your income entry was updated.",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: income.amount)),
                HomeAnswerRow(title: "Source", value: income.source),
                HomeAnswerRow(title: "Date", value: income.date.formatted(date: .abbreviated, time: .omitted))
            ]
        )
    }

    func moveExpenseCategory(
        expense: VariableExpense,
        category: Category,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        expense.category = category
        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Expense category updated",
            subtitle: "Moved this expense to \(category.name).",
            rows: [
                HomeAnswerRow(title: "Expense", value: expense.descriptionText),
                HomeAnswerRow(title: "Category", value: category.name)
            ]
        )
    }

    func updatePlannedExpenseAmount(
        expense: PlannedExpense,
        amount: Double,
        target: HomeAssistantPlannedExpenseAmountTarget,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        switch target {
        case .planned:
            expense.plannedAmount = amount
        case .actual:
            expense.actualAmount = amount
        }

        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Planned expense updated",
            subtitle: "Updated \(expense.title).",
            rows: [
                HomeAnswerRow(title: "Planned", value: CurrencyFormatter.string(from: expense.plannedAmount)),
                HomeAnswerRow(title: "Actual", value: CurrencyFormatter.string(from: expense.actualAmount))
            ]
        )
    }

    func deleteExpense(
        _ expense: VariableExpense,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        if let allocation = expense.allocation {
            expense.allocation = nil
            modelContext.delete(allocation)
        }
        if let offsetSettlement = expense.offsetSettlement {
            expense.offsetSettlement = nil
            modelContext.delete(offsetSettlement)
        }
        modelContext.delete(expense)
        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Expense deleted",
            subtitle: "The expense was removed.",
            rows: []
        )
    }

    func deleteIncome(
        _ income: Income,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        modelContext.delete(income)
        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Income deleted",
            subtitle: "The income entry was removed.",
            rows: []
        )
    }

    func matchedExpenses(
        for command: HomeAssistantCommandPlan,
        expenses: [VariableExpense]
    ) -> [VariableExpense] {
        var ranked: [(VariableExpense, Int)] = []

        for expense in expenses {
            var score = 0

            if let targetDate = command.date {
                if Calendar.current.isDate(expense.transactionDate, inSameDayAs: targetDate) {
                    score += 4
                } else {
                    continue
                }
            }

            if let originalAmount = command.originalAmount {
                if abs(expense.amount - originalAmount) < 0.01 {
                    score += 4
                } else {
                    continue
                }
            } else if let amount = command.amount {
                if abs(expense.amount - amount) < 0.01 {
                    score += 2
                }
            }

            if let notes = command.notes?.lowercased(), notes.isEmpty == false {
                if expense.descriptionText.lowercased().contains(notes) {
                    score += 3
                }
            }

            if score > 0 {
                ranked.append((expense, score))
            }
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.transactionDate > rhs.0.transactionDate
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    func matchedIncomes(
        for command: HomeAssistantCommandPlan,
        incomes: [Income]
    ) -> [Income] {
        var ranked: [(Income, Int)] = []

        for income in incomes {
            var score = 0

            if let targetDate = command.date {
                if Calendar.current.isDate(income.date, inSameDayAs: targetDate) {
                    score += 4
                } else {
                    continue
                }
            }

            if let originalAmount = command.originalAmount {
                if abs(income.amount - originalAmount) < 0.01 {
                    score += 4
                } else {
                    continue
                }
            } else if let amount = command.amount {
                if abs(income.amount - amount) < 0.01 {
                    score += 2
                }
            }

            if let source = command.source?.lowercased(), source.isEmpty == false {
                if income.source.lowercased().contains(source) {
                    score += 3
                }
            }

            if let isPlanned = command.isPlannedIncome, income.isPlanned == isPlanned {
                score += 1
            }

            if score > 0 {
                ranked.append((income, score))
            }
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.date > rhs.0.date
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }

    func matchedPlannedExpenses(
        for command: HomeAssistantCommandPlan,
        plannedExpenses: [PlannedExpense]
    ) -> [PlannedExpense] {
        var ranked: [(PlannedExpense, Int)] = []
        let normalizedPrompt = command.rawPrompt.lowercased()

        for expense in plannedExpenses {
            var score = 0

            if let targetDate = command.date {
                if Calendar.current.isDate(expense.expenseDate, inSameDayAs: targetDate) {
                    score += 4
                } else {
                    continue
                }
            }

            if let originalAmount = command.originalAmount {
                if abs(expense.plannedAmount - originalAmount) < 0.01
                    || abs(expense.actualAmount - originalAmount) < 0.01
                {
                    score += 3
                } else {
                    continue
                }
            }

            if normalizedPrompt.contains(expense.title.lowercased()) {
                score += 5
            }

            if let notes = command.notes?.lowercased(),
               notes.isEmpty == false,
               expense.title.lowercased().contains(notes) {
                score += 3
            }

            if score > 0 {
                ranked.append((expense, score))
            }
        }

        return ranked
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.expenseDate > rhs.0.expenseDate
                }
                return lhs.1 > rhs.1
            }
            .map(\.0)
    }
}

// MARK: - Assistant Button Modifiers

private struct AssistantChipButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .compositingGroup()
                .clipShape(Capsule())
        } else {
            content
                .buttonStyle(.bordered)
        }
    }
}

private struct AssistantActionButtonModifier: ViewModifier {
    let prominent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if prominent {
                content
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.capsule)
            } else {
                content
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
            }
        } else {
            if prominent {
                content
                    .buttonStyle(.borderedProminent)
            } else {
                content
                    .buttonStyle(.bordered)
            }
        }
    }
}

private struct AssistantIconButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
        } else {
            content
                .buttonStyle(.borderedProminent)
        }
    }
}
