//
//  AddBudgetView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct AddBudgetView: View {

    let workspace: Workspace
    let templateBudget: Budget?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]
    @Query private var presets: [Preset]
    @Query private var categories: [Category]

    // MARK: - Form State

    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

    @State private var name: String = ""
    @State private var userEditedName: Bool = false

    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var endDate: Date = Calendar.current.startOfDay(for: Date())

    @State private var selectedCardIDs: Set<UUID> = []
    @State private var selectedPresetIDs: Set<UUID> = []
    @State private var categoryGoalDrafts: [UUID: CategoryGoalDraft] = [:]
    @State private var didSeedForm: Bool = false

    @State private var repeatPeriodRaw = ""
    @State private var repeatInterval = 1
    @State private var repeatCount = 2
    @State private var manualEndDate: Date?
    @State private var userEditedEndDate = false
    @State private var batchPreview: BudgetBatchPreview?
    @State private var showingBatchPreview = false

    // MARK: - Alerts

    @State private var showingInvalidDatesAlert: Bool = false
    @State private var budgetSaveErrorMessage: String = ""
    @State private var showingBudgetSaveError: Bool = false

    init(workspace: Workspace, templateBudget: Budget? = nil) {
        self.workspace = workspace
        self.templateBudget = templateBudget
        let workspaceID = workspace.id

        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _presets = Query(
            filter: #Predicate<Preset> { $0.workspace?.id == workspaceID && $0.isArchived == false },
            sort: [SortDescriptor(\Preset.title, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )
    }

    private var goalCategories: [Category] {
        categories.filter { !$0.isArchived || (templateBudget != nil && categoryGoalDrafts[$0.id]?.hasValues == true) }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canCreate: Bool {
        guard !trimmedName.isEmpty else { return false }
        return startDate <= endDate && categoryGoalDrafts.values.allSatisfy(\.isValid)
    }

    var body: some View {
        BudgetFormView(
            modeTitle: "Add Budget",
            cards: cards,
            presets: presets,
            categories: goalCategories,
            scheduleString: scheduleString(for:),
            plannedGoalContributions: BudgetCategoryGoalStore.plannedContributions(
                presets: presets,
                selectedPresetIDs: selectedPresetIDs,
                selectedCardIDs: selectedCardIDs,
                workspaceID: workspace.id,
                startDate: startDate,
                endDate: endDate
            ),
            maximumGoalSuggestionProvider: workspace.categoryGoalAutoConfiguration.suggestMaximums
                ? { try loadMaximumSuggestions() } : nil,
            allowsRepeat: true,
            followingBudgets: templateBudget != nil,
            repeatPeriodRaw: $repeatPeriodRaw,
            repeatInterval: $repeatInterval,
            repeatCount: $repeatCount,
            name: $name,
            userEditedName: $userEditedName,
            startDate: $startDate,
            endDate: editableEndDate,
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
                    .clipShape(.containerRelative)
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(repeatPeriodRaw.isEmpty ? "Save" : "Preview") { submit() }
                        .disabled(!canCreate)
                        .tint(.accentColor)
                        .glassProminentButtonStyleCompat()
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(repeatPeriodRaw.isEmpty ? "Save" : "Preview") { submit() }
                        .disabled(!canCreate)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            guard !didSeedForm else { return }
            didSeedForm = true
            if let templateBudget {
                seedFollowingBudgets(from: templateBudget)
            } else {
                seedInitialDatesAndName()
                applyScreenshotPrefillIfNeeded()
            }
        }
        .onChange(of: defaultBudgetingPeriodRaw) { _, _ in
            guard templateBudget == nil, !userEditedEndDate else { return }
            applyDefaultPeriodRange()
            updateCycleEndDate()
            autoFillNameIfNeeded()
        }
        .onChange(of: repeatPeriodRaw) { oldValue, newValue in
            if oldValue.isEmpty && !newValue.isEmpty { manualEndDate = endDate }
            if newValue.isEmpty {
                if !userEditedEndDate { endDate = max(startDate, manualEndDate ?? endDate) }
                manualEndDate = nil
                autoFillNameIfNeeded()
            } else {
                updateCycleEndDate()
            }
        }
        .onChange(of: repeatInterval) { _, _ in updateCycleEndDate() }
        .appSheet(isPresented: $showingBatchPreview) {
            if let batchPreview {
                NavigationStack {
                    BudgetBatchPreviewView(
                        workspace: workspace, preview: batchPreview,
                        cards: cards.filter { selectedCardIDs.contains($0.id) },
                        presets: presets.filter { selectedPresetIDs.contains($0.id) },
                        categories: categories, categoryGoalDrafts: categoryGoalDrafts,
                        excludedArchivedPresetNames: excludedArchivedPresetNames
                    ) {
                        showingBatchPreview = false
                        dismiss()
                    }
                }
            }
        }
        .blocksAutomaticExpenseReview(while: showingInvalidDatesAlert)
        .alert("Invalid Dates", isPresented: $showingInvalidDatesAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Start date must be on or before the end date.")
        }
        .blocksAutomaticExpenseReview(while: showingBudgetSaveError)
        .alert("Couldn’t Save Budget", isPresented: $showingBudgetSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(budgetSaveErrorMessage)
        }
    }

    /// Fetch history only when Auto-Configure is requested, never during form rendering.
    private func loadMaximumSuggestions() throws -> [UUID: CategoryGoalSuggestion] {
        try BudgetCategoryGoalStore.maximumSuggestions(
            workspace: workspace, categories: CategoryArchivePolicy.activeCategories(from: categories),
            startDate: startDate, endDate: endDate, modelContext: modelContext
        )
    }

    // MARK: - Setup

    private func seedInitialDatesAndName() {
        userEditedName = false
        applyDefaultPeriodRange()
        autoFillNameIfNeeded(force: true)
    }

    private func applyScreenshotPrefillIfNeeded() {
        guard DebugScreenshotFormDefaults.isEnabled else { return }
        guard selectedCardIDs.isEmpty else { return }

        if let preferredCardID = DebugScreenshotFormDefaults.preferredCardID(in: cards) {
            selectedCardIDs.insert(preferredCardID)
        } else {
            selectedCardIDs = Set(cards.prefix(1).map { $0.id })
        }

        if selectedPresetIDs.isEmpty {
            if let firstPresetID = presets.first?.id {
                selectedPresetIDs.insert(firstPresetID)
            }
        }
    }

    private func applyDefaultPeriodRange() {
        let now = Date()
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let range = period.defaultRange(containing: now, calendar: .current)
        startDate = range.start
        endDate = range.end
    }

    // Only picker writes mark the date as manual; cycle suggestions do not.
    private var editableEndDate: Binding<Date> {
        Binding(
            get: { endDate },
            set: { newValue in
                guard newValue != endDate else { return }
                userEditedEndDate = true
                endDate = max(startDate, newValue)
            }
        )
    }

    private func handleStartDateChanged(_ newValue: Date) {
        updateCycleEndDate()
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

    private func autoFillNameIfNeeded(force: Bool = false) {
        guard force || !userEditedName else { return }
        name = BudgetNameSuggestion.suggestedName(start: startDate, end: endDate, calendar: .current)
    }

    // MARK: - Toggle Helpers

    private func toggleAllCards() {
        if cards.isEmpty { return }

        if selectedCardIDs.count == cards.count {
            selectedCardIDs.removeAll()
        } else {
            selectedCardIDs = Set(cards.map { $0.id })
        }
    }

    private func toggleAllPresets() {
        if presets.isEmpty { return }

        if selectedPresetIDs.count == presets.count {
            selectedPresetIDs.removeAll()
        } else {
            selectedPresetIDs = Set(presets.map { $0.id })
        }
    }

    private var excludedArchivedPresetNames: [String] {
        (templateBudget?.presetLinks ?? []).compactMap { $0.preset }
            .filter { $0.workspace?.id == workspace.id && $0.isArchived }
            .map(\.title).sorted()
    }

    private func seedFollowingBudgets(from template: Budget) {
        guard template.workspace?.id == workspace.id else { return }
        startDate = Calendar.current.date(byAdding: .day, value: 1,
            to: Calendar.current.startOfDay(for: template.endDate)) ?? template.endDate
        endDate = startDate
        name = template.name
        userEditedName = template.name != BudgetNameSuggestion.suggestedName(
            start: template.startDate, end: template.endDate, calendar: .current
        )
        selectedCardIDs = Set((template.cardLinks ?? []).compactMap { $0.card }
            .filter { $0.workspace?.id == workspace.id }.map(\.id))
        selectedPresetIDs = Set((template.presetLinks ?? []).compactMap { $0.preset }
            .filter { $0.workspace?.id == workspace.id && !$0.isArchived }.map(\.id))
        categoryGoalDrafts = BudgetCategoryGoalStore.drafts(for: template)
        repeatPeriodRaw = (BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly).rawValue
        updateCycleEndDate()
    }

    private func updateCycleEndDate() {
        guard !userEditedEndDate,
              let period = BudgetingPeriod(rawValue: repeatPeriodRaw),
              let range = try? BudgetCycleCalculator.ranges(
                startDate: startDate, period: period, interval: repeatInterval, count: 1
              ).first else { return }
        endDate = range.endDate
        autoFillNameIfNeeded()
    }

    private func submit() {
        guard !repeatPeriodRaw.isEmpty else { createBudget(); return }
        do {
            guard let period = BudgetingPeriod(rawValue: repeatPeriodRaw) else { return }
            let ranges = try BudgetCycleCalculator.ranges(
                startDate: startDate, period: period, interval: repeatInterval, count: repeatCount,
                firstPeriodEndDate: userEditedEndDate ? endDate : nil
            )
            batchPreview = try BudgetBatchCreationService.preview(
                workspace: workspace, ranges: ranges, templateName: trimmedName,
                customName: trimmedName != BudgetNameSuggestion.suggestedName(
                    start: startDate, end: endDate, calendar: .current
                ), preserveFirstName: templateBudget == nil,
                presets: presets.filter { selectedPresetIDs.contains($0.id) }, modelContext: modelContext
            )
            showingBatchPreview = true
        } catch {
            budgetSaveErrorMessage = error.localizedDescription
            showingBudgetSaveError = true
        }
    }

    // MARK: - Create

    private func createBudget() {
        guard categoryGoalDrafts.values.allSatisfy(\.isValid) else { return }
        guard startDate <= endDate else {
            showingInvalidDatesAlert = true
            return
        }

        let budget = Budget(
            name: trimmedName,
            startDate: startDate,
            endDate: endDate,
            workspace: workspace
        )

        modelContext.insert(budget)
        BudgetCategoryGoalStore.apply(
            categoryGoalDrafts,
            categories: categories,
            budget: budget,
            workspaceID: workspace.id,
            modelContext: modelContext
        )

        // Link selected cards
        for card in cards where selectedCardIDs.contains(card.id) {
            let link = BudgetCardLink(budget: budget, card: card)
            modelContext.insert(link)
        }

        // Link selected presets
        let selectedPresets = presets.filter { selectedPresetIDs.contains($0.id) && $0.isArchived == false }
        for preset in selectedPresets {
            let link = BudgetPresetLink(budget: budget, preset: preset)
            modelContext.insert(link)
        }

        // Materialize: presets -> planned expenses (inside this budget window)
        let createdPlannedExpenses = materializePlannedExpenses(
            for: budget,
            selectedPresets: selectedPresets,
            selectedCardIDs: selectedCardIDs
        )

        do {
            try WorkspaceProgressService.saveCompleting([.budget], in: workspace) {
                try modelContext.save()
            }
        } catch {
            // Discard only this failed creation attempt. A context-wide rollback
            // could discard unrelated changes made elsewhere in the app.
            BudgetCreationAttemptCleanup.discard(
                budget: budget,
                createdPlannedExpenses: createdPlannedExpenses,
                modelContext: modelContext
            )
            budgetSaveErrorMessage = error.localizedDescription
            showingBudgetSaveError = true
            return
        }

        Task {
            await LocalNotificationService.syncFromUserDefaultsIfPossible(
                modelContext: modelContext,
                workspaceID: workspace.id
            )
        }

        dismiss()
    }

    private func materializePlannedExpenses(
        for budget: Budget,
        selectedPresets: [Preset],
        selectedCardIDs: Set<UUID>
    ) -> [PlannedExpense] {
        var created: [PlannedExpense] = []
        // Budget-anchored recurrence
        for preset in selectedPresets {
            let dates = PresetScheduleEngine.occurrences(for: preset, in: budget)

            // Only attach the default card if it's being tracked by this budget.
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
                created.append(planned)
            }
        }
        return created
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

#Preview("Add Budget") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            AddBudgetView(workspace: ws)
        }
    }
}
