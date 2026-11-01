import SwiftUI

/// Shared, cancelable editor for creation drafts and existing budget goals.
/// The caller decides when to persist the returned values.
struct CategoryGoalsEditorView: View {
    let categories: [Category]
    let plannedContributions: [UUID: Double]
    let variableContributions: [UUID: Double]
    let allowsPlannedMinimum: Bool
    let maximumSuggestionProvider: (() throws -> [UUID: CategoryGoalSuggestion])?
    let onSave: ([UUID: CategoryGoalDraft]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var autoConfigure = false
    @State private var generatedValues = CategoryGoalAutoConfigurationDraft()
    @State private var maximumSuggestions: [UUID: CategoryGoalSuggestion] = [:]
    @State private var showingHistoryError = false
    @State private var drafts: [UUID: CategoryGoalDraft]

    init(
        categories: [Category],
        drafts: [UUID: CategoryGoalDraft],
        plannedContributions: [UUID: Double] = [:],
        variableContributions: [UUID: Double] = [:],
        allowsPlannedMinimum: Bool = false,
        maximumSuggestionProvider: (() throws -> [UUID: CategoryGoalSuggestion])? = nil,
        onSave: @escaping ([UUID: CategoryGoalDraft]) -> Void
    ) {
        self.categories = categories
        self.plannedContributions = plannedContributions
        self.variableContributions = variableContributions
        self.allowsPlannedMinimum = allowsPlannedMinimum
        self.maximumSuggestionProvider = maximumSuggestionProvider
        self.onSave = onSave
        _drafts = State(initialValue: drafts)
    }

    var body: some View {
        NavigationStack {
            List {
                if allowsPlannedMinimum {
                    Section {
                        Toggle("Auto-Configure", isOn: $autoConfigure)
                            .accessibilityIdentifier("categoryGoals.autoConfigure")
                            .onChange(of: autoConfigure) { _, enabled in
                                configureGoals(enabled: enabled)
                            }
                    } footer: {
                        Text("Sets minimums from attached presets assigned to selected cards within the budget dates. When Suggest Maximums is enabled in Manage Categories, fills blank maximums from comparable budget history. You can edit every amount. Turning this off restores generated values unless you edited them.")
                        Text("For categories without preset spending, blank minimums use the lowest comparable historical spending, including zero. Historical suggestions require Suggest Maximums to be enabled.")
                    }
                }
                Section {
                    ForEach(categories) { category in
                        NavigationLink {
                            CategoryGoalDraftEditorView(
                                category: category,
                                draft: draftBinding(for: category.id),
                                plannedContribution: plannedContributions[category.id] ?? 0,
                                variableContribution: variableContributions[category.id] ?? 0,
                                maximumSuggestion: maximumSuggestions[category.id],
                                showsMaximumSuggestion: autoConfigure && maximumSuggestionProvider != nil
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: category.hexColor) ?? .secondary)
                                        .frame(width: 12, height: 12)
                                        .accessibilityHidden(true)
                                    Text(category.name)
                                }
                                goalSummary(for: category.id)
                                if autoConfigure, maximumSuggestionProvider != nil {
                                    if let suggestion = maximumSuggestions[category.id] {
                                        Group {
                                            if suggestion.samples.count == 1 {
                                                Text("History: 1 past budget · \(suggestion.cushionPercent / 100, format: .percent.precision(.fractionLength(0))) cushion")
                                            } else {
                                                Text("History: \(suggestion.samples.count) past budgets · \(suggestion.cushionPercent / 100, format: .percent.precision(.fractionLength(0))) cushion")
                                            }
                                        }
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                    } else {
                                        Text("No comparable category history")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                } footer: {
                    Text("Goals apply only to this budget. Leave either amount blank if you don't want that goal.")
                    Text("Maximums also power Savings at Goal Maximums in Budget Detail and Category Availability on Home.")
                }
                Section {
                    HelpTopicLink(topicID: "budgets-category-goals", title: "Category Goals guide", font: .body)
                }
            }
            .overlay {
                if categories.isEmpty {
                    ContentUnavailableView(
                        "No Categories Yet",
                        systemImage: "tag",
                        description: Text("Create a category in Settings to set spending goals.")
                    )
                }
            }
            .navigationTitle("Category Goals")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Couldn’t Load Budget History", isPresented: $showingHistoryError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Minimums are still configured from your presets. Maximums were left unchanged. Turn Auto-Configure off and on to try again.")
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(drafts)
                        dismiss()
                    }
                    .disabled(!drafts.values.allSatisfy(\.isValid))
                }
            }
        }
    }

    @ViewBuilder
    private func goalSummary(for categoryID: UUID) -> some View {
        if let draft = drafts[categoryID], let message = draft.validationMessage {
            Text(message).font(.footnote).foregroundStyle(.red)
        } else if let draft = drafts[categoryID], draft.hasValues {
            HStack(spacing: 12) {
                if let minimum = draft.minimum {
                    LabeledContent("Min", value: CurrencyFormatter.string(from: minimum))
                }
                if let maximum = draft.maximum {
                    LabeledContent("Max", value: CurrencyFormatter.string(from: maximum))
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        } else {
            Text("No goals set").font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func configureGoals(enabled: Bool) {
        if enabled {
            do {
                maximumSuggestions = try maximumSuggestionProvider?() ?? [:]
            } catch {
                maximumSuggestions = [:]
                showingHistoryError = true
            }
            generatedValues.apply(
                to: &drafts,
                categoryIDs: categories.map(\.id),
                plannedContributions: plannedContributions,
                suggestions: maximumSuggestions
            )
        } else {
            generatedValues.restore(in: &drafts)
            maximumSuggestions = [:]
        }
    }

    private func draftBinding(for categoryID: UUID) -> Binding<CategoryGoalDraft> {
        Binding(
            get: { drafts[categoryID] ?? CategoryGoalDraft() },
            set: { drafts[categoryID] = $0 }
        )
    }
}
