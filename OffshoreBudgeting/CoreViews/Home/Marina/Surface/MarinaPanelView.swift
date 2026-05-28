import SwiftData
import SwiftUI

struct MarinaStarterPromptFactory {
    static let basePromptPool = [
        "What is my safe spend today?",
        "Show my savings outlook.",
        "How is my income progress?",
        "What is my next planned expense?",
        "Show category availability.",
        "What are my spend trends?",
        "What is my top category this period?"
    ]

    static func promptPool(cardNames: [String]) -> [String] {
        var pool = basePromptPool
        if let cardName = cardNames
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.isEmpty == false }) {
            pool.append("Summarize my \(cardName).")
        }
        return pool
    }

    static func randomPrompts(cardNames: [String]) -> [String] {
        Array(promptPool(cardNames: cardNames).shuffled().prefix(4))
    }
}

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

    private struct PendingClarification {
        let answerID: UUID
        let choices: MarinaClarificationChoices
    }

    let workspace: Workspace
    let onDismiss: () -> Void
    let shouldUseLargeMinimumSize: Bool
    let homeContext: MarinaPanelHomeContext?

    @Query private var cards: [Card]
    @Query private var categories: [Category]
    @Query private var presets: [Preset]

    @State private var answers: [HomeAnswer] = []
    @State private var promptText = ""
    @State private var hasLoadedConversation = false
    @State private var isResponding = false
    @State private var isShowingClearConversationAlert = false
    @State private var pendingClarification: PendingClarification?
    @State private var responseTask: Task<Void, Never>?
    @State private var answerUpdateTick = 0
    @State private var starterPrompts: [String] = []
    @FocusState private var isPromptFieldFocused: Bool

    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private let conversationStore = MarinaConversationStore()
    private let createService = MarinaCreateService()
    private let brain = MarinaBrain()

    init(
        workspace: Workspace,
        onDismiss: @escaping () -> Void,
        shouldUseLargeMinimumSize: Bool,
        homeContext: MarinaPanelHomeContext? = nil
    ) {
        self.workspace = workspace
        self.onDismiss = onDismiss
        self.shouldUseLargeMinimumSize = shouldUseLargeMinimumSize
        self.homeContext = homeContext

        let workspaceID = workspace.id
        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )
        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )
        _presets = Query(
            filter: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Preset.title, order: .forward)]
        )
    }

    var body: some View {
        let content = NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if answers.isEmpty {
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
                    .padding(.bottom, isPromptFieldFocused ? 128 : 96)
                }
                .scrollDismissesKeyboard(.interactively)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .safeAreaInset(edge: .bottom) {
                    inputSection
                }
                .onChange(of: answers.count) { _, _ in
                    scrollToLatestMessage(using: proxy, animated: true)
                }
                .onChange(of: answerUpdateTick) { _, _ in
                    scrollToLatestMessage(using: proxy, animated: true)
                }
                .onAppear {
                    loadConversationIfNeeded()
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
        .toolbarBackground(.visible, for: .navigationBar)
        .alert(
            String(localized: "assistant.clearHistory.confirmation", defaultValue: "Are you sure you want to clear your chat history?", comment: "Confirmation prompt before clearing assistant chat history."),
            isPresented: $isShowingClearConversationAlert
        ) {
            Button(String(localized: "common.cancel", defaultValue: "Cancel", comment: "Cancel action label."), role: .cancel) {}
            Button(String(localized: "common.clear", defaultValue: "Clear", comment: "Action to clear a selection."), role: .destructive) {
                clearConversation()
            }
        }
        .onDisappear {
            cancelResponseTask()
        }
        .accessibilityIdentifier("marina.panel")

        if shouldUseLargeMinimumSize {
            content.frame(minWidth: 700, minHeight: 520)
        } else {
            content
        }
    }

    private var inputSection: some View {
        GlassEffectContainer(spacing: 8) {
            inputControls
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var inputControls: some View {
        HStack(spacing: 8) {
            createMenu
            promptTextField
            submitButton
        }
    }

    private var submitButton: some View {
        Button {
            submitPrompt()
        } label: {
            if isResponding {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 33, height: 33)
            } else {
                Image(systemName: "paperplane.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 33, height: 33)
            }
        }
        .modifier(AssistantIconButtonModifier())
        .disabled(trimmedPromptText.isEmpty || isResponding)
        .accessibilityLabel(String(localized: "assistant.submitQuestion", defaultValue: "Submit Question", comment: "Accessibility label for submitting assistant question."))
        .accessibilityIdentifier("marina.submitButton")
    }

    private var createMenu: some View {
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
        .accessibilityIdentifier("marina.createMenu")
    }

    private var promptTextField: some View {
        TextField(String(localized: "assistant.messagePrompt", defaultValue: "Message Marina", comment: "Prompt placeholder for assistant message input."), text: $promptText)
            .textFieldStyle(.plain)
            .focused($isPromptFieldFocused)
            .submitLabel(.send)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .frame(maxWidth: .infinity)
            .glassEffect(.regular.interactive(), in: Capsule())
            .contentShape(Capsule())
            .accessibilityIdentifier("marina.promptField")
            .onSubmit {
                submitPrompt()
            }
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

    private var marinaEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.wave")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            Text("Marina")
                .font(.title2.weight(.semibold))

            Text(String(localized: "assistant.marina.emptyDescription", defaultValue: "Ask about the numbers on Home, or start with one of these.", comment: "Introductory Marina description shown in the empty assistant state."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 360)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                ForEach(starterPrompts, id: \.self) { prompt in
                    Button {
                        submitPrompt(prompt)
                    } label: {
                        Text(prompt)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isResponding)
                    .accessibilityIdentifier("marina.starterPrompt")
                }
            }
            .frame(maxWidth: 420)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .center)
        .padding(.vertical, 32)
        .accessibilityIdentifier("marina.emptyState")
    }

    private var answersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(MarinaConversationDisplayAdapter.messages(from: answers).enumerated()), id: \.element.id) { index, message in
                switch message.role {
                case .user:
                    if let prompt = message.prompt {
                        userMessageBubble(prompt: prompt, date: message.generatedAt, index: index)
                    }
                case .assistant:
                    if let answer = message.answer {
                        assistantMessageBubble(for: answer, index: index)
                    }
                }
            }
        }
        .accessibilityIdentifier("marina.answerList")
    }

    private func userMessageBubble(prompt: String, date: Date, index: Int) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(prompt)
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color("AccentColor"), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .accessibilityIdentifier("marina.userMessage.\(index)")

            Text(timestampText(for: date))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func assistantMessageBubble(for answer: HomeAnswer, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 10) {
                Text(answer.title)
                    .font(.headline)
                    .foregroundStyle(.primary)

                if let subtitle = answer.subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let primaryValue = answer.primaryValue, primaryValue.isEmpty == false {
                    Text(primaryValue)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color("AccentColor"))
                }

                ForEach(answer.rows) { row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                        Text(row.value)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
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

                if let choices = clarificationChoices(for: answer) {
                    clarificationChoicesView(choices, answerID: answer.id)
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

            if let explanation = answer.explanation?.trimmingCharacters(in: .whitespacesAndNewlines),
               explanation.isEmpty == false {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
                    .accessibilityIdentifier("marina.answerExplanation.\(index)")
            }

            Text(timestampText(for: answer.generatedAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var conversationBackdrop: some View {
        LinearGradient(
            colors: [
                Color(.systemBackground),
                Color(.secondarySystemBackground).opacity(0.72)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var assistantBubbleBackground: some ShapeStyle {
        .ultraThinMaterial
    }

    private var assistantBubbleStroke: Color {
        Color.secondary.opacity(0.16)
    }

    private var trimmedPromptText: String {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var defaultBudgetingPeriod: BudgetingPeriod {
        BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
    }

    private var shouldStackClarificationChoices: Bool {
        horizontalSizeClass == .compact || dynamicTypeSize.isAccessibilitySize
    }

    private var clarificationChoiceColumns: [GridItem] {
        if shouldStackClarificationChoices {
            return [GridItem(.flexible(), spacing: 8)]
        }
        return [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 8)]
    }

    private static func randomStarterPrompts(cards: [Card]) -> [String] {
        MarinaStarterPromptFactory.randomPrompts(cardNames: cards.map(\.name))
    }

    private func submitPrompt(_ promptOverride: String? = nil) {
        let prompt = (promptOverride ?? trimmedPromptText).trimmingCharacters(in: .whitespacesAndNewlines)
        guard prompt.isEmpty == false else { return }
        guard isResponding == false else { return }
        guard MarinaPromptSubmissionPolicy.shouldHandleFreeText(prompt) else {
            if promptOverride == nil {
                promptText = ""
            }
            return
        }
        let submittedPrompt = prompt
        if promptOverride == nil {
            promptText = ""
        }

        if let pendingClarification,
           let choice = pendingClarification.choices.choice(matching: submittedPrompt) {
            resolveClarification(
                pendingClarification,
                choice: choice,
                replyPrompt: submittedPrompt
            )
            return
        }

        cancelResponseTask()
        isResponding = true
        let conversationContext = MarinaConversationContext(recentAnswers: answers)
        responseTask = Task {
            let seed = await brain.answerSeed(
                prompt: submittedPrompt,
                workspace: workspace,
                modelContext: modelContext,
                ambientDateRange: homeContext?.dateRange,
                homeContext: homeContext,
                defaultBudgetingPeriod: defaultBudgetingPeriod,
                conversationContext: conversationContext
            )
            guard Task.isCancelled == false else { return }
            await handleAnswerSeed(seed)
            isResponding = false
            responseTask = nil
        }
    }

    @ViewBuilder
    private func clarificationChoicesView(_ choices: MarinaClarificationChoices, answerID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            LazyVGrid(columns: clarificationChoiceColumns, alignment: .leading, spacing: 8) {
                ForEach(choices.choices) { choice in
                    Button {
                        resolveClarification(
                            PendingClarification(answerID: answerID, choices: choices),
                            choice: choice,
                            replyPrompt: choice.title
                        )
                    } label: {
                        MarinaClarificationChoiceButton(
                            choice: choice,
                            isResolved: choices.resolvedChoiceID == choice.id
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(isResponding || choices.isResolved)
                    .accessibilityLabel(accessibilityLabel(for: choice))
                }
            }

            if let resolvedChoiceID = choices.resolvedChoiceID,
               let choice = choices.choices.first(where: { $0.id == resolvedChoiceID }) {
                Text("Using \(choice.title).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func accessibilityLabel(for choice: MarinaClarificationChoice) -> String {
        let parts = [choice.title, choice.kindLabel, choice.subtitle]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return parts.joined(separator: ", ")
    }

    private func clarificationChoices(for answer: HomeAnswer) -> MarinaClarificationChoices? {
        guard case .clarificationChoices(let choices)? = answer.attachment else {
            return nil
        }
        return choices
    }

    private func resolveClarification(
        _ pending: PendingClarification,
        choice: MarinaClarificationChoice,
        replyPrompt: String
    ) {
        guard isResponding == false else { return }
        markClarificationResolved(answerID: pending.answerID, choiceID: choice.id)
        pendingClarification = nil

        cancelResponseTask()
        isResponding = true
        responseTask = Task {
            let seed = await brain.answerSeed(
                resolvedRequest: choice.request,
                prompt: replyPrompt,
                workspace: workspace,
                modelContext: modelContext,
                ambientDateRange: homeContext?.dateRange,
                homeContext: homeContext,
                defaultBudgetingPeriod: defaultBudgetingPeriod
            )
            guard Task.isCancelled == false else { return }
            await handleAnswerSeed(seed)
            isResponding = false
            responseTask = nil
        }
    }

    private func markClarificationResolved(answerID: UUID, choiceID: UUID) {
        guard let index = answers.firstIndex(where: { $0.id == answerID }),
              case .clarificationChoices(var choices)? = answers[index].attachment else {
            return
        }
        choices.resolvedChoiceID = choiceID
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
            attachment: .clarificationChoices(choices),
            explanation: answer.explanation,
            semanticContext: answer.semanticContext,
            generatedAt: answer.generatedAt
        )
        conversationStore.saveAnswers(answers, workspaceID: workspace.id)
    }

    private func handleCreateMenuSelection(_ kind: MarinaCreateEntityKind) {
        let entity: MarinaInlineCreateEntity
        switch kind {
        case .expense:
            entity = .expense
        case .budget:
            entity = .budget
        case .income:
            entity = .income
        case .card:
            entity = .card
        case .preset:
            entity = .preset
        case .category:
            entity = .category
        }

        appendInlineCreateForm(makeInlineCreateForm(for: entity))
    }

    private func appendInlineCreateForm(_ form: MarinaInlineCreateForm) {
        appendAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: "Create \(form.entity.displayTitle)",
                attachment: .inlineCreateForm(form)
            )
        )
    }

    private func inlineCreateFormBinding(for answerID: UUID) -> Binding<MarinaInlineCreateForm>? {
        guard currentInlineCreateForm(for: answerID) != nil else { return nil }
        return Binding(
            get: { currentInlineCreateForm(for: answerID) ?? makeInlineCreateForm(for: .expense) },
            set: { updated in
                updateInlineCreateForm(answerID: answerID, form: updated)
            }
        )
    }

    private func currentInlineCreateForm(for answerID: UUID) -> MarinaInlineCreateForm? {
        guard let answer = answers.first(where: { $0.id == answerID }),
              case .inlineCreateForm(let form)? = answer.attachment else {
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
            explanation: answer.explanation,
            semanticContext: answer.semanticContext,
            generatedAt: answer.generatedAt
        )
        conversationStore.saveAnswers(answers, workspaceID: workspace.id)
    }

    private func finalizeInlineCreateForm(answerID: UUID, subtitle: String, rows: [HomeAnswerRow]) {
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
            explanation: answer.explanation,
            semanticContext: answer.semanticContext,
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
                subtitle: "Saved.",
                rows: inlineCreateSummaryRows(for: form)
            )
            appendMutationMessage(title: result.title, subtitle: result.subtitle, rows: result.rows)
        } catch {
            appendMutationMessage(
                title: "Could not create \(form.entity.displayTitle.lowercased())",
                subtitle: error.localizedDescription,
                rows: []
            )
        }
    }

    private func executeInlineCreateForm(_ form: MarinaInlineCreateForm) throws -> MarinaCreateResult {
        switch form.entity {
        case .expense:
            guard let amount = CurrencyFormatter.parseAmount(form.amountText), amount > 0 else {
                throw TransactionEntryService.ValidationError.invalidAmount
            }
            guard let card = cards.first(where: { $0.id == form.selectedCardID }) else {
                throw missingSelectionError("Select a card to continue.")
            }
            return try createService.addExpense(
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
            return try createService.addIncome(
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
            return try createService.addBudget(
                name: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines),
                dateRange: HomeQueryDateRange(startDate: form.date, endDate: form.secondaryDate),
                cards: cards.filter { form.selectedCardIDs.contains($0.id) },
                presets: presets.filter { form.selectedPresetIDs.contains($0.id) },
                workspace: workspace,
                modelContext: modelContext
            )
        case .card:
            return try createService.addCard(
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
            return try createService.addPreset(
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
            return try createService.addCategory(
                name: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines),
                colorHex: form.categoryColorHex,
                workspace: workspace,
                modelContext: modelContext
            )
        case .plannedExpense:
            throw missingSelectionError("Create a preset to generate planned expenses, or log a regular expense instead.")
        }
    }

    private func makeInlineCreateForm(for entity: MarinaInlineCreateEntity) -> MarinaInlineCreateForm {
        let now = calendarStartOfDay(Date())
        let periodRange = defaultBudgetingPeriod.defaultRange(containing: now, calendar: .current)
        let seededRange = HomeQueryDateRange(startDate: periodRange.start, endDate: periodRange.end)
        let defaultCardID = cards.count == 1 ? cards.first?.id : nil

        switch entity {
        case .expense:
            return MarinaInlineCreateForm(entity: .expense, date: now, selectedCardID: defaultCardID)
        case .income:
            return MarinaInlineCreateForm(
                entity: .income,
                date: now,
                secondaryDate: now,
                isPlannedIncome: false,
                recurrenceFrequencyRaw: RecurrenceFrequency.none.rawValue
            )
        case .budget:
            return MarinaInlineCreateForm(
                entity: .budget,
                nameText: BudgetNameSuggestion.suggestedName(start: seededRange.startDate, end: seededRange.endDate, calendar: .current),
                date: seededRange.startDate,
                secondaryDate: seededRange.endDate
            )
        case .card:
            return MarinaInlineCreateForm(entity: .card)
        case .preset:
            return MarinaInlineCreateForm(entity: .preset, selectedCardID: defaultCardID)
        case .category:
            return MarinaInlineCreateForm(entity: .category)
        case .plannedExpense:
            return MarinaInlineCreateForm(entity: .plannedExpense, date: now, selectedCardID: defaultCardID)
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
                HomeAnswerRow(title: "Title", value: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines)),
                HomeAnswerRow(title: "Amount", value: form.amountText),
                HomeAnswerRow(title: "Card", value: cards.first(where: { $0.id == form.selectedCardID })?.name ?? "Select"),
                HomeAnswerRow(title: "Repeat", value: RecurrenceFrequency(rawValue: form.recurrenceFrequencyRaw)?.displayName ?? "Monthly")
            ]
        case .category:
            return [
                HomeAnswerRow(title: "Name", value: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines)),
                HomeAnswerRow(title: "Color", value: form.categoryColorHex)
            ]
        case .plannedExpense:
            return [
                HomeAnswerRow(title: "Title", value: form.nameText.trimmingCharacters(in: .whitespacesAndNewlines)),
                HomeAnswerRow(title: "Amount", value: form.amountText)
            ]
        }
    }

    private func appendMutationMessage(title: String, subtitle: String?, rows: [HomeAnswerRow]) {
        appendAnswer(
            HomeAnswer(
                queryID: UUID(),
                kind: .message,
                title: title,
                subtitle: subtitle,
                rows: rows
            )
        )
    }

    private func appendAnswer(_ answer: HomeAnswer) {
        answers.append(answer)
        updatePendingClarification(afterAppending: answer)
        conversationStore.saveAnswers(answers, workspaceID: workspace.id)
    }

    private func handleAnswerSeed(_ seed: MarinaAnswerSeed) async {
        appendAnswer(seed.answer)
        guard let insightContext = seed.insightContext else { return }

        var latestNarration: String?
        do {
            for try await partial in brain.insightNarrationStream(for: insightContext) {
                guard Task.isCancelled == false else { return }
                latestNarration = partial
                replaceAnswerExplanation(
                    answerID: seed.answer.id,
                    baseExplanation: seed.answer.explanation,
                    insight: partial,
                    suffix: nil,
                    shouldSave: false
                )
            }

            guard Task.isCancelled == false else { return }
            let finalAnswer = brain.completedAnswer(
                from: seed,
                streamingNarration: latestNarration
            )
            replaceAnswer(finalAnswer, shouldSave: true)
        } catch {
            guard Task.isCancelled == false else { return }
            replaceAnswer(seed.answer, shouldSave: true)
        }
    }

    private func replaceAnswerExplanation(
        answerID: UUID,
        baseExplanation: String?,
        insight: String?,
        suffix: String?,
        shouldSave: Bool
    ) {
        guard let index = answers.firstIndex(where: { $0.id == answerID }) else { return }
        let answer = answers[index]
        let explanation = combinedExplanation(
            base: baseExplanation,
            insight: insight,
            suffix: suffix
        )
        answers[index] = HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows,
            attachment: answer.attachment,
            explanation: explanation,
            semanticContext: answer.semanticContext,
            generatedAt: answer.generatedAt
        )
        answerUpdateTick += 1
        if shouldSave {
            conversationStore.saveAnswers(answers, workspaceID: workspace.id)
        }
    }

    private func replaceAnswer(_ answer: HomeAnswer, shouldSave: Bool) {
        guard let index = answers.firstIndex(where: { $0.id == answer.id }) else { return }
        answers[index] = answer
        updatePendingClarification(afterAppending: answer)
        answerUpdateTick += 1
        if shouldSave {
            conversationStore.saveAnswers(answers, workspaceID: workspace.id)
        }
    }

    private func combinedExplanation(base: String?, insight: String?, suffix: String?) -> String? {
        let pieces = [base, insight, suffix]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return pieces.isEmpty ? nil : pieces.joined(separator: "\n\n")
    }

    private func loadConversationIfNeeded() {
        guard hasLoadedConversation == false else { return }
        answers = conversationStore.loadAnswers(workspaceID: workspace.id)
        pendingClarification = pendingClarification(from: answers.last)
        if answers.isEmpty {
            resetStarterPrompts()
        }
        hasLoadedConversation = true
    }

    private func clearConversation() {
        cancelResponseTask()
        answers = []
        pendingClarification = nil
        isResponding = false
        resetStarterPrompts()
        conversationStore.saveAnswers([], workspaceID: workspace.id)
    }

    private func cancelResponseTask() {
        responseTask?.cancel()
        responseTask = nil
    }

    private func resetStarterPrompts() {
        starterPrompts = Self.randomStarterPrompts(cards: cards)
    }

    private func updatePendingClarification(afterAppending answer: HomeAnswer) {
        pendingClarification = pendingClarification(from: answer)
    }

    private func pendingClarification(from answer: HomeAnswer?) -> PendingClarification? {
        guard let answer,
              case .clarificationChoices(let choices)? = answer.attachment,
              choices.isResolved == false else {
            return nil
        }
        return PendingClarification(answerID: answer.id, choices: choices)
    }

    private func scrollToLatestMessage(using proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo(ScrollTarget.bottomAnchor, anchor: .bottom)
        }
        if animated {
            withAnimation(.easeOut(duration: 0.2), action)
        } else {
            action()
        }
    }

    private func missingSelectionError(_ description: String) -> NSError {
        NSError(domain: "MarinaInlineCreateForm", code: 400, userInfo: [NSLocalizedDescriptionKey: description])
    }

    private func calendarStartOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private func timestampText(for date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }
}

private struct MarinaClarificationChoiceButton: View {
    let choice: MarinaClarificationChoice
    let isResolved: Bool

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isResolved ? "checkmark.circle.fill" : "arrow.turn.down.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color("AccentColor"))
                .frame(width: 18, height: 20, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(choice.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color("AccentColor"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let kindLabel = choice.kindLabel, kindLabel.isEmpty == false {
                    Text(kindLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color("AccentColor").opacity(isResolved ? 0.18 : 0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color("AccentColor").opacity(isResolved ? 0.32 : 0.16), lineWidth: 1)
        }
        .opacity(isEnabled ? 1 : 0.62)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct AssistantIconButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .frame(minWidth: 44, minHeight: 44)
    }
}

private struct AssistantPanelIconButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.automatic)
            .buttonBorderShape(.circle)
    }
}

private struct AssistantPanelActionButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.automatic)
            .buttonBorderShape(.capsule)
    }
}
