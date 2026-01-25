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

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(!canSave)
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
        userEditedName = true

        startDate = Calendar.current.startOfDay(for: budget.startDate)
        endDate = Calendar.current.startOfDay(for: budget.endDate)

        selectedCardIDs = Set((budget.cardLinks ?? []).compactMap { $0.card?.id })
        selectedPresetIDs = Set((budget.presetLinks ?? []).compactMap { $0.preset?.id })
    }

    // MARK: - Date handling

    private func handleStartDateChanged(_ newValue: Date) {
        if endDate < newValue {
            endDate = newValue
        }
    }

    private func handleEndDateChanged(_ newValue: Date) {
        // no-op, but keeps symmetry and a hook for later if we want it.
        if newValue < startDate {
            endDate = startDate
        }
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

        try? modelContext.save()
        dismiss()
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
