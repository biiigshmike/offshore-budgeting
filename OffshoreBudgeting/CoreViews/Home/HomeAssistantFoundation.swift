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

enum HomeAssistantPlanResolutionSource: String {
    case model
    case parser
    case contextual
    case entityAware
}

// MARK: - Presented Panel

struct HomeAssistantPanelView: View {
    private enum ScrollTarget {
        static let bottomAnchor = "assistant-bottom-anchor"
    }
    
    private enum HomeAssistantCreateEntityKind {
        case expense
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
        let provenance: String?
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
    let assistantDateRange: HomeQueryDateRange?
    let onOpenWhatIfPlanner: (HomeAssistantWhatIfPlannerDraft) -> Void
    
    @Query private var budgets: [Budget]
    @Query private var categories: [Category]
    @Query private var cards: [Card]
    @Query private var presets: [Preset]
    @Query private var incomes: [Income]
    @Query private var assistantAliasRules: [AssistantAliasRule]
    @Query private var plannedExpenses: [PlannedExpense]
    @Query private var variableExpenses: [VariableExpense]
    @Query private var savingsEntries: [SavingsLedgerEntry]
    
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
    @State private var recoverySuggestions: [HomeAssistantRecoverySuggestion] = []
    @State private var lastClarificationReasons: [HomeAssistantClarificationReason] = []
    @State private var activeClarificationContext: HomeAssistantClarificationContext? = nil
    @State private var selectedEmptySuggestionGroup: EmptySuggestionGroup?
    @State private var personaSessionSeed: UInt64 = UInt64.random(in: UInt64.min...UInt64.max)
    @State private var personaCooldownSessionID: String = UUID().uuidString
    @State private var pendingExpenseCardPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingExpenseCardOptions: [Card] = []
    @State private var pendingPresetCardPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingPresetRecurrencePlan: HomeAssistantCommandPlan? = nil
    @State private var pendingIncomeKindPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingExpenseDisambiguationPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingIncomeDisambiguationPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingCardDisambiguationPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingCategoryDisambiguationPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingPresetDisambiguationPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingBudgetDisambiguationPlan: HomeAssistantCommandPlan? = nil
    @State private var pendingPlannedExpenseDisambiguationPlan: HomeAssistantCommandPlan? = nil
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
    @State private var pendingWhatIfContext: HomeAssistantWhatIfContext? = nil
    @State private var pendingWhatIfCategoryMappingContext: HomeAssistantWhatIfContext? = nil
    @FocusState private var isPromptFieldFocused: Bool
    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue
    @AppStorage("general_confirmBeforeDeleting")
    private var confirmBeforeDeleting: Bool = true
    
    @Environment(\.modelContext) private var modelContext
    private let engine = HomeQueryEngine()
    private let parser = HomeAssistantTextParser()
    private let commandParser = HomeAssistantCommandParser()
    private let languageRouter = MarinaLanguageRouter()
    private let conversationStore = HomeAssistantConversationStore()
    private let telemetryStore = HomeAssistantTelemetryStore()
    private let entityMatcher = HomeAssistantEntityMatcher()
    private let aliasMatcher = HomeAssistantAliasMatcher()
    private let entityResolutionResolver = HomeAssistantEntityResolver()
    private let planReconciler = HomeAssistantPlanReconciler()
    private let requestRoutingResolver = HomeAssistantRequestRoutingResolver()
    private let executedQueryAnswerNormalizer = HomeAssistantExecutedQueryAnswerNormalizer()
    private let whatIfParser = HomeAssistantWhatIfParser()
    private let whatIfAnswerBuilder = HomeAssistantWhatIfAnswerBuilder()
    private let dailySpendAnswerBuilder = HomeAssistantDailySpendAnswerBuilder()
    private let incomePeriodSummaryAnswerBuilder = HomeAssistantIncomePeriodSummaryAnswerBuilder()
    private let categoryAvailabilityAnswerBuilder = HomeAssistantCategoryAvailabilityAnswerBuilder()
    private let cardSummaryAnswerBuilder = HomeAssistantCardSummaryAnswerBuilder()
    private let mutationService = HomeAssistantMutationService()
    private let followUpAnchorResolver = HomeAssistantFollowUpAnchorResolver()
    private var intentBuilder: HomeAssistantIntentBuilder {
        HomeAssistantIntentBuilder(
            categoryNames: categories.map(\.name),
            cardNames: cards.map(\.name),
            incomeSourceNames: Array(Set(incomes.map(\.source)))
        )
    }
    
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

    private var defaultBudgetingPeriod: BudgetingPeriod {
        BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
    }
    
    init(
        workspace: Workspace,
        onDismiss: @escaping () -> Void,
        shouldUseLargeMinimumSize: Bool,
        assistantDateRange: HomeQueryDateRange? = nil,
        onOpenWhatIfPlanner: @escaping (HomeAssistantWhatIfPlannerDraft) -> Void = { _ in }
    ) {
        self.workspace = workspace
        self.onDismiss = onDismiss
        self.shouldUseLargeMinimumSize = shouldUseLargeMinimumSize
        self.assistantDateRange = assistantDateRange
        self.onOpenWhatIfPlanner = onOpenWhatIfPlanner
        
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
                    if #available(iOS 26.0, macCatalyst 26.0, *) {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                                .frame(width: 33, height: 33)
                                .buttonStyle(.glass)
                        }
                        .accessibilityLabel(String(localized: "assistant.close", defaultValue: "Close Assistant", comment: "Accessibility label for closing assistant."))
                    } else {
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "assistant.close", defaultValue: "Close Assistant", comment: "Accessibility label for closing assistant."))
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    if #available(iOS 26.0, macCatalyst 26.0, *) {
                        Button {
                            isShowingClearConversationAlert = true
                        } label: {
                            Text(String(localized: "common.clear", defaultValue: "Clear", comment: "Action to clear a selection."))
                                .frame(height: 33)
                                .buttonStyle(.glass)
                        }
                        .disabled(answers.isEmpty)
                        .accessibilityLabel(String(localized: "assistant.clearChat", defaultValue: "Clear Chat", comment: "Accessibility label for clearing assistant chat."))
                    } else {
                        Button {
                            isShowingClearConversationAlert = true
                        } label: {
                            Text(String(localized: "common.clear", defaultValue: "Clear", comment: "Action to clear a selection."))
                        }
                        .buttonStyle(.plain)
                        .disabled(answers.isEmpty)
                        .accessibilityLabel(String(localized: "assistant.clearChat", defaultValue: "Clear Chat", comment: "Accessibility label for clearing assistant chat."))
                    }
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
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }
    
    private func handleCreateMenuSelection(_ kind: HomeAssistantCreateEntityKind) {
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
    
    private func creationGuidance(
        for kind: HomeAssistantCreateEntityKind
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

    private func appendInlineCreateForm(_ form: HomeAssistantInlineCreateForm) {
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

    private func inlineCreateFormBinding(for answerID: UUID) -> Binding<HomeAssistantInlineCreateForm>? {
        guard currentInlineCreateForm(for: answerID) != nil else { return nil }
        return Binding(
            get: { currentInlineCreateForm(for: answerID) ?? makeInlineCreateForm(for: .expense, command: nil) },
            set: { updated in
                updateInlineCreateForm(answerID: answerID, form: updated)
            }
        )
    }

    private func currentInlineCreateForm(for answerID: UUID) -> HomeAssistantInlineCreateForm? {
        guard let answer = answers.first(where: { $0.id == answerID }),
              case let .inlineCreateForm(form)? = answer.attachment else {
            return nil
        }
        return form
    }

    private func updateInlineCreateForm(answerID: UUID, form: HomeAssistantInlineCreateForm) {
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
        NSError(domain: "HomeAssistantInlineCreateForm", code: 400, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private func executeInlineCreateForm(_ form: HomeAssistantInlineCreateForm) throws -> HomeAssistantMutationResult {
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

    private func inlineCreateSummaryRows(for form: HomeAssistantInlineCreateForm) -> [HomeAnswerRow] {
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
        for entity: HomeAssistantInlineCreateEntity,
        command: HomeAssistantCommandPlan?
    ) -> HomeAssistantInlineCreateForm {
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
            return HomeAssistantInlineCreateForm(
                entity: .expense,
                summary: command == nil ? nil : "I prefilled the expense details from your message.",
                amountText: amountInputString(command?.amount),
                date: command?.date ?? now,
                notesText: command?.notes ?? "",
                selectedCardID: resolvedCardID,
                selectedCategoryID: resolvedCategoryID
            )
        case .income:
            return HomeAssistantInlineCreateForm(
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
            return HomeAssistantInlineCreateForm(
                entity: .budget,
                summary: command == nil ? nil : "I prefilled the budget details from your message.",
                nameText: command?.entityName ?? BudgetNameSuggestion.suggestedName(start: seededRange.startDate, end: seededRange.endDate, calendar: .current),
                date: seededRange.startDate,
                secondaryDate: seededRange.endDate,
                selectedCardIDs: command?.attachAllCards == true ? cards.map(\.id) : resolvedSelectedCardIDs(from: command),
                selectedPresetIDs: command?.attachAllPresets == true ? presets.map(\.id) : resolvedSelectedPresetIDs(from: command)
            )
        case .card:
            return HomeAssistantInlineCreateForm(
                entity: .card,
                summary: command == nil ? nil : "I prefilled the card details from your message.",
                nameText: command?.entityName ?? command?.notes ?? "",
                cardThemeRaw: command?.cardThemeRaw ?? CardThemeOption.ruby.rawValue,
                cardEffectRaw: command?.cardEffectRaw ?? CardEffectOption.plastic.rawValue
            )
        case .preset:
            return HomeAssistantInlineCreateForm(
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
            return HomeAssistantInlineCreateForm(
                entity: .category,
                summary: command == nil ? nil : "I prefilled the category details from your message.",
                nameText: command?.entityName ?? command?.notes ?? "",
                categoryColorHex: colorResolution.hex
            )
        case .plannedExpense:
            return HomeAssistantInlineCreateForm(
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

    private func resolvedSelectedCardIDs(from command: HomeAssistantCommandPlan?) -> [UUID] {
        guard let command else { return [] }
        return command.selectedCardNames.compactMap { name in
            resolveCard(from: name)?.id
        }
    }

    private func resolvedSelectedPresetIDs(from command: HomeAssistantCommandPlan?) -> [UUID] {
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
    
    private func inlineConversationSuggestionSections(
        for answer: HomeAnswer
    ) -> [(title: String, suggestions: [HomeAssistantSuggestion], isRecovery: Bool)] {
        var sections: [(title: String, suggestions: [HomeAssistantSuggestion], isRecovery: Bool)] = []

        if clarificationSuggestions.isEmpty == false {
            let title = lastClarificationReasons.isEmpty ? "Clarification" : "Clarification (\(lastClarificationReasons.count))"
            sections.append((title: title, suggestions: clarificationSuggestions, isRecovery: false))
        }

        if recoverySuggestions.isEmpty == false {
            sections.append((
                title: "Recovery",
                suggestions: recoverySuggestions.map(\.suggestion),
                isRecovery: true
            ))
        }

        let groundedQuery = sessionContext.recentAnswerContexts.last?.executedPlan?.query
            ?? sessionContext.recentAnswerContexts.last?.query
        let followUps = personaFormatter.followUpSuggestions(
            after: answer,
            executedQuery: groundedQuery,
            personaID: selectedPersonaID
        )
        if followUps.isEmpty == false {
            sections.append((title: "Follow-Up Suggestions", suggestions: followUps, isRecovery: false))
        }

        return sections
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
                HomeAssistantSuggestion(title: "Largest recent expenses", query: HomeQuery(intent: .largestRecentTransactions)),
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
    
    private var selectedPersonaProfile: HomeAssistantPersonaProfile {
        HomeAssistantPersonaCatalog.profile(for: selectedPersonaID)
    }
    
    private var emptyStatePersonaIntroduction: String {
        personaTransitionDescription
    }
    
    private var personaTransitionDescription: String {
        String(
            localized: "assistant.persona.transitionDescription",
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
                    }
                    
                    assistantMessageBubble(for: answer)
                    
                    if index == answers.count - 1, selectedEmptySuggestionGroup == nil {
                        let sections = inlineConversationSuggestionSections(for: answer)
                        if sections.isEmpty == false {
                            assistantFollowUpRail(sections: sections)
                        }
                    }
                }
            }
        }
    }
    
    private func assistantFollowUpRail(
        sections: [(title: String, suggestions: [HomeAssistantSuggestion], isRecovery: Bool)]
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

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(section.suggestions) { suggestion in
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

                if let formBinding = inlineCreateFormBinding(for: answer.id) {
                    HomeAssistantInlineCreateFormCard(
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
            
            Text(timestampText(for: answer.generatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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

        if let legacySourcesRange = bodyWithoutTechnicalFooter.range(of: "Sources:", options: .backwards) {
            let narrative = String(bodyWithoutTechnicalFooter[..<legacySourcesRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let provenance = String(bodyWithoutTechnicalFooter[legacySourcesRange.upperBound...])
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
        executedPlan: HomeQueryPlan? = nil
    ) {
        clarificationSuggestions = []
        recoverySuggestions = []
        lastClarificationReasons = []
        activeClarificationContext = nil
        
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
        let personaUserPrompt = (confidenceBand == .high || rawAnswer.kind != .comparison) ? userPrompt : nil
        
        let answer = personaFormatter.styledAnswer(
            from: explainedAnswer,
            userPrompt: personaUserPrompt,
            personaID: selectedPersonaID,
            seedContext: personaSeedContext(for: query),
            footerContext: personaFooterContext(for: [query]),
            echoContext: personaEchoContext(for: query),
            visibleProvenance: visibleProvenance(for: query)
        )
        
        updateSessionContext(after: executedPlan ?? HomeQueryPlan(
            metric: query.intent.metric,
            dateRange: query.dateRange,
            comparisonDateRange: query.comparisonDateRange,
            resultLimit: query.resultLimit,
            confidenceBand: confidenceBand,
            targetName: query.targetName,
            periodUnit: query.periodUnit
        ))
        rememberAnswerContext(
            for: query,
            executedPlan: executedPlan,
            rawAnswer: normalizedAnswer,
            presentedAnswer: answer,
            userPrompt: userPrompt
        )
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

        if handleClarificationRejection(prompt) {
            return
        }
        
        if let explainPrompt = planExplainPrompt(from: prompt) {
            appendAnswer(planExplanationAnswer(for: explainPrompt))
            return
        }
        
        if handleConversationalPrompt(prompt) {
            return
        }

        if resolvePendingWhatIfFollowUp(with: prompt) {
            return
        }

        if handleWhatIfPrompt(prompt) {
            return
        }

        if handleAnchoredFollowUpPrompt(prompt) {
            return
        }
        
        if handleUnsupportedPrompt(prompt) {
            return
        }

        Task { @MainActor in
            await interpretPrompt(prompt)
        }
    }

    private func handleWhatIfPrompt(_ prompt: String) -> Bool {
        guard let result = whatIfParser.parse(
            prompt,
            categories: categories,
            fallbackDateRange: assistantDateRange,
            dateParser: parser,
            defaultPeriodUnit: defaultQueryPeriodUnit
        ) else {
            return false
        }

        switch result {
        case let .clarification(message):
            clarificationSuggestions = []
            recoverySuggestions = []
            lastClarificationReasons = []
            activeClarificationContext = nil
            appendAnswer(
                HomeAnswer(
                    queryID: UUID(),
                    kind: .message,
                    userPrompt: prompt,
                    title: "What If needs one concrete change",
                    subtitle: message,
                    rows: []
                )
            )
            return true
        case let .request(request):
            let built = whatIfAnswerBuilder.makeAnswer(
                queryID: UUID(),
                userPrompt: prompt,
                request: request,
                categories: categories,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                incomes: incomes
            )
            let styled = personaFormatter.styledAnswer(
                from: built.rawAnswer,
                userPrompt: prompt,
                personaID: selectedPersonaID,
                seedContext: personaSeedContext(for: built.primaryQuery),
                footerContext: personaFooterContext(for: built.footerQueries),
                echoContext: personaEchoContext(for: built.primaryQuery),
                visibleProvenance: visibleProvenance(for: built.footerQueries)
            )

            pendingWhatIfContext = built.context
            pendingWhatIfCategoryMappingContext = nil
            appendAnswer(styled)
            return true
        }
    }

    private func resolvePendingWhatIfFollowUp(with prompt: String) -> Bool {
        if let pendingWhatIfCategoryMappingContext {
            return resolvePendingWhatIfCategoryMapping(prompt, context: pendingWhatIfCategoryMappingContext)
        }

        guard let pendingWhatIfContext else { return false }
        let normalized = normalizedPrompt(prompt)
        let wantsPlannerHandoff = [
            "open this in what if",
            "open this in planner",
            "open in what if",
            "open in planner",
            "put this in what if",
            "put this in planner",
            "add this to what if",
            "use this in what if",
            "save this to what if",
            "move this to what if"
        ].contains(where: normalized.contains)

        guard wantsPlannerHandoff else { return false }

        if pendingWhatIfContext.requiresExactCadenceSelection {
            appendAnswer(
                HomeAnswer(
                    queryID: UUID(),
                    kind: .message,
                    userPrompt: prompt,
                    title: "Pick one cadence first",
                    subtitle: "I can open the planner after you tell me which interval to use.",
                    rows: []
                )
            )
            return true
        }

        if let draft = pendingWhatIfContext.directPlannerDraft {
            onOpenWhatIfPlanner(draft)
            appendAnswer(
                HomeAnswer(
                    queryID: UUID(),
                    kind: .message,
                    userPrompt: prompt,
                    title: "Opening What If planner",
                    subtitle: "I carried this hypothetical over as a temporary draft. Nothing is saved until you save it there.",
                    rows: []
                )
            )
            return true
        }

        if pendingWhatIfContext.requiresPlannerCategoryName,
           pendingWhatIfContext.exactAdditionalSpendForPlanner != nil {
            pendingWhatIfCategoryMappingContext = pendingWhatIfContext
            appendAnswer(
                HomeAnswer(
                    queryID: UUID(),
                    kind: .message,
                    userPrompt: prompt,
                    title: "Which category should I map this to?",
                    subtitle: "The planner is category-based, so tell me the category you want this merchant scenario applied to.",
                    rows: []
                )
            )
            return true
        }

        return false
    }

    private func resolvePendingWhatIfCategoryMapping(
        _ prompt: String,
        context: HomeAssistantWhatIfContext
    ) -> Bool {
        guard let matchedCategory = aliasTarget(in: prompt, entityType: .category)
                ?? entityMatcher.bestCategoryMatch(in: prompt, categories: categories)
        else {
            appendAnswer(
                HomeAnswer(
                    queryID: UUID(),
                    kind: .message,
                    userPrompt: prompt,
                    title: "I still need the category",
                    subtitle: "Tell me which category should absorb this hypothetical so I can open the planner with the right draft.",
                    rows: []
                )
            )
            return true
        }

        guard let additionalSpend = context.exactAdditionalSpendForPlanner,
              let category = categories.first(where: { $0.name == matchedCategory })
        else {
            return false
        }

        let baselineByCategoryID = whatIfBaselineSpendByCategoryID(in: context.resolvedDateRange)
        let projectedCategorySpend = baselineByCategoryID[category.id, default: 0] + additionalSpend
        let draft = HomeAssistantWhatIfPlannerDraft(
            categoryScenarioSpendByID: [category.id: CurrencyFormatter.roundedToCurrency(projectedCategorySpend)],
            plannedIncomeOverride: nil,
            actualIncomeOverride: nil,
            sourcePrompt: context.request.targetName ?? matchedCategory,
            summary: "Mapped Marina What If to \(matchedCategory)."
        )

        pendingWhatIfCategoryMappingContext = nil
        pendingWhatIfContext = context
        onOpenWhatIfPlanner(draft)
        appendAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                userPrompt: prompt,
                title: "Opening What If planner",
                subtitle: "I mapped this hypothetical into \(matchedCategory) as a temporary draft. Nothing is saved until you save it there.",
                rows: []
            )
        )
        return true
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

        if MarinaCapabilityGuide.matchesPrompt(prompt) {
            let raw = MarinaCapabilityGuide.makeAnswer(for: prompt)
            let styled = personaFormatter.styledAnswer(
                from: raw,
                userPrompt: prompt,
                personaID: selectedPersonaID
            )
            appendAnswer(styled)
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
        rawPrompt: String,
        source: HomeAssistantPlanResolutionSource? = nil
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
    
    private func handleAddExpenseCommand(_ command: HomeAssistantCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .expense, command: command))
    }
    
    private func handleAddIncomeCommand(_ command: HomeAssistantCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .income, command: command))
    }
    
    private func handleAddBudgetCommand(_ command: HomeAssistantCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .budget, command: command))
    }
    
    private func handleAddCardCommand(_ command: HomeAssistantCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .card, command: command))
    }
    
    private func handleAddPresetCommand(_ command: HomeAssistantCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .preset, command: command))
    }
    
    private func handleAddCategoryCommand(_ command: HomeAssistantCommandPlan) {
        appendInlineCreateForm(makeInlineCreateForm(for: .category, command: command))
    }

    private func handleEditCategoryCommand(_ command: HomeAssistantCommandPlan) {
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

    private func handleDeleteCategoryCommand(_ command: HomeAssistantCommandPlan) {
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

    private func handleEditPresetCommand(_ command: HomeAssistantCommandPlan) {
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

    private func handleDeletePresetCommand(_ command: HomeAssistantCommandPlan) {
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

    private func handleEditBudgetCommand(_ command: HomeAssistantCommandPlan) {
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

    private func handleDeleteBudgetCommand(_ command: HomeAssistantCommandPlan) {
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

    private func handleAddPlannedExpenseCommand(_ command: HomeAssistantCommandPlan) {
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

    private func handleEditPlannedExpenseCommand(_ command: HomeAssistantCommandPlan) {
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

    private func handleDeletePlannedExpenseCommand(_ command: HomeAssistantCommandPlan) {
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
    
    private func handleEditCardCommand(_ command: HomeAssistantCommandPlan) {
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
    
    private func handleDeleteCardCommand(_ command: HomeAssistantCommandPlan) {
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
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
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
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
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

    private func executeAddPlannedExpense(_ command: HomeAssistantCommandPlan) {
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
    
    private func executeCardEdit(_ card: Card, using command: HomeAssistantCommandPlan) {
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

    private func executeCategoryEdit(_ category: Category, using command: HomeAssistantCommandPlan) {
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

    private func executePresetEdit(_ preset: Preset, using command: HomeAssistantCommandPlan) {
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

    private func executeBudgetEdit(_ budget: Budget, using command: HomeAssistantCommandPlan) {
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

    private func executePlannedExpenseEdit(_ expense: PlannedExpense, using command: HomeAssistantCommandPlan) {
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
    
    private func presentCardSelectionPrompt(for command: HomeAssistantCommandPlan) {
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
    
    private func matchedCards(for command: HomeAssistantCommandPlan) -> [Card] {
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

    private func matchedCategories(for command: HomeAssistantCommandPlan) -> [Category] {
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

    private func matchedPresets(for command: HomeAssistantCommandPlan) -> [Preset] {
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

    private func matchedBudgets(for command: HomeAssistantCommandPlan) -> [Budget] {
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
    
    private func shortDate(_ date: Date) -> String {
        AppDateFormat.shortDate(date)
    }
    
    private func resolvedPlan(
        for prompt: String
    ) -> (plan: HomeQueryPlan, source: HomeAssistantPlanResolutionSource)? {
        if let plan = parser.parsePlan(prompt, defaultPeriodUnit: defaultQueryPeriodUnit) {
            let fallbackPlan = enrichPlanWithEntities(plan, rawPrompt: prompt)
            let signals = parsedSignals(for: prompt, fallbackPlan: fallbackPlan)
            let resolvedPlan = intentBuilder.buildPlan(from: signals, fallbackPlan: fallbackPlan)
            return (resolvedPlan, .parser)
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
        let comparisonDetected = detectComparison(prompt)
        let explicitComparisonRequested = appearsToRequestExplicitComparisonDates(in: normalized)
        let signalTarget = extractedSignalTarget(for: prompt)
        let signalTargetSource = extractedSignalTargetSource(for: prompt)
        let signalScope: String = {
            guard let signalTarget else { return "global" }
            switch signalTargetSource {
            case .matchedEntity?:
                if entityMatcher.bestCategoryMatch(in: prompt, categories: categories)?.caseInsensitiveCompare(signalTarget) == .orderedSame
                    || aliasTarget(in: prompt, entityType: .category)?.caseInsensitiveCompare(signalTarget) == .orderedSame {
                    return "category"
                }
                if entityMatcher.bestCardMatch(in: prompt, cards: cards)?.caseInsensitiveCompare(signalTarget) == .orderedSame
                    || aliasTarget(in: prompt, entityType: .card)?.caseInsensitiveCompare(signalTarget) == .orderedSame {
                    return "card"
                }
                if entityMatcher.bestIncomeSourceMatch(in: prompt, incomes: incomes)?.caseInsensitiveCompare(signalTarget) == .orderedSame
                    || aliasTarget(in: prompt, entityType: .incomeSource)?.caseInsensitiveCompare(signalTarget) == .orderedSame {
                    return "incomeSource"
                }
                return "matchedEntity"
            case .merchantPhrase?:
                return "merchant"
            case .weakMerchantPhrase?:
                return "merchantCandidate"
            case .inferredComparisonText?:
                return "unresolved"
            case nil:
                return "global"
            }
        }()
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
                HomeAnswerRow(title: "Comparison Date Range", value: debugDateRangeLabel(plan.comparisonDateRange)),
                HomeAnswerRow(title: "Comparison Detected", value: comparisonDetected ? "Yes" : "No"),
                HomeAnswerRow(title: "Explicit Comparison Dates", value: explicitComparisonRequested ? "Yes" : "No"),
                HomeAnswerRow(title: "Signal Target", value: signalTarget ?? "None"),
                HomeAnswerRow(title: "Signal Target Source", value: signalTargetSource.map(debugSignalTargetSource) ?? "None"),
                HomeAnswerRow(title: "Resolved Comparison Scope", value: signalScope),
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
        return "\(AppDateFormat.shortDate(range.startDate)) - \(AppDateFormat.shortDate(range.endDate))"
    }

    private func debugSignalTargetSource(_ source: HomeAssistantSignalTargetSource) -> String {
        switch source {
        case .matchedEntity:
            return "matchedEntity"
        case .merchantPhrase:
            return "merchantPhrase"
        case .weakMerchantPhrase:
            return "weakMerchantPhrase"
        case .inferredComparisonText:
            return "inferredComparisonText"
        }
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
            attachment: answer.attachment,
            explanation: answer.explanation,
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
        recoverySuggestions = []
        lastClarificationReasons = []
        activeClarificationContext = nil
        pendingWhatIfContext = nil
        pendingWhatIfCategoryMappingContext = nil
        clearMutationPendingState()
        conversationStore.saveAnswers([], workspaceID: workspace.id)
    }
    
    private func handleResolvedPlan(
        _ plan: HomeQueryPlan,
        rawPrompt: String,
        allowsBroadBundle: Bool,
        source: HomeAssistantPlanResolutionSource,
        overrideClarificationPlan: HomeAssistantClarificationPlan? = nil,
        overrideResolution: HomeAssistantEntityResolution? = nil
    ) {
        let resolution = overrideResolution ?? resolveEntityResolution(for: plan, rawPrompt: rawPrompt)
        let reconciliation = planReconciler.reconcile(plan: plan, resolution: resolution)
        let resolvedPlan = reconciliation.plan
        let routedRequest = requestRoutingResolver.resolve(prompt: rawPrompt, basePlan: resolvedPlan)
        let routedPlan = routedRequest.plan
        let enrichedResolution = resolutionWithRecoverySuggestions(
            resolution,
            basePlan: routedPlan,
            rawPrompt: rawPrompt,
            explanation: reconciliation.explanation
        )
        let requiredClarification = requiredFieldClarificationPlan(for: routedPlan, rawPrompt: rawPrompt)
        let ambiguityClarification = ambiguityClarificationPlan(for: routedPlan, resolution: enrichedResolution)
        let clarificationPlan = mergeClarificationPlans(
            overrideClarificationPlan ?? requiredClarification,
            ambiguityClarification
        )

        if let requiredClarification, requiredClarification.shouldRunBestEffort == false {
            recordTelemetry(
                for: rawPrompt,
                outcome: .clarification,
                source: source,
                plan: routedPlan,
                notes: "required_clarification"
            )
            presentClarificationTurn(
                clarificationPlan ?? requiredClarification,
                userPrompt: rawPrompt,
                context: clarificationContext(
                    for: routedPlan,
                    rawPrompt: rawPrompt,
                    resolution: enrichedResolution
                )
            )
            return
        }

        if enrichedResolution.isTieAmbiguity {
            recordTelemetry(
                for: rawPrompt,
                outcome: .clarification,
                source: source,
                plan: routedPlan,
                notes: "tie_band_ambiguity"
            )
            presentClarificationTurn(
                clarificationPlan ?? HomeAssistantClarificationPlan(
                    reasons: [.lowConfidenceLanguage],
                    subtitle: "I found a few close matches. Pick one to continue.",
                    suggestions: [],
                    shouldRunBestEffort: false
                ),
                userPrompt: rawPrompt,
                context: clarificationContext(
                    for: routedPlan,
                    rawPrompt: rawPrompt,
                    resolution: enrichedResolution
                )
            )
            return
        }

        if enrichedResolution.confidence == .low {
            recordTelemetry(
                for: rawPrompt,
                outcome: .clarification,
                source: source,
                plan: routedPlan,
                notes: "recovery_only"
            )
            presentRecoveryTurn(
                enrichedResolution.recoverySuggestions,
                userPrompt: rawPrompt,
                subtitle: "I couldn’t lock onto a safe match, so here are the best fallback paths."
            )
            return
        }

        if allowsBroadBundle && shouldRunBroadOverviewBundle(for: rawPrompt, plan: routedPlan) {
            runBroadOverviewBundle(userPrompt: rawPrompt, basePlan: routedPlan)
            recordTelemetry(
                for: rawPrompt,
                outcome: .resolved,
                source: source,
                plan: routedPlan,
                notes: clarificationPlan == nil ? "broad_bundle" : "broad_bundle_with_clarification_chips"
            )
        } else {
            runRoutedRequest(
                routedRequest,
                userPrompt: rawPrompt,
                explanation: reconciliation.explanation,
                executedPlan: routedPlan
            )
            recordTelemetry(
                for: rawPrompt,
                outcome: .resolved,
                source: source,
                plan: routedPlan,
                notes: routedRequest.shape == .single
                    ? (clarificationPlan == nil ? nil : "resolved_with_clarification_chips")
                    : bundledRoutingTelemetryNote(
                        for: routedRequest.shape,
                        hasClarificationPlan: clarificationPlan != nil
                    )
            )
        }

        if let clarificationPlan {
            presentClarificationTurn(
                clarificationPlan,
                userPrompt: nil,
                context: clarificationContext(
                    for: routedPlan,
                    rawPrompt: rawPrompt,
                    resolution: enrichedResolution
                )
            )
        }
    }

    private func resolveEntityResolution(
        for plan: HomeQueryPlan,
        rawPrompt: String,
        rejectedCandidateNames: [String] = []
    ) -> HomeAssistantEntityResolution {
        entityResolutionResolver.resolve(
            input: HomeAssistantEntityResolutionInput(
                prompt: rawPrompt,
                targetPhrase: plan.targetName ?? extractedSignalTarget(for: rawPrompt) ?? rawPrompt,
                categories: categories.map(\.name).sorted(),
                cards: cards.map(\.name).sorted(),
                merchants: merchantCandidateNames(),
                presets: presets.map(\.title).sorted(),
                budgets: budgets.map(\.name).sorted(),
                incomeSources: Array(Set(incomes.map(\.source))).sorted(),
                aliasRules: assistantAliasRules,
                rejectedCandidateNames: rejectedCandidateNames
            )
        )
    }

    @MainActor
    private func merchantCandidateNames() -> [String] {
        Array(
            Set(
                variableExpenses
                    .map(\.descriptionText)
                    .map(MerchantNormalizer.displayName)
                    .filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
            )
        ).sorted()
    }

    private func resolutionWithRecoverySuggestions(
        _ resolution: HomeAssistantEntityResolution,
        basePlan: HomeQueryPlan,
        rawPrompt: String,
        explanation: String?
    ) -> HomeAssistantEntityResolution {
        let recovery = buildRecoverySuggestions(from: resolution, basePlan: basePlan, rawPrompt: rawPrompt)
        return HomeAssistantEntityResolution(
            resolvedPhrase: resolution.resolvedPhrase,
            bestMatch: resolution.bestMatch,
            ambiguityCandidates: resolution.ambiguityCandidates,
            rankedCandidates: resolution.rankedCandidates,
            confidence: resolution.confidence,
            originalCandidates: resolution.originalCandidates,
            rejectedCandidateNames: resolution.rejectedCandidateNames,
            recoverySuggestions: recovery,
            explanation: explanation,
            isTieAmbiguity: resolution.isTieAmbiguity
        )
    }

    private func requiredFieldClarificationPlan(
        for basePlan: HomeQueryPlan,
        rawPrompt: String
    ) -> HomeAssistantClarificationPlan? {
        guard let derivedPlan = clarificationPlan(for: basePlan, rawPrompt: rawPrompt) else {
            return nil
        }

        let allowedReasons: Set<HomeAssistantClarificationReason> = [
            .missingDate,
            .missingComparisonDate,
            .missingCategoryTarget,
            .missingCardTarget,
            .missingIncomeSourceTarget,
            .missingMerchantTarget
        ]
        let filteredReasons = derivedPlan.reasons.filter { allowedReasons.contains($0) }
        guard filteredReasons.isEmpty == false else { return nil }

        return HomeAssistantClarificationPlan(
            reasons: filteredReasons,
            subtitle: derivedPlan.subtitle,
            suggestions: clarificationSuggestions(
                for: basePlan,
                reasons: filteredReasons,
                normalizedPrompt: normalizedPrompt(rawPrompt)
            ),
            shouldRunBestEffort: derivedPlan.shouldRunBestEffort
        )
    }

    private func ambiguityClarificationPlan(
        for basePlan: HomeQueryPlan,
        resolution: HomeAssistantEntityResolution
    ) -> HomeAssistantClarificationPlan? {
        guard resolution.ambiguityCandidates.isEmpty == false else { return nil }

        let suggestions = resolution.ambiguityCandidates.prefix(4).map { match in
            suggestionForMatch(match, basePlan: basePlan)
        }

        return HomeAssistantClarificationPlan(
            reasons: [.lowConfidenceLanguage],
            subtitle: "I found a few close matches. Pick one to continue.",
            suggestions: suggestions,
            shouldRunBestEffort: resolution.isTieAmbiguity == false
        )
    }

    private func mergeClarificationPlans(
        _ lhs: HomeAssistantClarificationPlan?,
        _ rhs: HomeAssistantClarificationPlan?
    ) -> HomeAssistantClarificationPlan? {
        switch (lhs, rhs) {
        case (nil, nil):
            return nil
        case let (plan?, nil), let (nil, plan?):
            return plan
        case let (left?, right?):
            let reasons = uniqueClarificationReasons(left.reasons + right.reasons)
            var suggestions: [HomeAssistantSuggestion] = []
            var seenTitles: Set<String> = []
            for suggestion in left.suggestions + right.suggestions {
                if seenTitles.insert(suggestion.title).inserted {
                    suggestions.append(suggestion)
                }
            }
            return HomeAssistantClarificationPlan(
                reasons: reasons,
                subtitle: right.subtitle,
                suggestions: Array(suggestions.prefix(4)),
                shouldRunBestEffort: left.shouldRunBestEffort || right.shouldRunBestEffort
            )
        }
    }

    private func clarificationContext(
        for plan: HomeQueryPlan,
        rawPrompt: String,
        resolution: HomeAssistantEntityResolution
    ) -> HomeAssistantClarificationContext? {
        guard resolution.originalCandidates.isEmpty == false else { return nil }
        return HomeAssistantClarificationContext(
            originalCandidates: resolution.originalCandidates,
            activeCandidates: resolution.ambiguityCandidates.isEmpty ? resolution.originalCandidates : resolution.ambiguityCandidates,
            rejectedCandidateNames: resolution.rejectedCandidateNames,
            currentBestMatch: resolution.bestMatch,
            originalPrompt: rawPrompt,
            basePlan: plan,
            resolution: resolution
        )
    }

    private func suggestionForMatch(
        _ match: HomeAssistantEntityMatch,
        basePlan: HomeQueryPlan
    ) -> HomeAssistantSuggestion {
        let resolution = HomeAssistantEntityResolution(
            resolvedPhrase: match.name,
            bestMatch: match,
            rankedCandidates: [match],
            confidence: match.confidence
        )
        let reconciled = planReconciler.reconcile(plan: basePlan, resolution: resolution).plan
        return HomeAssistantSuggestion(
            title: match.name,
            query: reconciled.query,
            confidenceScore: match.score,
            reasoning: "Matched as \(match.entityType.rawValue) via \(match.source.rawValue)."
        )
    }

    private func buildRecoverySuggestions(
        from resolution: HomeAssistantEntityResolution,
        basePlan: HomeQueryPlan,
        rawPrompt: String
    ) -> [HomeAssistantRecoverySuggestion] {
        var suggestions: [HomeAssistantRecoverySuggestion] = resolution.rankedCandidates.prefix(3).map { match in
            HomeAssistantRecoverySuggestion(
                suggestion: suggestionForMatch(match, basePlan: basePlan),
                confidenceScore: match.score,
                reasoning: "Likely \(match.entityType.rawValue) match from \(match.source.rawValue)."
            )
        }

        let broadFallback = HomeAssistantRecoverySuggestion(
            suggestion: HomeAssistantSuggestion(
                title: "Show all results for this period",
                query: basePlan.updating(
                    metric: basePlan.metric == .monthComparison ? .monthComparison : .spendTotal,
                    targetName: .some(nil),
                    targetTypeRaw: .some(nil)
                ).query,
                confidenceScore: 0.1,
                reasoning: "Broad fallback across the current period."
            ),
            confidenceScore: 0.1,
            reasoning: "Broad fallback across the current period."
        )

        if suggestions.allSatisfy({ $0.confidenceScore < 0.45 }) {
            suggestions.append(broadFallback)
        }

        return suggestions.sorted { lhs, rhs in
            if lhs.confidenceScore == rhs.confidenceScore {
                return lhs.suggestion.title.localizedCaseInsensitiveCompare(rhs.suggestion.title) == .orderedAscending
            }
            return lhs.confidenceScore > rhs.confidenceScore
        }
    }

    private func presentRecoveryTurn(
        _ suggestions: [HomeAssistantRecoverySuggestion],
        userPrompt: String?,
        subtitle: String
    ) {
        clarificationSuggestions = []
        recoverySuggestions = suggestions
        lastClarificationReasons = []
        activeClarificationContext = nil

        appendAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                userPrompt: userPrompt,
                title: "Try one of these",
                subtitle: subtitle,
                rows: suggestions.prefix(3).map {
                    HomeAnswerRow(
                        title: $0.suggestion.title,
                        value: $0.reasoning
                    )
                }
            )
        )
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
            && reasons.contains(.missingComparisonDate) == false
            && reasons.contains(.missingMerchantTarget) == false

        return HomeAssistantClarificationPlan(
            reasons: reasons,
            subtitle: subtitle,
            suggestions: suggestions,
            shouldRunBestEffort: shouldRunBestEffort
        )
    }
    
    private func presentClarificationTurn(
        _ clarificationPlan: HomeAssistantClarificationPlan,
        userPrompt: String?,
        context: HomeAssistantClarificationContext? = nil
    ) {
        clarificationSuggestions = clarificationPlan.suggestions
        recoverySuggestions = []
        lastClarificationReasons = clarificationPlan.reasons
        activeClarificationContext = context
        
        let clarificationAnswer = HomeAnswer(
            queryID: UUID(),
            kind: .message,
            userPrompt: userPrompt,
            title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
            subtitle: clarificationPlan.subtitle,
            primaryValue: nil,
            rows: []
        )
        
        appendAnswer(clarificationAnswer)
    }

    private func handleClarificationRejection(_ prompt: String) -> Bool {
        guard let context = activeClarificationContext else { return false }
        let normalized = normalizedPrompt(prompt)
        guard ["no", "n", "nope", "nah"].contains(normalized) else { return false }

        let rejectedName = context.currentBestMatch?.name ?? context.activeCandidates.first?.name
        let rejectedNames = context.rejectedCandidateNames + (rejectedName.map { [$0] } ?? [])
        let resolution = resolveEntityResolution(
            for: context.basePlan,
            rawPrompt: context.originalPrompt,
            rejectedCandidateNames: rejectedNames
        )

        if resolution.rankedCandidates.isEmpty {
            let enrichedResolution = resolutionWithRecoverySuggestions(
                resolution,
                basePlan: context.basePlan,
                rawPrompt: context.originalPrompt,
                explanation: "Using recovery options after rejection"
            )
            presentRecoveryTurn(
                enrichedResolution.recoverySuggestions,
                userPrompt: prompt,
                subtitle: "Okay, I dropped that option. Here are the next best paths."
            )
            return true
        }

        handleResolvedPlan(
            context.basePlan,
            rawPrompt: context.originalPrompt,
            allowsBroadBundle: false,
            source: .contextual,
            overrideResolution: resolution
        )
        return true
    }
    
    private func clarificationReasons(
        for plan: HomeQueryPlan,
        normalizedPrompt: String
    ) -> [HomeAssistantClarificationReason] {
        var reasons: [HomeAssistantClarificationReason] = []
        
        if plan.confidenceBand == .low {
            reasons.append(.lowConfidenceLanguage)
        }

        if plan.comparisonDateRange == nil
            && appearsToRequestExplicitComparisonDates(in: normalizedPrompt)
        {
            reasons.append(.missingComparisonDate)
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
            } else if requiresMerchantTarget(plan.metric) {
                reasons.append(.missingMerchantTarget)
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

        if reasons.contains(.missingComparisonDate) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Compare this month vs last month",
                    query: HomeQuery(
                        intent: plan.metric.intent,
                        dateRange: monthRange(containing: now),
                        resultLimit: plan.resultLimit,
                        targetName: plan.targetName,
                        periodUnit: plan.periodUnit
                    )
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Use this month",
                    query: queryFromPlan(plan, overridingDateRange: monthRange(containing: now))
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

        if reasons.contains(.missingMerchantTarget) {
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Top merchants",
                    query: HomeQuery(
                        intent: .topMerchantsThisMonth,
                        dateRange: plan.dateRange ?? monthRange(containing: now),
                        resultLimit: 3
                    )
                )
            )
            suggestions.append(
                HomeAssistantSuggestion(
                    title: "Largest recent expenses",
                    query: HomeQuery(
                        intent: .largestRecentTransactions,
                        dateRange: plan.dateRange ?? monthRange(containing: now),
                        resultLimit: 5
                    )
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
            comparisonDateRange: plan.comparisonDateRange,
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

    @MainActor
    private func interpretPrompt(_ prompt: String) async {
        let interpreted = await languageRouter.interpret(
            prompt: prompt,
            context: makeMarinaRouterContext(),
            heuristicFallback: {
                heuristicInterpretedRequest(for: prompt)
            }
        )

        handleInterpretedRequest(interpreted, rawPrompt: prompt)
    }

    private func heuristicInterpretedRequest(for prompt: String) -> MarinaInterpretedRequest {
        if let command = commandParser.parse(prompt, defaultPeriodUnit: defaultQueryPeriodUnit) {
            return .command(command, source: .parser)
        }

        if let resolved = resolvedPlan(for: prompt) {
            return .query(resolved.plan, source: resolved.source)
        }

        return .unresolved
    }

    @MainActor
    private func handleInterpretedRequest(
        _ interpreted: MarinaInterpretedRequest,
        rawPrompt: String
    ) {
        switch interpreted {
        case .query(let plan, let source):
            let effectivePlan = source == .model
                ? normalizedModelQueryPlan(plan, rawPrompt: rawPrompt)
                : plan
            handleResolvedPlan(
                effectivePlan,
                rawPrompt: rawPrompt,
                allowsBroadBundle: allowsBroadBundle(for: source),
                source: source
            )
        case .command(let command, let source):
            let effectiveCommand = source == .model
                ? normalizedModelCommandPlan(command, rawPrompt: rawPrompt)
                : command
            handleCommandPlan(effectiveCommand, rawPrompt: rawPrompt, source: source)
        case .clarification(let clarification, let source):
            handleMarinaClarification(
                clarification,
                rawPrompt: rawPrompt,
                source: source
            )
        case .unresolved:
            clarificationSuggestions = []
            recoverySuggestions = []
            lastClarificationReasons = []
            activeClarificationContext = nil
            recordTelemetry(
                for: rawPrompt,
                outcome: .unresolved,
                source: nil,
                plan: nil,
                notes: "no_plan_resolved"
            )
            appendAnswer(personaFormatter.unresolvedPromptAnswer(for: rawPrompt, personaID: selectedPersonaID))
        }
    }

    private func makeMarinaRouterContext() -> MarinaLanguageRouterContext {
        let mostRecentAnswerContext = sessionContext.recentAnswerContexts.last
        return MarinaLanguageRouterContext(
            workspaceName: workspace.name,
            defaultPeriodUnit: defaultQueryPeriodUnit,
            sessionContext: sessionContext,
            priorQueryContext: MarinaPriorQueryContext(
                lastQueryPlan: sessionContext.lastQueryPlan,
                lastMetric: sessionContext.lastMetric,
                lastTargetName: sessionContext.lastTargetName ?? mostRecentAnswerContext?.targetName,
                lastTargetType: mostRecentAnswerContext?.targetType,
                lastDateRange: sessionContext.lastDateRange,
                lastResultLimit: sessionContext.lastResultLimit,
                lastPeriodUnit: sessionContext.lastPeriodUnit
            ),
            cardNames: cards.map(\.name).sorted(),
            categoryNames: categories.map(\.name).sorted(),
            incomeSourceNames: Array(Set(incomes.map(\.source))).sorted(),
            presetTitles: presets.map(\.title).sorted(),
            budgetNames: budgets.map(\.name).sorted(),
            aliasSummaries: assistantAliasRules.map {
                MarinaAliasSummary(
                    entityTypeRaw: $0.entityType.rawValue,
                    aliasKey: $0.aliasKey,
                    targetValue: $0.targetValue
                )
            },
            now: Date()
        )
    }

    private func allowsBroadBundle(for source: HomeAssistantPlanResolutionSource) -> Bool {
        source == .parser || source == .model
    }

    private func normalizedModelQueryPlan(
        _ plan: HomeQueryPlan,
        rawPrompt: String
    ) -> HomeQueryPlan {
        plan.updating(
            targetName: .some(plan.targetName?.trimmingCharacters(in: .whitespacesAndNewlines)),
            targetTypeRaw: .some(plan.targetTypeRaw?.trimmingCharacters(in: .whitespacesAndNewlines))
        )
    }

    @MainActor
    private func canonicalizedModelTargetPlan(
        _ plan: HomeQueryPlan,
        rawPrompt: String
    ) -> HomeQueryPlan {
        guard let targetName = plan.targetName?.trimmingCharacters(in: .whitespacesAndNewlines),
              targetName.isEmpty == false else {
            return plan
        }

        switch plan.metric {
        case .cardSpendTotal, .cardVariableSpendingHabits, .cardMonthComparison, .cardSnapshotSummary, .nextPlannedExpense, .spendTrendsSummary, .topCardChanges:
            let canonical = aliasTarget(in: targetName, entityType: .card)
                ?? entityMatcher.bestCardMatch(in: targetName, cards: cards)
                ?? aliasTarget(in: rawPrompt, entityType: .card)
                ?? entityMatcher.bestCardMatch(in: rawPrompt, cards: cards)
            return HomeQueryPlan(
                metric: plan.metric,
                dateRange: plan.dateRange,
                comparisonDateRange: plan.comparisonDateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: canonical == nil ? plan.confidenceBand : .high,
                targetName: canonical ?? plan.targetName,
                periodUnit: plan.periodUnit
            )
        case .incomeAverageActual, .incomeSourceShare, .incomeSourceShareTrend, .incomeSourceMonthComparison:
            let canonical = aliasTarget(in: targetName, entityType: .incomeSource)
                ?? entityMatcher.bestIncomeSourceMatch(in: targetName, incomes: incomes)
                ?? aliasTarget(in: rawPrompt, entityType: .incomeSource)
                ?? entityMatcher.bestIncomeSourceMatch(in: rawPrompt, incomes: incomes)
            return HomeQueryPlan(
                metric: plan.metric,
                dateRange: plan.dateRange,
                comparisonDateRange: plan.comparisonDateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: canonical == nil ? plan.confidenceBand : .high,
                targetName: canonical ?? plan.targetName,
                periodUnit: plan.periodUnit
            )
        case .categorySpendTotal, .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance, .categoryMonthComparison, .presetCategorySpend:
            let canonical = aliasTarget(in: targetName, entityType: .category)
                ?? entityMatcher.bestCategoryMatch(in: targetName, categories: categories)
                ?? aliasTarget(in: rawPrompt, entityType: .category)
                ?? entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories)
            return HomeQueryPlan(
                metric: plan.metric,
                dateRange: plan.dateRange,
                comparisonDateRange: plan.comparisonDateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: canonical == nil ? plan.confidenceBand : .high,
                targetName: canonical ?? plan.targetName,
                periodUnit: plan.periodUnit
            )
        case .merchantSpendTotal, .merchantSpendSummary, .merchantMonthComparison:
            let merchant = MerchantNormalizer.displayName(targetName)
            return HomeQueryPlan(
                metric: plan.metric,
                dateRange: plan.dateRange,
                comparisonDateRange: plan.comparisonDateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: plan.confidenceBand,
                targetName: merchant,
                periodUnit: plan.periodUnit
            )
        case .overview, .spendTotal, .topCategories, .monthComparison, .largestTransactions, .spendAveragePerPeriod, .savingsStatus, .savingsAverageRecentPeriods, .presetDueSoon, .presetHighestCost, .presetTopCategory, .safeSpendToday, .forecastSavings, .topMerchants, .topCategoryChanges:
            return plan
        }
    }

    private func normalizedModelCommandPlan(
        _ command: HomeAssistantCommandPlan,
        rawPrompt: String
    ) -> HomeAssistantCommandPlan {
        command.updating(
            cardName: normalizedModelCommandCardName(command.cardName, rawPrompt: rawPrompt),
            categoryName: normalizedModelCommandCategoryName(command.categoryName, rawPrompt: rawPrompt),
            entityName: normalizedModelCommandEntityName(command.entityName, intent: command.intent, rawPrompt: rawPrompt),
            updatedEntityName: command.updatedEntityName?.trimmingCharacters(in: .whitespacesAndNewlines),
            isPlannedIncome: command.isPlannedIncome
        )
    }

    private func normalizedModelCommandCardName(_ rawValue: String?, rawPrompt: String) -> String? {
        if let rawValue,
           let canonical = aliasTarget(in: rawValue, entityType: .card)
            ?? entityMatcher.bestCardMatch(in: rawValue, cards: cards) {
            return canonical
        }

        return aliasTarget(in: rawPrompt, entityType: .card)
            ?? entityMatcher.bestCardMatch(in: rawPrompt, cards: cards)
            ?? rawValue
    }

    private func normalizedModelCommandCategoryName(_ rawValue: String?, rawPrompt: String) -> String? {
        if let rawValue,
           let canonical = aliasTarget(in: rawValue, entityType: .category)
            ?? entityMatcher.bestCategoryMatch(in: rawValue, categories: categories) {
            return canonical
        }

        return aliasTarget(in: rawPrompt, entityType: .category)
            ?? entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories)
            ?? rawValue
    }

    private func normalizedModelCommandEntityName(
        _ rawValue: String?,
        intent: HomeAssistantCommandIntent,
        rawPrompt: String
    ) -> String? {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, trimmed.isEmpty == false else {
            return entityNameFromPrompt(for: intent, rawPrompt: rawPrompt)
        }

        return entityNameFromString(trimmed, for: intent) ?? entityNameFromPrompt(for: intent, rawPrompt: rawPrompt) ?? trimmed
    }

    private func entityNameFromPrompt(
        for intent: HomeAssistantCommandIntent,
        rawPrompt: String
    ) -> String? {
        let command = commandParser.parse(rawPrompt, defaultPeriodUnit: defaultQueryPeriodUnit)
        return entityNameFromString(command?.entityName, for: intent) ?? command?.entityName
    }

    private func entityNameFromString(
        _ rawValue: String?,
        for intent: HomeAssistantCommandIntent
    ) -> String? {
        guard let rawValue else { return nil }

        switch intent {
        case .addCard, .editCard, .deleteCard:
            return aliasTarget(in: rawValue, entityType: .card)
                ?? entityMatcher.bestCardMatch(in: rawValue, cards: cards)
                ?? rawValue
        case .addCategory, .editCategory, .deleteCategory, .moveExpenseCategory:
            return aliasTarget(in: rawValue, entityType: .category)
                ?? entityMatcher.bestCategoryMatch(in: rawValue, categories: categories)
                ?? rawValue
        case .addPreset, .editPreset, .deletePreset:
            return aliasTarget(in: rawValue, entityType: .preset)
                ?? entityMatcher.bestPresetMatch(in: rawValue, presets: presets)
                ?? rawValue
        case .addBudget, .editBudget, .deleteBudget:
            return matchedBudgetName(in: rawValue) ?? rawValue
        case .addExpense, .editExpense, .deleteExpense, .deleteLastExpense:
            return rawValue
        case .addIncome, .editIncome, .deleteIncome, .deleteLastIncome, .markIncomeReceived:
            return entityMatcher.bestIncomeSourceMatch(in: rawValue, incomes: incomes) ?? rawValue
        case .addPlannedExpense, .editPlannedExpense, .deletePlannedExpense, .updatePlannedExpenseAmount:
            return rawValue
        }
    }

    private func matchedBudgetName(in rawValue: String) -> String? {
        let normalized = normalizedPrompt(rawValue)
        return budgets.first {
            normalizedPrompt($0.name) == normalized
        }?.name ?? budgets.first {
            normalizedPrompt($0.name).contains(normalized) || normalized.contains(normalizedPrompt($0.name))
        }?.name
    }

    @MainActor
    private func handleMarinaClarification(
        _ clarification: MarinaClarificationRequest,
        rawPrompt: String,
        source: HomeAssistantPlanResolutionSource?
    ) {
        if let commandPlan = clarification.commandPlan {
            let effectiveCommand = source == .model
                ? normalizedModelCommandPlan(commandPlan, rawPrompt: rawPrompt)
                : commandPlan
            handleCommandPlan(effectiveCommand, rawPrompt: rawPrompt, source: source)
            return
        }

        if let queryPlan = clarification.queryPlan {
            let effectiveSource = source ?? .model
            let effectivePlan = effectiveSource == .model
                ? normalizedModelQueryPlan(queryPlan, rawPrompt: rawPrompt)
                : queryPlan
            let customPlan = HomeAssistantClarificationPlan(
                reasons: clarification.reasons,
                subtitle: clarification.subtitle,
                suggestions: clarificationSuggestions(
                    for: effectivePlan,
                    reasons: clarification.reasons,
                    normalizedPrompt: normalizedPrompt(rawPrompt)
                ),
                shouldRunBestEffort: clarification.shouldRunBestEffort
            )
            recordTelemetry(
                for: rawPrompt,
                outcome: .clarification,
                source: effectiveSource,
                plan: effectivePlan,
                notes: "model_query_clarification"
            )
            presentClarificationTurn(
                customPlan,
                userPrompt: rawPrompt
            )
            return
        }

        let fallbackPlan = HomeAssistantClarificationPlan(
            reasons: clarification.reasons,
            subtitle: clarification.subtitle,
            suggestions: [],
            shouldRunBestEffort: false
        )
        recordTelemetry(
            for: rawPrompt,
            outcome: .clarification,
            source: source,
            plan: nil,
            notes: "model_clarification"
        )
        presentClarificationTurn(
            fallbackPlan,
            userPrompt: rawPrompt
        )
    }
    
    private func isDateExpected(for metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .presetHighestCost, .presetTopCategory, .presetCategorySpend:
            return false
        case .savingsAverageRecentPeriods, .incomeSourceShareTrend, .categorySpendShareTrend:
            return false
        case .overview, .spendTotal, .categorySpendTotal, .spendAveragePerPeriod, .topCategories, .monthComparison, .categoryMonthComparison, .cardMonthComparison, .incomeSourceMonthComparison, .merchantMonthComparison, .largestTransactions, .cardSpendTotal, .cardVariableSpendingHabits, .incomeAverageActual, .savingsStatus, .incomeSourceShare, .categorySpendShare, .presetDueSoon, .categoryPotentialSavings, .categoryReallocationGuidance, .safeSpendToday, .forecastSavings, .nextPlannedExpense, .spendTrendsSummary, .cardSnapshotSummary, .merchantSpendTotal, .merchantSpendSummary, .topMerchants, .topCategoryChanges, .topCardChanges:
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
        case .categorySpendTotal, .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance, .presetCategorySpend, .categoryMonthComparison:
            return true
        default:
            return false
        }
    }
    
    private func requiresCardTarget(_ metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .cardSpendTotal, .cardVariableSpendingHabits, .cardMonthComparison:
            return true
        default:
            return false
        }
    }
    
    private func requiresIncomeTarget(_ metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .incomeSourceShare, .incomeSourceShareTrend, .incomeSourceMonthComparison:
            return true
        default:
            return false
        }
    }

    private func requiresMerchantTarget(_ metric: HomeQueryMetric) -> Bool {
        switch metric {
        case .merchantSpendTotal, .merchantSpendSummary, .merchantMonthComparison:
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
        presentedAnswer: HomeAnswer,
        userPrompt: String?
    ) {
        let context = HomeAssistantAnswerContext(
            query: query,
            answerTitle: presentedAnswer.title,
            answerKind: rawAnswer.kind,
            userPrompt: userPrompt,
            targetName: query.targetName,
            targetType: targetType(for: query.intent.metric),
            rowTitles: Array(rawAnswer.rows.prefix(5).map(\.title)),
            rowValues: Array(rawAnswer.rows.prefix(5).map(\.value)),
            scenarioPercent: extractedPercentValue(from: rawAnswer.subtitle ?? userPrompt ?? ""),
            executedPlan: executedPlan,
            generatedAt: presentedAnswer.generatedAt
        )

        sessionContext.recentAnswerContexts.append(context)
        if sessionContext.recentAnswerContexts.count > 3 {
            sessionContext.recentAnswerContexts = Array(sessionContext.recentAnswerContexts.suffix(3))
        }
    }

    private func targetType(for metric: HomeQueryMetric) -> HomeAssistantAnswerTargetType? {
        switch metric {
        case .categorySpendTotal, .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance, .categoryMonthComparison:
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

    private func handleAnchoredFollowUpPrompt(_ rawPrompt: String) -> Bool {
        let decision = followUpAnchorResolver.resolve(
            prompt: rawPrompt,
            recentContexts: sessionContext.recentAnswerContexts
        )

        switch decision {
        case .none:
            return false
        case let .matched(context):
            guard let plan = anchoredFollowUpPlan(for: rawPrompt, context: context) else {
                return false
            }
            handleResolvedPlan(
                plan,
                rawPrompt: rawPrompt,
                allowsBroadBundle: false,
                source: .contextual
            )
            return true
        case let .ambiguous(contexts):
            presentAnchoredFollowUpClarification(contexts, userPrompt: rawPrompt)
            return true
        }
    }

    private func anchoredFollowUpPlan(
        for rawPrompt: String,
        context: HomeAssistantAnswerContext
    ) -> HomeQueryPlan? {
        let normalized = normalizedPrompt(rawPrompt)
        let parsedDateRange = parser.parseDateRange(rawPrompt, defaultPeriodUnit: defaultQueryPeriodUnit)
        let parsedComparisonRanges = extractedComparisonDateRanges(for: rawPrompt)
        let parsedLimit = parser.parseLimit(rawPrompt)

        var metric = context.query.intent.metric
        var targetName = resolvedAnchoredTargetName(for: rawPrompt, context: context) ?? context.targetName
        var confidenceBand: HomeQueryConfidenceBand = .high

        if context.query.intent.metric == .categoryReallocationGuidance,
           ["save", "savings", "cut", "reduce", "decrease"].contains(where: normalized.contains) {
            metric = .categoryPotentialSavings
        } else if context.query.intent.metric == .categoryPotentialSavings,
                  ["reallocate", "rebalance", "other categories", "increase"].contains(where: normalized.contains) {
            metric = .categoryReallocationGuidance
        }

        if targetName == nil {
            targetName = context.targetName
            confidenceBand = .medium
        }

        return HomeQueryPlan(
            metric: metric,
            dateRange: parsedComparisonRanges?.primary ?? parsedDateRange ?? context.query.dateRange,
            comparisonDateRange: parsedComparisonRanges?.comparison ?? context.query.comparisonDateRange,
            resultLimit: parsedLimit ?? context.query.resultLimit,
            confidenceBand: confidenceBand,
            targetName: targetName,
            periodUnit: context.query.periodUnit
        )
    }

    private func resolvedAnchoredTargetName(
        for rawPrompt: String,
        context: HomeAssistantAnswerContext
    ) -> String? {
        switch context.targetType {
        case .category:
            return aliasTarget(in: rawPrompt, entityType: .category)
                ?? entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories)
                ?? bestPartialCategoryMatch(in: rawPrompt, anchoredTarget: context.targetName)
        case .card:
            return aliasTarget(in: rawPrompt, entityType: .card)
                ?? entityMatcher.bestCardMatch(in: rawPrompt, cards: cards)
        case .incomeSource:
            return aliasTarget(in: rawPrompt, entityType: .incomeSource)
                ?? entityMatcher.bestIncomeSourceMatch(in: rawPrompt, incomes: incomes)
        case .merchant:
            return extractedMerchantTarget(from: rawPrompt) ?? context.targetName
        case nil:
            return context.targetName
        }
    }

    private func bestPartialCategoryMatch(
        in rawPrompt: String,
        anchoredTarget: String?
    ) -> String? {
        guard let anchoredTarget else { return nil }
        let promptTokens = significantTokens(in: rawPrompt)
        let anchoredTokens = significantTokens(in: anchoredTarget)
        guard promptTokens.intersection(anchoredTokens).isEmpty == false else { return nil }
        return anchoredTarget
    }

    private func significantTokens(in text: String) -> Set<String> {
        let stopWords: Set<String> = [
            "the", "and", "for", "that", "this", "with", "from", "what", "about",
            "same", "will", "does", "mean", "your", "have", "been", "into", "than",
            "please", "month", "year", "save", "savings", "reduce", "increase"
        ]

        return Set(
            normalizedPrompt(text)
                .split(separator: " ")
                .map(String.init)
                .filter { $0.count > 2 && stopWords.contains($0) == false }
        )
    }

    private func presentAnchoredFollowUpClarification(
        _ contexts: [HomeAssistantAnswerContext],
        userPrompt: String
    ) {
        clarificationSuggestions = contexts.map { context in
            HomeAssistantSuggestion(
                title: context.targetName ?? context.answerTitle,
                query: context.query
            )
        }
        recoverySuggestions = []
        lastClarificationReasons = []
        activeClarificationContext = nil

        appendAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                userPrompt: userPrompt,
                title: String(localized: "assistant.quickClarification", defaultValue: "Quick clarification", comment: "Assistant clarification card title."),
                subtitle: "I found more than one recent answer this could refer to. Pick the one you want to continue from.",
                rows: contexts.prefix(2).map { context in
                    HomeAnswerRow(
                        title: context.targetName ?? context.answerTitle,
                        value: context.answerTitle
                    )
                }
            )
        )
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
        case .cardSpendTotal, .cardVariableSpendingHabits, .cardMonthComparison, .nextPlannedExpense, .spendTrendsSummary, .cardSnapshotSummary, .topCardChanges:
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
                comparisonDateRange: plan.comparisonDateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: card == nil ? plan.confidenceBand : .high,
                targetName: card,
                periodUnit: plan.periodUnit
            )
            
        case .incomeAverageActual, .incomeSourceShare, .incomeSourceShareTrend, .incomeSourceMonthComparison:
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
                comparisonDateRange: plan.comparisonDateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: source == nil ? plan.confidenceBand : .high,
                targetName: source,
                periodUnit: plan.periodUnit
            )
            
        case .categorySpendTotal, .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance, .categoryMonthComparison:
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
                comparisonDateRange: plan.comparisonDateRange,
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
                comparisonDateRange: plan.comparisonDateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: category == nil ? plan.confidenceBand : .high,
                targetName: category,
                periodUnit: plan.periodUnit
            )

        case .merchantSpendTotal, .merchantSpendSummary, .merchantMonthComparison:
            let merchant = extractedMerchantTarget(from: rawPrompt)
            return HomeQueryPlan(
                metric: plan.metric,
                dateRange: plan.dateRange,
                comparisonDateRange: plan.comparisonDateRange,
                resultLimit: plan.resultLimit,
                confidenceBand: merchant == nil ? plan.confidenceBand : .high,
                targetName: merchant,
                periodUnit: plan.periodUnit
            )
            
        case .overview, .spendTotal, .spendAveragePerPeriod, .topCategories, .monthComparison, .largestTransactions, .savingsStatus, .savingsAverageRecentPeriods, .presetDueSoon, .presetHighestCost, .presetTopCategory, .safeSpendToday, .forecastSavings, .topMerchants, .topCategoryChanges:
            return plan
        }
    }

    private func parsedSignals(
        for rawPrompt: String,
        fallbackPlan: HomeQueryPlan
    ) -> HomeAssistantParsedSignals {
        let comparisonRanges = extractedComparisonDateRanges(for: rawPrompt)
        let signalTarget = extractedSignalTarget(for: rawPrompt)
        let comparisonDetected = detectComparison(rawPrompt)
        let targetSource = extractedSignalTargetSource(for: rawPrompt)
        let signalMetric: HomeQueryMetric?
        if targetSource == .merchantPhrase, signalTarget != nil {
            if fallbackPlan.metric == .merchantSpendSummary {
                signalMetric = .merchantSpendSummary
            } else {
                signalMetric = comparisonDetected ? .merchantMonthComparison : .merchantSpendTotal
            }
        } else if targetSource == .weakMerchantPhrase, comparisonDetected {
            signalMetric = .merchantMonthComparison
        } else {
            signalMetric = nil
        }
        return HomeAssistantParsedSignals(
            metric: signalMetric,
            targetName: signalTarget,
            targetSource: targetSource,
            dateRange: comparisonRanges?.primary ?? extractedSignalDateRange(for: rawPrompt),
            comparisonDateRange: comparisonRanges?.comparison,
            comparisonDetected: comparisonDetected,
            rawPrompt: rawPrompt
        )
    }

    private func detectComparison(_ text: String) -> Bool {
        let keywords = ["compare", "vs", "versus", "difference", "changed"]
        let normalized = text.lowercased()
        return keywords.contains { normalized.contains($0) }
    }

    private func extractedSignalTarget(for rawPrompt: String) -> String? {
        let normalized = normalizedPrompt(rawPrompt)
        if hasExplicitGlobalComparisonScope(in: normalized)
            || normalized.contains("all cards")
            || normalized.contains("all categories")
            || normalized.contains("all sources")
            || normalized.contains("all income")
        {
            return nil
        }

        if let category = aliasTarget(in: rawPrompt, entityType: .category)
            ?? entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories)
        {
            return category
        }

        if let card = aliasTarget(in: rawPrompt, entityType: .card)
            ?? entityMatcher.bestCardMatch(in: rawPrompt, cards: cards)
        {
            return card
        }

        if let source = aliasTarget(in: rawPrompt, entityType: .incomeSource)
            ?? entityMatcher.bestIncomeSourceMatch(in: rawPrompt, incomes: incomes)
        {
            return source
        }

        if let merchant = extractedMerchantTarget(from: rawPrompt) {
            return merchant
        }

        if detectComparison(rawPrompt),
           appearsToRequestExplicitComparisonDates(in: normalized) == false,
           let unmatchedTarget = unmatchedComparisonTarget(in: rawPrompt)
        {
            return unmatchedTarget
        }

        return nil
    }

    private func categoryDisplayLabel(_ category: Category) -> String {
        "\(category.name) • \(category.hexColor)"
    }

    private func presetDisplayLabel(_ preset: Preset) -> String {
        "\(preset.title) • \(CurrencyFormatter.string(from: preset.plannedAmount)) • \(preset.frequency.displayName)"
    }

    private func budgetDisplayLabel(_ budget: Budget) -> String {
        "\(budget.name) • \(shortDate(budget.startDate)) – \(shortDate(budget.endDate))"
    }

    private func plannedExpenseDisplayLabel(_ expense: PlannedExpense) -> String {
        "\(expense.title) • \(CurrencyFormatter.string(from: expense.plannedAmount)) • \(shortDate(expense.expenseDate))"
    }

    private func extractedMerchantTarget(from rawPrompt: String) -> String? {
        let normalized = normalizedPrompt(rawPrompt)

        let explicitPatterns = [
            "\\bat\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\bwith\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\bto\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\bmerchant\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\bstore\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\bpayee\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\bvendor\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\b(?:spent|spend|spending|expense|expenses)\\s+on\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\b(?:spent|spend|spending|expense|expenses)\\s+with\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\b(?:how much\\s+)?went\\s+to\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\b(?:paid|pay)\\s+(?:to\\s+)?([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\bbuy\\s+from\\s+([a-z0-9 '&\\-\\.]+?)(?:\\s+(this|last|in|from|vs|versus|please|so|year|month|week|today|yesterday|for)\\b|$)",
            "\\b(?:summarize|summary of)\\s+(?:my\\s+)?([a-z0-9 '&\\-\\.]+?)\\s+(?:spend|spending|expense|expenses)\\b",
            "\\bcompare\\s+([a-z][a-z0-9 '&\\-\\.]*?)\\s+(?:spend|spending|expense|expenses)\\s+(?:from|between|vs|versus|this|last|in)\\b",
            "\\bcompare\\s+([a-z][a-z0-9 '&\\-\\.]*?)\\s+(?:from|between|vs|versus|this|last|in)\\b",
            "^([a-z][a-z0-9 '&\\-\\.]*?)\\s+(?:spend|spending|expense|expenses)\\s+(?:from|between|vs|versus|this|last|in)\\b"
        ]

        for pattern in explicitPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let searchRange = NSRange(normalized.startIndex..., in: normalized)
            guard let match = regex.firstMatch(in: normalized, options: [], range: searchRange),
                  let valueRange = Range(match.range(at: 1), in: normalized) else {
                continue
            }

            let candidate = String(normalized[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if merchantCandidateIsMeaningful(candidate),
               merchantCandidateConflictsWithKnownEntity(candidate) == false {
                return MerchantNormalizer.displayName(candidate)
            }
        }

        return nil
    }

    private func extractedSignalTargetSource(for rawPrompt: String) -> HomeAssistantSignalTargetSource? {
        let normalized = normalizedPrompt(rawPrompt)
        if hasExplicitGlobalComparisonScope(in: normalized) {
            return nil
        }

        if aliasTarget(in: rawPrompt, entityType: .category) != nil
            || entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories) != nil
            || aliasTarget(in: rawPrompt, entityType: .card) != nil
            || entityMatcher.bestCardMatch(in: rawPrompt, cards: cards) != nil
            || aliasTarget(in: rawPrompt, entityType: .incomeSource) != nil
            || entityMatcher.bestIncomeSourceMatch(in: rawPrompt, incomes: incomes) != nil
        {
            return .matchedEntity
        }

        if extractedMerchantTarget(from: rawPrompt) != nil {
            return .merchantPhrase
        }

        if hasWeakMerchantComparisonPrompt(in: rawPrompt) {
            return .weakMerchantPhrase
        }

        if detectComparison(rawPrompt),
           appearsToRequestExplicitComparisonDates(in: normalized) == false,
           unmatchedComparisonTarget(in: rawPrompt) != nil
        {
            return .inferredComparisonText
        }

        return nil
    }

    private func merchantCandidateIsMeaningful(_ candidate: String) -> Bool {
        let normalized = candidate
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { return false }

        let genericFillers: Set<String> = [
            "spend", "spent", "spending", "expense", "expenses",
            "amount", "total", "totals", "year", "month", "week",
            "today", "yesterday", "so far", "all categories", "all spending"
        ]
        return genericFillers.contains(normalized) == false
    }

    private func merchantCandidateConflictsWithKnownEntity(_ candidate: String) -> Bool {
        aliasTarget(in: candidate, entityType: .category) != nil
            || entityMatcher.bestCategoryMatch(in: candidate, categories: categories) != nil
            || aliasTarget(in: candidate, entityType: .card) != nil
            || entityMatcher.bestCardMatch(in: candidate, cards: cards) != nil
            || aliasTarget(in: candidate, entityType: .incomeSource) != nil
            || entityMatcher.bestIncomeSourceMatch(in: candidate, incomes: incomes) != nil
    }

    private func hasWeakMerchantComparisonPrompt(in rawPrompt: String) -> Bool {
        let normalized = normalizedPrompt(rawPrompt)
        guard detectComparison(rawPrompt) else { return false }
        guard hasExplicitGlobalComparisonScope(in: normalized) == false else { return false }
        guard extractedMerchantTarget(from: rawPrompt) == nil else { return false }
        guard aliasTarget(in: rawPrompt, entityType: .category) == nil,
              entityMatcher.bestCategoryMatch(in: rawPrompt, categories: categories) == nil,
              aliasTarget(in: rawPrompt, entityType: .card) == nil,
              entityMatcher.bestCardMatch(in: rawPrompt, cards: cards) == nil,
              aliasTarget(in: rawPrompt, entityType: .incomeSource) == nil,
              entityMatcher.bestIncomeSourceMatch(in: rawPrompt, incomes: incomes) == nil else {
            return false
        }

        let weakPatterns = [
            "\\bcompare\\s+(?:merchant|store)\\s+(?:spend|spending|expense|expenses)?\\s*(?:from|between|vs|versus|this|last|in)\\b",
            "\\bcompare\\s+[a-z][a-z0-9 '&\\-\\.]*\\s+(?:spend|spending|expense|expenses)\\s+(?:from|between|vs|versus|this|last|in)\\b"
        ]

        return weakPatterns.contains { pattern in
            normalized.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private func unmatchedComparisonTarget(in rawPrompt: String) -> String? {
        let normalized = normalizedPrompt(rawPrompt)
        guard detectComparison(rawPrompt) else { return nil }

        let candidate: String
        if let vsRange = normalized.range(of: " vs ") ?? normalized.range(of: " versus ") {
            candidate = String(normalized[..<vsRange.lowerBound])
        } else {
            candidate = normalized
        }

        let fillerPhrases = [
            "compare my ", "compare ", "this month", "last month",
            "spending", "spend", "income", "difference", "changed",
            "change", "month"
        ]

        let reduced = fillerPhrases.reduce(candidate) { partial, phrase in
            partial.replacingOccurrences(of: phrase, with: " ")
        }
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard reduced.isEmpty == false else { return nil }
        return reduced
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private func extractedSignalDateRange(for rawPrompt: String) -> HomeQueryDateRange? {
        parser.parseDateRange(rawPrompt, defaultPeriodUnit: defaultQueryPeriodUnit)
    }

    private func extractedComparisonDateRanges(
        for rawPrompt: String
    ) -> (primary: HomeQueryDateRange, comparison: HomeQueryDateRange)? {
        guard detectComparison(rawPrompt) else { return nil }
        let normalized = normalizedPrompt(rawPrompt)

        let candidatePairs: [(String, String)] = [
            capturedComparisonSnippets(
                normalizedPrompt: normalized,
                pattern: "\\bfrom\\s+(.+?)\\s+to\\s+(.+)$"
            ),
            capturedComparisonSnippets(
                normalizedPrompt: normalized,
                pattern: "\\bbetween\\s+(.+?)\\s+and\\s+(.+)$"
            ),
            capturedComparisonSnippets(
                normalizedPrompt: normalized,
                pattern: "\\bcompare\\s+(.+?)\\s+(?:vs|versus)\\s+(.+)$"
            ),
            comparisonSnippetsSeparatedByTo(normalizedPrompt: normalized)
        ].compactMap { $0 }

        for (firstSnippet, secondSnippet) in candidatePairs {
            guard let firstRange = parser.parseDateRange(firstSnippet, defaultPeriodUnit: defaultQueryPeriodUnit),
                  let secondRange = parser.parseDateRange(secondSnippet, defaultPeriodUnit: defaultQueryPeriodUnit),
                  firstRange != secondRange else {
                continue
            }

            return (firstRange, secondRange)
        }

        return nil
    }

    private func capturedComparisonSnippets(
        normalizedPrompt: String,
        pattern: String
    ) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }

        let fullRange = NSRange(normalizedPrompt.startIndex..., in: normalizedPrompt)
        guard let match = regex.firstMatch(in: normalizedPrompt, options: [], range: fullRange),
              match.numberOfRanges == 3,
              let firstRange = Range(match.range(at: 1), in: normalizedPrompt),
              let secondRange = Range(match.range(at: 2), in: normalizedPrompt) else {
            return nil
        }

        return (
            String(normalizedPrompt[firstRange]),
            String(normalizedPrompt[secondRange])
        )
    }

    private func appearsToRequestExplicitComparisonDates(in normalizedPrompt: String) -> Bool {
        let explicitDateTokenPattern = "\\b(jan|january|feb|february|mar|march|apr|april|may|jun|june|jul|july|aug|august|sep|sept|september|oct|october|nov|november|dec|december|q[1-4]|\\d{4}-\\d{1,2}-\\d{1,2}|\\d{4})\\b"
        let hasExplicitDateToken = normalizedPrompt.range(
            of: explicitDateTokenPattern,
            options: .regularExpression
        ) != nil
        let explicitDateTokenCount = regexMatchCount(
            pattern: explicitDateTokenPattern,
            in: normalizedPrompt
        )
        let hasComparisonVerb = normalizedPrompt.contains("compare")
        let hasComparisonBridge = normalizedPrompt.range(
            of: "\\b(from .+ to|between .+ and|vs|versus)\\b",
            options: .regularExpression
        ) != nil
        let hasToBridge = hasComparisonVerb
            && normalizedPrompt.contains(" to ")
            && explicitDateTokenCount >= 2
        return hasExplicitDateToken && (hasComparisonBridge || hasToBridge)
    }

    private func comparisonSnippetsSeparatedByTo(
        normalizedPrompt: String
    ) -> (String, String)? {
        guard normalizedPrompt.contains("compare"),
              let separatorRange = normalizedPrompt.range(of: " to ") else {
            return nil
        }

        let leadingSegment = String(normalizedPrompt[..<separatorRange.lowerBound])
        let trailingSegment = String(normalizedPrompt[separatorRange.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard trailingSegment.isEmpty == false else { return nil }

        let prefixes = [
            "compare spending in ",
            "compare spending ",
            "compare spend in ",
            "compare spend ",
            "compare income in ",
            "compare income ",
            "compare expenses in ",
            "compare expenses ",
            "compare in ",
            "compare "
        ]

        guard let matchedPrefix = prefixes.first(where: { leadingSegment.hasPrefix($0) }) else {
            return nil
        }

        let firstSnippet = String(leadingSegment.dropFirst(matchedPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard firstSnippet.isEmpty == false else { return nil }

        return (firstSnippet, trailingSegment)
    }

    private func regexMatchCount(
        pattern: String,
        in text: String
    ) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return 0
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    private func hasExplicitGlobalComparisonScope(in normalizedPrompt: String) -> Bool {
        let phrases = [
            "across all categories",
            "all categories",
            "overall",
            "total spending",
            "total spend",
            "all spending"
        ]
        return phrases.contains { normalizedPrompt.contains($0) }
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
            attachment: answer.attachment,
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
                savingsEntries: savingsEntries,
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
                savingsEntries: savingsEntries,
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
                savingsEntries: savingsEntries,
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
                savingsEntries: savingsEntries,
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
            echoContext: nil,
            visibleProvenance: visibleProvenance(
                for: [
                    overviewQuery,
                    savingsQuery,
                    categoriesQuery,
                    cardsQuery
                ]
            )
        )
        
        let overviewPlan = HomeQueryPlan(
            metric: overviewQuery.intent.metric,
            dateRange: overviewQuery.dateRange,
            comparisonDateRange: overviewQuery.comparisonDateRange,
            resultLimit: overviewQuery.resultLimit,
            confidenceBand: .high,
            targetName: overviewQuery.targetName,
            periodUnit: overviewQuery.periodUnit
        )
        updateSessionContext(after: overviewPlan)
        rememberAnswerContext(
            for: overviewQuery,
            executedPlan: overviewPlan,
            rawAnswer: bundled,
            presentedAnswer: styled,
            userPrompt: userPrompt
        )
        appendAnswer(styled)
    }

    private func runRoutedRequest(
        _ routedRequest: HomeAssistantRequestRoutingResolution,
        userPrompt: String,
        explanation: String? = nil,
        executedPlan: HomeQueryPlan? = nil
    ) {
        switch routedRequest.shape {
        case .single:
            runQuery(
                routedRequest.plan.query,
                userPrompt: userPrompt,
                confidenceBand: routedRequest.plan.confidenceBand,
                explanation: explanation,
                executedPlan: executedPlan ?? routedRequest.plan
            )
        case .spendAndWhere:
            runSpendWhereBundle(userPrompt: userPrompt, basePlan: routedRequest.plan)
        case .spendByDay:
            runSpendByDayAnswer(userPrompt: userPrompt, basePlan: routedRequest.plan)
        case .incomePeriodSummary:
            runIncomePeriodSummaryAnswer(userPrompt: userPrompt, basePlan: routedRequest.plan)
        case .savingsDiagnostic:
            runSavingsDiagnosticAnswer(userPrompt: userPrompt, basePlan: routedRequest.plan)
        case .categoryAvailability:
            runCategoryAvailabilityAnswer(userPrompt: userPrompt, basePlan: routedRequest.plan)
        case .spendDrivers:
            runSpendDriversAnswer(userPrompt: userPrompt, basePlan: routedRequest.plan)
        case .cardSummary:
            runCardSummaryAnswer(userPrompt: userPrompt, basePlan: routedRequest.plan)
        }
    }

    private func bundledRoutingTelemetryNote(
        for shape: HomeAssistantRequestShape,
        hasClarificationPlan: Bool
    ) -> String {
        let base: String
        switch shape {
        case .single:
            base = "single"
        case .spendAndWhere:
            base = "spend_where_bundle"
        case .spendByDay:
            base = "spend_by_day"
        case .incomePeriodSummary:
            base = "income_period_summary"
        case .savingsDiagnostic:
            base = "savings_diagnostic"
        case .categoryAvailability:
            base = "category_availability"
        case .spendDrivers:
            base = "spend_drivers"
        case .cardSummary:
            base = "card_summary"
        }

        return hasClarificationPlan ? "\(base)_with_clarification_chips" : base
    }

    private func runSpendWhereBundle(
        userPrompt: String,
        basePlan: HomeQueryPlan
    ) {
        let range = basePlan.dateRange
        let now = Date()

        let spendQuery = HomeQuery(intent: .spendThisMonth, dateRange: range)
        let merchantsQuery = HomeQuery(intent: .topMerchantsThisMonth, dateRange: range, resultLimit: 5)

        let spendAnswer = applyConfidenceTone(
            to: engine.execute(
                query: spendQuery,
                categories: categories,
                presets: presets,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                incomes: incomes,
                savingsEntries: savingsEntries,
                now: now
            ),
            confidenceBand: basePlan.confidenceBand
        )
        let merchantsAnswer = applyConfidenceTone(
            to: engine.execute(
                query: merchantsQuery,
                categories: categories,
                presets: presets,
                plannedExpenses: plannedExpenses,
                variableExpenses: variableExpenses,
                incomes: incomes,
                savingsEntries: savingsEntries,
                now: now
            ),
            confidenceBand: basePlan.confidenceBand
        )

        guard merchantsAnswer.kind != .message, merchantsAnswer.rows.isEmpty == false else {
            runQuery(spendQuery, userPrompt: userPrompt, confidenceBand: basePlan.confidenceBand)
            return
        }

        let bundled = HomeAnswer(
            queryID: spendQuery.id,
            kind: .list,
            userPrompt: userPrompt,
            title: spendWhereBundleTitle(for: userPrompt),
            subtitle: spendAnswer.subtitle ?? merchantsAnswer.subtitle,
            primaryValue: spendAnswer.primaryValue,
            rows: merchantsAnswer.rows
        )

        let styled = personaFormatter.styledAnswer(
            from: bundled,
            userPrompt: userPrompt,
            personaID: selectedPersonaID,
            seedContext: personaSeedContext(for: spendQuery),
            footerContext: personaFooterContext(for: [spendQuery, merchantsQuery]),
            echoContext: personaEchoContext(for: spendQuery),
            visibleProvenance: visibleProvenance(for: [spendQuery, merchantsQuery])
        )

        let spendPlan = HomeQueryPlan(
            metric: spendQuery.intent.metric,
            dateRange: spendQuery.dateRange,
            comparisonDateRange: spendQuery.comparisonDateRange,
            resultLimit: spendQuery.resultLimit,
            confidenceBand: basePlan.confidenceBand,
            targetName: spendQuery.targetName,
            periodUnit: spendQuery.periodUnit
        )
        updateSessionContext(after: spendPlan)
        rememberAnswerContext(
            for: spendQuery,
            executedPlan: spendPlan,
            rawAnswer: bundled,
            presentedAnswer: styled,
            userPrompt: userPrompt
        )
        appendAnswer(styled)
    }

    private func spendWhereBundleTitle(for prompt: String) -> String {
        let normalized = normalizedPrompt(prompt)
        if let scopeSuffix = promptTimeScopeSuffix(normalizedPrompt: normalized) {
            return "Spend \(scopeSuffix) and Where"
        }
        return "Spend and Where"
    }

    private func runSpendByDayAnswer(
        userPrompt: String,
        basePlan: HomeQueryPlan
    ) {
        let range = basePlan.dateRange ?? monthRange(containing: Date())
        let query = HomeQuery(
            intent: .spendThisMonth,
            dateRange: range,
            resultLimit: basePlan.resultLimit
        )
        let rawAnswer = dailySpendAnswerBuilder.makeAnswer(
            queryID: query.id,
            userPrompt: userPrompt,
            dateRange: range,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )
        let answer = personaFormatter.styledAnswer(
            from: rawAnswer,
            userPrompt: userPrompt,
            personaID: selectedPersonaID,
            seedContext: personaSeedContext(for: query),
            footerContext: personaFooterContext(for: [query]),
            echoContext: personaEchoContext(for: query),
            visibleProvenance: visibleProvenance(for: query)
        )

        let dailyPlan = HomeQueryPlan(
            metric: query.intent.metric,
            dateRange: query.dateRange,
            comparisonDateRange: query.comparisonDateRange,
            resultLimit: query.resultLimit,
            confidenceBand: basePlan.confidenceBand,
            targetName: query.targetName,
            periodUnit: query.periodUnit
        )
        updateSessionContext(after: dailyPlan)
        rememberAnswerContext(
            for: query,
            executedPlan: dailyPlan,
            rawAnswer: rawAnswer,
            presentedAnswer: answer,
            userPrompt: userPrompt
        )
        appendAnswer(answer)
    }

    private func runIncomePeriodSummaryAnswer(
        userPrompt: String,
        basePlan: HomeQueryPlan
    ) {
        let range = basePlan.dateRange ?? monthRange(containing: Date())
        let query = HomeQuery(intent: .incomeAverageActual, dateRange: range)
        let rawAnswer = incomePeriodSummaryAnswerBuilder.makeAnswer(
            queryID: query.id,
            userPrompt: userPrompt,
            dateRange: range,
            incomes: incomes
        )
        appendStyledRoutedAnswer(
            rawAnswer,
            userPrompt: userPrompt,
            primaryQuery: query,
            footerQueries: [query]
        )
    }

    private func runSavingsDiagnosticAnswer(
        userPrompt: String,
        basePlan: HomeQueryPlan
    ) {
        let range = basePlan.dateRange ?? monthRange(containing: Date())
        let savingsQuery = HomeQuery(intent: .savingsStatus, dateRange: range)
        let categoriesQuery = HomeQuery(intent: .topCategoriesThisMonth, dateRange: range, resultLimit: 3)
        let savings = engine.execute(
            query: savingsQuery,
            categories: categories,
            presets: presets,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            incomes: incomes,
            savingsEntries: savingsEntries
        )
        let topCategories = engine.execute(
            query: categoriesQuery,
            categories: categories,
            presets: presets,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            incomes: incomes,
            savingsEntries: savingsEntries
        )

        var rows = savings.rows
        rows.append(contentsOf: sectionRows("Top spend driver", from: topCategories, maxRows: 3))
        let rawAnswer = HomeAnswer(
            queryID: savingsQuery.id,
            kind: .list,
            userPrompt: userPrompt,
            title: "Savings Diagnostic",
            subtitle: savings.subtitle ?? topCategories.subtitle,
            primaryValue: savings.primaryValue,
            rows: rows
        )
        appendStyledRoutedAnswer(
            rawAnswer,
            userPrompt: userPrompt,
            primaryQuery: savingsQuery,
            footerQueries: [savingsQuery, categoriesQuery]
        )
    }

    private func runCategoryAvailabilityAnswer(
        userPrompt: String,
        basePlan: HomeQueryPlan
    ) {
        let range = basePlan.dateRange ?? monthRange(containing: Date())
        let query = HomeQuery(intent: .topCategoriesThisMonth, dateRange: range)
        let rawAnswer = categoryAvailabilityAnswerBuilder.makeAnswer(
            queryID: query.id,
            userPrompt: userPrompt,
            dateRange: range,
            budgets: budgets,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )
        appendStyledRoutedAnswer(
            rawAnswer,
            userPrompt: userPrompt,
            primaryQuery: query,
            footerQueries: [query]
        )
    }

    private func runSpendDriversAnswer(
        userPrompt: String,
        basePlan: HomeQueryPlan
    ) {
        let range = basePlan.dateRange ?? monthRange(containing: Date())
        let categoryChangesQuery = HomeQuery(intent: .topCategoryChangesThisMonth, dateRange: range, resultLimit: 3)
        let cardChangesQuery = HomeQuery(intent: .topCardChangesThisMonth, dateRange: range, resultLimit: 3)
        let merchantsQuery = HomeQuery(intent: .topMerchantsThisMonth, dateRange: range, resultLimit: 3)
        let categoryChanges = engine.execute(
            query: categoryChangesQuery,
            categories: categories,
            presets: presets,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            incomes: incomes,
            savingsEntries: savingsEntries
        )
        let cardChanges = engine.execute(
            query: cardChangesQuery,
            categories: categories,
            presets: presets,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            incomes: incomes,
            savingsEntries: savingsEntries
        )
        let merchants = engine.execute(
            query: merchantsQuery,
            categories: categories,
            presets: presets,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses,
            incomes: incomes,
            savingsEntries: savingsEntries
        )

        var rows: [HomeAnswerRow] = []
        rows.append(contentsOf: sectionRows("Category change", from: categoryChanges, maxRows: 3))
        rows.append(contentsOf: sectionRows("Card change", from: cardChanges, maxRows: 3))
        rows.append(contentsOf: sectionRows("Merchant", from: merchants, maxRows: 3))

        let rawAnswer = HomeAnswer(
            queryID: categoryChangesQuery.id,
            kind: rows.isEmpty ? .message : .list,
            userPrompt: userPrompt,
            title: "Spending Drivers",
            subtitle: rows.isEmpty ? "No driver signals in this range yet." : categoryChanges.subtitle,
            primaryValue: categoryChanges.primaryValue,
            rows: rows
        )
        appendStyledRoutedAnswer(
            rawAnswer,
            userPrompt: userPrompt,
            primaryQuery: categoryChangesQuery,
            footerQueries: [categoryChangesQuery, cardChangesQuery, merchantsQuery]
        )
    }

    private func runCardSummaryAnswer(
        userPrompt: String,
        basePlan: HomeQueryPlan
    ) {
        let range = basePlan.dateRange ?? monthRange(containing: Date())
        let query = HomeQuery(intent: .cardSnapshotSummary, dateRange: range, targetName: basePlan.targetName)
        let rawAnswer = cardSummaryAnswerBuilder.makeAnswer(
            queryID: query.id,
            userPrompt: userPrompt,
            dateRange: range,
            cards: cards,
            targetName: basePlan.targetName
        )
        appendStyledRoutedAnswer(
            rawAnswer,
            userPrompt: userPrompt,
            primaryQuery: query,
            footerQueries: [query]
        )
    }

    private func appendStyledRoutedAnswer(
        _ rawAnswer: HomeAnswer,
        userPrompt: String,
        primaryQuery: HomeQuery,
        footerQueries: [HomeQuery]
    ) {
        let styled = personaFormatter.styledAnswer(
            from: rawAnswer,
            userPrompt: userPrompt,
            personaID: selectedPersonaID,
            seedContext: personaSeedContext(for: primaryQuery),
            footerContext: personaFooterContext(for: footerQueries),
            echoContext: personaEchoContext(for: primaryQuery),
            visibleProvenance: visibleProvenance(for: footerQueries)
        )

        let routedPlan = HomeQueryPlan(
            metric: primaryQuery.intent.metric,
            dateRange: primaryQuery.dateRange,
            comparisonDateRange: primaryQuery.comparisonDateRange,
            resultLimit: primaryQuery.resultLimit,
            confidenceBand: .high,
            targetName: primaryQuery.targetName,
            periodUnit: primaryQuery.periodUnit
        )
        updateSessionContext(after: routedPlan)
        rememberAnswerContext(
            for: primaryQuery,
            executedPlan: routedPlan,
            rawAnswer: rawAnswer,
            presentedAnswer: styled,
            userPrompt: userPrompt
        )
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

    private func whatIfBaselineSpendByCategoryID(
        in range: HomeQueryDateRange
    ) -> [UUID: Double] {
        var totals: [UUID: Double] = [:]

        for expense in plannedExpenses where expense.expenseDate >= range.startDate && expense.expenseDate <= range.endDate {
            guard let category = expense.category else { continue }
            totals[category.id, default: 0] += max(0, CurrencyFormatter.roundedToCurrency(expense.effectiveAmount()))
        }

        for expense in variableExpenses where expense.transactionDate >= range.startDate && expense.transactionDate <= range.endDate {
            guard let category = expense.category else { continue }
            totals[category.id, default: 0] += expense.ledgerSignedAmount()
        }

        return totals.mapValues { CurrencyFormatter.roundedToCurrency(max(0, $0)) }
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
    
    private func personaEchoContext(for query: HomeQuery) -> HomeAssistantPersonaEchoContext? {
        guard let targetName = query.targetName?.trimmingCharacters(in: .whitespacesAndNewlines), targetName.isEmpty == false else {
            return nil
        }
        
        switch query.intent {
        case .cardSpendTotal, .cardVariableSpendingHabits, .compareCardThisMonthToPreviousMonth, .nextPlannedExpense, .spendTrendsSummary, .cardSnapshotSummary, .topCardChangesThisMonth:
            return HomeAssistantPersonaEchoContext(
                cardName: targetName,
                categoryName: nil,
                incomeSourceName: nil
            )
        case .categorySpendTotal, .categorySpendShare, .categorySpendShareTrend, .categoryPotentialSavings, .categoryReallocationGuidance, .presetCategorySpend, .compareCategoryThisMonthToPreviousMonth, .topCategoryChangesThisMonth:
            return HomeAssistantPersonaEchoContext(
                cardName: nil,
                categoryName: targetName,
                incomeSourceName: nil
            )
        case .incomeAverageActual, .incomeSourceShare, .incomeSourceShareTrend, .compareIncomeSourceThisMonthToPreviousMonth:
            return HomeAssistantPersonaEchoContext(
                cardName: nil,
                categoryName: nil,
                incomeSourceName: targetName
            )
        case .merchantSpendTotal, .merchantSpendSummary, .compareMerchantThisMonthToPreviousMonth:
            return nil
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
final class HomeAssistantMutationService {
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
        
        return HomeAssistantMutationResult(
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
    ) throws -> HomeAssistantMutationResult {
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

        return HomeAssistantMutationResult(
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
    ) throws -> HomeAssistantMutationResult {
        let resolvedFrequency = RecurrenceFrequency(rawValue: recurrenceFrequencyRaw ?? RecurrenceFrequency.none.rawValue) ?? .none

        if resolvedFrequency != .none {
            guard let recurrenceEndDate else {
                throw NSError(
                    domain: "HomeAssistantMutationService",
                    code: 400,
                    userInfo: [NSLocalizedDescriptionKey: "Repeat income needs an end date."]
                )
            }

            let startDay = Calendar.current.startOfDay(for: date)
            let endDay = Calendar.current.startOfDay(for: recurrenceEndDate)
            guard endDay >= startDay else {
                throw NSError(
                    domain: "HomeAssistantMutationService",
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

            return HomeAssistantMutationResult(
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
        
        return HomeAssistantMutationResult(
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
    
    func editCardStyle(
        card: Card,
        themeRaw: String?,
        effectRaw: String?,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
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
        
        return HomeAssistantMutationResult(
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
    ) throws -> HomeAssistantMutationResult {
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

        return HomeAssistantMutationResult(
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
    ) throws -> HomeAssistantMutationResult {
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

        return HomeAssistantMutationResult(
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
        command: HomeAssistantCommandPlan,
        card: Card?,
        category: Category?,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
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

        return HomeAssistantMutationResult(
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
        command: HomeAssistantCommandPlan,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        if let newName = command.updatedEntityName?.trimmingCharacters(in: .whitespacesAndNewlines), newName.isEmpty == false {
            budget.name = newName
        }
        if let range = command.dateRange {
            budget.startDate = Calendar.current.startOfDay(for: range.startDate)
            budget.endDate = Calendar.current.startOfDay(for: range.endDate)
        }

        syncGeneratedPlannedExpenses(for: budget, workspace: workspace, modelContext: modelContext)
        try modelContext.save()

        return HomeAssistantMutationResult(
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
                HomeAnswerRow(title: "Amount", value: CurrencyFormatter.string(from: expense.ledgerSignedAmount())),
                HomeAnswerRow(title: "Description", value: expense.descriptionText),
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(expense.transactionDate))
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
                HomeAnswerRow(title: "Date", value: AppDateFormat.abbreviatedDate(income.date))
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

    func editPlannedExpense(
        _ expense: PlannedExpense,
        command: HomeAssistantCommandPlan,
        card: Card?,
        category: Category?,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
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

        return HomeAssistantMutationResult(
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
    ) throws -> HomeAssistantMutationResult {
        VariableExpenseDeletionService.delete(expense, modelContext: modelContext)
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
    
    func deleteCard(
        _ card: Card,
        workspace: Workspace,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
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
        
        return HomeAssistantMutationResult(
            title: "Card deleted",
            subtitle: "Removed \(card.name) and its linked entries.",
            rows: []
        )
    }

    func deleteCategory(
        _ category: Category,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
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

        return HomeAssistantMutationResult(
            title: "Category deleted",
            subtitle: "Removed \(category.name).",
            rows: []
        )
    }

    func deletePreset(
        _ preset: Preset,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        if let links = preset.budgetPresetLinks {
            for link in links {
                modelContext.delete(link)
            }
        }
        modelContext.delete(preset)
        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Preset deleted",
            subtitle: "Removed \(preset.title).",
            rows: []
        )
    }

    func deleteBudget(
        _ budget: Budget,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        try BudgetDeletionService.deleteBudgetAndGeneratedPlannedExpenses(budget, modelContext: modelContext)
        return HomeAssistantMutationResult(
            title: "Budget deleted",
            subtitle: "Removed \(budget.name).",
            rows: []
        )
    }

    func deletePlannedExpense(
        _ expense: PlannedExpense,
        modelContext: ModelContext
    ) throws -> HomeAssistantMutationResult {
        PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
        try modelContext.save()

        return HomeAssistantMutationResult(
            title: "Planned expense deleted",
            subtitle: "The planned expense was removed.",
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
    
    private func deleteVariableExpense(
        _ expense: VariableExpense,
        modelContext: ModelContext
    ) {
        VariableExpenseDeletionService.delete(expense, modelContext: modelContext)
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
