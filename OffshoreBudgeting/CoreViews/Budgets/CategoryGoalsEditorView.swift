import SwiftUI

/// Shared, cancelable editor for creation drafts and existing budget goals.
/// The caller decides when to persist the returned values.
struct CategoryGoalsEditorView: View {
    let categories: [Category]
    let plannedContributions: [UUID: Double]
    let variableContributions: [UUID: Double]
    let onSave: ([UUID: CategoryGoalDraft]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [UUID: CategoryGoalDraft]

    init(
        categories: [Category],
        drafts: [UUID: CategoryGoalDraft],
        plannedContributions: [UUID: Double] = [:],
        variableContributions: [UUID: Double] = [:],
        onSave: @escaping ([UUID: CategoryGoalDraft]) -> Void
    ) {
        self.categories = categories
        self.plannedContributions = plannedContributions
        self.variableContributions = variableContributions
        self.onSave = onSave
        _drafts = State(initialValue: drafts)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(categories) { category in
                        NavigationLink {
                            CategoryGoalDraftEditorView(
                                category: category,
                                draft: draftBinding(for: category.id),
                                plannedContribution: plannedContributions[category.id] ?? 0,
                                variableContribution: variableContributions[category.id] ?? 0
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
                            }
                        }
                    }
                } footer: {
                    Text("Goals apply only to this budget. Leave either amount blank if you don't want that goal.")
                }
                Section {
                    HelpTopicLink(topicID: "budgets-category-goals", title: "Category Goals guide")
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

    private func draftBinding(for categoryID: UUID) -> Binding<CategoryGoalDraft> {
        Binding(
            get: { drafts[categoryID] ?? CategoryGoalDraft() },
            set: { drafts[categoryID] = $0 }
        )
    }
}
