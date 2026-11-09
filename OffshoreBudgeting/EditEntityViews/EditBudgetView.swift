//
//  EditBudgetView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI
import SwiftData

struct EditBudgetView: View {

    let workspace: Workspace
    let budget: Budget

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]
    @Query private var presets: [Preset]
    @Query private var categories: [Category]

    // MARK: - Form State

    @State private var name: String = ""
    @State private var userEditedName: Bool = true

    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var endDate: Date = Calendar.current.startOfDay(for: Date())

    @State private var selectedCardIDs: Set<UUID> = []
    @State private var selectedPresetIDs: Set<UUID> = []
    @State private var categoryGoalDrafts: [UUID: CategoryGoalDraft] = [:]
    @State private var didSeedForm: Bool = false

    // MARK: - Alerts

    @State private var showingInvalidDatesAlert: Bool = false
    @State private var showingFollowingBudgets = false

    init(workspace: Workspace, budget: Budget) {
        self.workspace = workspace
        self.budget = budget

        let workspaceID = workspace.id

        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _presets = Query(
            filter: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Preset.title, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard !trimmedName.isEmpty else { return false }
        return startDate <= endDate && categoryGoalDrafts.values.allSatisfy(\.isValid)
    }

    private var linkedPresetIDs: Set<UUID> {
        Set((budget.presetLinks ?? []).compactMap { $0.preset?.id })
    }

    private var visiblePresets: [Preset] {
        let linkedIDs = linkedPresetIDs
        return presets.filter { preset in
            preset.isArchived == false || linkedIDs.contains(preset.id)
        }
    }

    private var goalCategories: [Category] {
        let existingCategoryIDs = Set((budget.categoryLimits ?? []).compactMap { $0.category?.id })
        return categories.filter { !$0.isArchived || existingCategoryIDs.contains($0.id) }
    }

    var body: some View {
        BudgetFormView(
            modeTitle: "Edit Budget",
            cards: cards,
            presets: visiblePresets,
            categories: goalCategories,
            scheduleString: scheduleString(for:),
            reconfiguresExistingGoals: true,
            plannedGoalContributions: BudgetCategoryGoalStore.plannedContributions(
                presets: presets, selectedPresetIDs: selectedPresetIDs, selectedCardIDs: selectedCardIDs,
                workspaceID: workspace.id, startDate: startDate, endDate: endDate
            ),
            maximumGoalSuggestionProvider: workspace.categoryGoalAutoConfiguration.suggestMaximums ? {
                try BudgetCategoryGoalStore.maximumSuggestions(
                    workspace: workspace, categories: goalCategories, startDate: startDate, endDate: endDate,
                    excludingBudgetID: budget.id, modelContext: modelContext
                )
            } : nil,
            repeatPeriodRaw: .constant(""),
            repeatInterval: .constant(1),
            repeatCount: .constant(2),
            onCreateFollowingBudgets: { showingFollowingBudgets = true },
            canCreateFollowingBudgets: didSeedForm && !hasUnsavedChanges,
            name: $name,
            userEditedName: $userEditedName,
            startDate: $startDate,
            endDate: $endDate,
            selectedCardIDs: $selectedCardIDs,
            selectedPresetIDs: $selectedPresetIDs,
            categoryGoalDrafts: $categoryGoalDrafts,
            onToggleAllCards: toggleAllCards,
            onToggleAllPresets: toggleAllPresets,
            onStartDateChanged: handleStartDateChanged(_:),
            onEndDateChanged: handleEndDateChanged(_:)
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .glassProminentButtonStyleCompat()
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }
            }
        }
        .appSheet(isPresented: $showingFollowingBudgets) {
            NavigationStack {
                AddBudgetView(workspace: workspace, templateBudget: budget)
            }
        }
        .blocksAutomaticExpenseReview(while: showingInvalidDatesAlert)
        .alert("Invalid Dates", isPresented: $showingInvalidDatesAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Start date must be on or before the end date.")
        }
        .onAppear {
            guard !didSeedForm else { return }
            didSeedForm = true
            seedFromBudget()
            applyScreenshotPrefillIfNeeded()
        }
    }

    private var hasUnsavedChanges: Bool {
        name != budget.name
            || startDate != Calendar.current.startOfDay(for: budget.startDate)
            || endDate != Calendar.current.startOfDay(for: budget.endDate)
            || selectedCardIDs != Set((budget.cardLinks ?? []).compactMap { $0.card?.id })
            || selectedPresetIDs != linkedPresetIDs
            || categoryGoalDrafts != BudgetCategoryGoalStore.drafts(for: budget)
    }

    // MARK: - Seed

    private func seedFromBudget() {
        name = budget.name

        startDate = Calendar.current.startOfDay(for: budget.startDate)
        endDate = Calendar.current.startOfDay(for: budget.endDate)

        let suggested = BudgetNameSuggestion.suggestedName(start: startDate, end: endDate, calendar: .current)
        userEditedName = trimmedName != suggested

        selectedCardIDs = Set((budget.cardLinks ?? []).compactMap { $0.card?.id })
        selectedPresetIDs = Set((budget.presetLinks ?? []).compactMap { $0.preset?.id })
        categoryGoalDrafts = BudgetCategoryGoalStore.drafts(for: budget)
    }

    private func applyScreenshotPrefillIfNeeded() {
        guard DebugScreenshotFormDefaults.isEnabled else { return }

        if trimmedName.isEmpty {
            name = BudgetNameSuggestion.suggestedName(start: startDate, end: endDate, calendar: .current)
        }

        if selectedCardIDs.isEmpty, let preferredCardID = DebugScreenshotFormDefaults.preferredCardID(in: cards) {
            selectedCardIDs.insert(preferredCardID)
        }

        if selectedPresetIDs.isEmpty, let firstPresetID = visiblePresets.first?.id {
            selectedPresetIDs.insert(firstPresetID)
        }
    }

    // MARK: - Date handling

    private func handleStartDateChanged(_ newValue: Date) {
        if endDate < newValue {
            endDate = newValue
        }
        autoFillNameIfNeeded()
    }

    private func handleEndDateChanged(_ newValue: Date) {
        if newValue < startDate {
            endDate = startDate
        }
        autoFillNameIfNeeded()
    }

    private func autoFillNameIfNeeded() {
        guard !userEditedName else { return }
        name = BudgetNameSuggestion.suggestedName(start: startDate, end: endDate, calendar: .current)
    }

    // MARK: - Toggle helpers

    private func toggleAllCards() {
        if cards.isEmpty { return }

        if selectedCardIDs.count == cards.count {
            selectedCardIDs.removeAll()
        } else {
            selectedCardIDs = Set(cards.map { $0.id })
        }
    }

    private func toggleAllPresets() {
        let visiblePresetIDs = Set(visiblePresets.map { $0.id })
        if visiblePresetIDs.isEmpty { return }

        if selectedPresetIDs.intersection(visiblePresetIDs).count == visiblePresetIDs.count {
            selectedPresetIDs.subtract(visiblePresetIDs)
        } else {
            selectedPresetIDs.formUnion(visiblePresetIDs)
        }
    }

    // MARK: - Save

    private func save() {
        guard budget.workspace?.id == workspace.id, categoryGoalDrafts.values.allSatisfy(\.isValid) else { return }
        guard startDate <= endDate else {
            showingInvalidDatesAlert = true
            return
        }

        budget.name = trimmedName
        budget.startDate = startDate
        budget.endDate = endDate
        BudgetCategoryGoalStore.apply(
            categoryGoalDrafts,
            categories: categories,
            budget: budget,
            workspaceID: workspace.id,
            modelContext: modelContext
        )

        // Update Card Links
        let currentCardIDs = Set((budget.cardLinks ?? []).compactMap { $0.card?.id })
        let toRemove = currentCardIDs.subtracting(selectedCardIDs)
        let toAdd = selectedCardIDs.subtracting(currentCardIDs)

        for link in budget.cardLinks ?? [] {
            if let cardID = link.card?.id, toRemove.contains(cardID) {
                modelContext.delete(link)
            }
        }

        for card in cards where toAdd.contains(card.id) {
            modelContext.insert(BudgetCardLink(budget: budget, card: card))
        }

        // Update Preset Links
        let currentPresetIDs = Set((budget.presetLinks ?? []).compactMap { $0.preset?.id })
        let allowedSelectedPresetIDs = Set(selectedPresetIDs.filter { selectedID in
            if currentPresetIDs.contains(selectedID) {
                return true
            }

            guard let preset = presets.first(where: { $0.id == selectedID }) else {
                return false
            }

            return preset.isArchived == false
        })
        let presetsToRemove = currentPresetIDs.subtracting(allowedSelectedPresetIDs)
        let presetsToAdd = allowedSelectedPresetIDs.subtracting(currentPresetIDs)

        for link in budget.presetLinks ?? [] {
            if let presetID = link.preset?.id, presetsToRemove.contains(presetID) {
                modelContext.delete(link)
            }
        }

        for preset in presets where presetsToAdd.contains(preset.id) && preset.isArchived == false {
            modelContext.insert(BudgetPresetLink(budget: budget, preset: preset))
        }

        // Reconcile generated planned expenses based on new:
        // - budget dates
        // - selected presets
        // - selected cards
        let selectedPresets = presets.filter { allowedSelectedPresetIDs.contains($0.id) }
        syncGeneratedPlannedExpenses(
            for: budget,
            selectedPresets: selectedPresets,
            selectedCardIDs: selectedCardIDs
        )

        try? modelContext.save()

        Task {
            await LocalNotificationService.syncFromUserDefaultsIfPossible(
                modelContext: modelContext,
                workspaceID: workspace.id
            )
        }

        dismiss()
    }

    // MARK: - PlannedExpense sync (budget-local generated rows)

    private func syncGeneratedPlannedExpenses(
        for budget: Budget,
        selectedPresets: [Preset],
        selectedCardIDs: Set<UUID>
    ) {
        let selectedPresetIDSet = Set(selectedPresets.map { $0.id })
        let windowStart = Calendar.current.startOfDay(for: budget.startDate)
        let windowEnd = Calendar.current.startOfDay(for: budget.endDate)

        // 1) Delete generated expenses that should no longer exist:
        //    - preset unselected
        //    - outside new date window
        //    - card no longer linked to this budget
        deleteGeneratedPlannedExpensesNotMatchingSelection(
            budgetID: budget.id,
            selectedPresetIDs: selectedPresetIDSet,
            windowStart: windowStart,
            windowEnd: windowEnd,
            selectedCardIDs: selectedCardIDs
        )

        // 2) Materialize missing occurrences for selected presets within the window.
        materializePlannedExpenses(
            for: budget,
            selectedPresets: selectedPresets,
            selectedCardIDs: selectedCardIDs
        )
    }

    private func deleteGeneratedPlannedExpensesNotMatchingSelection(
        budgetID: UUID,
        selectedPresetIDs: Set<UUID>,
        windowStart: Date,
        windowEnd: Date,
        selectedCardIDs: Set<UUID>
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
            // Intentionally ignore fetch errors for now.
        }
    }

    private func materializePlannedExpenses(
        for budget: Budget,
        selectedPresets: [Preset],
        selectedCardIDs: Set<UUID>
    ) {
        for preset in selectedPresets {
            let dates = PresetScheduleEngine.occurrences(for: preset, in: budget)

            let defaultCard: Card? = {
                guard let card = preset.defaultCard else { return nil }
                return selectedCardIDs.contains(card.id) ? card : nil
            }()

            for date in dates {
                if plannedExpenseExists(budgetID: budget.id, presetID: preset.id, date: date) {
                    continue
                }

                let planned = PlannedExpense(
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

                modelContext.insert(planned)
            }
        }
    }

    private func plannedExpenseExists(budgetID: UUID, presetID: UUID, date: Date) -> Bool {
        let day = Calendar.current.startOfDay(for: date)

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID &&
                expense.sourcePresetID == presetID &&
                expense.expenseDate == day
            }
        )

        do {
            let matches = try modelContext.fetch(descriptor)
            return !matches.isEmpty
        } catch {
            return false
        }
    }

    // MARK: - Display

    private func scheduleString(for preset: Preset) -> String {
        guard preset.interval > 1 else { return preset.frequency.displayName }
        switch preset.frequency {
        case .none:
            return preset.frequency.displayName
        case .daily:
            return String(localized: "Every \(localizedInt(preset.interval)) days")
        case .weekly:
            return String(localized: "Every \(localizedInt(preset.interval)) weeks")
        case .monthly:
            return String(localized: "Every \(localizedInt(preset.interval)) months")
        case .yearly:
            return String(localized: "Every \(localizedInt(preset.interval)) years")
        }
    }

    private func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }
}
