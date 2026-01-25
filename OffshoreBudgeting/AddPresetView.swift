//
//  AddPresetView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/20/26.
//

import SwiftUI
import SwiftData

struct AddPresetView: View {

    let workspace: Workspace

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]
    @Query private var categories: [Category]

    // MARK: - Form State

    @State private var title: String = ""
    @State private var plannedAmountText: String = ""

    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var interval: Int = 1

    @State private var weeklyWeekday: Int = 6 // Friday
    @State private var monthlyDayOfMonth: Int = 15
    @State private var monthlyIsLastDay: Bool = false
    @State private var yearlyMonth: Int = 1
    @State private var yearlyDayOfMonth: Int = 15

    @State private var selectedCardID: UUID? = nil
    @State private var selectedCategoryID: UUID? = nil

    // MARK: - Alerts

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id

        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )
    }

    private var trimmedTitle: String {
        PresetFormView.trimmedTitle(title)
    }

    private var parsedPlannedAmount: Double? {
        PresetFormView.parsePlannedAmount(plannedAmountText)
    }

    private var canSave: Bool {
        PresetFormView.canSave(
            title: title,
            plannedAmountText: plannedAmountText,
            selectedCardID: selectedCardID,
            hasAtLeastOneCard: !cards.isEmpty
        )
    }

    var body: some View {
        PresetFormView(
            workspace: workspace,
            cards: cards,
            categories: categories,
            title: $title,
            plannedAmountText: $plannedAmountText,
            frequency: $frequency,
            interval: $interval,
            weeklyWeekday: $weeklyWeekday,
            monthlyDayOfMonth: $monthlyDayOfMonth,
            monthlyIsLastDay: $monthlyIsLastDay,
            yearlyMonth: $yearlyMonth,
            yearlyDayOfMonth: $yearlyDayOfMonth,
            selectedCardID: $selectedCardID,
            selectedCategoryID: $selectedCategoryID
        )
        .navigationTitle("Add Preset")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { save() }
                    .disabled(!canSave)
            }
        }
        .alert("Invalid Amount", isPresented: $showingInvalidAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter a planned amount greater than 0.")
        }
        .alert("Select a Card", isPresented: $showingMissingCardAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Choose a default card for this preset.")
        }
    }

    private func save() {
        guard !trimmedTitle.isEmpty else { return }
        guard let amt = parsedPlannedAmount, amt > 0 else {
            showingInvalidAmountAlert = true
            return
        }

        guard let selectedCard = cards.first(where: { $0.id == selectedCardID }) else {
            showingMissingCardAlert = true
            return
        }
        let selectedCategory = categories.first(where: { $0.id == selectedCategoryID })

        let preset = Preset(
            title: trimmedTitle,
            plannedAmount: amt,
            frequencyRaw: frequency.rawValue,
            interval: interval,
            weeklyWeekday: weeklyWeekday,
            monthlyDayOfMonth: monthlyDayOfMonth,
            monthlyIsLastDay: monthlyIsLastDay,
            yearlyMonth: yearlyMonth,
            yearlyDayOfMonth: yearlyDayOfMonth,
            workspace: workspace,
            defaultCard: selectedCard,
            defaultCategory: selectedCategory
        )

        modelContext.insert(preset)
        dismiss()
    }
}
