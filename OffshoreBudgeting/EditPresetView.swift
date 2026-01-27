//
//  EditPresetView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct EditPresetView: View {

    let workspace: Workspace
    let preset: Preset

    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]
    @Query private var categories: [Category]

    // MARK: - Form State

    @State private var title: String
    @State private var plannedAmountText: String

    @State private var frequency: RecurrenceFrequency
    @State private var interval: Int

    @State private var weeklyWeekday: Int
    @State private var monthlyDayOfMonth: Int
    @State private var monthlyIsLastDay: Bool
    @State private var yearlyMonth: Int
    @State private var yearlyDayOfMonth: Int

    @State private var selectedCardID: UUID?
    @State private var selectedCategoryID: UUID?

    // MARK: - Alerts

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false

    init(workspace: Workspace, preset: Preset) {
        self.workspace = workspace
        self.preset = preset

        let workspaceID = workspace.id
        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )

        // Prefill from the existing preset
        _title = State(initialValue: preset.title)
        _plannedAmountText = State(initialValue: CurrencyFormatter.editingString(from: preset.plannedAmount))

        _frequency = State(initialValue: preset.frequency)
        _interval = State(initialValue: max(1, preset.interval))

        _weeklyWeekday = State(initialValue: preset.weeklyWeekday)
        _monthlyDayOfMonth = State(initialValue: preset.monthlyDayOfMonth)
        _monthlyIsLastDay = State(initialValue: preset.monthlyIsLastDay)
        _yearlyMonth = State(initialValue: preset.yearlyMonth)
        _yearlyDayOfMonth = State(initialValue: preset.yearlyDayOfMonth)

        _selectedCardID = State(initialValue: preset.defaultCard?.id)
        _selectedCategoryID = State(initialValue: preset.defaultCategory?.id)
    }

    // MARK: - Shared Validation (via PresetFormView)

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
        .navigationTitle("Edit Preset")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { dismiss() }
            }
            if #available(iOS 26.0, *) {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveChanges() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.glassProminent)
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveChanges() }
                        .disabled(!canSave)
                        .tint(.accentColor)
                        .controlSize(.large)
                        .buttonStyle(.plain)
                }
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

    // MARK: - Actions

    private func saveChanges() {
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

        // Update existing model (do NOT insert a new one)
        preset.title = trimmedTitle
        preset.plannedAmount = amt

        preset.frequencyRaw = frequency.rawValue
        preset.interval = max(1, interval)

        preset.weeklyWeekday = min(7, max(1, weeklyWeekday))
        preset.monthlyDayOfMonth = min(31, max(1, monthlyDayOfMonth))
        preset.monthlyIsLastDay = monthlyIsLastDay

        preset.yearlyMonth = min(12, max(1, yearlyMonth))
        preset.yearlyDayOfMonth = min(31, max(1, yearlyDayOfMonth))

        preset.defaultCard = selectedCard
        preset.defaultCategory = selectedCategory

        dismiss()
    }
}

#Preview("Edit Preset") {
    let container = PreviewSeed.makeContainer()
    PreviewHost(container: container) { ws in
        NavigationStack {
            EditPresetPreview(workspace: ws)
        }
    }
}

private struct EditPresetPreview: View {
    let workspace: Workspace

    @Query private var presets: [Preset]

    init(workspace: Workspace) {
        self.workspace = workspace
        let workspaceID = workspace.id
        _presets = Query(
            filter: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Preset.title, order: .forward)]
        )
    }

    var body: some View {
        if let preset = presets.first {
            EditPresetView(workspace: workspace, preset: preset)
        } else {
            ContentUnavailableView(
                "No Preset Seeded",
                systemImage: "list.bullet.rectangle",
                description: Text("PreviewSeed.seedBasicData(in:) didn’t create a Preset.")
            )
        }
    }
}
