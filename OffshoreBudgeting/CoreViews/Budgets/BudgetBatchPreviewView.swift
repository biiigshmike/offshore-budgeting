import SwiftUI
import SwiftData

struct BudgetBatchPreviewView: View {
    let workspace: Workspace
    let preview: BudgetBatchPreview
    let cards: [Card]
    let presets: [Preset]
    let categories: [Category]
    let categoryGoalDrafts: [UUID: CategoryGoalDraft]
    let excludedArchivedPresetNames: [String]
    let onCreated: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isSaving = false
    @State private var showingOverlapConfirmation = false
    @State private var showingError = false
    @State private var errorMessage = ""

    var body: some View {
        List {
            Section {
                Text("\(preview.drafts.count) budgets")
                Text("\(preview.plannedExpenseCount) planned expenses")
                Text("Each budget is independent. Editing or deleting one will not change the others.")
                    .foregroundStyle(.secondary)
            }
            Section("Budgets to Create") {
                ForEach(Array(preview.drafts.enumerated()), id: \.offset) { _, draft in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.name).font(.headline)
                        Text("\(draft.startDate.formatted(date: .abbreviated, time: .omitted)) – \(draft.endDate.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if !excludedArchivedPresetNames.isEmpty {
                Section("Archived Presets Excluded") {
                    ForEach(Array(excludedArchivedPresetNames.enumerated()), id: \.offset) { _, name in
                        Text(name)
                    }
                }
            }
            if !preview.overlappingBudgetNames.isEmpty {
                Section("Overlapping Existing Budgets") {
                    ForEach(Array(preview.overlappingBudgetNames.enumerated()), id: \.offset) { _, name in
                        Text(name)
                    }
                    Text("These dates overlap existing budgets. Review the ranges before creating.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Preview")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    if dynamicTypeSize.isAccessibilitySize {
                        Label("Back", systemImage: "chevron.left").labelStyle(.iconOnly)
                    } else {
                        Text("Back")
                    }
                }
                .disabled(isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if preview.overlappingBudgetNames.isEmpty {
                        create(allowOverlaps: false)
                    } else {
                        showingOverlapConfirmation = true
                    }
                } label: {
                    if dynamicTypeSize.isAccessibilitySize {
                        Label("Create", systemImage: "checkmark").labelStyle(.iconOnly)
                    } else {
                        Text("Create")
                    }
                }
                .disabled(isSaving)
                .tint(.accentColor)
                .glassProminentButtonStyleCompat()
                .accessibilityIdentifier("budget.confirmBatch")
            }
        }
        .interactiveDismissDisabled(isSaving)
        .blocksAutomaticExpenseReview(while: showingOverlapConfirmation || showingError)
        .confirmationDialog("Create overlapping budgets?", isPresented: $showingOverlapConfirmation, titleVisibility: .visible) {
            Button("Create") { create(allowOverlaps: true) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The new budgets overlap existing budgets shown in the preview. Existing budgets will not be changed.")
        }
        .alert("Couldn’t Create Budgets", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func create(allowOverlaps: Bool) {
        guard !isSaving else { return }
        isSaving = true
        do {
            _ = try BudgetBatchCreationService.create(
                workspace: workspace, preview: preview, cards: cards, presets: presets,
                categories: categories, categoryGoalDrafts: categoryGoalDrafts,
                allowOverlaps: allowOverlaps, modelContext: modelContext
            )
            Task {
                await LocalNotificationService.syncFromUserDefaultsIfPossible(
                    modelContext: modelContext, workspaceID: workspace.id
                )
            }
            onCreated()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
            showingError = true
        }
    }
}
