//
//  MarinaFoundation.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/8/26.
//

import SwiftUI
import SwiftData
#if os(iOS)
import UIKit
#endif

// MARK: - Assistant State

enum MarinaState: Equatable {
    case collapsed
    case presented
}

enum MarinaAnswerProvenance: String {
    case foundationModels
    case deterministicQuery
    case explicitSuggestion
    case capabilityHelp
    case appleIntelligenceRequired
}

// MARK: - Presented Panel

struct MarinaPanelView: View {
    private enum ScrollTarget {
        static let bottomAnchor = "assistant-bottom-anchor"
    }
    
    private enum MarinaCreateEntityKind {
        case expense
        case budget
        case income
        case card
        case preset
        case category
    }
    
    private enum MarinaBudgetCreationStep {
        case cardsChoice
        case cardsSelection
        case presetsChoice
        case presetsSelection
    }
    
    private enum MarinaCardStyleStep {
        case offer
        case themeSelection
        case effectSelection
    }
    
    private struct AssistantSubtitlePresentation {
        let narrative: String?
        let provenance: String?
    }
    
    let workspace: Workspace
    let onDismiss: () -> Void
    let shouldUseLargeMinimumSize: Bool
    let ambientDateRange: HomeQueryDateRange?
    let cardSummaryExcludeFuturePlannedExpensesOverride: Bool?
    let cardSummaryExcludeFutureVariableExpensesOverride: Bool?
    
    @Query private var budgets: [Budget]
    @Query private var categories: [Category]
    @Query private var cards: [Card]
    @Query private var presets: [Preset]
    @Query private var incomes: [Income]
    @Query private var allocationAccounts: [AllocationAccount]
    @Query private var assistantAliasRules: [AssistantAliasRule]
    @Query private var plannedExpenses: [PlannedExpense]
    @Query private var variableExpenses: [VariableExpense]
    @Query private var savingsAccounts: [SavingsAccount]
    @Query private var savingsEntries: [SavingsLedgerEntry]
    
    @State private var answers: [HomeAnswer] = []
    @State private var promptText = ""
    @State private var pendingUserPromptForNextAnswer: String? = nil
    @State private var pendingThinkingPrompt: String? = nil
    @State private var pendingThinkingStartedAt: Date? = nil
    @State private var latestTraceAccessibilityValue: String = ""
    @State private var quickButtonsVisible = false
    @State private var followUpsCollapsed = false
    @State private var hasLoadedConversation = false
    @State private var isShowingClearConversationAlert = false
    @State private var sessionContext = MarinaSessionContext()
    @State private var clarificationSuggestions: [MarinaSuggestion] = []
    @State private var recoverySuggestions: [MarinaRecoverySuggestion] = []
    @State private var lastClarificationReasons: [MarinaClarificationReason] = []
    @State private var activeClarificationContext: MarinaClarificationContext? = nil
    @State private var foundationPipelineClarification: MarinaTypedClarification? = nil
    @State private var foundationPipelineClarificationChoiceContext: MarinaTypedClarification? = nil
    @State private var foundationPipelineClarificationChoicesByID: [UUID: MarinaClarificationChoice] = [:]
    @State private var foundationPipelineClarificationChoicesByTitle: [String: MarinaClarificationChoice] = [:]
    @State private var selectedEmptySuggestionGroup: MarinaPresetPromptGroup?
    @State private var pendingExpenseCardPlan: MarinaCommandPlan? = nil
    @State private var pendingExpenseCardOptions: [Card] = []
    @State private var pendingPresetCardPlan: MarinaCommandPlan? = nil
    @State private var pendingPresetRecurrencePlan: MarinaCommandPlan? = nil
    @State private var pendingIncomeKindPlan: MarinaCommandPlan? = nil
    @State private var pendingExpenseDisambiguationPlan: MarinaCommandPlan? = nil
    @State private var pendingIncomeDisambiguationPlan: MarinaCommandPlan? = nil
    @State private var pendingCardDisambiguationPlan: MarinaCommandPlan? = nil
    @State private var pendingCategoryDisambiguationPlan: MarinaCommandPlan? = nil
    @State private var pendingPresetDisambiguationPlan: MarinaCommandPlan? = nil
    @State private var pendingBudgetDisambiguationPlan: MarinaCommandPlan? = nil
    @State private var pendingPlannedExpenseDisambiguationPlan: MarinaCommandPlan? = nil
    @State private var pendingExpenseCandidates: [VariableExpense] = []
    @State private var pendingIncomeCandidates: [Income] = []
    @State private var pendingCardCandidates: [Card] = []
    @State private var pendingCategoryCandidates: [Category] = []
    @State private var pendingPresetCandidates: [Preset] = []
    @State private var pendingBudgetCandidates: [Budget] = []
    @State private var pendingDeleteExpense: VariableExpense? = nil
    @State private var pendingDeleteIncome: Income? = nil
    @State private var pendingDeleteCard: Card? = nil
    @State private var pendingDeleteCategory: Category? = nil
    @State private var pendingDeletePreset: Preset? = nil
    @State private var pendingDeleteBudget: Budget? = nil
    @State private var pendingDeletePlannedExpense: PlannedExpense? = nil
    @State private var pendingBudgetCreationPlan: MarinaCommandPlan? = nil
    @State private var pendingBudgetCreationStep: MarinaBudgetCreationStep? = nil
    @State private var pendingBudgetSelectedCardIDs: Set<UUID> = []
    @State private var pendingBudgetSelectedPresetIDs: Set<UUID> = []
    @State private var pendingBudgetMatchingPresets: [Preset] = []
    @State private var pendingCategoryColorPlan: MarinaCommandPlan? = nil
    @State private var pendingCategoryColorHex: String? = nil
    @State private var pendingCategoryColorName: String? = nil
    @State private var pendingCardStyleCardName: String? = nil
    @State private var pendingCardStyleStep: MarinaCardStyleStep? = nil
    @State private var pendingCardStyleTheme: CardThemeOption? = nil
    @State private var pendingPlannedExpenseAmountPlan: MarinaCommandPlan? = nil
    @State private var pendingPlannedExpenseAmountExpense: PlannedExpense? = nil
    @State private var pendingPlannedExpenseCandidates: [PlannedExpense] = []
    @State private var generatedFollowUpSuggestionsByAnswerID: [UUID: [MarinaSuggestion]] = [:]
    @FocusState private var isPromptFieldFocused: Bool
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue
    @AppStorage("general_excludeFuturePlannedExpensesFromCalculations")
    private var excludeFuturePlannedExpensesFromCalculationsDefault: Bool = false
    @AppStorage("general_excludeFutureVariableExpensesFromCalculations")
    private var excludeFutureVariableExpensesFromCalculationsDefault: Bool = false
    @AppStorage("general_confirmBeforeDeleting")
    private var confirmBeforeDeleting: Bool = true
    @AppStorage(MarinaRuntimeSettings.aiOptInKey)
    private var marinaAIOptInEnabled: Bool = MarinaRuntimeSettings.defaultAIOptInEnabled

    private var marinaRuntimeSettings: MarinaRuntimeSettings {
        MarinaRuntimeSettings.resolve(
            aiOptInFallback: marinaAIOptInEnabled
        )
    }
    
    @Environment(\.modelContext) private var modelContext
    private let engine = HomeQueryEngine()
    private let dateRangeTextResolver = MarinaDateRangeTextResolver()
    private let resultLimitExtractor = MarinaResultLimitExtractor()
    private let mutationIntentGuard = MarinaMutationIntentGuard()
    private let conversationStore = MarinaConversationStore()
    private let telemetryStore = MarinaTelemetryStore()
    private let entityMatcher = MarinaEntityMatcher()
    private let aliasMatcher = MarinaAliasMatcher()
    private let executedQueryAnswerNormalizer = MarinaExecutedQueryAnswerNormalizer()
    private let responseGenerationService: any MarinaResponseGenerating = MarinaResponseGenerationService()
    private let followUpSuggestionBuilder = MarinaFollowUpSuggestionBuilder()
    private let mutationService = MarinaMutationService()
    
    private var defaultQueryPeriodUnit: HomeQueryPeriodUnit {
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        return period.queryPeriodUnit
    }

    private var defaultBudgetingPeriod: BudgetingPeriod {
        BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
    }

    private var supportsPromptBackedSuggestions: Bool {
        guard marinaRuntimeSettings.aiOptIn.isEnabled else { return false }
        #if DEBUG
        if MarinaTypedFixtureInterpreter.isEnabled {
            return true
        }
        #endif
        return MarinaModelAvailability().currentStatus() == .available
    }

    private var presetPromptContext: MarinaPresetPromptContext {
        MarinaPresetPromptContext(
            budgetNames: budgets.map(\.name),
            cardNames: cards.map(\.name),
            categoryNames: categories.map(\.name),
            presetTitles: presets.map(\.title),
            incomeSourceNames: recentIncomeSourceNames,
            savingsAccountNames: savingsAccounts.map(\.name),
            allocationAccountNames: allocationAccounts.map(\.name),
            supportsPromptBackedSuggestions: supportsPromptBackedSuggestions
        )
    }

    private var recentIncomeSourceNames: [String] {
        var seen: Set<String> = []
        var names: [String] = []
        for income in incomes.sorted(by: { $0.date > $1.date }) {
            let source = income.source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard source.isEmpty == false else { continue }
            guard seen.insert(source.lowercased()).inserted else { continue }
            names.append(source)
        }
        return names
    }

    private var cardSummaryExcludeFuturePlannedExpenses: Bool {
        cardSummaryExcludeFuturePlannedExpensesOverride ?? excludeFuturePlannedExpensesFromCalculationsDefault
    }

    private var cardSummaryExcludeFutureVariableExpenses: Bool {
        cardSummaryExcludeFutureVariableExpensesOverride ?? excludeFutureVariableExpensesFromCalculationsDefault
    }

    private func cardSummaryDateRange() -> HomeQueryDateRange {
        if let ambientDateRange {
            return ambientDateRange
        }

        let calendar = Calendar.current
        let range = defaultBudgetingPeriod.defaultRange(
            containing: marinaRuntimeSettings.now,
            calendar: calendar
        )
        return HomeQueryDateRange(
            startDate: calendar.startOfDay(for: range.start),
            endDate: range.end
        )
    }

    private func visualAttachmentAnswer(from answer: HomeAnswer) -> HomeAnswer {
        MarinaVisualAttachmentBuilder().attachingVisualAttachmentIfNeeded(
            to: answer,
            workspace: workspace,
            cards: cards,
            allocationAccounts: allocationAccounts,
            savingsAccounts: savingsAccounts,
            categories: categories,
            presets: presets,
            variableExpenses: variableExpenses,
            plannedExpenses: plannedExpenses,
            savingsEntries: savingsEntries,
            dateRange: cardSummaryDateRange(),
            excludeFuturePlannedExpenses: cardSummaryExcludeFuturePlannedExpenses,
            excludeFutureVariableExpenses: cardSummaryExcludeFutureVariableExpenses
        )
    }
    
    init(
        workspace: Workspace,
        onDismiss: @escaping () -> Void,
        shouldUseLargeMinimumSize: Bool,
        ambientDateRange: HomeQueryDateRange? = nil,
        cardSummaryExcludeFuturePlannedExpensesOverride: Bool? = nil,
        cardSummaryExcludeFutureVariableExpensesOverride: Bool? = nil
    ) {
        self.workspace = workspace
        self.onDismiss = onDismiss
        self.shouldUseLargeMinimumSize = shouldUseLargeMinimumSize
        self.ambientDateRange = ambientDateRange
        self.cardSummaryExcludeFuturePlannedExpensesOverride = cardSummaryExcludeFuturePlannedExpensesOverride
        self.cardSummaryExcludeFutureVariableExpensesOverride = cardSummaryExcludeFutureVariableExpensesOverride
        
        let workspaceID = workspace.id

        _budgets = Query(
            filter: #Predicate<Budget> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Budget.startDate, order: .reverse)]
        )
        
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
        
        _savingsEntries = Query(
            filter: #Predicate<SavingsLedgerEntry> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\SavingsLedgerEntry.date, order: .forward)]
        )

        _savingsAccounts = Query(
            filter: #Predicate<SavingsAccount> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\SavingsAccount.name, order: .forward)]
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

        _allocationAccounts = Query(
            filter: #Predicate<AllocationAccount> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\AllocationAccount.name, order: .forward)]
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
                        if answers.isEmpty && pendingThinkingPrompt == nil {
                            marinaEmptyState
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
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .frame(width: 33, height: 33)
                    }
                    .modifier(AssistantPanelIconButtonModifier())
                    .accessibilityLabel(String(localized: "assistant.close", defaultValue: "Close Assistant", comment: "Accessibility label for closing assistant."))
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    clearConversationButton
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
            .alert(String(localized: "assistant.clearHistory.confirmation", defaultValue: "Are you sure you want to clear your chat history?", comment: "Confirmation prompt before clearing assistant chat history."), isPresented: $isShowingClearConversationAlert) {
                Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Cancel action label."), role: .cancel) {}
                Button(String(localized: "common.clear", defaultValue: "Clear", comment: "Action to clear a selection."), role: .destructive) {
                    clearConversation()
                }
            }
            .onAppear {
                loadConversationIfNeeded()
                prewarmFoundationModelsIfNeeded()
            }
            .accessibilityIdentifier("marina.panel")
            .overlay(alignment: .topLeading) {
                debugTraceAccessibilityOverlay
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
                Section(String(localized: "assistant.createNew.section", defaultValue: "Create New", comment: "Section title for assistant create-new menu.")) {
                    Button {
                        handleCreateMenuSelection(.expense)
                    } label: {
                        Label("Expense", systemImage: "plus.circle")
                    }

                    Button {
                        handleCreateMenuSelection(.budget)
                    } label: {
                        Label(String(localized: "app.section.budgets", defaultValue: "Budgets", comment: "Main tab title for the Budgets section."), systemImage: "chart.pie.fill")
                    }
                    
                    Button {
                        handleCreateMenuSelection(.income)
                    } label: {
                        Label(String(localized: "app.section.income", defaultValue: "Income", comment: "Main tab title for the Income section."), systemImage: "calendar")
                    }
                    
                    Button {
                        handleCreateMenuSelection(.card)
                    } label: {
                        Label(String(localized: "common.card", defaultValue: "Card", comment: "Label for card entity."), systemImage: "creditcard")
                    }
                    
                    Button {
                        handleCreateMenuSelection(.preset)
                    } label: {
                        Label(String(localized: "common.preset", defaultValue: "Preset", comment: "Label for preset entity."), systemImage: "list.bullet.rectangle")
                    }
                    
                    Button {
                        handleCreateMenuSelection(.category)
                    } label: {
                        Label(String(localized: "categories.title.singular", defaultValue: "Category", comment: "Label for category entity."), systemImage: "tag.fill")
                    }

                }
            } label: {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 33, height: 33)
            }
            .modifier(AssistantIconButtonModifier())
            .accessibilityLabel(String(localized: "assistant.createNew.section", defaultValue: "Create New", comment: "Section title for assistant create-new menu."))
            
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
            .accessibilityLabel(String(localized: "assistant.submitQuestion", defaultValue: "Submit Question", comment: "Accessibility label for submitting assistant question."))
            .accessibilityIdentifier("marina.submitButton")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var debugTraceAccessibilityOverlay: some View {
        #if DEBUG
        if UITestSupport.shouldRunMarinaHarness {
            Text(latestTraceAccessibilityValue)
                .font(.caption2)
                .frame(width: 1, height: 1)
                .opacity(0.01)
                .accessibilityIdentifier("marina.trace.latest")
                .accessibilityLabel("Marina trace latest")
                .accessibilityValue(latestTraceAccessibilityValue)
        }
        #endif
    }
    
    private func handleCreateMenuSelection(_ kind: MarinaCreateEntityKind) {
        appendInlineCreateForm(
            makeInlineCreateForm(
                for: {
                    switch kind {
                    case .expense:
                        return .expense
                    case .budget:
                        return .budget
                    case .income:
                        return .income
                    case .card:
                        return .card
                    case .preset:
                        return .preset
                    case .category:
                        return .category
                    }
                }(),
                command: nil
            )
        )
    }

    private var clearConversationButton: some View {
        Button {
            isShowingClearConversationAlert = true
        } label: {
            Text(String(localized: "common.clear", defaultValue: "Clear", comment: "Action to clear a selection."))
                .frame(height: 33)
        }
        .modifier(AssistantPanelActionButtonModifier())
        .disabled(answers.isEmpty)
        .accessibilityLabel(String(localized: "assistant.clearChat", defaultValue: "Clear Chat", comment: "Accessibility label for clearing assistant chat."))
    }

    private func prewarmFoundationModelsIfNeeded() {
        guard marinaAIOptInEnabled else { return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            Task {
                let provider = MarinaFoundationModelsSessionProvider()
                provider.prewarm(
                    instructions: MarinaFoundationSurfacePromptBuilder.instructions(),
                    promptPrefix: "User prompt:"
                )
                provider.prewarm(
                    instructions: "Prompt version: \(MarinaFoundationPromptVersion.interpretation.rawValue)\nExtract coarse Marina budgeting language for deterministic Offshore execution.",
                    promptPrefix: "User prompt:"
                )
            }
        }
        #endif
    }
    
    private func creationGuidance(
        for kind: MarinaCreateEntityKind
    ) -> (title: String, subtitle: String, rows: [HomeAnswerRow]) {
        switch kind {
        case .expense:
            return (
                title: "Create New Expense",
                subtitle: "Log an expense with its description, amount, date, card, and optional category.",
                rows: [
                    HomeAnswerRow(title: "Example 1", value: "log $25 for coffee on Apple Card"),
                    HomeAnswerRow(title: "Example 2", value: "add expense groceries $84 on Friday")
                ]
            )
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

    private func appendInlineCreateForm(_ form: MarinaInlineCreateForm) {
        clearMutationPendingState()
        appendAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "Create \(form.entity.displayTitle)",
                subtitle: nil,
                attachment: .inlineCreateForm(form)
            )
        )
    }

    private func inlineCreateFormBinding(for answerID: UUID) -> Binding<MarinaInlineCreateForm>? {
        guard currentInlineCreateForm(for: answerID) != nil else { return nil }
        return Binding(
            get: { currentInlineCreateForm(for: answerID) ?? makeInlineCreateForm(for: .expense, command: nil) },
            set: { updated in
                updateInlineCreateForm(answerID: answerID, form: updated)
            }
        )
    }

    private func currentInlineCreateForm(for answerID: UUID) -> MarinaInlineCreateForm? {
        guard let answer = answers.first(where: { $0.id == answerID }),
              case let .inlineCreateForm(form)? = answer.attachment else {
            return nil
        }
        return form
    }

    private func updateInlineCreateForm(answerID: UUID, form: MarinaInlineCreateForm) {
        guard let index = answers.firstIndex(where: { $0.id == answerID }) else { return }
        let answer = answers[index]
        answers[index] = HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            attachment: .inlineCreateForm(form),
            generatedAt: answer.generatedAt
        )
        conversationStore.saveAnswers(answers, workspaceID: workspace.id)
    }

    private func finalizeInlineCreateForm(
        answerID: UUID,
        subtitle: String,
        rows: [HomeAnswerRow]
    ) {
        guard let index = answers.firstIndex(where: { $0.id == answerID }) else { return }
        let answer = answers[index]
        answers[index] = HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: subtitle,
            primaryValue: answer.primaryValue,
            rows: rows,
            attachment: nil,
            generatedAt: answer.generatedAt
        )
        conversationStore.saveAnswers(answers, workspaceID: workspace.id)
    }

    private func cancelInlineCreateForm(answerID: UUID) {
        guard let form = currentInlineCreateForm(for: answerID) else { return }
        finalizeInlineCreateForm(
            answerID: answerID,
            subtitle: "Draft canceled.",
            rows: inlineCreateSummaryRows(for: form)
        )
    }

    private func submitInlineCreateForm(answerID: UUID) {
        guard var form = currentInlineCreateForm(for: answerID) else { return }
        form.showsValidation = true
        updateInlineCreateForm(answerID: answerID, form: form)

        do {
            let result = try executeInlineCreateForm(form)
            finalizeInlineCreateForm(
                answerID: answerID,
                subtitle: "Sent back to Marina.",
                rows: inlineCreateSummaryRows(for: form)
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not create \(form.entity.displayTitle.lowercased())",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func missingSelectionError(_ description: String) -> NSError {
        NSError(domain: "MarinaInlineCreateForm", code: 400, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private func executeInlineCreateForm(_ form: MarinaInlineCreateForm) throws -> MarinaMutationResult {
        switch form.entity {
        case .expense:
            guard let amount = CurrencyFormatter.parseAmount(form.amountText), amount > 0 else {
                throw TransactionEntryService.ValidationError.invalidAmount
            }
            guard let card = cards.first(where: { $0.id == form.selectedCardID }) else {
                throw missingSelectionError("Select a card to continue.")
            }
            return try mutationService.addExpense(
                amount: amount,
                notes: form.notesText.trimmingCharacters(in: .whitespacesAndNewlines),
                date: calendarStartOfDay(form.date),
                card: card,
                category: categories.first(where: { $0.id == form.selectedCategoryID }),
                workspace: workspace,
                modelContext: modelContext
            )
        case .income:
            guard let amount = CurrencyFormatter.parseAmount(form.amountText), amount > 0 else {
                throw TransactionEntryService.ValidationError.invalidAmount
            }
            let frequency = RecurrenceFrequency(rawValue: form.recurrenceFrequencyRaw) ?? .none
            return try mutationService.addIncome(
                amount: amount,
                source: form.sourceText.trimmingCharacters(in: .whitespacesAndNewlines),
                date: calendarStartOfDay(form.date),
                isPlanned: form.isPlannedIncome,
                recurrenceFrequencyRaw: frequency.rawValue,
                recurrenceInterval: form.recurrenceInterval,
                weeklyWeekday: form.weeklyWeekday,
                monthlyDayOfMonth: form.monthlyDayOfMonth,
                monthlyIsLastDay: form.monthlyIsLastDay,
                yearlyMonth: form.yearlyMonth,
                yearlyDayOfMonth: form.yearlyDayOfMonth,
                recurrenceEndDate: frequency == .none ? nil : calendarStartOfDay(form.secondaryDate),
                workspace: workspace,
                modelContext: modelContext
            )
        case .budget:
            return try mutationService.addBudget(
                name: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines),
                dateRange: HomeQueryDateRange(startDate: form.date, endDate: form.secondaryDate),
                cards: cards.filter { form.selectedCardIDs.contains($0.id) },
                presets: presets.filter { form.selectedPresetIDs.contains($0.id) },
                workspace: workspace,
                modelContext: modelContext
            )
        case .card:
            return try mutationService.addCard(
                name: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines),
                themeRaw: form.cardThemeRaw,
                effectRaw: form.cardEffectRaw,
                workspace: workspace,
                modelContext: modelContext
            )
        case .preset:
            guard let amount = CurrencyFormatter.parseAmount(form.amountText), amount > 0 else {
                throw TransactionEntryService.ValidationError.invalidAmount
            }
            guard let card = cards.first(where: { $0.id == form.selectedCardID }) else {
                throw missingSelectionError("Select a default card to continue.")
            }
            return try mutationService.addPreset(
                title: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines),
                plannedAmount: amount,
                frequencyRaw: form.recurrenceFrequencyRaw,
                interval: max(1, form.recurrenceInterval),
                weeklyWeekday: form.weeklyWeekday,
                monthlyDayOfMonth: form.monthlyDayOfMonth,
                monthlyIsLastDay: form.monthlyIsLastDay,
                yearlyMonth: form.yearlyMonth,
                yearlyDayOfMonth: form.yearlyDayOfMonth,
                card: card,
                category: categories.first(where: { $0.id == form.selectedCategoryID }),
                workspace: workspace,
                modelContext: modelContext
            )
        case .category:
            return try mutationService.addCategory(
                name: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines),
                colorHex: form.categoryColorHex,
                workspace: workspace,
                modelContext: modelContext
            )
        case .plannedExpense:
            throw missingSelectionError("Create a preset to generate planned expenses, or log a regular expense instead.")
        }
    }

    private func inlineCreateSummaryRows(for form: MarinaInlineCreateForm) -> [HomeAnswerRow] {
        switch form.entity {
        case .expense:
            return [
                HomeAnswerRow(title: "Description", value: form.notesText.trimmingCharacters(in: .whitespacesAndNewlines)),
                HomeAnswerRow(title: "Amount", value: form.amountText),
                HomeAnswerRow(title: "Card", value: cards.first(where: { $0.id == form.selectedCardID })?.name ?? "Select"),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(form.date))
            ]
        case .income:
            var rows = [
                HomeAnswerRow(title: "Source", value: form.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)),
                HomeAnswerRow(title: "Amount", value: form.amountText),
                HomeAnswerRow(title: "Type", value: form.isPlannedIncome ? "Planned" : "Actual")
            ]
            let frequency = RecurrenceFrequency(rawValue: form.recurrenceFrequencyRaw) ?? .none
            if frequency != .none {
                rows.append(HomeAnswerRow(title: "Repeat", value: frequency.displayName))
            }
            return rows
        case .budget:
            return [
                HomeAnswerRow(title: "Name", value: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines)),
                HomeAnswerRow(title: "Start", value: AppDateFormat.abbreviatedDate(form.date)),
                HomeAnswerRow(title: "End", value: AppDateFormat.abbreviatedDate(form.secondaryDate)),
                HomeAnswerRow(title: "Cards", value: AppNumberFormat.integer(form.selectedCardIDs.count)),
                HomeAnswerRow(title: "Presets", value: AppNumberFormat.integer(form.selectedPresetIDs.count))
            ]
        case .card:
            return [
                HomeAnswerRow(title: "Name", value: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines)),
                HomeAnswerRow(title: "Theme", value: CardThemeOption(rawValue: form.cardThemeRaw)?.displayName ?? "Ruby"),
                HomeAnswerRow(title: "Effect", value: CardEffectOption(rawValue: form.cardEffectRaw)?.displayName ?? "Plastic")
            ]
        case .preset:
            return [
                HomeAnswerRow(title: "Name", value: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines)),
                HomeAnswerRow(title: "Amount", value: form.amountText),
                HomeAnswerRow(title: "Card", value: cards.first(where: { $0.id == form.selectedCardID })?.name ?? "Select")
            ]
        case .category:
            return [
                HomeAnswerRow(title: "Name", value: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines)),
                HomeAnswerRow(title: "Color", value: form.categoryColorHex)
            ]
        case .plannedExpense:
            return []
        }
    }

    private func amountInputString(_ value: Double?) -> String {
        guard let value else { return "" }
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func calendarStartOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func makeInlineCreateForm(
        for entity: MarinaInlineCreateEntity,
        command: MarinaCommandPlan?
    ) -> MarinaInlineCreateForm {
        let now = calendarStartOfDay(Date())
        let periodRange = defaultBudgetingPeriod.defaultRange(containing: now, calendar: .current)
        let seededRange = command?.dateRange ?? HomeQueryDateRange(startDate: periodRange.start, endDate: periodRange.end)
        let colorResolution = MarinaColorResolver.resolve(
            rawPrompt: command?.rawPrompt ?? "",
            parserHex: command?.categoryColorHex,
            parserName: command?.categoryColorName
        )
        let resolvedCardID = command?.cardName.flatMap { resolveCard(from: $0)?.id } ?? (cards.count == 1 ? cards.first?.id : nil)
        let resolvedCategoryID = command?.categoryName.flatMap { resolveCategory(from: $0)?.id }

        switch entity {
        case .expense:
            return MarinaInlineCreateForm(
                entity: .expense,
                summary: command == nil ? nil : "I prefilled the expense details from your message.",
                amountText: amountInputString(command?.amount),
                date: command?.date ?? now,
                notesText: command?.notes ?? "",
                selectedCardID: resolvedCardID,
                selectedCategoryID: resolvedCategoryID
            )
        case .income:
            return MarinaInlineCreateForm(
                entity: .income,
                summary: command == nil ? nil : "I prefilled the income details from your message.",
                amountText: amountInputString(command?.amount),
                date: command?.date ?? now,
                secondaryDate: command?.recurrenceEndDate ?? command?.date ?? now,
                sourceText: command?.source ?? command?.notes ?? "",
                isPlannedIncome: command?.isPlannedIncome ?? false,
                recurrenceFrequencyRaw: command?.recurrenceFrequencyRaw ?? RecurrenceFrequency.none.rawValue,
                recurrenceInterval: max(1, command?.recurrenceInterval ?? 1),
                weeklyWeekday: command?.weeklyWeekday ?? 6,
                monthlyDayOfMonth: command?.monthlyDayOfMonth ?? 15,
                monthlyIsLastDay: command?.monthlyIsLastDay ?? false,
                yearlyMonth: command?.yearlyMonth ?? 1,
                yearlyDayOfMonth: command?.yearlyDayOfMonth ?? 15
            )
        case .budget:
            return MarinaInlineCreateForm(
                entity: .budget,
                summary: command == nil ? nil : "I prefilled the budget details from your message.",
                nameText: command?.entityName ?? BudgetNameSuggestion.suggestedName(start: seededRange.startDate, end: seededRange.endDate, calendar: .current),
                date: seededRange.startDate,
                secondaryDate: seededRange.endDate,
                selectedCardIDs: command?.attachAllCards == true ? cards.map(\.id) : resolvedSelectedCardIDs(from: command),
                selectedPresetIDs: command?.attachAllPresets == true ? presets.map(\.id) : resolvedSelectedPresetIDs(from: command)
            )
        case .card:
            return MarinaInlineCreateForm(
                entity: .card,
                summary: command == nil ? nil : "I prefilled the card details from your message.",
                nameText: command?.entityName ?? command?.notes ?? "",
                cardThemeRaw: command?.cardThemeRaw ?? CardThemeOption.ruby.rawValue,
                cardEffectRaw: command?.cardEffectRaw ?? CardEffectOption.plastic.rawValue
            )
        case .preset:
            return MarinaInlineCreateForm(
                entity: .preset,
                summary: command == nil ? nil : "I prefilled the preset details from your message.",
                nameText: command?.entityName ?? command?.notes ?? "",
                amountText: amountInputString(command?.amount),
                selectedCardID: resolvedCardID,
                selectedCategoryID: resolvedCategoryID,
                recurrenceFrequencyRaw: command?.recurrenceFrequencyRaw ?? RecurrenceFrequency.monthly.rawValue,
                recurrenceInterval: max(1, command?.recurrenceInterval ?? 1),
                weeklyWeekday: command?.weeklyWeekday ?? 6,
                monthlyDayOfMonth: command?.monthlyDayOfMonth ?? 15,
                monthlyIsLastDay: command?.monthlyIsLastDay ?? false,
                yearlyMonth: command?.yearlyMonth ?? 1,
                yearlyDayOfMonth: command?.yearlyDayOfMonth ?? 15
            )
        case .category:
            return MarinaInlineCreateForm(
                entity: .category,
                summary: command == nil ? nil : "I prefilled the category details from your message.",
                nameText: command?.entityName ?? command?.notes ?? "",
                categoryColorHex: colorResolution.hex
            )
        case .plannedExpense:
            return MarinaInlineCreateForm(
                entity: .plannedExpense,
                summary: command == nil ? nil : "I prefilled the planned expense details from your message.",
                nameText: command?.entityName ?? command?.notes ?? "",
                amountText: amountInputString(command?.amount),
                date: command?.date ?? now,
                selectedCardID: resolvedCardID,
                selectedCategoryID: resolvedCategoryID
            )
        }
    }

    private func resolvedSelectedCardIDs(from command: MarinaCommandPlan?) -> [UUID] {
        guard let command else { return [] }
        return command.selectedCardNames.compactMap { name in
            resolveCard(from: name)?.id
        }
    }

    private func resolvedSelectedPresetIDs(from command: MarinaCommandPlan?) -> [UUID] {
        guard let command else { return [] }
        return command.selectedPresetTitles.compactMap { title in
            presets.first(where: { $0.title.compare(title, options: .caseInsensitive) == .orderedSame })?.id
        }
    }

    @ViewBuilder
    private var promptTextField: some View {
        if #available(iOS 26.0, *) {
            TextField(String(localized: "assistant.messagePrompt", defaultValue: "Message Marina", comment: "Prompt placeholder for assistant message input."), text: $promptText)
                .textFieldStyle(.automatic)
                .focused($isPromptFieldFocused)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .accessibilityIdentifier("marina.promptField")
//                .background(Color.white.opacity(0.28), in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color.gray.opacity(0.25), lineWidth: 1)
                }
                .onSubmit {
                    submitPrompt()
                }
        } else {
            TextField(String(localized: "assistant.messagePrompt", defaultValue: "Message Marina", comment: "Prompt placeholder for assistant message input."), text: $promptText)
                .textFieldStyle(.automatic)
                .focused($isPromptFieldFocused)
                .frame(minHeight: 44)
                .accessibilityIdentifier("marina.promptField")
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
                                    handleSuggestionTap(suggestion)
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
                let groups = Array(MarinaPresetPromptGroup.allCases.enumerated())
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
    
    private func inlineConversationSuggestionSections(
        for answer: HomeAnswer
    ) -> [MarinaSuggestionSection] {
        let groundedQuery = sessionContext.recentAnswerContexts.last?.executedPlan?.query
            ?? sessionContext.recentAnswerContexts.last?.query
        let followUps = generatedFollowUpSuggestionsByAnswerID[answer.id]
            ?? followUpSuggestionBuilder.suggestions(
                after: answer,
                executedQuery: groundedQuery,
                supportsPromptBackedSuggestions: supportsPromptBackedSuggestions
            )
        let sections = MarinaSuggestionSectionBuilder.build(
            clarificationSuggestions: clarificationSuggestions,
            clarificationReasonCount: lastClarificationReasons.count,
            recoverySuggestions: recoverySuggestions,
            followUpSuggestions: followUps
        )
        return sections
    }
    
    private func emptyStateSuggestions(for group: MarinaPresetPromptGroup) -> [MarinaSuggestion] {
        MarinaPresetPromptCatalog.suggestions(
            for: group,
            defaultPeriodUnit: defaultQueryPeriodUnit,
            context: presetPromptContext
        )
    }

    private var marinaEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.wave")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            Text("Marina")
                .font(.title2.weight(.semibold))

            marinaBetaBadge

            Text(marinaEmptyStateDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)

            marinaAppleIntelligenceRequirementBadge
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("marina.emptyState")
    }

    @ViewBuilder
    private var marinaBetaBadge: some View {
        let badge = Text(String(localized: "assistant.marina.betaBadge", defaultValue: "BETA", comment: "Short badge indicating Marina is in beta."))
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color("AccentColor"))
            .tracking(0.8)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .accessibilityIdentifier("marina.betaBadge")

        if #available(iOS 26.0, *) {
            badge
                .glassEffect(.regular, in: .capsule)
        } else {
            badge
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule()
                        .stroke(Color("AccentColor").opacity(0.24), lineWidth: 1)
                }
        }
    }

    private var marinaAppleIntelligenceRequirementBadge: some View {
        Label {
            Text(
                String(
                    localized: "assistant.marina.appleIntelligenceRequirement",
                    defaultValue: "Requires Apple Intelligence with \(marinaRequiredPlatformDisplayName) or higher",
                    comment: "Requirement badge shown on Marina's empty assistant state."
                )
            )
        } icon: {
            Image(systemName: "apple.intelligence")
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color("AccentColor"))
        .lineLimit(2)
        .minimumScaleFactor(0.82)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color("AccentColor").opacity(0.24), lineWidth: 1)
        }
        .accessibilityIdentifier("marina.appleIntelligenceRequirementBadge")
    }

    private var marinaRequiredPlatformDisplayName: String {
#if os(macOS)
        return "macOS 26"
#elseif targetEnvironment(macCatalyst)
        return "macOS 26"
#elseif os(iOS)
        if ProcessInfo.processInfo.isiOSAppOnMac {
            return "macOS 26"
        }

        switch UIDevice.current.userInterfaceIdiom {
        case .pad:
            return "iPadOS 26"
        case .mac:
            return "macOS 26"
        default:
            return "iOS 26"
        }
#else
        return "iOS 26"
#endif
    }
    
    private var marinaEmptyStateDescription: String {
        String(
            localized: "assistant.marina.emptyDescription",
            defaultValue: "I’ll help you stay encouraged and grounded with quick, practical reads on your spending and trends.",
            comment: "Introductory Marina description shown in the empty assistant state."
        )
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
                            .accessibilityIdentifier("marina.userMessage.\(index)")
                    }
                    
                    assistantMessageBubble(for: answer, index: index)
                    
                    if index == answers.count - 1, selectedEmptySuggestionGroup == nil {
                        let sections = inlineConversationSuggestionSections(for: answer)
                        if sections.isEmpty == false {
                            assistantFollowUpRail(sections: sections)
                        }
                    }
                }
            }

            if let pendingThinkingPrompt {
                pendingThinkingTurn(
                    prompt: pendingThinkingPrompt,
                    generatedAt: pendingThinkingStartedAt ?? Date()
                )
            }
        }
        .accessibilityIdentifier("marina.answerList")
    }

    private func pendingThinkingTurn(prompt: String, generatedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            userMessageBubble(text: prompt, generatedAt: generatedAt)
                .accessibilityIdentifier("marina.pendingUserMessage")

            assistantThinkingBubble(generatedAt: generatedAt)
        }
    }

    private func assistantThinkingBubble(generatedAt: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Thinking...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(assistantBubbleBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(assistantBubbleStroke, lineWidth: 1)
                }
                .accessibilityIdentifier("marina.thinking")
                .accessibilityLabel("Marina is thinking")

            Text(timestampText(for: generatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
    
    private func assistantFollowUpRail(
        sections: [MarinaSuggestionSection]
    ) -> some View {
        let hasPrioritySections = sections.contains { $0.title != "Follow-Up Suggestions" }
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Suggestions")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if hasPrioritySections == false {
                    if #available(iOS 26.0, *) {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                followUpsCollapsed.toggle()
                            }
                        } label: {
                            Image(systemName: followUpsCollapsed ? "ellipsis.message.fill" : "xmark")
                                .font(.footnote.weight(.semibold))
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .accessibilityLabel(
                            followUpsCollapsed
                                ? String(localized: "assistant.followups.show", defaultValue: "Show follow-up suggestions", comment: "Accessibility label to expand follow-up suggestions.")
                                : String(localized: "assistant.followups.hide", defaultValue: "Hide follow-up suggestions", comment: "Accessibility label to collapse follow-up suggestions.")
                        )
                    } else {
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
                        .accessibilityLabel(
                            followUpsCollapsed
                                ? String(localized: "assistant.followups.show", defaultValue: "Show follow-up suggestions", comment: "Accessibility label to expand follow-up suggestions.")
                                : String(localized: "assistant.followups.hide", defaultValue: "Hide follow-up suggestions", comment: "Accessibility label to collapse follow-up suggestions.")
                        )
                    }
                }
            }
            
            if hasPrioritySections || followUpsCollapsed == false {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("marina.suggestionSection.\(normalizedAccessibilityToken(section.title))")

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(Array(section.suggestions.enumerated()), id: \.element.id) { chipIndex, suggestion in
                                        Button {
                                            handleSuggestionTap(suggestion)
                                        } label: {
                                            Text(suggestion.title)
                                                .lineLimit(1)
                                                .padding(.horizontal, 12)
                                                .frame(height: 33)
                                        }
                                        .modifier(AssistantChipButtonModifier())
                                        .accessibilityIdentifier(suggestionAccessibilityIdentifier(section: section, index: chipIndex))
                                    }
                                }
                            }

                            if section.isRecovery {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(recoverySuggestions.prefix(3)) { recovery in
                                        Text("\(recovery.suggestion.title): \(recovery.reasoning)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
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
    
    private func assistantMessageBubble(for answer: HomeAnswer, index: Int) -> some View {
        let subtitlePresentation = assistantSubtitlePresentation(for: answer.subtitle)
        
        return VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 8) {
                Text(answer.title)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("marina.answer.\(index).title")
                
                if shouldRenderPrimaryValue(for: answer), let primaryValue = answer.primaryValue {
                    Text(primaryValue)
                        .font(.title2.weight(.bold))
                        .accessibilityIdentifier("marina.answer.\(index).primaryValue")
                }

                if let summary = cardSummaryAttachment(for: answer) {
                    MarinaCardSummaryAttachmentView(
                        workspace: workspace,
                        summary: summary,
                        card: cards.first(where: { $0.id == summary.cardID })
                    )
                    .padding(.top, 2)
                }

                if let summary = entitySummaryAttachment(for: answer) {
                    MarinaEntitySummaryAttachmentView(
                        workspace: workspace,
                        summary: summary,
                        allocationAccount: summary.sourceID.flatMap { id in
                            allocationAccounts.first(where: { $0.id == id })
                        },
                        savingsAccount: summary.sourceID.flatMap { id in
                            savingsAccounts.first(where: { $0.id == id })
                        }
                    )
                    .padding(.top, 2)
                }

                if let rowList = rowListAttachment(for: answer) {
                    MarinaRowListAttachmentView(
                        model: rowList,
                        variableExpenses: variableExpenses,
                        plannedExpenses: plannedExpenses,
                        savingsEntries: savingsEntries
                    )
                    .padding(.top, 2)
                }

                if let metric = metricSummaryAttachment(for: answer) {
                    MarinaMetricSummaryAttachmentView(
                        model: metric,
                        accessibilityPrefix: "marina.answer.\(index).metricSummary"
                    )
                        .padding(.top, 2)
                }

                if let comparison = comparisonSummaryAttachment(for: answer) {
                    MarinaComparisonSummaryAttachmentView(
                        model: comparison,
                        accessibilityPrefix: "marina.answer.\(index).comparisonSummary"
                    )
                        .padding(.top, 2)
                }

                if let breakdown = breakdownListAttachment(for: answer) {
                    MarinaBreakdownListAttachmentView(
                        model: breakdown,
                        accessibilityPrefix: "marina.answer.\(index).breakdownList"
                    )
                        .padding(.top, 2)
                }

                if let trend = trendChartAttachment(for: answer) {
                    MarinaTrendChartAttachmentView(model: trend)
                        .padding(.top, 2)
                }

                if let contract = formulaContractAttachment(for: answer) {
                    MarinaFormulaContractAttachmentView(
                        model: contract,
                        accessibilityPrefix: "marina.answer.\(index).formulaContract"
                    )
                        .padding(.top, 2)
                }

                if let clarification = clarificationAttachment(for: answer) {
                    MarinaClarificationAttachmentView(
                        model: clarification,
                        accessibilityPrefix: "marina.answer.\(index).clarification"
                    )
                        .padding(.top, 2)
                }

                if let deadEnd = deadEndAttachment(for: answer) {
                    MarinaDeadEndAttachmentView(
                        model: deadEnd,
                        accessibilityPrefix: "marina.answer.\(index).deadEnd"
                    )
                        .padding(.top, 2)
                }

                if let generic = genericSummaryAttachment(for: answer) {
                    MarinaGenericSummaryAttachmentView(
                        model: generic,
                        accessibilityPrefix: "marina.answer.\(index).genericSummary"
                    )
                        .padding(.top, 2)
                }

                uiTestAttachmentProbe(for: answer, index: index)
                
                if let narrative = subtitlePresentation.narrative {
                    Text(narrative)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("marina.answer.\(index).narrative")
                }
                
                if shouldRenderRowsVisually(for: answer) {
                    ForEach(Array(answer.rows.enumerated()), id: \.element.id) { rowIndex, row in
                        HStack {
                            Text(row.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .accessibilityIdentifier("marina.answer.\(index).row.\(rowIndex).title")
                            Spacer()
                            Text(row.value)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("marina.answer.\(index).row.\(rowIndex).value")
                        }
                    }
                }

                if let formBinding = inlineCreateFormBinding(for: answer.id) {
                    MarinaInlineCreateFormCard(
                        form: formBinding,
                        cards: cards,
                        categories: categories,
                        presets: presets,
                        onSubmit: {
                            submitInlineCreateForm(answerID: answer.id)
                        },
                        onCancel: {
                            cancelInlineCreateForm(answerID: answer.id)
                        }
                    )
                }
                
                if let provenance = subtitlePresentation.provenance {
                    Divider()
                        .padding(.top, 2)
                    Text(provenance)
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
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("marina.answer.\(index)")
            .accessibilityLabel(answerStateAccessibilityLabel(for: answer))
            .accessibilityValue(answerAccessibilityValue(answer, subtitlePresentation: subtitlePresentation))
            
            Text(timestampText(for: answer.generatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func cardSummaryAttachment(for answer: HomeAnswer) -> CardSummaryPresentationModel? {
        guard case let .cardSummary(summary)? = answer.attachment else { return nil }
        return summary
    }

    private func entitySummaryAttachment(for answer: HomeAnswer) -> MarinaEntitySummaryPresentationModel? {
        guard case let .entitySummary(summary)? = answer.attachment else { return nil }
        return summary
    }

    private func rowListAttachment(for answer: HomeAnswer) -> MarinaRowListPresentationModel? {
        guard case let .rowList(rowList)? = answer.attachment else { return nil }
        return rowList
    }

    private func metricSummaryAttachment(for answer: HomeAnswer) -> MarinaMetricSummaryPresentationModel? {
        guard case let .metricSummary(summary)? = answer.attachment else { return nil }
        return summary
    }

    private func comparisonSummaryAttachment(for answer: HomeAnswer) -> MarinaComparisonSummaryPresentationModel? {
        guard case let .comparisonSummary(summary)? = answer.attachment else { return nil }
        return summary
    }

    private func breakdownListAttachment(for answer: HomeAnswer) -> MarinaBreakdownListPresentationModel? {
        guard case let .breakdownList(list)? = answer.attachment else { return nil }
        return list
    }

    private func trendChartAttachment(for answer: HomeAnswer) -> MarinaTrendChartPresentationModel? {
        guard case let .trendChart(chart)? = answer.attachment else { return nil }
        return chart
    }

    private func formulaContractAttachment(for answer: HomeAnswer) -> MarinaFormulaContractPresentationModel? {
        guard case let .formulaContract(contract)? = answer.attachment else { return nil }
        return contract
    }

    private func clarificationAttachment(for answer: HomeAnswer) -> MarinaClarificationPresentationModel? {
        guard case let .clarification(clarification)? = answer.attachment else { return nil }
        return clarification
    }

    private func deadEndAttachment(for answer: HomeAnswer) -> MarinaDeadEndPresentationModel? {
        guard case let .deadEnd(deadEnd)? = answer.attachment else { return nil }
        return deadEnd
    }

    private func genericSummaryAttachment(for answer: HomeAnswer) -> MarinaGenericSummaryPresentationModel? {
        guard case let .genericSummary(summary)? = answer.attachment else { return nil }
        return summary
    }

    @ViewBuilder
    private func uiTestAttachmentProbe(for answer: HomeAnswer, index: Int) -> some View {
        #if DEBUG
        if UITestSupport.shouldRunMarinaHarness {
            let rows = attachmentProbeRows(for: answer)
            if rows.isEmpty == false {
                VStack(spacing: 0) {
                    Text(rows.map { "\($0.title): \($0.value)" }.joined(separator: "\n"))
                        .accessibilityIdentifier("marina.answer.\(index).attachmentText")

                    ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                        Text(row.title)
                            .accessibilityIdentifier("marina.answer.\(index).attachment.row.\(rowIndex).title")
                        Text(row.value)
                            .accessibilityIdentifier("marina.answer.\(index).attachment.row.\(rowIndex).value")
                    }
                }
                .frame(width: 1, height: 1)
                .opacity(0.01)
            }
        }
        #endif
    }

    private func attachmentProbeRows(for answer: HomeAnswer) -> [(title: String, value: String)] {
        guard let attachment = answer.attachment else { return [] }
        switch attachment {
        case let .cardSummary(summary):
            return [
                ("Card", summary.title),
                ("Period", summary.dateRangeSubtitle),
                ("Total", CurrencyFormatter.string(from: summary.total)),
                ("Planned", CurrencyFormatter.string(from: summary.plannedTotal)),
                ("Variable", CurrencyFormatter.string(from: summary.variableTotal))
            ]
        case let .entitySummary(summary):
            return [
                ("Entity", summary.title),
                ("Type", summary.subtitle)
            ] + summary.rows.map { ($0.title, $0.value) }
        case let .rowList(rowList):
            return rowList.rows.map { ($0.title, $0.value) }
        case let .metricSummary(summary):
            return summary.rows.map { ($0.title, $0.value) }
        case let .comparisonSummary(summary):
            var rows: [(title: String, value: String)] = [
                (summary.primaryLabel, summary.primaryValue),
                (summary.comparisonLabel, summary.comparisonValue)
            ]
            if let deltaLabel = summary.deltaLabel, let deltaValue = summary.deltaValue {
                rows.append((deltaLabel, deltaValue))
            }
            rows.append(contentsOf: summary.rows.map { ($0.title, $0.value) })
            return rows
        case let .breakdownList(list):
            return list.rows.map { ($0.title, $0.value) }
        case let .trendChart(chart):
            return chart.points.map { ($0.label, $0.renderedValue) }
        case let .formulaContract(contract):
            return contract.rows.map { ($0.title, $0.value) }
        case let .clarification(clarification):
            return clarification.rows.map { ($0.title, $0.value) }
        case let .deadEnd(deadEnd):
            return deadEnd.rows.map { ($0.title, $0.value) }
        case let .genericSummary(summary):
            return summary.rows.map { ($0.title, $0.value) }
        case .inlineCreateForm:
            return []
        }
    }

    private func shouldRenderPrimaryValue(for answer: HomeAnswer) -> Bool {
        switch answer.attachment {
        case .some(.metricSummary), .some(.breakdownList), .some(.formulaContract), .some(.clarification), .some(.deadEnd), .some(.genericSummary):
            return false
        case .some(.cardSummary), .some(.entitySummary), .some(.rowList), .some(.comparisonSummary), .some(.trendChart), .some(.inlineCreateForm), nil:
            return true
        }
    }

    private func shouldRenderRowsVisually(for answer: HomeAnswer) -> Bool {
        switch answer.attachment {
        case .some(.cardSummary), .some(.entitySummary), .some(.metricSummary), .some(.comparisonSummary), .some(.breakdownList), .some(.trendChart), .some(.formulaContract), .some(.clarification), .some(.deadEnd), .some(.genericSummary):
            return false
        case let .some(.rowList(rowList)):
            return rowList.hidesSourceRows == false && answer.rows.isEmpty == false
        case .some(.inlineCreateForm), nil:
            return answer.rows.isEmpty == false
        }
    }

    private func answerStateAccessibilityLabel(for answer: HomeAnswer) -> String {
        if case .clarification? = answer.attachment {
            return "Marina answer clarification \(answer.kind.rawValue)"
        }
        if case .deadEnd? = answer.attachment {
            return "Marina answer needs attention \(answer.kind.rawValue)"
        }

        let normalizedTitle = normalizedPrompt(answer.title)
        let normalizedSubtitle = normalizedPrompt(answer.subtitle ?? "")
        if normalizedTitle.contains("quick clarification") || normalizedSubtitle.contains("pick") {
            return "Marina answer clarification \(answer.kind.rawValue)"
        }
        if normalizedTitle.contains("can answer") || normalizedSubtitle.contains("different way") || normalizedSubtitle.contains("unsupported") {
            return "Marina answer unsupported \(answer.kind.rawValue)"
        }
        if normalizedTitle.contains("no ") || normalizedSubtitle.contains("no data") {
            return "Marina answer no data \(answer.kind.rawValue)"
        }
        return "Marina answer \(answer.kind.rawValue)"
    }

    private func answerAccessibilityValue(
        _ answer: HomeAnswer,
        subtitlePresentation: AssistantSubtitlePresentation
    ) -> String {
        var parts: [String] = [answer.title]
        if shouldRenderPrimaryValue(for: answer), let primaryValue = answer.primaryValue {
            parts.append(primaryValue)
        }
        if let narrative = subtitlePresentation.narrative {
            parts.append(narrative)
        }
        if let attachment = answer.attachment {
            parts.append(attachmentAccessibilityValue(attachment))
        }
        if sourceRowsAreVisibleToAccessibility(for: answer.attachment) {
            for row in answer.rows where row.role != .trace && row.role != .contract {
                parts.append("\(row.title): \(row.value)")
            }
        }
        if let provenance = subtitlePresentation.provenance {
            parts.append("Based on: \(provenance)")
        }
        parts.append("kind=\(answer.kind.rawValue)")
        return parts.joined(separator: "\n")
    }

    private func attachmentAccessibilityValue(_ attachment: MarinaAttachment) -> String {
        switch attachment {
        case .inlineCreateForm:
            return "Inline create form"
        case let .cardSummary(summary):
            return [
                "\(summary.title) card summary",
                summary.dateRangeSubtitle,
                "Total \(CurrencyFormatter.string(from: summary.total))",
                "Planned \(CurrencyFormatter.string(from: summary.plannedTotal))",
                "Variable \(CurrencyFormatter.string(from: summary.variableTotal))"
            ].joined(separator: ", ")
        case let .entitySummary(summary):
            var parts = ["\(summary.title) \(summary.subtitle)"]
            if let primaryValue = summary.primaryValue {
                parts.append(primaryValue)
            }
            parts.append(contentsOf: summary.rows.map { "\($0.title): \($0.value)" })
            return parts.joined(separator: ", ")
        case let .rowList(rowList):
            return rowList.rows.map { "\($0.title): \($0.value)" }.joined(separator: ", ")
        case let .metricSummary(summary):
            return polishedRowsAccessibility(
                title: summary.title,
                primaryValue: summary.primaryValue,
                rows: summary.rows
            )
        case let .comparisonSummary(summary):
            return [
                summary.title,
                "\(summary.primaryLabel): \(summary.primaryValue)",
                "\(summary.comparisonLabel): \(summary.comparisonValue)",
                summary.deltaLabel.flatMap { label in summary.deltaValue.map { "\(label): \($0)" } },
                polishedRowsAccessibility(rows: summary.rows)
            ].compactMap { $0 }.joined(separator: ", ")
        case let .breakdownList(list):
            return polishedRowsAccessibility(
                title: list.title,
                primaryValue: list.primaryValue,
                rows: list.rows
            )
        case let .trendChart(chart):
            return chart.points.map { "\($0.label): \($0.renderedValue)" }.joined(separator: ", ")
        case let .formulaContract(contract):
            return polishedRowsAccessibility(
                title: contract.title,
                primaryValue: contract.status,
                rows: contract.rows
            )
        case let .clarification(clarification):
            return polishedRowsAccessibility(
                title: clarification.title,
                rows: clarification.rows
            )
        case let .deadEnd(deadEnd):
            return polishedRowsAccessibility(
                title: deadEnd.title,
                rows: deadEnd.rows
            )
        case let .genericSummary(summary):
            return polishedRowsAccessibility(
                title: summary.title,
                primaryValue: summary.primaryValue,
                rows: summary.rows
            )
        }
    }

    private func sourceRowsAreVisibleToAccessibility(for attachment: MarinaAttachment?) -> Bool {
        switch attachment {
        case .none:
            return true
        case .inlineCreateForm, .cardSummary, .entitySummary:
            return true
        case let .rowList(rowList):
            return rowList.hidesSourceRows == false
        case let .metricSummary(summary):
            return summary.hidesSourceRows == false
        case let .comparisonSummary(summary):
            return summary.hidesSourceRows == false
        case let .breakdownList(list):
            return list.hidesSourceRows == false
        case let .trendChart(chart):
            return chart.hidesSourceRows == false
        case let .formulaContract(contract):
            return contract.hidesSourceRows == false
        case let .clarification(clarification):
            return clarification.hidesSourceRows == false
        case let .deadEnd(deadEnd):
            return deadEnd.hidesSourceRows == false
        case let .genericSummary(summary):
            return summary.hidesSourceRows == false
        }
    }

    private func polishedRowsAccessibility(
        title: String? = nil,
        primaryValue: String? = nil,
        rows: [MarinaDisplayRow]
    ) -> String {
        var parts: [String] = []
        if let title { parts.append(title) }
        if let primaryValue { parts.append(primaryValue) }
        parts.append(contentsOf: rows.map { "\($0.title): \($0.value)" })
        return parts.joined(separator: ", ")
    }

    private func suggestionAccessibilityIdentifier(
        section: MarinaSuggestionSection,
        index: Int
    ) -> String {
        if section.isRecovery {
            return "marina.recoveryChip.\(index)"
        }
        if section.title.localizedCaseInsensitiveContains("clarification") {
            return "marina.clarificationChip.\(index)"
        }
        return "marina.followupChip.\(index)"
    }

    private func normalizedAccessibilityToken(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
    
    private func assistantSubtitlePresentation(for subtitle: String?) -> AssistantSubtitlePresentation {
        guard let subtitle else {
            return AssistantSubtitlePresentation(narrative: nil, provenance: nil)
        }
        
        let bodyWithoutTechnicalFooter = subtitle
            .components(separatedBy: "\n\n---\n")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        guard bodyWithoutTechnicalFooter.isEmpty == false else {
            return AssistantSubtitlePresentation(narrative: nil, provenance: nil)
        }

        if let provenanceRange = bodyWithoutTechnicalFooter.range(of: "\n\nBased on:\n", options: .backwards) {
            let narrative = String(bodyWithoutTechnicalFooter[..<provenanceRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let provenance = String(bodyWithoutTechnicalFooter[provenanceRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return AssistantSubtitlePresentation(
                narrative: narrative.isEmpty ? nil : narrative,
                provenance: provenance.isEmpty ? nil : provenance
            )
        }

        if let sourcesRange = bodyWithoutTechnicalFooter.range(of: "Sources:", options: .backwards) {
            let narrative = String(bodyWithoutTechnicalFooter[..<sourcesRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let provenance = String(bodyWithoutTechnicalFooter[sourcesRange.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)

            return AssistantSubtitlePresentation(
                narrative: narrative.isEmpty ? nil : narrative,
                provenance: provenance.isEmpty ? nil : provenance
            )
        }

        return AssistantSubtitlePresentation(
            narrative: bodyWithoutTechnicalFooter,
            provenance: nil
        )
    }
    
    private func runQuery(
        _ query: HomeQuery,
        userPrompt: String?,
        confidenceBand: HomeQueryConfidenceBand = .high,
        explanation: String? = nil,
        executedPlan: HomeQueryPlan? = nil,
        source: MarinaAnswerProvenance = .deterministicQuery
    ) {
        // Query chips and prebuilt HomeQuery actions still execute through the
        // deterministic HomeQueryEngine path; live natural-language reads stay in Marina.
        clarificationSuggestions = []
        recoverySuggestions = []
        lastClarificationReasons = []
        activeClarificationContext = nil
        foundationPipelineClarification = nil
        foundationPipelineClarificationChoiceContext = nil
        foundationPipelineClarificationChoicesByID = [:]
        foundationPipelineClarificationChoicesByTitle = [:]
        
        let baseAnswer = engine.execute(
            query: query,
            categories: categories,
            presets: presets,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            incomes: incomes,
            savingsEntries: savingsEntries
        )

        let normalizedAnswer = executedQueryAnswerNormalizer.normalize(baseAnswer, for: query)
        let rawAnswer = applyConfidenceTone(to: normalizedAnswer, confidenceBand: confidenceBand)
        let titledAnswer = applyPromptAwareTitle(
            to: rawAnswer,
            query: query,
            userPrompt: userPrompt
        )
        let explainedAnswer = applyResolutionExplanation(explanation, to: titledAnswer)
        let presentationAnswer = visualAttachmentAnswer(from: explainedAnswer)
        
        let executedPlanForMemory = executedPlan ?? HomeQueryPlan(
            metric: query.intent.metric,
            dateRange: query.dateRange,
            comparisonDateRange: query.comparisonDateRange,
            resultLimit: query.resultLimit,
            confidenceBand: confidenceBand,
            targetName: query.targetName,
            periodUnit: query.periodUnit
        )
        presentMarinaAnswer(
            deterministicAnswer: presentationAnswer,
            deterministicRecoveryAnswer: presentationAnswer,
            rawPrompt: userPrompt ?? "",
            source: source,
            homeQueryPlan: executedPlanForMemory,
            surfaceKind: presentationAnswer.primaryValue == nil && presentationAnswer.rows.isEmpty ? .noData : .answer,
            groundingSummary: executedPlanForMemory.traceSummary,
            followUpSuggestions: followUpSuggestions(for: presentationAnswer, query: query)
        ) { presentedAnswer in
            updateSessionContext(after: executedPlanForMemory)
            rememberAnswerContext(
                for: query,
                executedPlan: executedPlanForMemory,
                rawAnswer: normalizedAnswer,
                presentedAnswer: presentedAnswer,
                userPrompt: userPrompt
            )
        }
    }

    private func handleFoundationPipelineAnswer(
        _ answer: HomeAnswer,
        aggregationResult: MarinaAggregationResult?,
        rawPrompt: String,
        homeQueryPlan: HomeQueryPlan?,
        source: MarinaAnswerProvenance
    ) async {
        clarificationSuggestions = []
        recoverySuggestions = []
        lastClarificationReasons = []
        activeClarificationContext = nil
        foundationPipelineClarification = nil
        foundationPipelineClarificationChoiceContext = nil
        foundationPipelineClarificationChoicesByID = [:]
        foundationPipelineClarificationChoicesByTitle = [:]

        let query = homeQueryPlan?.query
        let normalizedAnswer = query.map {
            executedQueryAnswerNormalizer.normalize(answer, for: $0)
        } ?? answer
        let titledAnswer = query.map {
            MarinaAnswerTitleResolver().applyingTitle(
                to: normalizedAnswer,
                query: $0,
                userPrompt: rawPrompt,
                now: marinaRuntimeSettings.now
            )
        } ?? normalizedAnswer
        let presentationAnswer = visualAttachmentAnswer(from: titledAnswer)
        let deterministicFollowUps = followUpSuggestions(for: presentationAnswer, query: query)
        let surfaced = await presentMarinaAnswer(
            deterministicAnswer: presentationAnswer,
            deterministicRecoveryAnswer: presentationAnswer,
            rawPrompt: rawPrompt,
            source: source,
            homeQueryPlan: homeQueryPlan,
            surfaceKind: presentationAnswer.primaryValue == nil && presentationAnswer.rows.isEmpty ? .noData : .answer,
            groundingSummary: aggregationResult?.sourceAnswer?.traceSummary ?? presentationAnswer.traceSummary,
            followUpSuggestions: deterministicFollowUps
        )

        if let homeQueryPlan, let query {
            updateSessionContext(after: homeQueryPlan)
            rememberAnswerContext(
                for: query,
                executedPlan: homeQueryPlan,
                rawAnswer: presentationAnswer,
                aggregationResult: aggregationResult,
                presentedAnswer: surfaced.answer,
                userPrompt: rawPrompt
            )
        }

        recordTelemetry(
            for: rawPrompt,
            outcome: .resolved,
            source: source,
            plan: homeQueryPlan,
            notes: "foundationPipeline"
        )
    }

    @MainActor
    private func presentMarinaSystemAnswer(
        _ answer: HomeAnswer,
        rawPrompt: String,
        surfaceKind: MarinaPresentationSurfaceKind,
        validationOutcomeSummary: String
    ) async {
        clarificationSuggestions = []
        recoverySuggestions = []
        lastClarificationReasons = []
        activeClarificationContext = nil
        foundationPipelineClarification = nil
        foundationPipelineClarificationChoiceContext = nil
        foundationPipelineClarificationChoicesByID = [:]
        foundationPipelineClarificationChoicesByTitle = [:]

        let presentationAnswer = visualAttachmentAnswer(from: answer)
        _ = await presentMarinaAnswer(
            deterministicAnswer: presentationAnswer,
            deterministicRecoveryAnswer: presentationAnswer,
            rawPrompt: rawPrompt,
            source: .foundationModels,
            surfaceKind: surfaceKind,
            validationOutcomeSummary: validationOutcomeSummary,
            groundingSummary: validationOutcomeSummary
        )

        recordTelemetry(
            for: rawPrompt,
            outcome: .unresolved,
            source: .foundationModels,
            plan: nil,
            notes: validationOutcomeSummary
        )
    }

    private func marinaPresentationModeDecision() -> MarinaPresentationMode {
        guard marinaRuntimeSettings.aiOptIn.isEnabled else {
            return .basicDeterministic
        }

        return MarinaModelAvailability().currentStatus() == .available
            ? .foundationModelsStreaming
            : .plainDeterministic
    }

    @MainActor
    @discardableResult
    private func presentMarinaAnswer(
        deterministicAnswer: HomeAnswer,
        deterministicRecoveryAnswer: HomeAnswer,
        rawPrompt: String,
        source: MarinaAnswerProvenance,
        homeQueryPlan: HomeQueryPlan? = nil,
        surfaceKind: MarinaPresentationSurfaceKind = .answer,
        validationOutcomeSummary: String? = nil,
        clarificationChoices: [String] = [],
        groundingSummary: String? = nil,
        allowedTone: String? = nil,
        followUpSuggestions: [MarinaSuggestion] = []
    ) async -> MarinaResponseSurfaceApplication {
        let presentationMode = marinaPresentationModeDecision()
        let deterministicApplication: MarinaResponseSurfaceApplication
        switch presentationMode {
        case .foundationModelsStreaming, .basicDeterministic:
            deterministicApplication = MarinaResponseSurfaceApplication(
                answer: deterministicRecoveryAnswer,
                followUpSuggestions: followUpSuggestions
            )
        case .plainDeterministic:
            deterministicApplication = MarinaResponseSurfaceApplication(
                answer: deterministicAnswer,
                followUpSuggestions: followUpSuggestions
            )
        }

        switch presentationMode {
        case .foundationModelsStreaming:
            appendAnswer(streamingPreparedAnswer(deterministicAnswer, surfaceKind: surfaceKind))
            let surfaced = await surfaceGeneratedPresentation(
                generationBaseAnswer: deterministicAnswer,
                deterministicApplication: deterministicApplication,
                rawPrompt: rawPrompt,
                source: source,
                homeQueryPlan: homeQueryPlan,
                surfaceKind: surfaceKind,
                validationOutcomeSummary: validationOutcomeSummary,
                clarificationChoices: clarificationChoices,
                groundingSummary: groundingSummary,
                allowedTone: allowedTone,
                streamingAnswerID: deterministicAnswer.id
            )
            replaceAnswerPreservingPrompt(surfaced.answer)
            storeGeneratedFollowUps(surfaced.followUpSuggestions, for: surfaced.answer.id)
            return surfaced

        case .basicDeterministic:
            MarinaTraceRecorder.shared.recordResponseSurface(
                source: .deterministicSurface,
                recoveryReason: .aiOptOut
            )
            appendAnswer(deterministicApplication.answer)
            storeGeneratedFollowUps(deterministicApplication.followUpSuggestions, for: deterministicApplication.answer.id)
            return deterministicApplication

        case .plainDeterministic:
            MarinaTraceRecorder.shared.recordResponseSurface(
                source: .deterministicSurface,
                recoveryReason: .modelUnavailable
            )
            appendAnswer(deterministicApplication.answer)
            storeGeneratedFollowUps(deterministicApplication.followUpSuggestions, for: deterministicApplication.answer.id)
            return deterministicApplication
        }
    }

    @MainActor
    private func presentMarinaAnswer(
        deterministicAnswer: HomeAnswer,
        deterministicRecoveryAnswer: HomeAnswer,
        rawPrompt: String,
        source: MarinaAnswerProvenance,
        homeQueryPlan: HomeQueryPlan? = nil,
        surfaceKind: MarinaPresentationSurfaceKind = .answer,
        validationOutcomeSummary: String? = nil,
        clarificationChoices: [String] = [],
        groundingSummary: String? = nil,
        allowedTone: String? = nil,
        followUpSuggestions: [MarinaSuggestion] = [],
        onPresented: (@MainActor @Sendable (HomeAnswer) -> Void)? = nil
    ) {
        Task { @MainActor in
            let surfaced = await presentMarinaAnswer(
                deterministicAnswer: deterministicAnswer,
                deterministicRecoveryAnswer: deterministicRecoveryAnswer,
                rawPrompt: rawPrompt,
                source: source,
                homeQueryPlan: homeQueryPlan,
                surfaceKind: surfaceKind,
                validationOutcomeSummary: validationOutcomeSummary,
                clarificationChoices: clarificationChoices,
                groundingSummary: groundingSummary,
                allowedTone: allowedTone,
                followUpSuggestions: followUpSuggestions
            )
            onPresented?(surfaced.answer)
        }
    }

    private func storeGeneratedFollowUps(
        _ suggestions: [MarinaSuggestion],
        for answerID: UUID
    ) {
        guard suggestions.isEmpty == false else { return }
        generatedFollowUpSuggestionsByAnswerID[answerID] = suggestions
    }

    private func streamingPreparedAnswer(
        _ answer: HomeAnswer,
        surfaceKind: MarinaPresentationSurfaceKind
    ) -> HomeAnswer {
        guard answer.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else {
            return answer
        }

        return HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: streamingPlaceholderSubtitle(for: surfaceKind),
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            attachment: answer.attachment,
            explanation: answer.explanation,
            generatedAt: answer.generatedAt
        )
    }

    private func streamingPlaceholderSubtitle(
        for surfaceKind: MarinaPresentationSurfaceKind
    ) -> String {
        switch surfaceKind {
        case .clarification:
            return "Let me frame the safest choice."
        case .help:
            return "Let me make the options easier to scan."
        case .noData:
            return "Let me check what the empty result means."
        case .recovery:
            return "Let me find the safest next step."
        case .simulation:
            return "Let me ground this what-if."
        case .answer:
            return "Let me read the signal in this."
        }
    }

    private func followUpSuggestions(for answer: HomeAnswer, query: HomeQuery?) -> [MarinaSuggestion] {
        followUpSuggestionBuilder.suggestions(
            after: answer,
            executedQuery: query,
            supportsPromptBackedSuggestions: supportsPromptBackedSuggestions
        )
    }

    private func surfaceGeneratedPresentation(
        generationBaseAnswer: HomeAnswer,
        deterministicApplication: MarinaResponseSurfaceApplication,
        rawPrompt: String,
        source: MarinaAnswerProvenance,
        homeQueryPlan: HomeQueryPlan?,
        surfaceKind: MarinaPresentationSurfaceKind = .answer,
        validationOutcomeSummary: String? = nil,
        clarificationChoices: [String] = [],
        groundingSummary: String? = nil,
        allowedTone: String? = nil,
        streamingAnswerID: UUID? = nil
    ) async -> MarinaResponseSurfaceApplication {
        let fallback = deterministicApplication
        let plainDeterministic = MarinaResponseSurfaceApplication(
            answer: generationBaseAnswer,
            followUpSuggestions: fallback.followUpSuggestions
        )
        guard marinaRuntimeSettings.aiOptIn.isEnabled else {
            MarinaTraceRecorder.shared.recordResponseSurface(
                source: .deterministicSurface,
                recoveryReason: .aiOptOut
            )
            return fallback
        }

        let availability = MarinaModelAvailability().currentStatus()
        guard availability == .available else {
            MarinaTraceRecorder.shared.recordResponseSurface(
                source: .deterministicSurface,
                recoveryReason: .modelUnavailable
            )
            return fallback
        }

        do {
            let grounding = presentationGrounding(
                rawPrompt: rawPrompt,
                answer: generationBaseAnswer,
                surfaceKind: surfaceKind,
                homeQueryPlan: homeQueryPlan,
                validationOutcomeSummary: validationOutcomeSummary,
                sourceSummary: groundingSummary,
                clarificationChoices: clarificationChoices
            )
            let request = MarinaResponseSurfaceRequestFactory.make(
                userPrompt: rawPrompt,
                workspaceName: workspace.name,
                routeSourceRaw: source.rawValue,
                generationBaseAnswer: generationBaseAnswer,
                deterministicApplication: fallback,
                presentationMode: .foundationModelsStreaming,
                surfaceKind: surfaceKind,
                voiceProfile: .marina,
                presentationGrounding: grounding,
                groundingSummary: groundingSummary,
                allowedTone: allowedTone ?? MarinaAIVoiceProfile.marina.allowedTone,
                dateWindow: homeQueryPlan?.dateRange?.traceSummary,
                provenance: visibleProvenance(for: homeQueryPlan.map { [$0.query] } ?? []),
                validationOutcomeSummary: validationOutcomeSummary,
                clarificationChoices: clarificationChoices,
                followUpCandidates: fallback.followUpSuggestions.enumerated().map { index, suggestion in
                    MarinaResponseSuggestionCandidate(
                        index: index,
                        title: suggestion.title,
                        querySummary: responseGenerationSuggestionSummary(suggestion)
                    )
                },
                recentResponses: sessionContext.recentAnswerContexts.suffix(3).map { context in
                    MarinaRecentResponseSummary(
                        title: context.answerTitle,
                        kindRaw: context.answerKind.rawValue,
                        primaryValue: context.rowValues.first
                    )
                }
            )
            let generated = try await responseGenerationService.generateSurfaceResponse(
                context: request.context,
                onPartialText: streamingAnswerID.map { answerID in
                    { @MainActor @Sendable partialText in
                        updateAnswerSubtitle(answerID: answerID, subtitle: partialText)
                    }
                }
            )
            let applied = try MarinaResponseSurfaceApplicator().apply(
                generated: generated,
                to: request.context.deterministicAnswer,
                deterministicFollowUps: request.deterministicApplication.followUpSuggestions
            )
            MarinaTraceRecorder.shared.recordResponseSurface(
                source: .foundationModelsSurface,
                recoveryReason: nil
            )
            return applied
        } catch MarinaResponseGenerationError.unavailable {
            MarinaTraceRecorder.shared.recordResponseSurface(
                source: .deterministicSurface,
                recoveryReason: .modelUnavailable
            )
            return plainDeterministic
        } catch MarinaResponseGenerationError.malformedResponse {
            MarinaTraceRecorder.shared.recordResponseSurface(
                source: .deterministicSurface,
                recoveryReason: .malformedResponse
            )
            return plainDeterministic
        } catch MarinaResponseGenerationError.invariantViolation {
            MarinaTraceRecorder.shared.recordResponseSurface(
                source: .deterministicSurface,
                recoveryReason: .invariantViolation
            )
            return plainDeterministic
        } catch MarinaResponseGenerationError.generationFailed(let category) {
            MarinaTraceRecorder.shared.recordResponseSurface(
                source: .deterministicSurface,
                recoveryReason: responseSurfaceRecoveryReason(for: category)
            )
            return plainDeterministic
        } catch {
            MarinaTraceRecorder.shared.recordResponseSurface(
                source: .deterministicSurface,
                recoveryReason: .modelServiceFailed
            )
            return plainDeterministic
        }
    }

    private func presentationGrounding(
        rawPrompt: String,
        answer: HomeAnswer,
        surfaceKind: MarinaPresentationSurfaceKind,
        homeQueryPlan: HomeQueryPlan?,
        validationOutcomeSummary: String?,
        sourceSummary: String?,
        clarificationChoices: [String]
    ) -> MarinaPresentationGrounding {
        MarinaPresentationGroundingBuilder().build(
            userPrompt: rawPrompt,
            answer: answer,
            surfaceKind: surfaceKind,
            dateWindow: homeQueryPlan?.dateRange?.traceSummary,
            provenance: visibleProvenance(for: homeQueryPlan.map { [$0.query] } ?? []),
            validationOutcomeSummary: validationOutcomeSummary,
            sourceSummary: sourceSummary,
            clarificationChoices: clarificationChoices
        )
    }

    private func responseSurfaceRecoveryReason(
        for category: MarinaFoundationModelsErrorCategory
    ) -> MarinaResponseGenerationRecoveryReason {
        switch category {
        case .unavailable:
            return .modelUnavailable
        case .assetsUnavailable:
            return .assetsUnavailable
        case .decodingFailure:
            return .decodingFailure
        case .exceededContextWindowSize:
            return .exceededContextWindowSize
        case .guardrailViolation:
            return .guardrailViolation
        case .rateLimited:
            return .rateLimited
        case .refusal:
            return .refusal
        case .concurrentRequests:
            return .concurrentRequests
        case .unsupportedGuide:
            return .unsupportedGuide
        case .unsupportedLanguageOrLocale:
            return .unsupportedLanguageOrLocale
        case .toolCallFailed:
            return .toolCallFailed
        case .malformedResponse:
            return .malformedResponse
        case .cancelled:
            return .cancelled
        case .unknown:
            return .unknown
        }
    }

    private func responseGenerationSuggestionSummary(_ suggestion: MarinaSuggestion) -> String {
        if case .typedIntent(let typedIntent) = suggestion.action {
            return "typed=\(typedIntent.traceSummary)"
        }
        if let promptText = suggestion.promptText {
            return "prompt=\(promptText)"
        }
        return responseGenerationQuerySummary(suggestion.query)
    }

    private func responseGenerationQuerySummary(_ query: HomeQuery) -> String {
        var parts = ["intent=\(query.intent.rawValue)"]
        if let targetName = query.targetName {
            parts.append("target=\(targetName)")
        }
        if let dateRange = query.dateRange {
            parts.append("date=\(dateRange.traceSummary)")
        }
        if let comparisonDateRange = query.comparisonDateRange {
            parts.append("comparison=\(comparisonDateRange.traceSummary)")
        }
        parts.append("limit=\(query.resultLimit)")
        if let periodUnit = query.periodUnit {
            parts.append("period=\(periodUnit.rawValue)")
        }
        return parts.joined(separator: ",")
    }
    
    private func submitPrompt() {
        let prompt = trimmedPromptText
        guard prompt.isEmpty == false else { return }
        pendingUserPromptForNextAnswer = prompt
        beginPendingThinking(for: prompt)
        
        defer { promptText = "" }
        
        if hasPendingMutationTurn {
            clearMutationPendingState()
            Task { @MainActor in
                await presentMarinaSystemAnswer(
                    MarinaTurnCoordinator.deferredCRUDAnswer(prompt: prompt),
                    rawPrompt: prompt,
                    surfaceKind: .recovery,
                    validationOutcomeSummary: "marina_foundation_pending_crud_deferred"
                )
            }
            return
        }

        let turnClassifier = MarinaPromptTurnClassifier(mutationGuard: mutationIntentGuard)
        let turnClassification = turnClassifier.classify(
            prompt,
            defaultPeriodUnit: defaultQueryPeriodUnit,
            hasActiveClarification: foundationPipelineClarification != nil
        )

        if let clarification = foundationPipelineClarification {
            if turnClassification == .freshQuestion || turnClassification == .command {
                foundationPipelineClarification = nil
            } else {
                Task {
                    await handleFoundationPipelineTypedClarificationResolution(
                        foundationPipelineTypedChoiceResolution(from: prompt, clarification: clarification),
                        reply: prompt,
                        clarification: clarification
                    )
                }
                return
            }
        }

        if let clarification = foundationPipelineClarification {
            Task {
                await handleFoundationPipelineTypedClarificationResolution(
                    foundationPipelineTypedChoiceResolution(from: prompt, clarification: clarification),
                    reply: prompt,
                    clarification: clarification
                )
            }
            return
        }
        
        if handleConversationalPrompt(prompt) {
            return
        }

        if mutationIntentGuard.isMutationPrompt(prompt) {
            Task { @MainActor in
                await presentMarinaSystemAnswer(
                    MarinaTurnCoordinator.deferredCRUDAnswer(prompt: prompt),
                    rawPrompt: prompt,
                    surfaceKind: .recovery,
                    validationOutcomeSummary: "marina_foundation_crud_deferred"
                )
            }
            return
        }

        Task { @MainActor in
            await interpretPrompt(prompt, turnClassification: turnClassification)
        }
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
            appendAnswer(marinaGreetingAnswer(userPrompt: prompt))
            return true
        }

        if MarinaCapabilityGuide.matchesPrompt(prompt) {
            let raw = MarinaCapabilityGuide.makeAnswer(for: prompt)
            presentMarinaAnswer(
                deterministicAnswer: raw,
                deterministicRecoveryAnswer: raw,
                rawPrompt: prompt,
                source: .capabilityHelp,
                surfaceKind: .help,
                groundingSummary: "capability guide"
            )
            return true
        }
        return false
    }

    private func marinaGreetingAnswer(userPrompt: String?) -> HomeAnswer {
        HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: userPrompt,
            title: "Marina",
            subtitle: "Ask me for quick answers from your budget data.",
            rows: []
        )
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

    private func plainUnresolvedAnswer(for prompt: String) -> HomeAnswer {
        HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: prompt,
            title: "I need a clearer budgeting prompt",
            subtitle: "Try asking about a total, a list, a comparison, or a named card, category, merchant, budget, income source, or preset.",
            rows: []
        )
    }
    
    private func handleCommandPlan(
        _ command: MarinaCommandPlan,
        rawPrompt: String,
        source: MarinaAnswerProvenance? = nil
    ) {
        clarificationSuggestions = []
        recoverySuggestions = []
        lastClarificationReasons = []
        activeClarificationContext = nil
        
        switch command.intent {
        case .addExpense:
            handleAddExpenseCommand(command)
        case .addIncome:
            handleAddIncomeCommand(command)
        case .addBudget:
            handleAddBudgetCommand(command)
        case .editBudget:
            handleEditBudgetCommand(command)
        case .deleteBudget:
            handleDeleteBudgetCommand(command)
        case .addCard:
            handleAddCardCommand(command)
        case .editCard:
            handleEditCardCommand(command)
        case .deleteCard:
            handleDeleteCardCommand(command)
        case .addPreset:
            handleAddPresetCommand(command)
        case .editPreset:
            handleEditPresetCommand(command)
        case .deletePreset:
            handleDeletePresetCommand(command)
        case .addCategory:
            handleAddCategoryCommand(command)
        case .editCategory:
            handleEditCategoryCommand(command)
        case .deleteCategory:
            handleDeleteCategoryCommand(command)
        case .addPlannedExpense:
            handleAddPlannedExpenseCommand(command)
        case .editPlannedExpense:
            handleEditPlannedExpenseCommand(command)
        case .deletePlannedExpense:
            handleDeletePlannedExpenseCommand(command)
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
            source: source,
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
        
        if pendingDeleteExpense != nil
            || pendingDeleteIncome != nil
            || pendingDeleteCard != nil
            || pendingDeleteCategory != nil
            || pendingDeletePreset != nil
            || pendingDeleteBudget != nil
            || pendingDeletePlannedExpense != nil
        {
            resolveDeleteConfirmation(with: prompt)
            return true
        }

        if pendingCardCandidates.isEmpty == false {
            resolveCardDisambiguation(with: prompt)
            return true
        }

        if pendingCategoryCandidates.isEmpty == false {
            resolveCategoryDisambiguation(with: prompt)
            return true
        }

        if pendingPresetCandidates.isEmpty == false {
            resolvePresetDisambiguation(with: prompt)
            return true
        }

        if pendingBudgetCandidates.isEmpty == false {
            resolveBudgetDisambiguation(with: prompt)
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
        
        if pendingPresetRecurrencePlan != nil {
            resolvePresetRecurrenceSelection(with: prompt)
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

    private var hasPendingMutationTurn: Bool {
        pendingCategoryColorPlan != nil
            || pendingCardStyleStep != nil
            || pendingBudgetCreationPlan != nil
            || pendingDeleteExpense != nil
            || pendingDeleteIncome != nil
            || pendingDeleteCard != nil
            || pendingDeleteCategory != nil
            || pendingDeletePreset != nil
            || pendingDeleteBudget != nil
            || pendingDeletePlannedExpense != nil
            || pendingCardCandidates.isEmpty == false
            || pendingCategoryCandidates.isEmpty == false
            || pendingPresetCandidates.isEmpty == false
            || pendingBudgetCandidates.isEmpty == false
            || pendingExpenseCandidates.isEmpty == false
            || pendingPlannedExpenseCandidates.isEmpty == false
            || pendingIncomeCandidates.isEmpty == false
            || pendingExpenseCardPlan != nil
            || pendingPresetRecurrencePlan != nil
            || pendingPresetCardPlan != nil
            || pendingIncomeKindPlan != nil
            || (pendingPlannedExpenseAmountPlan != nil && pendingPlannedExpenseAmountExpense != nil)
    }
    
    private func handleAddExpenseCommand(_ command: MarinaCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .expense, command: command))
    }
    
    private func handleAddIncomeCommand(_ command: MarinaCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .income, command: command))
    }
    
    private func handleAddBudgetCommand(_ command: MarinaCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .budget, command: command))
    }
    
    private func handleAddCardCommand(_ command: MarinaCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .card, command: command))
    }
    
    private func handleAddPresetCommand(_ command: MarinaCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .preset, command: command))
    }
    
    private func handleAddCategoryCommand(_ command: MarinaCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .category, command: command))
    }

    private func handleEditCategoryCommand(_ command: MarinaCommandPlan) {
        guard command.updatedEntityName != nil || command.categoryColorHex != nil || command.categoryColorName != nil else {
            appendMutationMessage(
                title: "Need category edit details",
                subtitle: "Tell me the new name or color for the category.",
                rows: []
            )
            return
        }

        let matches = matchedCategories(for: command)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching category found",
                subtitle: "Try adding the category name so I can update it.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingCategoryDisambiguationPlan = command
            pendingCategoryCandidates = Array(matches.prefix(3))
            presentCategoryDisambiguationPrompt(action: "edit")
            return
        }

        executeCategoryEdit(matches[0], using: command)
    }

    private func handleDeleteCategoryCommand(_ command: MarinaCommandPlan) {
        let matches = matchedCategories(for: command)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching category found",
                subtitle: "Try adding the category name so I can delete it.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingCategoryDisambiguationPlan = command
            pendingCategoryCandidates = Array(matches.prefix(3))
            presentCategoryDisambiguationPrompt(action: "delete")
            return
        }

        executeCategoryDelete(matches[0])
    }

    private func handleEditPresetCommand(_ command: MarinaCommandPlan) {
        let hasRecurrenceEdit = command.recurrenceFrequencyRaw != nil
        guard command.updatedEntityName != nil
            || command.amount != nil
            || command.cardName != nil
            || command.categoryName != nil
            || hasRecurrenceEdit
        else {
            appendMutationMessage(
                title: "Need preset edit details",
                subtitle: "Tell me what to change for the preset, like amount, card, category, or schedule.",
                rows: []
            )
            return
        }

        let matches = matchedPresets(for: command)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching preset found",
                subtitle: "Try adding the preset title so I can update it.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingPresetDisambiguationPlan = command
            pendingPresetCandidates = Array(matches.prefix(3))
            presentPresetDisambiguationPrompt(action: "edit")
            return
        }

        executePresetEdit(matches[0], using: command)
    }

    private func handleDeletePresetCommand(_ command: MarinaCommandPlan) {
        let matches = matchedPresets(for: command)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching preset found",
                subtitle: "Try adding the preset title so I can delete it.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingPresetDisambiguationPlan = command
            pendingPresetCandidates = Array(matches.prefix(3))
            presentPresetDisambiguationPrompt(action: "delete")
            return
        }

        executePresetDelete(matches[0])
    }

    private func handleEditBudgetCommand(_ command: MarinaCommandPlan) {
        guard command.updatedEntityName != nil || command.dateRange != nil else {
            appendMutationMessage(
                title: "Need budget edit details",
                subtitle: "Tell me the new name or period for the budget.",
                rows: []
            )
            return
        }

        let matches = matchedBudgets(for: command)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching budget found",
                subtitle: "Try adding the budget name so I can update it.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingBudgetDisambiguationPlan = command
            pendingBudgetCandidates = Array(matches.prefix(3))
            presentBudgetDisambiguationPrompt(action: "edit")
            return
        }

        executeBudgetEdit(matches[0], using: command)
    }

    private func handleDeleteBudgetCommand(_ command: MarinaCommandPlan) {
        let matches = matchedBudgets(for: command)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching budget found",
                subtitle: "Try adding the budget name so I can delete it.",
                rows: []
            )
            return
        }

        if matches.count > 1 {
            pendingBudgetDisambiguationPlan = command
            pendingBudgetCandidates = Array(matches.prefix(3))
            presentBudgetDisambiguationPrompt(action: "delete")
            return
        }

        executeBudgetDelete(matches[0])
    }

    private func handleAddPlannedExpenseCommand(_ command: MarinaCommandPlan) {
        let amountLine: String
        if let amount = command.amount {
            amountLine = CurrencyFormatter.string(from: amount)
        } else {
            amountLine = "the amount"
        }

        appendMutationMessage(
            title: "Use a preset or an expense instead",
            subtitle: "Planned expenses come from presets. Create a preset for something recurring, or create an expense if this is a one-off entry.",
            rows: [
                HomeAnswerRow(title: "Recurring", value: "Create a preset for \(command.entityName ?? command.notes ?? "this item")"),
                HomeAnswerRow(title: "One-off", value: "Create an expense for \(amountLine)")
            ]
        )
    }

    private func handleEditPlannedExpenseCommand(_ command: MarinaCommandPlan) {
        guard command.updatedEntityName != nil
            || command.amount != nil
            || command.date != nil
            || command.cardName != nil
            || command.categoryName != nil
        else {
            appendMutationMessage(
                title: "Need planned expense edit details",
                subtitle: "Tell me what to change for the planned expense, like amount, date, card, category, or title.",
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
            pendingPlannedExpenseDisambiguationPlan = command
            pendingPlannedExpenseCandidates = Array(matches.prefix(3))
            presentPlannedExpenseDisambiguationPrompt()
            return
        }

        if command.amount != nil && command.plannedExpenseAmountTarget == nil {
            pendingPlannedExpenseAmountPlan = command
            pendingPlannedExpenseAmountExpense = matches[0]
            presentPlannedExpenseAmountTargetPrompt()
            return
        }

        executePlannedExpenseEdit(matches[0], using: command)
    }

    private func handleDeletePlannedExpenseCommand(_ command: MarinaCommandPlan) {
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
            pendingPlannedExpenseDisambiguationPlan = command
            pendingPlannedExpenseCandidates = Array(matches.prefix(3))
            presentPlannedExpenseDisambiguationPrompt()
            return
        }

        executePlannedExpenseDelete(matches[0])
    }
    
    private func handleEditCardCommand(_ command: MarinaCommandPlan) {
        guard command.cardThemeRaw != nil || command.cardEffectRaw != nil || command.updatedEntityName != nil else {
            appendMutationMessage(
                title: "Need card edit details",
                subtitle: "Tell me the new name, theme, or effect to update for the card.",
                rows: []
            )
            return
        }
        
        let matches = matchedCards(for: command)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching card found",
                subtitle: "Try adding the card name so I can update it.",
                rows: []
            )
            return
        }
        
        if matches.count > 1 {
            pendingCardDisambiguationPlan = command
            pendingCardCandidates = Array(matches.prefix(3))
            presentCardDisambiguationPrompt(action: "edit")
            return
        }
        
        executeCardEdit(matches[0], using: command)
    }
    
    private func handleDeleteCardCommand(_ command: MarinaCommandPlan) {
        let matches = matchedCards(for: command)
        guard matches.isEmpty == false else {
            appendMutationMessage(
                title: "No matching card found",
                subtitle: "Try adding the card name so I can delete it.",
                rows: []
            )
            return
        }
        
        if matches.count > 1 {
            pendingCardDisambiguationPlan = command
            pendingCardCandidates = Array(matches.prefix(3))
            presentCardDisambiguationPrompt(action: "delete")
            return
        }
        
        executeCardDelete(matches[0])
    }
    
    private func handleEditExpenseCommand(_ command: MarinaCommandPlan) {
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
    
    private func handleDeleteExpenseCommand(_ command: MarinaCommandPlan) {
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
    
    private func handleEditIncomeCommand(_ command: MarinaCommandPlan) {
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
    
    private func handleDeleteIncomeCommand(_ command: MarinaCommandPlan) {
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
    
    private func handleMarkIncomeReceivedCommand(_ command: MarinaCommandPlan) {
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
    
    private func handleMoveExpenseCategoryCommand(_ command: MarinaCommandPlan) {
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
    
    private func handleUpdatePlannedExpenseAmountCommand(_ command: MarinaCommandPlan) {
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
    
    private func handleDeleteLastExpenseCommand(_ command: MarinaCommandPlan) {
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
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
            subtitle: "Pick the expense to delete.",
            rows: candidates.enumerated().map { index, expense in
                HomeAnswerRow(title: "\(index + 1)", value: expenseDisplayLabel(expense))
            }
        )
    }
    
    private func handleDeleteLastIncomeCommand(_ command: MarinaCommandPlan) {
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
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
            subtitle: "Pick the income entry to delete.",
            rows: candidates.enumerated().map { index, income in
                HomeAnswerRow(title: "\(index + 1)", value: incomeDisplayLabel(income))
            }
        )
    }
    
    private func executeAddExpense(_ command: MarinaCommandPlan) {
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
    
    private func executeAddIncome(_ command: MarinaCommandPlan) {
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
    
    private func executeAddPreset(_ command: MarinaCommandPlan) {
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
        let recurrenceFrequency = RecurrenceFrequency(rawValue: command.recurrenceFrequencyRaw ?? "")
        ?? .monthly
        let recurrenceInterval = max(1, command.recurrenceInterval ?? 1)
        let weeklyWeekday = min(7, max(1, command.weeklyWeekday ?? 6))
        let monthlyDayOfMonth = min(31, max(1, command.monthlyDayOfMonth ?? 15))
        let monthlyIsLastDay = command.monthlyIsLastDay ?? false
        let yearlyMonth = min(12, max(1, command.yearlyMonth ?? 1))
        let yearlyDayOfMonth = min(31, max(1, command.yearlyDayOfMonth ?? 15))
        
        do {
            let result = try mutationService.addPreset(
                title: title,
                plannedAmount: amount,
                frequencyRaw: recurrenceFrequency.rawValue,
                interval: recurrenceInterval,
                weeklyWeekday: weeklyWeekday,
                monthlyDayOfMonth: monthlyDayOfMonth,
                monthlyIsLastDay: monthlyIsLastDay,
                yearlyMonth: yearlyMonth,
                yearlyDayOfMonth: yearlyDayOfMonth,
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

    private func executeAddPlannedExpense(_ command: MarinaCommandPlan) {
        guard let amount = command.amount, amount > 0 else {
            appendMutationMessage(title: "Need planned expense amount", subtitle: "Tell me the amount to save.", rows: [])
            return
        }

        let title = (command.entityName ?? command.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.isEmpty == false else {
            appendMutationMessage(title: "Need planned expense title", subtitle: "Tell me the planned expense title.", rows: [])
            return
        }

        do {
            let result = try mutationService.addPlannedExpense(
                title: title,
                amount: amount,
                date: calendarStartOfDay(command.date ?? Date()),
                card: resolveCard(from: command.cardName),
                category: resolveCategory(from: command.categoryName),
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not create planned expense", subtitle: error.localizedDescription, rows: [])
        }
    }
    
    private func executeExpenseEdit(_ expense: VariableExpense, using command: MarinaCommandPlan) {
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
    
    private func executeIncomeEdit(_ income: Income, using command: MarinaCommandPlan) {
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
    
    private func executeCardEdit(_ card: Card, using command: MarinaCommandPlan) {
        do {
            let result = try mutationService.editCard(
                card: card,
                newName: command.updatedEntityName,
                themeRaw: command.cardThemeRaw,
                effectRaw: command.cardEffectRaw,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not edit card",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func executeCategoryEdit(_ category: Category, using command: MarinaCommandPlan) {
        let colorResolution = MarinaColorResolver.resolve(
            rawPrompt: command.rawPrompt,
            parserHex: command.categoryColorHex,
            parserName: command.categoryColorName
        )

        do {
            let result = try mutationService.editCategory(
                category,
                newName: command.updatedEntityName,
                colorHex: colorResolution.hex,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not edit category", subtitle: error.localizedDescription, rows: [])
        }
    }

    private func executePresetEdit(_ preset: Preset, using command: MarinaCommandPlan) {
        do {
            let result = try mutationService.editPreset(
                preset,
                command: command,
                card: resolveCard(from: command.cardName),
                category: resolveCategory(from: command.categoryName),
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not edit preset", subtitle: error.localizedDescription, rows: [])
        }
    }

    private func executeBudgetEdit(_ budget: Budget, using command: MarinaCommandPlan) {
        do {
            let result = try mutationService.editBudget(
                budget,
                command: command,
                workspace: workspace,
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not edit budget", subtitle: error.localizedDescription, rows: [])
        }
    }

    private func executePlannedExpenseEdit(_ expense: PlannedExpense, using command: MarinaCommandPlan) {
        do {
            let result = try mutationService.editPlannedExpense(
                expense,
                command: command,
                card: resolveCard(from: command.cardName),
                category: resolveCategory(from: command.categoryName),
                modelContext: modelContext
            )
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not edit planned expense", subtitle: error.localizedDescription, rows: [])
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
    
    private func executeCardDelete(_ card: Card) {
        if confirmBeforeDeleting {
            pendingDeleteCard = card
            appendMutationMessage(
                title: "Confirm delete",
                subtitle: "Delete this card and all of its expenses? Reply with yes to confirm or no to cancel.",
                rows: [HomeAnswerRow(title: "Card", value: cardDisplayLabel(card))]
            )
            return
        }
        
        do {
            let result = try mutationService.deleteCard(card, workspace: workspace, modelContext: modelContext)
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not delete card", subtitle: error.localizedDescription, rows: [])
        }
    }

    private func executeCategoryDelete(_ category: Category) {
        if confirmBeforeDeleting {
            pendingDeleteCategory = category
            appendMutationMessage(
                title: "Confirm delete",
                subtitle: "Delete this category? Reply with yes to confirm or no to cancel.",
                rows: [HomeAnswerRow(title: "Category", value: categoryDisplayLabel(category))]
            )
            return
        }

        do {
            let result = try mutationService.deleteCategory(category, modelContext: modelContext)
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not delete category", subtitle: error.localizedDescription, rows: [])
        }
    }

    private func executePresetDelete(_ preset: Preset) {
        if confirmBeforeDeleting {
            pendingDeletePreset = preset
            appendMutationMessage(
                title: "Confirm delete",
                subtitle: "Delete this preset? Reply with yes to confirm or no to cancel.",
                rows: [HomeAnswerRow(title: "Preset", value: presetDisplayLabel(preset))]
            )
            return
        }

        do {
            let result = try mutationService.deletePreset(preset, modelContext: modelContext)
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not delete preset", subtitle: error.localizedDescription, rows: [])
        }
    }

    private func executeBudgetDelete(_ budget: Budget) {
        if confirmBeforeDeleting {
            pendingDeleteBudget = budget
            appendMutationMessage(
                title: "Confirm delete",
                subtitle: "Delete this budget and its generated planned expenses? Reply with yes to confirm or no to cancel.",
                rows: [HomeAnswerRow(title: "Budget", value: budgetDisplayLabel(budget))]
            )
            return
        }

        do {
            let result = try mutationService.deleteBudget(budget, modelContext: modelContext)
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not delete budget", subtitle: error.localizedDescription, rows: [])
        }
    }

    private func executePlannedExpenseDelete(_ expense: PlannedExpense) {
        if confirmBeforeDeleting {
            pendingDeletePlannedExpense = expense
            appendMutationMessage(
                title: "Confirm delete",
                subtitle: "Delete this planned expense? Reply with yes to confirm or no to cancel.",
                rows: [HomeAnswerRow(title: "Planned Expense", value: plannedExpenseDisplayLabel(expense))]
            )
            return
        }

        do {
            let result = try mutationService.deletePlannedExpense(expense, modelContext: modelContext)
            clearMutationPendingState()
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(title: "Could not delete planned expense", subtitle: error.localizedDescription, rows: [])
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
        target: MarinaPlannedExpenseAmountTarget
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
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
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
        
        plan = plan.updating(cardName: selected.name)
        
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
                title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
                subtitle: "Reply planned or actual.",
                rows: [
                    HomeAnswerRow(title: "1", value: "Planned"),
                    HomeAnswerRow(title: "2", value: "Actual")
                ]
            )
            return
        }
        
        plan = plan.updating(isPlannedIncome: resolved)
        
        pendingIncomeKindPlan = nil
        executeAddIncome(plan)
    }
    
    private func resolvePresetRecurrenceSelection(with prompt: String) {
        guard var plan = pendingPresetRecurrencePlan else { return }
        
        let normalized = prompt.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedFrequency: RecurrenceFrequency?
        if normalized == "1" || normalized.contains("daily") {
            resolvedFrequency = .daily
        } else if normalized == "2" || normalized.contains("weekly") {
            resolvedFrequency = .weekly
        } else if normalized == "3" || normalized.contains("monthly") {
            resolvedFrequency = .monthly
        } else if normalized == "4" || normalized.contains("yearly") || normalized.contains("annual") {
            resolvedFrequency = .yearly
        } else {
            resolvedFrequency = nil
        }
        
        guard let resolvedFrequency else {
            presentPresetRecurrencePrompt()
            return
        }
        
        plan = plan.updating(
            recurrenceFrequencyRaw: resolvedFrequency.rawValue,
            recurrenceInterval: plan.recurrenceInterval ?? 1
        )
        
        pendingPresetRecurrencePlan = nil
        handleAddPresetCommand(plan)
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
        
        plan = plan.updating(cardName: selected.name)
        
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
                title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
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
                title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
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
    
    private func executePendingBudgetCreation(plan: MarinaCommandPlan) {
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

    private func presentCategoryDisambiguationPrompt(action: String) {
        let rows = pendingCategoryCandidates.enumerated().map { index, category in
            HomeAnswerRow(title: "\(index + 1)", value: categoryDisplayLabel(category))
        }
        appendMutationMessage(
            title: "Choose category",
            subtitle: "Reply with the category to \(action).",
            rows: rows
        )
    }

    private func presentPresetDisambiguationPrompt(action: String) {
        let rows = pendingPresetCandidates.enumerated().map { index, preset in
            HomeAnswerRow(title: "\(index + 1)", value: presetDisplayLabel(preset))
        }
        appendMutationMessage(
            title: "Choose preset",
            subtitle: "Reply with the preset to \(action).",
            rows: rows
        )
    }

    private func presentBudgetDisambiguationPrompt(action: String) {
        let rows = pendingBudgetCandidates.enumerated().map { index, budget in
            HomeAnswerRow(title: "\(index + 1)", value: budgetDisplayLabel(budget))
        }
        appendMutationMessage(
            title: "Choose budget",
            subtitle: "Reply with the budget to \(action).",
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

    private func selectedCategoryCandidate(from prompt: String, candidates: [Category]) -> Category? {
        let indexes = selectedIndexes(from: prompt, max: candidates.count)
        if let first = indexes.first {
            return candidates[first]
        }
        if let match = entityMatcher.bestCategoryMatch(in: prompt, categories: candidates) {
            return candidates.first { $0.name == match }
        }
        return nil
    }

    private func selectedPresetCandidate(from prompt: String, candidates: [Preset]) -> Preset? {
        let indexes = selectedIndexes(from: prompt, max: candidates.count)
        if let first = indexes.first {
            return candidates[first]
        }
        let names = candidates.map(\.title)
        if let match = entityMatcher.bestMatch(in: prompt, candidateNames: names) {
            return candidates.first { $0.title == match }
        }
        return nil
    }

    private func selectedBudgetCandidate(from prompt: String, candidates: [Budget]) -> Budget? {
        let indexes = selectedIndexes(from: prompt, max: candidates.count)
        if let first = indexes.first {
            return candidates[first]
        }
        let names = candidates.map(\.name)
        if let match = entityMatcher.bestMatch(in: prompt, candidateNames: names) {
            return candidates.first { $0.name == match }
        }
        return nil
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
    
    private func matchingPresets(for command: MarinaCommandPlan) -> [Preset] {
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
        guard let command = pendingPlannedExpenseDisambiguationPlan ?? pendingPlannedExpenseAmountPlan else { return }

        let selected = selectedPlannedExpenseCandidate(
            from: prompt,
            candidates: pendingPlannedExpenseCandidates
        )
        guard let selected else {
            presentPlannedExpenseDisambiguationPrompt()
            return
        }

        pendingPlannedExpenseCandidates = []
        pendingPlannedExpenseDisambiguationPlan = nil

        if command.intent == .deletePlannedExpense {
            executePlannedExpenseDelete(selected)
            return
        }

        if command.intent == .editPlannedExpense {
            if command.amount != nil && command.plannedExpenseAmountTarget == nil {
                pendingPlannedExpenseAmountPlan = command
                pendingPlannedExpenseAmountExpense = selected
                presentPlannedExpenseAmountTargetPrompt()
                return
            }
            executePlannedExpenseEdit(selected, using: command)
            return
        }

        pendingPlannedExpenseAmountExpense = selected
        guard let amount = command.amount, amount > 0 else { return }
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
        let target: MarinaPlannedExpenseAmountTarget?
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

        if plan.intent == .editPlannedExpense {
            executePlannedExpenseEdit(
                expense,
                using: plan.updating(plannedExpenseAmountTarget: target)
            )
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
    
    private func resolveCardDisambiguation(with prompt: String) {
        guard pendingCardCandidates.isEmpty == false else { return }
        guard let command = pendingCardDisambiguationPlan else { return }
        
        let selected = selectedCardCandidate(from: prompt, candidates: pendingCardCandidates)
        guard let selected else {
            let action = command.intent == .deleteCard ? "delete" : "edit"
            presentCardDisambiguationPrompt(action: action)
            return
        }
        
        if command.intent == .deleteCard {
            executeCardDelete(selected)
        } else {
            executeCardEdit(selected, using: command)
        }
    }

    private func resolveCategoryDisambiguation(with prompt: String) {
        guard pendingCategoryCandidates.isEmpty == false else { return }
        guard let command = pendingCategoryDisambiguationPlan else { return }

        let selected = selectedCategoryCandidate(from: prompt, candidates: pendingCategoryCandidates)
        guard let selected else {
            let action = command.intent == .deleteCategory ? "delete" : "edit"
            presentCategoryDisambiguationPrompt(action: action)
            return
        }

        if command.intent == .deleteCategory {
            executeCategoryDelete(selected)
        } else {
            executeCategoryEdit(selected, using: command)
        }
    }

    private func resolvePresetDisambiguation(with prompt: String) {
        guard pendingPresetCandidates.isEmpty == false else { return }
        guard let command = pendingPresetDisambiguationPlan else { return }

        let selected = selectedPresetCandidate(from: prompt, candidates: pendingPresetCandidates)
        guard let selected else {
            let action = command.intent == .deletePreset ? "delete" : "edit"
            presentPresetDisambiguationPrompt(action: action)
            return
        }

        if command.intent == .deletePreset {
            executePresetDelete(selected)
        } else {
            executePresetEdit(selected, using: command)
        }
    }

    private func resolveBudgetDisambiguation(with prompt: String) {
        guard pendingBudgetCandidates.isEmpty == false else { return }
        guard let command = pendingBudgetDisambiguationPlan else { return }

        let selected = selectedBudgetCandidate(from: prompt, candidates: pendingBudgetCandidates)
        guard let selected else {
            let action = command.intent == .deleteBudget ? "delete" : "edit"
            presentBudgetDisambiguationPrompt(action: action)
            return
        }

        if command.intent == .deleteBudget {
            executeBudgetDelete(selected)
        } else {
            executeBudgetEdit(selected, using: command)
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
            
            if let card = pendingDeleteCard {
                pendingDeleteCard = nil
                do {
                    let result = try mutationService.deleteCard(card, workspace: workspace, modelContext: modelContext)
                    clearMutationPendingState()
                    appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
                } catch {
                    appendMutationMessage(title: "Could not delete card", subtitle: error.localizedDescription, rows: [])
                }
                return
            }

            if let category = pendingDeleteCategory {
                pendingDeleteCategory = nil
                do {
                    let result = try mutationService.deleteCategory(category, modelContext: modelContext)
                    clearMutationPendingState()
                    appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
                } catch {
                    appendMutationMessage(title: "Could not delete category", subtitle: error.localizedDescription, rows: [])
                }
                return
            }

            if let preset = pendingDeletePreset {
                pendingDeletePreset = nil
                do {
                    let result = try mutationService.deletePreset(preset, modelContext: modelContext)
                    clearMutationPendingState()
                    appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
                } catch {
                    appendMutationMessage(title: "Could not delete preset", subtitle: error.localizedDescription, rows: [])
                }
                return
            }

            if let budget = pendingDeleteBudget {
                pendingDeleteBudget = nil
                do {
                    let result = try mutationService.deleteBudget(budget, modelContext: modelContext)
                    clearMutationPendingState()
                    appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
                } catch {
                    appendMutationMessage(title: "Could not delete budget", subtitle: error.localizedDescription, rows: [])
                }
                return
            }

            if let expense = pendingDeletePlannedExpense {
                pendingDeletePlannedExpense = nil
                do {
                    let result = try mutationService.deletePlannedExpense(expense, modelContext: modelContext)
                    clearMutationPendingState()
                    appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
                } catch {
                    appendMutationMessage(title: "Could not delete planned expense", subtitle: error.localizedDescription, rows: [])
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
    
    private func presentCardSelectionPrompt(for command: MarinaCommandPlan) {
        let rows = pendingExpenseCardOptions.enumerated().prefix(5).map { index, card in
            HomeAnswerRow(title: "\(index + 1)", value: card.name)
        }
        
        appendMutationMessage(
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
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
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
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
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
            subtitle: "I found multiple matching planned expenses. Pick one by number.",
            rows: rows
        )
    }
    
    private func presentPresetCardSelectionPrompt() {
        let rows = cards.enumerated().prefix(5).map { index, card in
            HomeAnswerRow(title: "\(index + 1)", value: card.name)
        }
        appendMutationMessage(
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
            subtitle: "Which card should be the default for this preset?",
            rows: rows
        )
    }
    
    private func presentPresetRecurrencePrompt() {
        appendMutationMessage(
            title: "Need preset schedule",
            subtitle: "How often should this preset repeat?",
            rows: [
                HomeAnswerRow(title: "1", value: "Daily"),
                HomeAnswerRow(title: "2", value: "Weekly"),
                HomeAnswerRow(title: "3", value: "Monthly"),
                HomeAnswerRow(title: "4", value: "Yearly")
            ]
        )
    }
    
    private func presentIncomeDisambiguationPrompt() {
        let rows = pendingIncomeCandidates.enumerated().map { index, income in
            HomeAnswerRow(title: "\(index + 1)", value: incomeDisplayLabel(income))
        }
        appendMutationMessage(
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
            subtitle: "I found multiple matching income entries. Pick one by number.",
            rows: rows
        )
    }
    
    private func presentCardDisambiguationPrompt(action: String) {
        let rows = pendingCardCandidates.enumerated().map { index, card in
            HomeAnswerRow(title: "\(index + 1)", value: cardDisplayLabel(card))
        }
        appendMutationMessage(
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
            subtitle: "I found multiple matching cards. Pick one to \(action).",
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
    
    private func selectedCardCandidate(
        from prompt: String,
        candidates: [Card]
    ) -> Card? {
        if let index = Int(prompt.trimmingCharacters(in: .whitespacesAndNewlines)),
           index >= 1,
           index <= candidates.count {
            return candidates[index - 1]
        }
        
        if let match = entityMatcher.bestCardMatch(in: prompt, cards: candidates) {
            return candidates.first { $0.name == match }
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
        pendingPresetRecurrencePlan = nil
        pendingIncomeKindPlan = nil
        pendingExpenseDisambiguationPlan = nil
        pendingIncomeDisambiguationPlan = nil
        pendingCardDisambiguationPlan = nil
        pendingCategoryDisambiguationPlan = nil
        pendingPresetDisambiguationPlan = nil
        pendingBudgetDisambiguationPlan = nil
        pendingPlannedExpenseDisambiguationPlan = nil
        pendingExpenseCandidates = []
        pendingPlannedExpenseAmountPlan = nil
        pendingPlannedExpenseAmountExpense = nil
        pendingPlannedExpenseCandidates = []
        pendingIncomeCandidates = []
        pendingCardCandidates = []
        pendingCategoryCandidates = []
        pendingPresetCandidates = []
        pendingBudgetCandidates = []
        pendingDeleteExpense = nil
        pendingDeleteIncome = nil
        pendingDeleteCard = nil
        pendingDeleteCategory = nil
        pendingDeletePreset = nil
        pendingDeleteBudget = nil
        pendingDeletePlannedExpense = nil
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
    
    private func matchedCards(for command: MarinaCommandPlan) -> [Card] {
        guard cards.isEmpty == false else { return [] }
        let candidateNames = cards.map(\.name)
        
        let explicitName = (command.entityName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if explicitName.isEmpty == false {
            let exactMatches = cards.filter { $0.name.compare(explicitName, options: .caseInsensitive) == .orderedSame }
            if exactMatches.isEmpty == false {
                return exactMatches
            }
            
            let ranked = entityMatcher.rankedMatches(in: explicitName, candidateNames: candidateNames, limit: 3)
            if ranked.isEmpty == false {
                return ranked.compactMap { name in cards.first(where: { $0.name == name }) }
            }
        }
        
        let rankedFromPrompt = entityMatcher.rankedMatches(in: command.rawPrompt, candidateNames: candidateNames, limit: 3)
        return rankedFromPrompt.compactMap { name in cards.first(where: { $0.name == name }) }
    }

    private func matchedCategories(for command: MarinaCommandPlan) -> [Category] {
        guard categories.isEmpty == false else { return [] }
        let explicitName = (command.entityName ?? command.categoryName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if explicitName.isEmpty == false {
            let exactMatches = categories.filter { $0.name.compare(explicitName, options: .caseInsensitive) == .orderedSame }
            if exactMatches.isEmpty == false {
                return exactMatches
            }
            let ranked = entityMatcher.rankedMatches(in: explicitName, candidateNames: categories.map(\.name), limit: 3)
            if ranked.isEmpty == false {
                return ranked.compactMap { name in categories.first(where: { $0.name == name }) }
            }
        }

        let ranked = entityMatcher.rankedMatches(in: command.rawPrompt, candidateNames: categories.map(\.name), limit: 3)
        return ranked.compactMap { name in categories.first(where: { $0.name == name }) }
    }

    private func matchedPresets(for command: MarinaCommandPlan) -> [Preset] {
        guard presets.isEmpty == false else { return [] }
        let explicitName = (command.entityName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if explicitName.isEmpty == false {
            let exactMatches = presets.filter { $0.title.compare(explicitName, options: .caseInsensitive) == .orderedSame }
            if exactMatches.isEmpty == false {
                return exactMatches
            }
            let ranked = entityMatcher.rankedMatches(in: explicitName, candidateNames: presets.map(\.title), limit: 3)
            if ranked.isEmpty == false {
                return ranked.compactMap { name in presets.first(where: { $0.title == name }) }
            }
        }

        let ranked = entityMatcher.rankedMatches(in: command.rawPrompt, candidateNames: presets.map(\.title), limit: 3)
        return ranked.compactMap { name in presets.first(where: { $0.title == name }) }
    }

    private func matchedBudgets(for command: MarinaCommandPlan) -> [Budget] {
        guard budgets.isEmpty == false else { return [] }
        let explicitName = (command.entityName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if explicitName.isEmpty == false {
            let exactMatches = budgets.filter { $0.name.compare(explicitName, options: .caseInsensitive) == .orderedSame }
            if exactMatches.isEmpty == false {
                return exactMatches
            }
            let ranked = entityMatcher.rankedMatches(in: explicitName, candidateNames: budgets.map(\.name), limit: 3)
            if ranked.isEmpty == false {
                return ranked.compactMap { name in budgets.first(where: { $0.name == name }) }
            }
        }

        let ranked = entityMatcher.rankedMatches(in: command.rawPrompt, candidateNames: budgets.map(\.name), limit: 3)
        return ranked.compactMap { name in budgets.first(where: { $0.name == name }) }
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
        "\(CurrencyFormatter.string(from: expense.ledgerSignedAmount())) • \(expense.descriptionText) • \(shortDate(expense.transactionDate))"
    }
    
    private func incomeDisplayLabel(_ income: Income) -> String {
        let label = income.isPlanned ? "Planned" : "Actual"
        return "\(CurrencyFormatter.string(from: income.amount)) • \(income.source) • \(shortDate(income.date)) • \(label)"
    }
    
    private func cardDisplayLabel(_ card: Card) -> String {
        let theme = CardThemeOption(rawValue: card.theme)?.displayName ?? "Ruby"
        let effect = CardEffectOption(rawValue: card.effect)?.displayName ?? "Plastic"
        return "\(card.name) • \(theme) • \(effect)"
    }

    private func categoryDisplayLabel(_ category: Category) -> String {
        category.name
    }

    private func presetDisplayLabel(_ preset: Preset) -> String {
        "\(preset.title) • \(CurrencyFormatter.string(from: preset.plannedAmount))"
    }

    private func budgetDisplayLabel(_ budget: Budget) -> String {
        "\(budget.name) • \(shortDate(budget.startDate)) - \(shortDate(budget.endDate))"
    }

    private func plannedExpenseDisplayLabel(_ expense: PlannedExpense) -> String {
        "\(CurrencyFormatter.string(from: expense.effectiveAmount())) • \(expense.title) • \(shortDate(expense.expenseDate))"
    }
    
    private func shortDate(_ date: Date) -> String {
        AppDateFormat.shortDate(date)
    }
    
    private func aliasTarget(
        in prompt: String,
        entityType: MarinaAliasEntityType
    ) -> String? {
        aliasMatcher.matchedTarget(
            in: prompt,
            entityType: entityType,
            rules: assistantAliasRules
        )
    }
    
    private func recordTelemetry(
        for prompt: String,
        outcome: MarinaTelemetryOutcome,
        source: MarinaAnswerProvenance?,
        plan: HomeQueryPlan?,
        notes: String?
    ) {
        let event = MarinaTelemetryEvent(
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
        clearPendingThinking()

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
            attachment: answer.attachment,
            explanation: answer.explanation,
            generatedAt: answer.generatedAt
        )
        MarinaTraceRecorder.shared.recordResponse(
            type: answerToAppend.kind.rawValue,
            finalAnswerSummary: answerToAppend.traceSummary
        )
        
        pendingUserPromptForNextAnswer = nil
        followUpsCollapsed = false
        answers.append(answerToAppend)
        conversationStore.saveAnswers(answers, workspaceID: workspace.id)
    }

    private func beginPendingThinking(for prompt: String) {
        pendingThinkingPrompt = prompt
        pendingThinkingStartedAt = Date()
    }

    private func clearPendingThinking() {
        pendingThinkingPrompt = nil
        pendingThinkingStartedAt = nil
    }

    private func updateAnswerSubtitle(answerID: UUID, subtitle: String) {
        guard let index = answers.firstIndex(where: { $0.id == answerID }) else { return }
        let answer = answers[index]
        answers[index] = HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            attachment: answer.attachment,
            explanation: answer.explanation,
            generatedAt: answer.generatedAt
        )
    }

    private func replaceAnswerPreservingPrompt(_ replacement: HomeAnswer) {
        clearPendingThinking()

        guard let index = answers.firstIndex(where: { $0.id == replacement.id }) else {
            appendAnswer(replacement)
            return
        }
        let existing = answers[index]
        answers[index] = HomeAnswer(
            id: existing.id,
            queryID: replacement.queryID,
            kind: replacement.kind,
            userPrompt: replacement.userPrompt ?? existing.userPrompt,
            title: replacement.title,
            subtitle: replacement.subtitle,
            primaryValue: replacement.primaryValue,
            rows: replacement.rows,
            attachment: replacement.attachment,
            explanation: replacement.explanation,
            generatedAt: replacement.generatedAt
        )
        MarinaTraceRecorder.shared.recordResponse(
            type: answers[index].kind.rawValue,
            finalAnswerSummary: answers[index].traceSummary
        )
        conversationStore.saveAnswers(answers, workspaceID: workspace.id)
    }
    
    private func quickButtonAccordionAnimation(for index: Int) -> Animation {
        let count = MarinaPresetPromptGroup.allCases.count
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
        sessionContext = MarinaSessionContext()
        clarificationSuggestions = []
        recoverySuggestions = []
        lastClarificationReasons = []
        activeClarificationContext = nil
        clearMutationPendingState()
        conversationStore.saveAnswers([], workspaceID: workspace.id)
    }
    
    private func normalizedPrompt(_ rawPrompt: String) -> String {
        rawPrompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func handleSuggestionTap(_ suggestion: MarinaSuggestion) {
        if let choice = foundationPipelineClarificationChoicesByID[suggestion.id]
            ?? foundationPipelineClarificationChoice(matching: suggestion.title),
           let clarification = foundationPipelineClarification ?? foundationPipelineClarificationChoiceContext {
            Task {
                MarinaTraceRecorder.shared.recordDebugMarker("clarification_chip_tapped:title=\(suggestion.title)")
                await handleFoundationPipelineClarificationChoice(choice, clarification: clarification)
            }
            return
        }

        if clarificationSuggestions.contains(where: { $0.title == suggestion.title }) {
            emitFoundationPipelineClarificationDiagnostic(
                title: suggestion.title,
                reason: "missing_pending_foundationPipeline_clarification"
            )
            return
        }

        Task { @MainActor in
            await runPresetSuggestion(suggestion)
        }
    }

    @MainActor
    private func runPresetSuggestion(_ suggestion: MarinaSuggestion) async {
        let runtimeSettings = marinaRuntimeSettings
        let prompt = suggestion.executionPrompt
        latestTraceAccessibilityValue = ""
        MarinaTraceRecorder.shared.begin(
            prompt: prompt,
            routingMode: runtimeSettings.routingMode,
            runtimeSettingsSummary: "\(runtimeSettings.traceSummary),presetPrompt=\(suggestionTraceSummary(suggestion))"
        )
        MarinaDebugLogger.log("[MarinaPresetPrompt] title='\(suggestion.title)' action='\(suggestionTraceSummary(suggestion))'")
        let runtime = marinaPanelRuntime(turnClassification: .freshQuestion)
        let result: MarinaTurnResult
        switch suggestion.action {
        case .homeQuery(let query):
            result = await runtime.run(
                query: query,
                sourceTitle: suggestion.title
            )
        case .typedIntent(let typedIntent):
            result = await runtime.run(
                typedIntent: typedIntent,
                sourceTitle: prompt
            )
        case .freeformPrompt(let promptText):
            result = await runtime.run(prompt: promptText)
        }
        await handleMarinaTurnResult(result, rawPrompt: prompt)
        finishMarinaTrace()
    }

    private func suggestionTraceSummary(_ suggestion: MarinaSuggestion) -> String {
        suggestion.action.traceSummary(fallbackQuery: suggestion.query)
    }

    @discardableResult
    private func finishMarinaTrace() -> MarinaExecutionTrace? {
        let trace = MarinaTraceRecorder.shared.finish()
        if let trace {
            latestTraceAccessibilityValue = MarinaExecutionTraceSnapshot(trace).accessibilityValue
        }
        return trace
    }

    @MainActor
    private func interpretPrompt(
        _ prompt: String,
        turnClassification: MarinaPromptTurnClassification
    ) async {
        let runtimeSettings = marinaRuntimeSettings
        latestTraceAccessibilityValue = ""
        MarinaTraceRecorder.shared.begin(
            prompt: prompt,
            routingMode: runtimeSettings.routingMode,
            runtimeSettingsSummary: runtimeSettings.traceSummary
        )
        MarinaDebugLogger.log("[MarinaRuntime] \(runtimeSettings.traceSummary)")

        let result = await marinaPanelRuntime(turnClassification: turnClassification).run(prompt: prompt)
        await handleMarinaTurnResult(result, rawPrompt: prompt)
        finishMarinaTrace()
    }

    @MainActor
    private func marinaPanelRuntime(
        turnClassification: MarinaPromptTurnClassification
    ) -> MarinaPanelRuntime {
        MarinaPanelRuntime(
            modelContext: modelContext,
            workspaceID: workspace.id,
            defaultPeriodUnit: defaultQueryPeriodUnit,
            runtimeSettings: marinaRuntimeSettings,
            routerContext: makeMarinaRouterContext(turnClassification: turnClassification),
            turnClassification: turnClassification
        )
    }

    @MainActor
    private func handleMarinaTurnResult(
        _ result: MarinaTurnResult,
        rawPrompt prompt: String
    ) async {
        switch result {
        case .handled(let answer, let aggregationResult, let homeQueryPlan, let amountBasis, let executionRoute):
            MarinaTraceRecorder.shared.recordSelectedRoute(.foundationModels, reason: "marina_foundation")
            MarinaTraceRecorder.shared.recordAggregation(
                path: "marina_foundation",
                summary: [
                    amountBasis.map { "amountBasis=\($0.rawValue)" },
                    executionRoute.map { "route=\($0.traceName)" }
                ].compactMap { $0 }.joined(separator: ",")
            )
            await handleFoundationPipelineAnswer(
                answer,
                aggregationResult: aggregationResult,
                rawPrompt: prompt,
                homeQueryPlan: homeQueryPlan,
                source: .foundationModels
            )
        case .clarification(let answer, let clarification):
            MarinaTraceRecorder.shared.recordSelectedRoute(.clarification, reason: "marina_foundation_clarification")
            await handleFoundationPipelineClarification(
                answer,
                clarification: clarification,
                rawPrompt: prompt,
                source: .foundationModels
            )
        case .blocked(let answer, let validationOutcome):
            MarinaTraceRecorder.shared.recordSelectedRoute(.foundationModels, reason: "marina_foundation_blocked")
            await presentMarinaSystemAnswer(
                answer,
                rawPrompt: prompt,
                surfaceKind: .recovery,
                validationOutcomeSummary: validationOutcome.map { "\($0)" } ?? "marina_foundation_blocked"
            )
        case .unavailable(let answer):
            MarinaTraceRecorder.shared.recordSelectedRoute(.foundationModels, reason: "marina_foundation_ai_unavailable")
            await presentMarinaSystemAnswer(
                answer,
                rawPrompt: prompt,
                surfaceKind: .recovery,
                validationOutcomeSummary: "marina_foundation_ai_unavailable"
            )
        }
    }

    @MainActor
    private func handleFoundationPipelineClarification(
        _ answer: HomeAnswer,
        clarification: MarinaTypedClarification,
        rawPrompt: String,
        source: MarinaAnswerProvenance
    ) async {
        let actionable = clarification.isActionable(for: rawPrompt)
        let actionableChoices = clarification.actionableChoices(for: rawPrompt)
        foundationPipelineClarification = actionable ? clarification : nil
        foundationPipelineClarificationChoiceContext = actionable ? clarification : nil
        foundationPipelineClarificationChoicesByID = actionable
            ? Dictionary(uniqueKeysWithValues: actionableChoices.map { ($0.id, $0) })
            : [:]
        foundationPipelineClarificationChoicesByTitle = actionable ? foundationPipelineChoiceLookup(for: actionableChoices) : [:]
        clarificationSuggestions = actionable ? actionableChoices.map { choice in
            MarinaSuggestion(
                id: choice.id,
                title: foundationPipelineChoiceTitle(choice),
                query: HomeQuery(intent: .periodOverview),
                reasoning: "clarification_choice:\(choice.id.uuidString)"
            )
        } : []
        recoverySuggestions = []
        lastClarificationReasons = [.lowConfidenceLanguage]
        activeClarificationContext = nil

        recordTelemetry(
            for: rawPrompt,
            outcome: .clarification,
            source: source,
            plan: nil,
            notes: "foundationPipeline_clarification"
        )
        let baseAnswer = actionable || actionableChoices.isEmpty == false
            ? answer
            : HomeAnswer(
                queryID: UUID(),
                kind: .message,
                userPrompt: rawPrompt,
                title: "Try a more specific prompt",
                subtitle: "I could not turn that into a safe clarification choice. Try asking for a total, a list, or a named object, like \"How much did I spend on Groceries?\"",
                rows: []
            )
        let presentationAnswer = visualAttachmentAnswer(from: baseAnswer)
        _ = await presentMarinaAnswer(
            deterministicAnswer: presentationAnswer,
            deterministicRecoveryAnswer: presentationAnswer,
            rawPrompt: rawPrompt,
            source: source,
            homeQueryPlan: nil,
            surfaceKind: .clarification,
            validationOutcomeSummary: "clarification:\(clarification.kind.rawValue)",
            clarificationChoices: actionableChoices.map(foundationPipelineChoiceTitle),
            groundingSummary: "clarification:\(clarification.kind.rawValue)"
        )
    }

    @MainActor
    private func handleFoundationPipelineTypedClarificationResolution(
        _ resolution: MarinaClarificationChoiceResolution,
        reply: String,
        clarification: MarinaTypedClarification
    ) async {
        switch resolution {
        case .resolved(let choice):
            await handleFoundationPipelineClarificationChoice(choice, clarification: clarification)
        case .ambiguous(let choices):
            presentFoundationPipelineTypedClarificationRetry(
                reply: reply,
                clarification: clarification,
                title: "I found more than one matching choice",
                subtitle: "Pick one of the existing choices so I can keep this pinned to the right data.",
                choices: choices
            )
        case .unresolved:
            presentFoundationPipelineTypedClarificationRetry(
                reply: reply,
                clarification: clarification,
                title: "I need one of those choices",
                subtitle: "I could not match that reply to a unique clarification choice. Use a chip title or a unique type like category, card, merchant, or expense.",
                choices: clarification.actionableChoices
            )
        }
    }

    @MainActor
    private func presentFoundationPipelineTypedClarificationRetry(
        reply: String,
        clarification: MarinaTypedClarification,
        title: String,
        subtitle: String,
        choices: [MarinaClarificationChoice]
    ) {
        let actionableChoices = choices.isEmpty ? clarification.actionableChoices : choices
        foundationPipelineClarification = clarification
        foundationPipelineClarificationChoiceContext = clarification
        foundationPipelineClarificationChoicesByID = Dictionary(uniqueKeysWithValues: actionableChoices.map { ($0.id, $0) })
        foundationPipelineClarificationChoicesByTitle = foundationPipelineChoiceLookup(for: actionableChoices)
        clarificationSuggestions = actionableChoices.map { choice in
            MarinaSuggestion(
                id: choice.id,
                title: foundationPipelineChoiceTitle(choice),
                query: HomeQuery(intent: .periodOverview),
                reasoning: "clarification_choice:\(choice.id.uuidString)"
            )
        }
        recoverySuggestions = []
        lastClarificationReasons = [.lowConfidenceLanguage]
        activeClarificationContext = nil

        let answer = HomeAnswer(
            queryID: clarification.id,
            kind: .message,
            userPrompt: reply,
            title: title,
            subtitle: subtitle,
            rows: actionableChoices.prefix(4).map { choice in
                HomeAnswerRow(
                    title: foundationPipelineChoiceTitle(choice),
                    value: choice.subtitle ?? choice.rawValue ?? choice.entityTypeHint?.rawValue ?? ""
                )
            }
        )
        let presentationAnswer = visualAttachmentAnswer(from: answer)
        presentMarinaAnswer(
            deterministicAnswer: presentationAnswer,
            deterministicRecoveryAnswer: presentationAnswer,
            rawPrompt: reply,
            source: .foundationModels,
            surfaceKind: .clarification,
            validationOutcomeSummary: "clarification_retry:\(clarification.kind.rawValue)",
            clarificationChoices: actionableChoices.map(foundationPipelineChoiceTitle),
            groundingSummary: "typed clarification retry"
        )
    }

    @MainActor
    private func handleFoundationPipelineClarificationChoice(
        _ choice: MarinaClarificationChoice,
        clarification: MarinaTypedClarification
    ) async {
        let runtimeSettings = marinaRuntimeSettings
        let rawPrompt = clarification.candidate?.rawPrompt ?? choice.title
        MarinaTraceRecorder.shared.begin(
            prompt: rawPrompt,
            routingMode: runtimeSettings.routingMode,
            runtimeSettingsSummary: runtimeSettings.traceSummary
        )
        MarinaTraceRecorder.shared.recordFoundationPipelineTurnClassification(.clarificationAnswer)
        MarinaTraceRecorder.shared.recordAggregation(
            path: "marina_foundation_clarification_resume_start",
            summary: "choice=\(foundationPipelineChoiceTitle(choice))"
        )
        let result = await marinaPanelRuntime(turnClassification: .clarificationAnswer).resume(
            clarification: clarification,
            choice: choice
        )
        await handleMarinaTurnResult(result, rawPrompt: rawPrompt)
        if case .clarification = result {
            finishMarinaTrace()
            return
        }
        foundationPipelineClarification = nil
        foundationPipelineClarificationChoiceContext = nil
        foundationPipelineClarificationChoicesByID = [:]
        foundationPipelineClarificationChoicesByTitle = [:]
        finishMarinaTrace()
    }

    private func foundationPipelineChoiceTitle(_ choice: MarinaClarificationChoice) -> String {
        MarinaClarificationChoiceResolver.displayTitle(for: choice)
    }

    private func foundationPipelineClarificationChoice(matching rawTitle: String) -> MarinaClarificationChoice? {
        foundationPipelineClarificationChoicesByTitle[foundationPipelineChoiceLookupKey(rawTitle)]
            ?? foundationPipelineClarificationChoicesByTitle[rawTitle]
    }

    private func foundationPipelineChoiceLookup(for choices: [MarinaClarificationChoice]) -> [String: MarinaClarificationChoice] {
        var buckets: [String: [MarinaClarificationChoice]] = [:]
        for choice in choices {
            for key in foundationPipelineChoiceLookupKeys(for: choice) {
                buckets[key, default: []].append(choice)
            }
        }
        var lookup: [String: MarinaClarificationChoice] = [:]
        for (key, choices) in buckets where choices.count == 1 {
            lookup[key] = choices[0]
        }
        return lookup
    }

    private func foundationPipelineChoiceLookupKeys(for choice: MarinaClarificationChoice) -> Set<String> {
        var keys: Set<String> = [
            foundationPipelineChoiceTitle(choice),
            choice.title
        ]
        if let rawValue = choice.rawValue {
            keys.insert(rawValue)
        }
        if let type = choice.entityTypeHint {
            keys.insert(type.rawValue)
            keys.insert("\(choice.title) \(type.rawValue)")
            keys.insert("\(choice.title) (\(type.rawValue))")
            for alias in foundationPipelineChoiceTypeAliases(for: type) {
                keys.insert(alias)
                keys.insert("\(choice.title) \(alias)")
                keys.insert("\(choice.title) (\(alias))")
            }
        }
        return Set(keys.map(foundationPipelineChoiceLookupKey).filter { $0.isEmpty == false })
    }

    private func foundationPipelineChoiceTypeAliases(for type: MarinaCandidateEntityTypeHint) -> [String] {
        switch type {
        case .category:
            return ["category"]
        case .card:
            return ["card"]
        case .merchant:
            return ["merchant", "expense description", "description"]
        case .expense, .transaction:
            return ["expense", "transaction", "purchase"]
        case .budget:
            return ["budget"]
        case .preset:
            return ["preset"]
        case .incomeSource:
            return ["income source"]
        case .allocationAccount:
            return ["reconciliation", "reconciliation account", "shared balance"]
        case .savingsAccount:
            return ["savings", "savings account"]
        case .workspace:
            return ["workspace"]
        }
    }

    private func foundationPipelineChoiceLookupKey(_ value: String) -> String {
        MarinaClarificationChoiceResolver.normalized(value)
    }

    private func foundationPipelineTypedChoiceResolution(
        from prompt: String,
        clarification: MarinaTypedClarification
    ) -> MarinaClarificationChoiceResolution {
        if let choice = foundationPipelineClarificationChoice(matching: prompt)
            ?? foundationPipelineChoiceLookup(for: clarification.actionableChoices)[foundationPipelineChoiceLookupKey(prompt)] {
            return .resolved(choice)
        }
        let resolution = MarinaClarificationChoiceResolver().resolve(reply: prompt, clarification: clarification)
        if resolution != .unresolved {
            return resolution
        }
        guard shouldSynthesizeFreeTextClarificationChoice(prompt, clarification: clarification) else {
            return .unresolved
        }
        return .resolved(
            MarinaClarificationChoice(
                title: prompt,
                entityRole: clarification.choices.first?.entityRole,
                entityTypeHint: clarification.choices.first?.entityTypeHint,
                patchSlot: clarification.patchSlot,
                rawValue: prompt,
                mentionID: clarification.choices.first?.mentionID
            )
        )
    }

    private func shouldSynthesizeFreeTextClarificationChoice(
        _ prompt: String,
        clarification: MarinaTypedClarification
    ) -> Bool {
        guard prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return false
        }
        switch clarification.patchSlot {
        case .date, .comparison, .amount, .simulation:
            return true
        case .target, nil:
            return clarification.choices.isEmpty && clarification.patchSlot != .target
        }
    }

    @MainActor
    private func emitFoundationPipelineClarificationDiagnostic(title: String, reason: String) {
        let runtimeSettings = marinaRuntimeSettings
        MarinaTraceRecorder.shared.begin(
            prompt: title,
            routingMode: runtimeSettings.routingMode,
            runtimeSettingsSummary: runtimeSettings.traceSummary
        )
        MarinaTraceRecorder.shared.recordFoundationPipelineTurnClassification(.clarificationAnswer)
        MarinaTraceRecorder.shared.recordSelectedRoute(.clarification, reason: reason)
        MarinaTraceRecorder.shared.recordAggregation(
            path: "marina_foundationPipeline_clarification_diagnostic",
            summary: "title=\(title),reason=\(reason)"
        )
        MarinaTraceRecorder.shared.recordResponse(
            type: HomeAnswerKind.message.rawValue,
            finalAnswerSummary: "clarification diagnostic \(reason)"
        )
        appendAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                userPrompt: title,
                title: "I need that choice again",
                subtitle: "That clarification state expired before I could apply the chip. Ask the original question again and I can resume from the choices.",
                rows: [
                    HomeAnswerRow(title: "Reason", value: reason)
                ]
            )
        )
        _ = finishMarinaTrace()
    }

    private func activeBudgetDateRange() -> HomeQueryDateRange? {
        let now = marinaRuntimeSettings.now
        if let activeBudget = budgets.first(where: { budget in
            budget.startDate <= now && budget.endDate >= now
        }) {
            return HomeQueryDateRange(startDate: activeBudget.startDate, endDate: activeBudget.endDate)
        }
        return nil
    }

    private func makeMarinaRouterContext(
        turnClassification: MarinaPromptTurnClassification
    ) -> MarinaInterpretationContext {
        let mostRecentAnswerContext = sessionContext.recentAnswerContexts.last
        let priorQueryContext = MarinaPriorQueryContext(
            lastQueryPlan: sessionContext.lastQueryPlan,
            lastMetric: sessionContext.lastMetric,
            lastTargetName: sessionContext.lastTargetName ?? mostRecentAnswerContext?.targetName ?? mostRecentAnswerContext?.topRowTitle,
            lastTargetType: mostRecentAnswerContext?.targetType ?? mostRecentAnswerContext?.topRowTargetType,
            lastDateRange: sessionContext.lastDateRange,
            lastResultLimit: sessionContext.lastResultLimit,
            lastPeriodUnit: sessionContext.lastPeriodUnit
        )
        return MarinaInterpretationContext(
            workspaceName: workspace.name,
            defaultPeriodUnit: defaultQueryPeriodUnit,
            ambientDateRange: ambientDateRange,
            sessionContext: sessionContext,
            priorQueryContext: turnClassification == .followUp ? priorQueryContext : .empty,
            cardNames: cards.map(\.name).sorted(),
            categoryNames: categories.map(\.name).sorted(),
            incomeSourceNames: Array(Set(incomes.map(\.source))).sorted(),
            presetTitles: presets.map(\.title).sorted(),
            budgetNames: budgets.map(\.name).sorted(),
            allocationAccountNames: allocationAccounts.map(\.name).sorted(),
            savingsAccountNames: savingsAccounts.map(\.name).sorted(),
            aliasSummaries: assistantAliasRules.map {
                MarinaAliasSummary(
                    entityTypeRaw: $0.entityType.rawValue,
                    aliasKey: $0.aliasKey,
                    targetValue: $0.targetValue
                )
            },
            now: marinaRuntimeSettings.now
        )
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
        _ reasons: [MarinaClarificationReason]
    ) -> [MarinaClarificationReason] {
        var unique: [MarinaClarificationReason] = []
        var seen: Set<MarinaClarificationReason> = []
        
        for reason in reasons {
            if seen.insert(reason).inserted {
                unique.append(reason)
            }
        }
        
        return unique
    }

    private func applyResolutionExplanation(
        _ explanation: String?,
        to answer: HomeAnswer
    ) -> HomeAnswer {
        guard let explanation = explanation?.trimmingCharacters(in: .whitespacesAndNewlines),
              explanation.isEmpty == false else {
            return answer
        }

        let mergedSubtitle: String
        if let subtitle = answer.subtitle, subtitle.isEmpty == false {
            mergedSubtitle = "\(explanation). \(subtitle)"
        } else {
            mergedSubtitle = explanation
        }

        return HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: mergedSubtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            attachment: answer.attachment,
            explanation: explanation,
            generatedAt: answer.generatedAt
        )
    }
    
    private func updateSessionContext(after plan: HomeQueryPlan) {
        sessionContext.lastQueryPlan = plan
        sessionContext.lastMetric = plan.metric
        sessionContext.lastDateRange = plan.dateRange
        sessionContext.lastTargetName = plan.targetName
        sessionContext.lastPeriodUnit = plan.periodUnit
        
        if plan.metric == .topCategories
            || plan.metric == .largestTransactions
            || plan.metric == .savingsAverageRecentPeriods
            || plan.metric == .incomeSourceShareTrend
            || plan.metric == .categorySpendShareTrend
            || plan.metric == .presetDueSoon
            || plan.metric == .presetHighestCost
            || plan.metric == .presetTopCategory
            || plan.metric == .cardVariableSpendingHabits
            || plan.metric == .categoryPotentialSavings
            || plan.metric == .categoryReallocationGuidance
        {
            sessionContext.lastResultLimit = plan.resultLimit
        } else {
            sessionContext.lastResultLimit = nil
        }
    }

    private func rememberAnswerContext(
        for query: HomeQuery,
        executedPlan: HomeQueryPlan?,
        rawAnswer: HomeAnswer,
        aggregationResult: MarinaAggregationResult? = nil,
        presentedAnswer: HomeAnswer,
        userPrompt: String?
    ) {
        let contextRows = answerContextRows(
            from: aggregationResult,
            sourceRows: rawAnswer.rows
        )
        let topRow = contextRows.first
        let inferredTargetType = targetType(for: query.intent.metric) ?? topRow?.targetType
        let inferredTargetName = query.targetName
            ?? inferredTargetName(for: query.intent.metric, rows: contextRows)
        let context = MarinaAnswerContext(
            query: query,
            answerTitle: presentedAnswer.title,
            answerKind: rawAnswer.kind,
            userPrompt: userPrompt,
            targetName: inferredTargetName,
            targetType: inferredTargetType,
            rowTitles: Array(contextRows.prefix(5).map(\.title)),
            rowValues: Array(contextRows.prefix(5).map(\.value)),
            topRowTitle: topRow?.title,
            topRowValue: topRow?.value,
            topRowTargetType: topRow?.targetType ?? inferredTargetType,
            scenarioPercent: extractedPercentValue(from: rawAnswer.subtitle ?? userPrompt ?? ""),
            executedPlan: executedPlan,
            generatedAt: presentedAnswer.generatedAt
        )

        sessionContext.recentAnswerContexts.append(context)
        if sessionContext.recentAnswerContexts.count > 3 {
            sessionContext.recentAnswerContexts = Array(sessionContext.recentAnswerContexts.suffix(3))
        }
    }

    private struct AssistantAnswerContextRow {
        let title: String
        let value: String
        let targetType: MarinaAnswerTargetType?
    }

    private func answerContextRows(
        from aggregationResult: MarinaAggregationResult?,
        sourceRows: [HomeAnswerRow]
    ) -> [AssistantAnswerContextRow] {
        let rows: [AssistantAnswerContextRow]
        switch aggregationResult {
        case .rankedList(let list), .groupedBreakdown(let list):
            rows = list.rows.map {
                AssistantAnswerContextRow(
                    title: $0.label,
                    value: $0.renderedValue,
                    targetType: nil
                )
            }
        case .workspaceCard(let card):
            let cardRows = card.rows.isEmpty == false
                ? card.rows
                : card.items.map {
                    MarinaWorkspaceAggregationCard.Row(
                        label: $0.label,
                        value: $0.value,
                        amount: $0.amount,
                        date: $0.date,
                        objectType: $0.objectType,
                        sourceID: $0.sourceID,
                        sortValue: $0.sortValue
                    )
                }
            rows = cardRows.map {
                AssistantAnswerContextRow(
                    title: $0.label,
                    value: $0.value,
                    targetType: targetType(for: $0.objectType)
                )
            }
        case .scalar, .comparison, .message, .noData, .unsupported, nil:
            rows = []
        }

        if rows.isEmpty == false {
            return rows
        }
        return sourceRows.map {
            AssistantAnswerContextRow(title: $0.title, value: $0.value, targetType: nil)
        }
    }

    private func inferredTargetName(for metric: HomeQueryMetric, rows: [AssistantAnswerContextRow]) -> String? {
        switch metric {
        case .topCategories, .topMerchants, .cardVariableSpendingHabits, .topCardChanges:
            return rows.first?.title
        default:
            return nil
        }
    }

    private func targetType(for objectType: MarinaLookupObjectType?) -> MarinaAnswerTargetType? {
        switch objectType {
        case .category:
            return .category
        case .card:
            return .card
        case .income, .incomeSeries:
            return .incomeSource
        case .importMerchantRule:
            return .merchant
        case .budget, .variableExpense, .plannedExpense, .preset, .savingsAccount,
            .savingsLedgerEntry, .reconciliationAccount, .reconciliationItem,
            .expenseAllocation, .assistantAliasRule, .workspace, .unknown, nil:
            return nil
        }
    }

    private func targetType(for metric: HomeQueryMetric) -> MarinaAnswerTargetType? {
        switch metric {
        case .categorySpendTotal, .topCategories, .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance, .categoryMonthComparison, .topCategoryChanges:
            return .category
        case .cardSpendTotal, .cardVariableSpendingHabits, .cardMonthComparison, .cardSnapshotSummary, .topCardChanges:
            return .card
        case .incomeAverageActual, .incomeSourceShare, .incomeSourceShareTrend, .incomeSourceMonthComparison:
            return .incomeSource
        case .merchantSpendTotal, .merchantSpendSummary, .merchantMonthComparison, .topMerchants:
            return .merchant
        default:
            return nil
        }
    }

    private func extractedPercentValue(from text: String) -> Double? {
        let normalized = normalizedPrompt(text)
        guard let regex = try? NSRegularExpression(pattern: "(\\d+(?:\\.\\d+)?)\\s*%", options: []) else {
            return nil
        }
        let searchRange = NSRange(normalized.startIndex..., in: normalized)
        guard let match = regex.firstMatch(in: normalized, options: [], range: searchRange),
              let valueRange = Range(match.range(at: 1), in: normalized) else {
            return nil
        }
        return Double(normalized[valueRange])
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
                attachment: answer.attachment,
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
                attachment: answer.attachment,
                generatedAt: answer.generatedAt
            )
        }
    }
    
    private func applyPromptAwareTitle(
        to answer: HomeAnswer,
        query: HomeQuery,
        userPrompt: String?
    ) -> HomeAnswer {
        MarinaAnswerTitleResolver().applyingTitle(
            to: answer,
            query: query,
            userPrompt: userPrompt,
            now: marinaRuntimeSettings.now
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
                baseTitle = "Expenses"
            } else if normalized.contains("what did i spend")
                        || normalized.contains("spend my money on")
                        || normalized.contains("where did my money go")
            {
                baseTitle = "Spending"
            } else {
                baseTitle = "Expenses"
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
    
    private var trimmedPromptText: String {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func visibleProvenance(for query: HomeQuery) -> String? {
        let periodLine = visiblePeriodLine(for: query)
        let dataLabels = visibleDataSourceLabels(for: query)
        let dataLine = dataLabels.isEmpty ? nil : "Data used: \(dataLabels.joined(separator: ", "))"

        let lines: [String] = [periodLine, dataLine]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        guard lines.isEmpty == false else { return nil }
        return lines.joined(separator: "\n")
    }

    private func visibleProvenance(for queries: [HomeQuery]) -> String? {
        let range = queries.compactMap(\.dateRange).first
        let periodLine = range.map { "Period: \(visibleRangeLabel(for: $0))" }
        let dataLabels = Array(Set(queries.flatMap { visibleDataSourceLabels(for: $0) })).sorted()
        let dataLine = dataLabels.isEmpty ? nil : "Data used: \(dataLabels.joined(separator: ", "))"

        let lines: [String] = [periodLine, dataLine]
            .compactMap { value in
                guard let value else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        guard lines.isEmpty == false else { return nil }
        return lines.joined(separator: "\n")
    }

    private func visiblePeriodLine(for query: HomeQuery) -> String? {
        switch query.intent {
        case .compareThisMonthToPreviousMonth,
             .compareCategoryThisMonthToPreviousMonth,
             .compareCardThisMonthToPreviousMonth,
             .compareIncomeSourceThisMonthToPreviousMonth,
             .compareMerchantThisMonthToPreviousMonth:
            let ranges = visibleComparisonRanges(for: query)
            let scopePrefix: String
            switch query.intent {
            case .compareCategoryThisMonthToPreviousMonth:
                scopePrefix = query.targetName.map { "Compared: \($0) in " } ?? "Compared: "
            case .compareCardThisMonthToPreviousMonth:
                scopePrefix = query.targetName.map { "Compared: \($0) card in " } ?? "Compared: "
            case .compareIncomeSourceThisMonthToPreviousMonth:
                scopePrefix = query.targetName.map { "Compared: \($0) income in " } ?? "Compared: "
            case .compareMerchantThisMonthToPreviousMonth:
                scopePrefix = query.targetName.map { "Compared: \($0) at " } ?? "Compared: "
            default:
                scopePrefix = "Compared: "
            }

            return "\(scopePrefix)\(visibleRangeLabel(for: ranges.current)) vs \(visibleRangeLabel(for: ranges.previous))"

        default:
            guard let range = query.dateRange else { return nil }
            return "Period: \(visibleRangeLabel(for: range))"
        }
    }

    private func visibleDataSourceLabels(for query: HomeQuery) -> [String] {
        switch query.intent {
        case .periodOverview:
            return ["Planned expenses", "Variable expenses", "Income", "Savings"]
        case .spendThisMonth,
             .categorySpendTotal,
             .spendAveragePerPeriod,
             .topCategoriesThisMonth,
             .compareThisMonthToPreviousMonth,
             .compareCategoryThisMonthToPreviousMonth,
             .compareCardThisMonthToPreviousMonth,
             .largestRecentTransactions,
             .mostFrequentTransactions,
             .cardSpendTotal,
             .cardVariableSpendingHabits,
             .categorySpendShare,
             .categorySpendShareTrend,
             .topCategoryChangesThisMonth,
             .topCardChangesThisMonth,
             .spendTrendsSummary,
             .cardSnapshotSummary,
             .presetCategorySpend,
             .categoryPotentialSavings,
             .categoryReallocationGuidance:
            return ["Planned expenses", "Variable expenses"]
        case .compareMerchantThisMonthToPreviousMonth,
             .merchantSpendTotal,
             .merchantSpendSummary,
             .topMerchantsThisMonth:
            return ["Variable expenses"]
        case .nextPlannedExpense:
            return ["Planned expenses"]
        case .compareIncomeSourceThisMonthToPreviousMonth,
             .incomeAverageActual,
             .incomeSourceShare,
             .incomeSourceShareTrend:
            return ["Income"]
        case .savingsStatus,
             .savingsAverageRecentPeriods,
             .safeSpendToday,
             .forecastSavings:
            return ["Income", "Planned expenses", "Variable expenses", "Savings"]
        case .presetDueSoon,
             .presetHighestCost,
             .presetTopCategory:
            return ["Presets"]
        }
    }

    private func visibleComparisonRanges(for query: HomeQuery) -> (current: HomeQueryDateRange, previous: HomeQueryDateRange) {
        if let currentRange = query.dateRange, let comparisonRange = query.comparisonDateRange {
            return (currentRange, comparisonRange)
        }

        let currentRange = query.dateRange ?? monthRange(containing: Date())
        let previousRange = query.dateRange == nil
            ? previousMonthRange(from: currentRange.startDate)
            : previousEquivalentRange(matching: currentRange)
        return (currentRange, previousRange)
    }

    private func previousEquivalentRange(matching range: HomeQueryDateRange) -> HomeQueryDateRange {
        let calendar = Calendar.current
        let startOfCurrent = calendar.startOfDay(for: range.startDate)
        let startOfEnd = calendar.startOfDay(for: range.endDate)
        let daySpan = (calendar.dateComponents([.day], from: startOfCurrent, to: startOfEnd).day ?? 0) + 1
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: startOfCurrent) ?? startOfCurrent
        let previousStart = calendar.date(byAdding: .day, value: -(daySpan - 1), to: previousEnd) ?? previousEnd
        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }

    private func visibleRangeLabel(for range: HomeQueryDateRange) -> String {
        if visibleRangeIsFullMonth(range) {
            return range.startDate.formatted(.dateTime.year().month(.wide))
        }

        if visibleRangeIsFullYear(range) {
            return range.startDate.formatted(.dateTime.year())
        }

        return "\(AppDateFormat.abbreviatedDate(range.startDate)) - \(AppDateFormat.abbreviatedDate(range.endDate))"
    }

    private func visibleRangeIsFullMonth(_ range: HomeQueryDateRange) -> Bool {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: range.startDate)) ?? range.startDate
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart
        return calendar.isDate(range.startDate, inSameDayAs: monthStart)
            && calendar.isDate(range.endDate, inSameDayAs: monthEnd)
    }

    private func visibleRangeIsFullYear(_ range: HomeQueryDateRange) -> Bool {
        let calendar = Calendar.current
        let yearStart = calendar.date(from: calendar.dateComponents([.year], from: range.startDate)) ?? range.startDate
        let yearEnd = calendar.date(byAdding: DateComponents(year: 1, day: -1), to: yearStart) ?? yearStart
        return calendar.isDate(range.startDate, inSameDayAs: yearStart)
            && calendar.isDate(range.endDate, inSameDayAs: yearEnd)
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
final class MarinaMutationService {
    private let transactionEntryService = TransactionEntryService()
    
    func addBudget(
        name: String,
        dateRange: HomeQueryDateRange,
        cards: [Card],
        presets: [Preset],
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
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
        
        return MarinaMutationResult(
            title: "Budget created",
            subtitle: "Saved budget \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Start", value: AppDateFormat.abbreviatedDate(dateRange.startDate)),
                HomeAnswerRow(title: "End", value: AppDateFormat.abbreviatedDate(dateRange.endDate)),
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
    ) throws -> MarinaMutationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }
        
        let theme = CardThemeOption(rawValue: themeRaw ?? "")?.rawValue ?? CardThemeOption.ruby.rawValue
        let effect = CardEffectOption(rawValue: effectRaw ?? "")?.rawValue ?? CardEffectOption.plastic.rawValue
        let card = Card(name: trimmed, theme: theme, effect: effect, workspace: workspace)
        modelContext.insert(card)
        try modelContext.save()
        
        return MarinaMutationResult(
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
    ) throws -> MarinaMutationResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }
        
        let resolvedHex = (colorHex ?? "#3B82F6").trimmingCharacters(in: .whitespacesAndNewlines)
        let category = Category(name: trimmed, hexColor: resolvedHex, workspace: workspace)
        modelContext.insert(category)
        try modelContext.save()
        
        return MarinaMutationResult(
            title: "Category created",
            subtitle: "Saved category \(trimmed).",
            rows: [HomeAnswerRow(title: "Color", value: resolvedHex)]
        )
    }
    
    func addPreset(
        title: String,
        plannedAmount: Double,
        frequencyRaw: String,
        interval: Int,
        weeklyWeekday: Int,
        monthlyDayOfMonth: Int,
        monthlyIsLastDay: Bool,
        yearlyMonth: Int,
        yearlyDayOfMonth: Int,
        card: Card,
        category: Category?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
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
            frequencyRaw: frequencyRaw,
            interval: interval,
            weeklyWeekday: weeklyWeekday,
            monthlyDayOfMonth: monthlyDayOfMonth,
            monthlyIsLastDay: monthlyIsLastDay,
            yearlyMonth: yearlyMonth,
            yearlyDayOfMonth: yearlyDayOfMonth,
            workspace: workspace,
            defaultCard: card,
            defaultCategory: category
        )
        modelContext.insert(preset)
        try modelContext.save()
        
        return MarinaMutationResult(
            title: "Preset created",
            subtitle: "Saved preset \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: plannedAmount)),
                HomeAnswerRow(title: "Card", value: card.name),
                HomeAnswerRow(title: "Frequency", value: RecurrenceFrequency(rawValue: frequencyRaw)?.displayName ?? "Monthly")
            ]
        )
    }

    func addPlannedExpense(
        title: String,
        amount: Double,
        date: Date,
        card: Card?,
        category: Category?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw TransactionEntryService.ValidationError.missingDescription
        }
        guard amount > 0 else {
            throw TransactionEntryService.ValidationError.invalidAmount
        }

        let expense = PlannedExpense(
            title: trimmed,
            plannedAmount: amount,
            actualAmount: 0,
            expenseDate: Calendar.current.startOfDay(for: date),
            workspace: workspace,
            card: card,
            category: category
        )
        modelContext.insert(expense)
        try modelContext.save()

        return MarinaMutationResult(
            title: "Planned expense created",
            subtitle: "Saved planned expense \(trimmed).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(expense.expenseDate)),
                HomeAnswerRow(title: "Card", value: card?.name ?? "None")
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
    ) throws -> MarinaMutationResult {
        _ = try transactionEntryService.addExpense(
            notes: notes,
            amount: amount,
            date: date,
            workspace: workspace,
            card: card,
            category: category,
            modelContext: modelContext
        )
        
        return MarinaMutationResult(
            title: "Expense logged",
            subtitle: "Saved \(CurrencyFormatter.string(from: amount)) on \(card.name).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: "Card", value: card.name),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(date))
            ]
        )
    }
    
    func addIncome(
        amount: Double,
        source: String,
        date: Date,
        isPlanned: Bool,
        recurrenceFrequencyRaw: String? = nil,
        recurrenceInterval: Int? = nil,
        weeklyWeekday: Int? = nil,
        monthlyDayOfMonth: Int? = nil,
        monthlyIsLastDay: Bool? = nil,
        yearlyMonth: Int? = nil,
        yearlyDayOfMonth: Int? = nil,
        recurrenceEndDate: Date? = nil,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        let resolvedFrequency = RecurrenceFrequency(rawValue: recurrenceFrequencyRaw ?? RecurrenceFrequency.none.rawValue) ?? .none

        if resolvedFrequency != .none {
            guard let recurrenceEndDate else {
                throw NSError(
                    domain: "MarinaMutationService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Repeat income needs an end date."]
                )
            }

            let startDay = Calendar.current.startOfDay(for: date)
            let endDay = Calendar.current.startOfDay(for: recurrenceEndDate)
            guard endDay >= startDay else {
                throw NSError(
                    domain: "MarinaMutationService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Repeat income end date must be on or after the start date."]
                )
            }

            let series = IncomeSeries(
                source: source.trimmingCharacters(in: .whitespacesAndNewlines),
                amount: amount,
                isPlanned: isPlanned,
                frequencyRaw: resolvedFrequency.rawValue,
                interval: max(1, recurrenceInterval ?? 1),
                weeklyWeekday: weeklyWeekday ?? 6,
                monthlyDayOfMonth: monthlyDayOfMonth ?? 15,
                monthlyIsLastDay: monthlyIsLastDay ?? false,
                yearlyMonth: yearlyMonth ?? 1,
                yearlyDayOfMonth: yearlyDayOfMonth ?? 15,
                startDate: startDay,
                endDate: endDay,
                workspace: workspace
            )
            modelContext.insert(series)

            let occurrenceDays = IncomeScheduleEngine.occurrences(for: series)
            for occurrenceDay in occurrenceDays {
                let income = Income(
                    source: series.source,
                    amount: series.amount,
                    date: Calendar.current.startOfDay(for: occurrenceDay),
                    isPlanned: series.isPlanned,
                    isException: false,
                    workspace: workspace,
                    series: series
                )
                modelContext.insert(income)
            }

            try modelContext.save()

            return MarinaMutationResult(
                title: "Income logged",
                subtitle: "Saved recurring \(isPlanned ? "planned" : "actual") income for \(source).",
                rows: [
                    HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                    HomeAnswerRow(title: "Source", value: source),
                    HomeAnswerRow(title: "Frequency", value: resolvedFrequency.displayName)
                ]
            )
        }

        _ = try transactionEntryService.addIncome(
            source: source,
            amount: amount,
            date: date,
            isPlanned: isPlanned,
            workspace: workspace,
            modelContext: modelContext
        )
        
        return MarinaMutationResult(
            title: "Income logged",
            subtitle: "Saved \(CurrencyFormatter.string(from: amount)) as \(isPlanned ? "planned" : "actual") income.",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: amount)),
                HomeAnswerRow(title: "Source", value: source),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(date))
            ]
        )
    }
    
    func updateCardStyle(
        cardName: String,
        workspace: Workspace,
        themeRaw: String,
        effectRaw: String,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
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
                domain: "MarinaMutationService",
                code: 404,
                userInfo: [NSLocalizedDescriptionKey: "Could not find the card to update."]
            )
        }
        
        card.theme = CardThemeOption(rawValue: themeRaw)?.rawValue ?? CardThemeOption.ruby.rawValue
        card.effect = CardEffectOption(rawValue: effectRaw)?.rawValue ?? CardEffectOption.plastic.rawValue
        try modelContext.save()
        
        return MarinaMutationResult(
            title: "Card style updated",
            subtitle: "Updated \(trimmed) with your selected theme and effect.",
            rows: [
                HomeAnswerRow(title: "Theme", value: CardThemeOption(rawValue: card.theme)?.displayName ?? "Ruby"),
                HomeAnswerRow(title: "Effect", value: CardEffectOption(rawValue: card.effect)?.displayName ?? "Plastic")
            ]
        )
    }
    
    func editCardStyle(
        card: Card,
        themeRaw: String?,
        effectRaw: String?,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        guard themeRaw != nil || effectRaw != nil else {
            throw TransactionEntryService.ValidationError.missingDescription
        }
        
        if let themeRaw, let theme = CardThemeOption(rawValue: themeRaw) {
            card.theme = theme.rawValue
        }
        
        if let effectRaw, let effect = CardEffectOption(rawValue: effectRaw) {
            card.effect = effect.rawValue
        }
        
        try modelContext.save()
        
        return MarinaMutationResult(
            title: "Card updated",
            subtitle: "Updated \(card.name).",
            rows: [
                HomeAnswerRow(title: "Theme", value: CardThemeOption(rawValue: card.theme)?.displayName ?? "Ruby"),
                HomeAnswerRow(title: "Effect", value: CardEffectOption(rawValue: card.effect)?.displayName ?? "Plastic")
            ]
        )
    }

    func editCard(
        card: Card,
        newName: String?,
        themeRaw: String?,
        effectRaw: String?,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let newName {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                card.name = trimmed
            }
        }

        if let themeRaw, let theme = CardThemeOption(rawValue: themeRaw) {
            card.theme = theme.rawValue
        }

        if let effectRaw, let effect = CardEffectOption(rawValue: effectRaw) {
            card.effect = effect.rawValue
        }

        try modelContext.save()

        return MarinaMutationResult(
            title: "Card updated",
            subtitle: "Updated \(card.name).",
            rows: [
                HomeAnswerRow(title: "Name", value: card.name),
                HomeAnswerRow(title: "Theme", value: CardThemeOption(rawValue: card.theme)?.displayName ?? "Ruby"),
                HomeAnswerRow(title: "Effect", value: CardEffectOption(rawValue: card.effect)?.displayName ?? "Plastic")
            ]
        )
    }

    func editCategory(
        _ category: Category,
        newName: String?,
        colorHex: String?,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let newName {
            let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty == false {
                category.name = trimmed
            }
        }

        if let colorHex, colorHex.isEmpty == false {
            category.hexColor = colorHex
        }

        try modelContext.save()

        return MarinaMutationResult(
            title: "Category updated",
            subtitle: "Updated \(category.name).",
            rows: [
                HomeAnswerRow(title: "Name", value: category.name),
                HomeAnswerRow(title: "Color", value: category.hexColor)
            ]
        )
    }

    func editPreset(
        _ preset: Preset,
        command: MarinaCommandPlan,
        card: Card?,
        category: Category?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let newName = command.updatedEntityName?.trimmingCharacters(in: .whitespacesAndNewlines), newName.isEmpty == false {
            preset.title = newName
        }
        if let amount = command.amount, amount > 0 {
            preset.plannedAmount = amount
        }
        if let card {
            preset.defaultCard = card
        }
        if command.categoryName != nil {
            preset.defaultCategory = category
        }
        if let frequencyRaw = command.recurrenceFrequencyRaw, RecurrenceFrequency(rawValue: frequencyRaw) != nil {
            preset.frequencyRaw = frequencyRaw
            preset.interval = max(1, command.recurrenceInterval ?? preset.interval)
            if let weeklyWeekday = command.weeklyWeekday {
                preset.weeklyWeekday = weeklyWeekday
            }
            if let monthlyDayOfMonth = command.monthlyDayOfMonth {
                preset.monthlyDayOfMonth = monthlyDayOfMonth
            }
            if let monthlyIsLastDay = command.monthlyIsLastDay {
                preset.monthlyIsLastDay = monthlyIsLastDay
            }
            if let yearlyMonth = command.yearlyMonth {
                preset.yearlyMonth = yearlyMonth
            }
            if let yearlyDayOfMonth = command.yearlyDayOfMonth {
                preset.yearlyDayOfMonth = yearlyDayOfMonth
            }
        }

        syncGeneratedPlannedExpenses(for: preset, workspace: workspace, modelContext: modelContext)
        try modelContext.save()

        return MarinaMutationResult(
            title: "Preset updated",
            subtitle: "Updated \(preset.title).",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: preset.plannedAmount)),
                HomeAnswerRow(title: "Card", value: preset.defaultCard?.name ?? "None"),
                HomeAnswerRow(title: "Frequency", value: preset.frequency.displayName)
            ]
        )
    }

    func editBudget(
        _ budget: Budget,
        command: MarinaCommandPlan,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let newName = command.updatedEntityName?.trimmingCharacters(in: .whitespacesAndNewlines), newName.isEmpty == false {
            budget.name = newName
        }
        if let range = command.dateRange {
            budget.startDate = Calendar.current.startOfDay(for: range.startDate)
            budget.endDate = Calendar.current.startOfDay(for: range.endDate)
        }

        syncGeneratedPlannedExpenses(for: budget, workspace: workspace, modelContext: modelContext)
        try modelContext.save()

        return MarinaMutationResult(
            title: "Budget updated",
            subtitle: "Updated \(budget.name).",
            rows: [
                HomeAnswerRow(title: "Start", value: AppDateFormat.abbreviatedDate(budget.startDate)),
                HomeAnswerRow(title: "End", value: AppDateFormat.abbreviatedDate(budget.endDate))
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
        command: MarinaCommandPlan,
        card: Card?,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
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
        
        return MarinaMutationResult(
            title: "Expense updated",
            subtitle: "Your expense entry was updated.",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: expense.ledgerSignedAmount())),
                HomeAnswerRow(title: "Description", value: expense.descriptionText),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(expense.transactionDate))
            ]
        )
    }
    
    func editIncome(
        _ income: Income,
        command: MarinaCommandPlan,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
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
        
        return MarinaMutationResult(
            title: "Income updated",
            subtitle: "Your income entry was updated.",
            rows: [
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: income.amount)),
                HomeAnswerRow(title: "Source", value: income.source),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(income.date))
            ]
        )
    }
    
    func moveExpenseCategory(
        expense: VariableExpense,
        category: Category,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        expense.category = category
        try modelContext.save()
        
        return MarinaMutationResult(
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
        target: MarinaPlannedExpenseAmountTarget,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        switch target {
        case .planned:
            expense.plannedAmount = amount
        case .actual:
            expense.actualAmount = amount
        }
        
        try modelContext.save()
        
        return MarinaMutationResult(
            title: "Planned expense updated",
            subtitle: "Updated \(expense.title).",
            rows: [
                HomeAnswerRow(title: "Planned", value: CurrencyFormatter.string(from: expense.plannedAmount)),
                HomeAnswerRow(title: "Actual", value: CurrencyFormatter.string(from: expense.actualAmount))
            ]
        )
    }

    func editPlannedExpense(
        _ expense: PlannedExpense,
        command: MarinaCommandPlan,
        card: Card?,
        category: Category?,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let newName = command.updatedEntityName?.trimmingCharacters(in: .whitespacesAndNewlines), newName.isEmpty == false {
            expense.title = newName
        }
        if let date = command.date {
            expense.expenseDate = Calendar.current.startOfDay(for: date)
        }
        if let card {
            expense.card = card
        }
        if command.categoryName != nil {
            expense.category = category
        }
        if let amount = command.amount, amount > 0 {
            switch command.plannedExpenseAmountTarget ?? .planned {
            case .planned:
                expense.plannedAmount = amount
            case .actual:
                expense.actualAmount = amount
            }
        }

        try modelContext.save()

        return MarinaMutationResult(
            title: "Planned expense updated",
            subtitle: "Updated \(expense.title).",
            rows: [
                HomeAnswerRow(title: "Planned", value: CurrencyFormatter.string(from: expense.plannedAmount)),
                HomeAnswerRow(title: "Actual", value: CurrencyFormatter.string(from: expense.actualAmount)),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(expense.expenseDate))
            ]
        )
    }
    
    func deleteExpense(
        _ expense: VariableExpense,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        VariableExpenseDeletionService.delete(expense, modelContext: modelContext)
        try modelContext.save()
        
        return MarinaMutationResult(
            title: "Expense deleted",
            subtitle: "The expense was removed.",
            rows: []
        )
    }
    
    func deleteIncome(
        _ income: Income,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        modelContext.delete(income)
        try modelContext.save()
        
        return MarinaMutationResult(
            title: "Income deleted",
            subtitle: "The income entry was removed.",
            rows: []
        )
    }
    
    func deleteCard(
        _ card: Card,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        let workspaceID = workspace.id
        let cardID = card.id
        
        HomePinnedItemsStore(workspaceID: workspaceID).removePinnedCard(id: cardID)
        HomePinnedCardsStore(workspaceID: workspaceID).removePinnedCardID(cardID)
        
        if let planned = card.plannedExpenses {
            for expense in planned {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        }
        
        if let variable = card.variableExpenses {
            for expense in variable {
                deleteVariableExpense(expense, modelContext: modelContext)
            }
        }
        
        if let incomes = card.incomes {
            for income in incomes {
                modelContext.delete(income)
            }
        }
        
        if let links = card.budgetLinks {
            for link in links {
                modelContext.delete(link)
            }
        }
        
        modelContext.delete(card)
        try modelContext.save()
        
        return MarinaMutationResult(
            title: "Card deleted",
            subtitle: "Removed \(card.name) and its linked entries.",
            rows: []
        )
    }

    func deleteCategory(
        _ category: Category,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let variableExpenses = category.variableExpenses {
            for expense in variableExpenses {
                expense.category = nil
            }
        }
        if let plannedExpenses = category.plannedExpenses {
            for expense in plannedExpenses {
                expense.category = nil
            }
        }
        if let presets = category.defaultForPresets {
            for preset in presets {
                preset.defaultCategory = nil
            }
        }
        if let limits = category.budgetCategoryLimits {
            for limit in limits {
                modelContext.delete(limit)
            }
        }
        modelContext.delete(category)
        try modelContext.save()

        return MarinaMutationResult(
            title: "Category deleted",
            subtitle: "Removed \(category.name).",
            rows: []
        )
    }

    func deletePreset(
        _ preset: Preset,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        if let links = preset.budgetPresetLinks {
            for link in links {
                modelContext.delete(link)
            }
        }
        modelContext.delete(preset)
        try modelContext.save()

        return MarinaMutationResult(
            title: "Preset deleted",
            subtitle: "Removed \(preset.title).",
            rows: []
        )
    }

    func deleteBudget(
        _ budget: Budget,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        try BudgetDeletionService.deleteBudgetAndGeneratedPlannedExpenses(budget, modelContext: modelContext)
        return MarinaMutationResult(
            title: "Budget deleted",
            subtitle: "Removed \(budget.name).",
            rows: []
        )
    }

    func deletePlannedExpense(
        _ expense: PlannedExpense,
        modelContext: ModelContext
    ) throws -> MarinaMutationResult {
        PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        try modelContext.save()

        return MarinaMutationResult(
            title: "Planned expense deleted",
            subtitle: "The planned expense was removed.",
            rows: []
        )
    }
    
    func matchedExpenses(
        for command: MarinaCommandPlan,
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
    
    private func deleteVariableExpense(
        _ expense: VariableExpense,
        modelContext: ModelContext
    ) {
        VariableExpenseDeletionService.delete(expense, modelContext: modelContext)
    }
    
    func matchedIncomes(
        for command: MarinaCommandPlan,
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
        for command: MarinaCommandPlan,
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

    private func syncGeneratedPlannedExpenses(
        for preset: Preset,
        workspace: Workspace,
        modelContext: ModelContext
    ) {
        let linkedBudgets = (preset.budgetPresetLinks ?? []).compactMap(\.budget)
        for budget in linkedBudgets {
            deleteGeneratedPlannedExpenses(
                budgetID: budget.id,
                presetID: preset.id,
                modelContext: modelContext
            )

            let selectedPresets = (budget.presetLinks ?? []).compactMap(\.preset)
            let selectedCardIDs = Set((budget.cardLinks ?? []).compactMap { $0.card?.id })
            materializePlannedExpenses(
                for: budget,
                selectedPresets: selectedPresets,
                selectedCardIDs: selectedCardIDs,
                workspace: workspace,
                modelContext: modelContext
            )
        }

        applyPresetAttributesToGeneratedExpenses(preset: preset, modelContext: modelContext)
    }

    private func syncGeneratedPlannedExpenses(
        for budget: Budget,
        workspace: Workspace,
        modelContext: ModelContext
    ) {
        let selectedPresetIDs = Set((budget.presetLinks ?? []).compactMap { $0.preset?.id })
        let selectedCardIDs = Set((budget.cardLinks ?? []).compactMap { $0.card?.id })

        deleteGeneratedPlannedExpensesNotMatchingSelection(
            budgetID: budget.id,
            selectedPresetIDs: selectedPresetIDs,
            windowStart: Calendar.current.startOfDay(for: budget.startDate),
            windowEnd: Calendar.current.startOfDay(for: budget.endDate),
            selectedCardIDs: selectedCardIDs,
            modelContext: modelContext
        )

        materializePlannedExpenses(
            for: budget,
            selectedPresets: (budget.presetLinks ?? []).compactMap(\.preset),
            selectedCardIDs: selectedCardIDs,
            workspace: workspace,
            modelContext: modelContext
        )
    }

    private func deleteGeneratedPlannedExpensesNotMatchingSelection(
        budgetID: UUID,
        selectedPresetIDs: Set<UUID>,
        windowStart: Date,
        windowEnd: Date,
        selectedCardIDs: Set<UUID>,
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID
            }
        )

        do {
            let matches = try modelContext.fetch(descriptor)
            for expense in matches {
                let presetID = expense.sourcePresetID
                let inSelectedPresets = presetID.map { selectedPresetIDs.contains($0) } ?? false
                let day = Calendar.current.startOfDay(for: expense.expenseDate)
                let inWindow = (day >= windowStart && day <= windowEnd)
                let cardID = expense.card?.id
                let cardStillLinked = cardID.map { selectedCardIDs.contains($0) } ?? true

                if !inSelectedPresets || !inWindow || !cardStillLinked {
                    PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
                }
            }
        } catch {
            return
        }
    }

    private func deleteGeneratedPlannedExpenses(
        budgetID: UUID,
        presetID: UUID,
        modelContext: ModelContext
    ) {
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID &&
                expense.sourcePresetID == presetID
            }
        )

        do {
            let matches = try modelContext.fetch(descriptor)
            for expense in matches {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        } catch {
            return
        }
    }

    private func applyPresetAttributesToGeneratedExpenses(
        preset: Preset,
        modelContext: ModelContext
    ) {
        let presetID = preset.id
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourcePresetID == presetID
            }
        )

        do {
            let matches = try modelContext.fetch(descriptor)
            for expense in matches {
                expense.title = preset.title
                expense.plannedAmount = preset.plannedAmount
                expense.category = preset.defaultCategory

                if let budgetID = expense.sourceBudgetID,
                   let budgetCardIDs = budgetCardIDs(for: budgetID, modelContext: modelContext),
                   let defaultCard = preset.defaultCard,
                   budgetCardIDs.contains(defaultCard.id) {
                    expense.card = defaultCard
                } else if expense.sourceBudgetID == nil {
                    expense.card = preset.defaultCard
                } else {
                    expense.card = nil
                }
            }
        } catch {
            return
        }
    }

    private func budgetCardIDs(
        for budgetID: UUID,
        modelContext: ModelContext
    ) -> Set<UUID>? {
        let descriptor = FetchDescriptor<BudgetCardLink>(
            predicate: #Predicate { link in
                link.budget?.id == budgetID
            }
        )

        do {
            return Set(try modelContext.fetch(descriptor).compactMap { $0.card?.id })
        } catch {
            return nil
        }
    }
}

// MARK: - Assistant Button Modifiers

private enum AssistantPanelToolbarStyle {
    static var usesNativeLiquidGlass: Bool {
#if targetEnvironment(macCatalyst)
        return false
#elseif os(iOS)
        guard ProcessInfo.processInfo.isiOSAppOnMac == false else {
            return false
        }

        switch UIDevice.current.userInterfaceIdiom {
        case .phone, .pad:
            return true
        default:
            return false
        }
#else
        return false
#endif
    }
}

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

private struct AssistantPanelActionButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), AssistantPanelToolbarStyle.usesNativeLiquidGlass {
            content
                .buttonStyle(.automatic)
                .buttonBorderShape(.capsule)
        } else if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        } else {
            content
                .buttonStyle(.bordered)
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

private struct AssistantPanelIconButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), AssistantPanelToolbarStyle.usesNativeLiquidGlass {
            content
                .buttonStyle(.automatic)
                .buttonBorderShape(.circle)
        } else if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            content
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
        }
    }
}
