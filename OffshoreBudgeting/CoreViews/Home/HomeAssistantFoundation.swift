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

// MARK: - Launcher Bar (iPhone)

struct HomeAssistantLauncherBar: View {
    let onTap: () -> Void
    @AppStorage(HomeAssistantPersonaStore.defaultStorageKey)
    private var assistantPersonaRaw: String = HomeAssistantPersonaCatalog.defaultPersona.rawValue

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
            Image(systemName: "message")
                .font(.subheadline.weight(.semibold))

            Text("\(selectedPersonaName)")
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

    private var selectedPersonaName: String {
        let selectedPersona = HomeAssistantPersonaID(rawValue: assistantPersonaRaw)
            ?? HomeAssistantPersonaCatalog.defaultPersona

        return HomeAssistantPersonaCatalog.profile(for: selectedPersona).displayName
    }
}

// MARK: - Presented Panel

struct HomeAssistantPanelView: View {
    let workspace: Workspace
    let onDismiss: () -> Void
    let shouldUseLargeMinimumSize: Bool

    @Query private var categories: [Category]
    @Query private var plannedExpenses: [PlannedExpense]
    @Query private var variableExpenses: [VariableExpense]

    @State private var answers: [HomeAnswer] = []
    @State private var promptText = ""
    @State private var hasLoadedConversation = false
    @State private var selectedPersonaID: HomeAssistantPersonaID = HomeAssistantPersonaCatalog.defaultPersona
    @State private var isShowingClearConversationAlert = false

    private let engine = HomeQueryEngine()
    private let parser = HomeAssistantTextParser()
    private let conversationStore = HomeAssistantConversationStore()
    private let personaStore = HomeAssistantPersonaStore()
    private let personaFormatter = HomeAssistantPersonaFormatter()

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
    }

    var body: some View {
        let content = NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    suggestionsSection

                    followUpSection

                    if answers.isEmpty {
                        ContentUnavailableView(
                            "No answers yet",
                            systemImage: "bubble.left.and.bubble.right",
                            description: Text("Tap a suggested question to generate your first answer.")
                        )
                    } else {
                        answersSection
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .padding(.bottom, 96)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Assistant")
            .safeAreaInset(edge: .bottom) {
                inputSection
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
                    personaTrailingNavBarItem
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
        return VStack(alignment: .leading, spacing: 8) {
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
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var promptTextField: some View {
        if #available(iOS 26.0, *) {
            TextField("Try: Top 3 categories this month", text: $promptText)
                .textFieldStyle(.plain)
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
            TextField("Try: Top 3 categories this month", text: $promptText)
                .textFieldStyle(.roundedBorder)
                .frame(minHeight: 44)
                .onSubmit {
                    submitPrompt()
                }
        }
    }

    @ViewBuilder
    private var personaTrailingNavBarItem: some View {
        let baseMenu = Menu {
            ForEach(HomeAssistantPersonaCatalog.allProfiles, id: \.id) { profile in
                Button {
                    selectPersona(profile.id)
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName)
                            Text(profile.summary)
                                .font(.caption)
                        }

                        if profile.id == selectedPersonaID {
                            Spacer(minLength: 8)
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "person.crop.circle")
        }

        if #available(iOS 26.0, *) {
            baseMenu
                .buttonStyle(.glassProminent)
                .accessibilityLabel("Assistant Persona")
                .accessibilityValue(HomeAssistantPersonaCatalog.profile(for: selectedPersonaID).displayName)
        } else {
            baseMenu
                .buttonStyle(.plain)
                .accessibilityLabel("Assistant Persona")
                .accessibilityValue(HomeAssistantPersonaCatalog.profile(for: selectedPersonaID).displayName)
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suggested Questions")
                .font(.subheadline.weight(.semibold))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(engine.defaultSuggestions()) { suggestion in
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

    @ViewBuilder
    private var followUpSection: some View {
        if let latestAnswer = answers.last {
            let followUps = personaFormatter.followUpSuggestions(
                after: latestAnswer,
                personaID: selectedPersonaID
            )

            if followUps.isEmpty == false {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Follow-Up")
                        .font(.subheadline.weight(.semibold))

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(followUps) { suggestion in
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
        }
    }

    private var answersSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(answers) { answer in
                VStack(alignment: .leading, spacing: 10) {
                    if let userPrompt = answer.userPrompt, userPrompt.isEmpty == false {
                        userMessageBubble(text: userPrompt, generatedAt: answer.generatedAt)
                    }

                    assistantMessageBubble(for: answer)
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

    private func runQuery(_ query: HomeQuery, userPrompt: String?) {
        let rawAnswer = engine.execute(
            query: query,
            categories: categories,
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )

        let answer = personaFormatter.styledAnswer(
            from: rawAnswer,
            userPrompt: userPrompt,
            personaID: selectedPersonaID
        )

        appendAnswer(answer)
    }

    private func submitPrompt() {
        let prompt = trimmedPromptText
        guard prompt.isEmpty == false else { return }

        defer { promptText = "" }

        guard let query = parser.parse(prompt) else {
            appendAnswer(personaFormatter.unresolvedPromptAnswer(for: prompt, personaID: selectedPersonaID))
            return
        }

        runQuery(query, userPrompt: prompt)
    }

    private func appendAnswer(_ answer: HomeAnswer) {
        answers.append(answer)
        conversationStore.saveAnswers(answers, workspaceID: workspace.id)
    }

    private func selectPersona(_ personaID: HomeAssistantPersonaID) {
        guard personaID != selectedPersonaID else { return }

        let previousPersonaID = selectedPersonaID
        selectedPersonaID = personaID
        personaStore.saveSelectedPersona(personaID)
        appendAnswer(
            personaFormatter.personaDidChangeAnswer(
                from: previousPersonaID,
                to: personaID
            )
        )
    }

    private func loadConversationIfNeeded() {
        guard hasLoadedConversation == false else { return }
        selectedPersonaID = personaStore.loadSelectedPersona()
        answers = conversationStore.loadAnswers(workspaceID: workspace.id)

        if answers.isEmpty && conversationStore.hasGreetedPersona(selectedPersonaID, workspaceID: workspace.id) == false {
            answers.append(personaFormatter.greetingAnswer(for: selectedPersonaID))
            conversationStore.markPersonaAsGreeted(selectedPersonaID, workspaceID: workspace.id)
            conversationStore.saveAnswers(answers, workspaceID: workspace.id)
        }

        hasLoadedConversation = true
    }

    private func clearConversation() {
        answers.removeAll()
        conversationStore.saveAnswers([], workspaceID: workspace.id)
    }

    private var trimmedPromptText: String {
        promptText.trimmingCharacters(in: .whitespacesAndNewlines)
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
