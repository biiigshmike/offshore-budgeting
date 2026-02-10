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
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Presented Panel

struct HomeAssistantPanelView: View {
    private enum ScrollTarget {
        static let bottomAnchor = "assistant-bottom-anchor"
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
                return "Budget Ideas"
            case .income:
                return "Income Ideas"
            case .card:
                return "Card Ideas"
            case .preset:
                return "Preset Ideas"
            case .category:
                return "Category Ideas"
            case .trends:
                return "Trend Ideas"
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
    @State private var hasLoadedConversation = false
    private let selectedPersonaID: HomeAssistantPersonaID = .marina
    @State private var isShowingClearConversationAlert = false
    @State private var sessionContext = HomeAssistantSessionContext()
    @State private var clarificationSuggestions: [HomeAssistantSuggestion] = []
    @State private var lastClarificationReasons: [HomeAssistantClarificationReason] = []
    @State private var selectedEmptySuggestionGroup: EmptySuggestionGroup?
    @State private var personaSessionSeed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)
    @State private var personaCooldownSessionID: String = UUID().uuidString
    @FocusState private var isPromptFieldFocused: Bool
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

    private let engine = HomeQueryEngine()
    private let parser = HomeAssistantTextParser()
    private let conversationStore = HomeAssistantConversationStore()
    private let telemetryStore = HomeAssistantTelemetryStore()
    private let entityMatcher = HomeAssistantEntityMatcher()
    private let aliasMatcher = HomeAssistantAliasMatcher()

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
                    .padding(.bottom, isPromptFieldFocused ? 170 : 130)
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
                    guard isFocused else { return }
                    dismissEmptySuggestionDrawer()
                    scrollToLatestMessage(using: proxy, animated: true)
                }
                .onAppear {
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
            }
        }
        .background(conversationBackdrop)
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
            Button {
                isShowingClearConversationAlert = true
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 33, height: 33)
            }
            .modifier(AssistantIconButtonModifier())
            .disabled(answers.isEmpty)
            .accessibilityLabel("Clear Chat")

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
        emptyStateSuggestionRail
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
                ForEach(EmptySuggestionGroup.allCases) { group in
                    Button {
                        selectedEmptySuggestionGroup = selectedEmptySuggestionGroup == group ? nil : group
                    } label: {
                        Image(systemName: group.iconName)
                            .font(.subheadline.weight(.semibold))
                            .frame(width: 33, height: 33)
                    }
                    .modifier(AssistantIconButtonModifier())
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

        return "Follow-Up"
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
        VStack(alignment: .leading, spacing: 8) {
            Text(activeSuggestionHeaderTitle)
                .font(.subheadline.weight(.semibold))

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
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 8) {
                Text(answer.title)
                    .font(.headline)

                if let primaryValue = answer.primaryValue {
                    Text(primaryValue)
                        .font(.title3.weight(.semibold))
                }

                if let subtitle = answer.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if answer.rows.isEmpty == false {
                    ForEach(answer.rows) { row in
                        HStack {
                            Text(row.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(row.value)
                                .foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                    }
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

        let answer = personaFormatter.styledAnswer(
            from: rawAnswer,
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

        defer { promptText = "" }

        if let explainPrompt = planExplainPrompt(from: prompt) {
            appendAnswer(planExplanationAnswer(for: explainPrompt))
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
        answers.append(answer)
        conversationStore.saveAnswers(answers, workspaceID: workspace.id)
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
        sessionContext = HomeAssistantSessionContext()
        clarificationSuggestions = []
        lastClarificationReasons = []
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
