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
    let categories: [Category]
    
    let scheduleString: (Preset) -> String
    var reconfiguresExistingGoals = false
    var plannedGoalContributions: [UUID: Double]? = nil
    var maximumGoalSuggestionProvider: (() throws -> [UUID: CategoryGoalSuggestion])? = nil
    
    var allowsRepeat = false
    var followingBudgets = false
    @Binding var repeatPeriodRaw: String
    @Binding var repeatInterval: Int
    @Binding var repeatCount: Int
    var onCreateFollowingBudgets: (() -> Void)? = nil
    var canCreateFollowingBudgets = false

    // MARK: - Multiple-selection menus

    private var cardsMenu: some View {
        Menu {
            Button(selectedCardIDs.count == cards.count ? "Clear All" : "Select All", action: onToggleAllCards)
                .menuActionDismissBehavior(.disabled)
            Divider()
            ForEach(cards) { card in
                Toggle(isOn: bindingForCard(card)) {
                    Label {
                        Text(card.name)
                    } icon: {
                        if let image = EntityMenuImageCache.card(
                            themeRaw: card.theme,
                            effectRaw: card.effect,
                            colorScheme: colorScheme,
                            scale: displayScale
                        ) {
                            Image(uiImage: image).renderingMode(.original)
                        } else {
                            Image(systemName: "creditcard")
                        }
                    }
                }
                .menuActionDismissBehavior(.disabled)
            }
        } label: {
            selectionMenuLabel("Cards") {
                if cards.isEmpty {
                    Text("No cards available")
                } else if selectedCardIDs.count == 1,
                          let card = cards.first(where: { selectedCardIDs.contains($0.id) }) {
                    CardMenuLabel(card: card)
                } else if selectedCardIDs.isEmpty {
                    Text("None selected")
                } else {
                    Text("\(selectedCardIDs.count) selected")
                }
            }
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .menuActionDismissBehavior(.disabled)
        .disabled(cards.isEmpty)
        .accessibilityIdentifier("budget.cards")
    }

    private var presetsMenu: some View {
        Menu {
            Button(selectedPresetIDs.count == presets.count ? "Clear All" : "Select All", action: onToggleAllPresets)
                .menuActionDismissBehavior(.disabled)
            Divider()
            ForEach(presets) { preset in
                Toggle(isOn: bindingForPreset(preset)) {
                    Text(verbatim: presetMenuTitle(preset))
                    Text(scheduleString(preset))
                }
                .menuActionDismissBehavior(.disabled)
            }
        } label: {
            selectionMenuLabel("Presets") {
                if presets.isEmpty {
                    Text("No presets available")
                } else if selectedPresetIDs.count == 1,
                          let preset = presets.first(where: { selectedPresetIDs.contains($0.id) }) {
                    Text(preset.title)
                } else if selectedPresetIDs.isEmpty {
                    Text("None selected")
                } else {
                    Text("\(selectedPresetIDs.count) selected")
                }
            }
        }
        .buttonStyle(.borderless)
        .menuIndicator(.hidden)
        .menuActionDismissBehavior(.disabled)
        .disabled(presets.isEmpty)
        .accessibilityIdentifier("budget.presets")
    }

    private func presetMenuTitle(_ preset: Preset) -> String {
        preset.isArchived
            ? "\(preset.title) (\(String(localized: "Archived")))"
            : preset.title
    }

    private func selectionMenuLabel<Summary: View>(
        _ title: LocalizedStringKey,
        @ViewBuilder summary: () -> Summary
    ) -> some View {
        let value = HStack(spacing: 8) {
            summary()
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(.primary).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
                value
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).foregroundStyle(.primary)
                value
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    // MARK: - Bindings
    
    @Binding var name: String
    @Binding var userEditedName: Bool
    
    @Binding var startDate: Date
    @Binding var endDate: Date
    
    @Binding var selectedCardIDs: Set<UUID>
    @Binding var selectedPresetIDs: Set<UUID>
    @Binding var categoryGoalDrafts: [UUID: CategoryGoalDraft]
    @Binding var categoryGoalAutoConfiguration: CategoryGoalAutoConfigurationDraft
    @State private var showingCategoryGoals: Bool = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale
    
    // MARK: - Actions
    
    let onToggleAllCards: () -> Void
    let onToggleAllPresets: () -> Void
    let onStartDateChanged: (Date) -> Void
    let onEndDateChanged: (Date) -> Void
    
    // MARK: - Body
    
    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField(
                        "January 2026",
                        text: $name,
                        onEditingChanged: { isEditing in
                            if isEditing { userEditedName = true }
                        }
                    )
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("budget.name")
                }

                LabeledContent("Start Date") {
                    if followingBudgets {
                        Text(startDate, format: .dateTime.month().day().year())
                    } else {
                        PillDatePickerField(title: "Start Date", date: $startDate)
                            .accessibilityIdentifier("budget.startDate")
                    }
                }
                .onChange(of: startDate) { _, newValue in
                    onStartDateChanged(newValue)
                }

                LabeledContent("End Date") {
                    PillDatePickerField(title: "End Date", date: $endDate)
                        .accessibilityIdentifier("budget.endDate")
                }
                .onChange(of: endDate) { _, newValue in
                    onEndDateChanged(newValue)
                }

                #if targetEnvironment(macCatalyst)
                BudgetSelectionChecklist(
                    title: "Cards",
                    items: cards,
                    selectedCount: selectedCardIDs.count,
                    accessibilityID: "budget.cards",
                    selection: bindingForCard,
                    onToggleAll: onToggleAllCards
                ) { card in
                    CardMenuLabel(card: card)
                }

                BudgetSelectionChecklist(
                    title: "Presets",
                    items: presets,
                    selectedCount: selectedPresetIDs.count,
                    accessibilityID: "budget.presets",
                    selection: bindingForPreset,
                    onToggleAll: onToggleAllPresets
                ) { preset in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(preset.title)
                            if preset.isArchived {
                                Text("Archived")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(scheduleString(preset))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                #else
                cardsMenu
                presetsMenu
                #endif

                Button {
                    showingCategoryGoals = true
                } label: {
                    HStack {
                        Text("Category Goals").foregroundStyle(.primary)
                        Spacer()
                        let count = categoryGoalDrafts.values.filter(\.hasValues).count
                        if count > 0 {
                            Text("\(count) configured").foregroundStyle(.secondary)
                        } else {
                            Text("Optional").foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                    }
                }
                .accessibilityIdentifier("budget.categoryGoals")
            } header: {
                Text("Budget")
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if cards.isEmpty {
                        Text("No cards yet. Create a card first.")
                    }
                    if presets.isEmpty {
                        Text("No presets yet. You can add them later.")
                    }
                    Text("Choose which presets to include. Offshore creates their planned expenses within this budget’s dates.")
                    Text("Set optional minimum and maximum spending goals for this budget. You can change them later.")
                }
            }
            if allowsRepeat {
                BudgetRepeatOptionsView(
                    periodRaw: $repeatPeriodRaw, interval: $repeatInterval, count: $repeatCount,
                    allowsNone: !followingBudgets, followingBudgets: followingBudgets
                )
            }
            if let onCreateFollowingBudgets {
                Section {
                    Button("Copy Budget Setup", action: onCreateFollowingBudgets)
                        .disabled(!canCreateFollowingBudgets)
                        .accessibilityIdentifier("budget.createFollowing")
                } footer: {
                    if !canCreateFollowingBudgets {
                        Text("Save or discard your changes before copying this budget’s setup.")
                    } else {
                        Text("Use this saved budget as a template for new, independent budgets.")
                    }
                }
            }
        }
        .navigationTitle(modeTitle)
        .appSheet(isPresented: $showingCategoryGoals) {
            CategoryGoalsEditorView(
                categories: categories,
                drafts: categoryGoalDrafts,
                plannedContributions: plannedGoalContributions ?? [:],
                allowsPlannedMinimum: plannedGoalContributions != nil,
                maximumSuggestionProvider: maximumGoalSuggestionProvider,
                replacesExistingGoals: reconfiguresExistingGoals,
                autoConfiguration: categoryGoalAutoConfiguration
            ) { updatedDrafts, autoConfiguration in
                categoryGoalDrafts = updatedDrafts
                categoryGoalAutoConfiguration = autoConfiguration
            }
        }
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
