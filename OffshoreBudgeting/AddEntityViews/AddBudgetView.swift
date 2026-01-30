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

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]
    @Query private var presets: [Preset]

    // MARK: - Form State

    @AppStorage("general_defaultBudgetingPeriod")
    private var defaultBudgetingPeriodRaw: String = BudgetingPeriod.monthly.rawValue

    @State private var name: String = ""
    @State private var userEditedName: Bool = false

    @State private var startDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var endDate: Date = Calendar.current.startOfDay(for: Date())

    @State private var selectedCardIDs: Set<UUID> = []
    @State private var selectedPresetIDs: Set<UUID> = []

    // MARK: - Alerts

    @State private var showingInvalidDatesAlert: Bool = false

    init(workspace: Workspace) {
        self.workspace = workspace
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

    private var canCreate: Bool {
        guard !trimmedName.isEmpty else { return false }
        return startDate <= endDate
    }

    var body: some View {
        BudgetFormView(
            modeTitle: "Add Budget",
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
                    .clipShape(.containerRelative)
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { createBudget() }
                        .disabled(!canCreate)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.glassProminent)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { createBudget() }
                        .disabled(!canCreate)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            seedInitialDatesAndName()
        }
        .onChange(of: defaultBudgetingPeriodRaw) { _, _ in
            applyDefaultPeriodRange()
            autoFillNameIfNeeded()
        }
        .alert("Invalid Dates", isPresented: $showingInvalidDatesAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Start date must be on or before the end date.")
        }
    }

    // MARK: - Setup

    private func seedInitialDatesAndName() {
        userEditedName = false
        applyDefaultPeriodRange()
        autoFillNameIfNeeded(force: true)
    }

    private func applyDefaultPeriodRange() {
        let now = Date()
        let period = BudgetingPeriod(rawValue: defaultBudgetingPeriodRaw) ?? .monthly
        let range = period.defaultRange(containing: now, calendar: .current)
        startDate = range.start
        endDate = range.end
    }

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

    // MARK: - Create

    private func createBudget() {
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

        // Link selected cards
        for card in cards where selectedCardIDs.contains(card.id) {
            let link = BudgetCardLink(budget: budget, card: card)
            modelContext.insert(link)
        }

        // Link selected presets
        let selectedPresets = presets.filter { selectedPresetIDs.contains($0.id) }
        for preset in selectedPresets {
            let link = BudgetPresetLink(budget: budget, preset: preset)
            modelContext.insert(link)
        }

        // Materialize: presets -> planned expenses (inside this budget window)
        materializePlannedExpenses(
            for: budget,
            selectedPresets: selectedPresets,
            selectedCardIDs: selectedCardIDs
        )

        dismiss()
    }

    private func materializePlannedExpenses(
        for budget: Budget,
        selectedPresets: [Preset],
        selectedCardIDs: Set<UUID>
    ) {
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
            return preset.interval == 1 ? "Daily" : "Every \(preset.interval) days"

        case .weekly:
            let day = weekdayName(preset.weeklyWeekday)
            return preset.interval == 1 ? "Weekly • \(day)" : "Every \(preset.interval) weeks • \(day)"

        case .monthly:
            if preset.monthlyIsLastDay {
                return preset.interval == 1 ? "Monthly • Last day" : "Every \(preset.interval) months • Last day"
            } else {
                let day = ordinalDay(preset.monthlyDayOfMonth)
                return preset.interval == 1 ? "Monthly • \(day)" : "Every \(preset.interval) months • \(day)"
            }

        case .yearly:
            let month = monthName(preset.yearlyMonth)
            let day = ordinalDay(preset.yearlyDayOfMonth)
            return preset.interval == 1 ? "Yearly • \(month) \(day)" : "Every \(preset.interval) years • \(month) \(day)"
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
        return formatter.string(from: NSNumber(value: clamped)) ?? "\(clamped)"
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
