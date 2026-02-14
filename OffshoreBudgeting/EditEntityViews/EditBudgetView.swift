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

    // MARK: - Form State

    @State private var name: String = ""
    @State private var userEditedName: Bool = true

    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var endDate: Date = Calendar.current.startOfDay(for: Date())

    @State private var selectedCardIDs: Set<UUID> = []
    @State private var selectedPresetIDs: Set<UUID> = []

    // MARK: - Alerts

    @State private var showingInvalidDatesAlert: Bool = false

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
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        guard !trimmedName.isEmpty else { return false }
        return startDate <= endDate
    }

    var body: some View {
        BudgetFormView(
            modeTitle: "Edit Budget",
            cards: cards,
            presets: presets,
            scheduleString: scheduleString(for:),
            name: $name,
            userEditedName: $userEditedName,
            startDate: $startDate,
            endDate: $endDate,
            selectedCardIDs: $selectedCardIDs,
            selectedPresetIDs: $selectedPresetIDs,
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
                        .controlSize(.large)
                        .buttonStyle(.glassProminent)
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
        .alert("Invalid Dates", isPresented: $showingInvalidDatesAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Start date must be on or before the end date.")
        }
        .onAppear {
            seedFromBudget()
        }
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
        if presets.isEmpty { return }

        if selectedPresetIDs.count == presets.count {
            selectedPresetIDs.removeAll()
        } else {
            selectedPresetIDs = Set(presets.map { $0.id })
        }
    }

    // MARK: - Save

    private func save() {
        guard startDate <= endDate else {
            showingInvalidDatesAlert = true
            return
        }

        budget.name = trimmedName
        budget.startDate = startDate
        budget.endDate = endDate

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
        let presetsToRemove = currentPresetIDs.subtracting(selectedPresetIDs)
        let presetsToAdd = selectedPresetIDs.subtracting(currentPresetIDs)

        for link in budget.presetLinks ?? [] {
            if let presetID = link.preset?.id, presetsToRemove.contains(presetID) {
                modelContext.delete(link)
            }
        }

        for preset in presets where presetsToAdd.contains(preset.id) {
            modelContext.insert(BudgetPresetLink(budget: budget, preset: preset))
        }

        // Reconcile generated planned expenses based on new:
        // - budget dates
        // - selected presets
        // - selected cards
        let selectedPresets = presets.filter { selectedPresetIDs.contains($0.id) }
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
                    modelContext.delete(expense)
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
        switch preset.frequency {
        case .none:
            return "None"

        case .daily:
            return preset.interval == 1 ? "Daily" : "Every \(localizedInt(preset.interval)) days"

        case .weekly:
            let day = weekdayName(preset.weeklyWeekday)
            return preset.interval == 1 ? "Weekly • \(day)" : "Every \(localizedInt(preset.interval)) weeks • \(day)"

        case .monthly:
            if preset.monthlyIsLastDay {
                return preset.interval == 1 ? "Monthly • Last day" : "Every \(localizedInt(preset.interval)) months • Last day"
            } else {
                let day = ordinalDay(preset.monthlyDayOfMonth)
                return preset.interval == 1 ? "Monthly • \(day)" : "Every \(localizedInt(preset.interval)) months • \(day)"
            }

        case .yearly:
            let month = monthName(preset.yearlyMonth)
            let day = ordinalDay(preset.yearlyDayOfMonth)
            return preset.interval == 1 ? "Yearly • \(month) \(day)" : "Every \(localizedInt(preset.interval)) years • \(month) \(day)"
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        let clamped = min(7, max(1, weekday))
        return Calendar.current.weekdaySymbols[clamped - 1]
    }

    private func monthName(_ month: Int) -> String {
        let clamped = min(12, max(1, month))
        return Calendar.current.monthSymbols[clamped - 1]
    }

    private func ordinalDay(_ day: Int) -> String {
        let clamped = min(31, max(1, day))
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: clamped)) ?? localizedInt(clamped)
    }

    private func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }
}
