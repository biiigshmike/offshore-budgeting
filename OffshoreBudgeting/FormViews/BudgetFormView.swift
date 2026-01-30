//
//  BudgetFormView.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/22/26.
//

import SwiftUI

struct BudgetFormView: View {

    // MARK: - Inputs

    let modeTitle: String

    let cards: [Card]
    let presets: [Preset]

    let scheduleString: (Preset) -> String

    // MARK: - Bindings

    @Binding var name: String
    @Binding var userEditedName: Bool

    @Binding var startDate: Date
    @Binding var endDate: Date

    @Binding var selectedCardIDs: Set<UUID>
    @Binding var selectedPresetIDs: Set<UUID>

    // MARK: - Actions

    let onToggleAllCards: () -> Void
    let onToggleAllPresets: () -> Void
    let onStartDateChanged: (Date) -> Void
    let onEndDateChanged: (Date) -> Void

    // MARK: - Body

    var body: some View {
        Form {

            Section("Name") {
                TextField(
                    "January 2026",
                    text: $name,
                    onEditingChanged: { isEditing in
                        if isEditing {
                            userEditedName = true
                        }
                    }
                )
            }

            Section("Dates") {
                HStack(spacing: 12) {
                    Spacer(minLength: 0)

                    PillDatePickerField(title: "Start Date", date: $startDate)
                    PillDatePickerField(title: "End Date", date: $endDate)

                    Spacer(minLength: 0)
                }
                .onChange(of: startDate) { _, newValue in
                    onStartDateChanged(newValue)
                }
                .onChange(of: endDate) { _, newValue in
                    onEndDateChanged(newValue)
                }
            }

            Section("Cards to Track") {
                if #available(iOS 26.0, *) {
                    Button {
                        onToggleAllCards()
                    } label: {
                        Text(selectedCardIDs.count == cards.count && !cards.isEmpty ? "Clear All" : "Toggle All")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(cards.isEmpty)
                } else {
                    Button {
                        onToggleAllCards()
                    } label: {
                        Text(selectedCardIDs.count == cards.count && !cards.isEmpty ? "Clear All" : "Toggle All")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(cards.isEmpty)
                }
                
                ForEach(cards) { card in
                    Toggle(isOn: bindingForCard(card)) {
                        Text(card.name)
                    }
                }

                if cards.isEmpty {
                    Text("No cards yet. Create a card first.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Preset Planned Expenses") {
                if #available(iOS 26.0, *) {
                    Button {
                        onToggleAllPresets()
                    } label: {
                        Text(selectedPresetIDs.count == presets.count && !presets.isEmpty ? "Clear All" : "Toggle All")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(presets.isEmpty)
                } else {
                    Button {
                        onToggleAllPresets()
                    } label: {
                        Text(selectedPresetIDs.count == presets.count && !presets.isEmpty ? "Clear All" : "Toggle All")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(presets.isEmpty)
                }

                ForEach(presets) { preset in
                    Toggle(isOn: bindingForPreset(preset)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.title)

                            HStack(spacing: 8) {
                                Text(preset.plannedAmount, format: CurrencyFormatter.currencyStyle())
                                Text("•")
                                Text(scheduleString(preset))
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                if presets.isEmpty {
                    Text("No presets yet. Create a preset first.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(modeTitle)
    }

    // MARK: - Bindings

    private func bindingForCard(_ card: Card) -> Binding<Bool> {
        Binding(
            get: { selectedCardIDs.contains(card.id) },
            set: { newValue in
                if newValue {
                    selectedCardIDs.insert(card.id)
                } else {
                    selectedCardIDs.remove(card.id)
                }
            }
        )
    }

    private func bindingForPreset(_ preset: Preset) -> Binding<Bool> {
        Binding(
            get: { selectedPresetIDs.contains(preset.id) },
            set: { newValue in
                if newValue {
                    selectedPresetIDs.insert(preset.id)
                } else {
                    selectedPresetIDs.remove(preset.id)
                }
            }
        )
    }
}
