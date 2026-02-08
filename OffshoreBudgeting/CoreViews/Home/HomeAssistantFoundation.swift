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
                    .background(.thinMaterial, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var launcherLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "message")
                .font(.subheadline.weight(.semibold))

            Text("Ask about your budget")
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
                    Text("Assistant")
                        .font(.headline)

                    Text("Quick answers from your budgeting data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    personaSummarySection

                    inputSection

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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle("Assistant")
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
        .toolbarBackground(panelHeaderBackgroundStyle, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear {
            loadConversationIfNeeded()
        }

        if shouldUseLargeMinimumSize {
            content.frame(minWidth: 700, minHeight: 520)
        } else {
            content
        }
    }

    private var personaSummarySection: some View {
        let profile = HomeAssistantPersonaCatalog.profile(for: selectedPersonaID)

        return VStack(alignment: .leading, spacing: 4) {
            Text(profile.displayName)
                .font(.subheadline.weight(.semibold))
            Text(profile.summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask a Question")
                .font(.subheadline.weight(.semibold))

            HStack(spacing: 8) {
                TextField("Try: Top 3 categories this month", text: $promptText)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        submitPrompt()
                    }

                Button {
                    submitPrompt()
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .disabled(trimmedPromptText.isEmpty)
                .accessibilityLabel("Submit Question")
            }

            Button("Clear", role: .destructive) {
                clearConversation()
            }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(answers.isEmpty)
        }
    }

    @ViewBuilder
    private var personaTrailingNavBarItem: some View {
        let baseMenu = Menu {
            ForEach(HomeAssistantPersonaCatalog.allProfiles, id: \.id) { profile in
                Button {
                    selectPersona(profile.id)
                } label: {
                    if profile.id == selectedPersonaID {
                        Label(profile.displayName, systemImage: "checkmark")
                    } else {
                        Text(profile.displayName)
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
                HStack(spacing: 8) {
                    ForEach(engine.defaultSuggestions()) { suggestion in
                        Button(suggestion.title) {
                            runQuery(suggestion.query, userPrompt: suggestion.title)
                        }
                        .buttonStyle(.bordered)
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
                        HStack(spacing: 8) {
                            ForEach(followUps) { suggestion in
                                Button(suggestion.title) {
                                    runQuery(suggestion.query, userPrompt: suggestion.title)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
    }

    private var answersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(answers.reversed()) { answer in
                VStack(alignment: .leading, spacing: 8) {
                    if let userPrompt = answer.userPrompt, userPrompt.isEmpty == false {
                        HStack {
                            Spacer(minLength: 0)
                            Text(userPrompt)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
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
                    } label: {
                        Text(answer.title)
                            .font(.headline)
                    }
                }
            }
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
            return AnyShapeStyle(.bar)
        }
        #endif

        return AnyShapeStyle(.thinMaterial)
    }
}
