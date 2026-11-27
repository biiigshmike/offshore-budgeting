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
    private let offersBudgetAfterSave: Bool
    private let offerBudgetID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query private var cards: [Card]
    @Query private var categories: [Category]
    @Query private var budgets: [Budget]

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

    @AppStorage("sort.cards.mode") private var cardsSortModeRaw: String = "az"
    @State private var selectedCardID: UUID? = nil
    @State private var selectedCategoryID: UUID? = nil

    // MARK: - Alerts

    @State private var showingInvalidAmountAlert: Bool = false
    @State private var showingMissingCardAlert: Bool = false
    @State private var showingSaveError = false
    @State private var showingApplyError = false
    @State private var savedPreset: Preset?
    @State private var selectedBudgetIDs: Set<UUID> = []
    @State private var budgetSearchText = ""
    @State private var budgetUnavailable = false

    init(workspace: Workspace, offersBudgetAfterSave: Bool = false, offerBudgetID: UUID? = nil) {
        self.workspace = workspace
        self.offersBudgetAfterSave = offersBudgetAfterSave
        self.offerBudgetID = offerBudgetID
        let workspaceID = workspace.id

        _cards = Query(
            filter: #Predicate<Card> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Card.name, order: .forward)]
        )

        _categories = Query(
            filter: #Predicate<Category> { $0.workspace?.id == workspaceID && $0.isArchived == false },
            sort: [SortDescriptor(\Category.name, order: .forward)]
        )

        _budgets = Query(
            filter: #Predicate<Budget> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Budget.startDate, order: .reverse), SortDescriptor(\Budget.name)]
        )
    }

    private var sortedCards: [Card] {
        cards.sorted {
            let comparison = $0.name.localizedCaseInsensitiveCompare($1.name)
            return cardsSortModeRaw == "za" ? comparison == .orderedDescending : comparison == .orderedAscending
        }
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
        Group {
            if let savedPreset {
                budgetOffer(for: savedPreset)
            } else {
                presetForm
            }
        }
        .blocksAutomaticExpenseReview(while: showingSaveError || showingApplyError)
        .alert("Unable to Save Preset", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Try saving the preset again.")
        }
        .alert("Unable to Add Preset", isPresented: $showingApplyError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Try adding the preset again.")
        }
    }

    private var presetForm: some View {
        PresetFormView(
            workspace: workspace,
            cards: sortedCards,
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
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!canSave)
                    .tint(.accentColor)
                    .glassProminentButtonStyleCompat()
            }
        }
        .blocksAutomaticExpenseReview(while: showingInvalidAmountAlert)
        .alert("Invalid Amount", isPresented: $showingInvalidAmountAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please enter a planned amount greater than 0.")
        }
        .blocksAutomaticExpenseReview(while: showingMissingCardAlert)
        .alert("Select a Card", isPresented: $showingMissingCardAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Choose a default card for this preset.")
        }
        .onAppear {
            guard DebugScreenshotFormDefaults.isEnabled else { return }

            if trimmedTitle.isEmpty {
                title = DebugScreenshotFormDefaults.presetTitle
            }

            let trimmedAmount = plannedAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedAmount.isEmpty {
                plannedAmountText = DebugScreenshotFormDefaults.presetAmountText
            }

            if selectedCardID == nil {
                selectedCardID = DebugScreenshotFormDefaults.preferredCardID(in: cards)
            }

            if selectedCategoryID == nil {
                selectedCategoryID = DebugScreenshotFormDefaults.preferredCategoryID(in: categories)
            }
        }
    }

    private func eligibleBudgets(for preset: Preset) -> [Budget] {
        budgets.filter {
            (offerBudgetID == nil || $0.id == offerBudgetID)
                && BudgetPresetApplicationService.isEligibleForOffer(preset, in: $0, workspace: workspace)
        }
    }

    private func budgetOffer(for preset: Preset) -> some View {
        let eligibleBudgets = eligibleBudgets(for: preset)
        let eligibleIDs = Set(eligibleBudgets.map(\.id))
        let selectedBudgets = eligibleBudgets.filter { selectedBudgetIDs.contains($0.id) }

        return Group {
            if eligibleBudgets.isEmpty {
                List {
                    budgetOfferGuidance(for: preset, hasEligibleBudgets: false)
                }
            } else {
                budgetChecklist(for: preset, budgets: eligibleBudgets)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Preset Saved")
        .onAppear {
            if eligibleBudgets.count == 1 {
                selectedBudgetIDs = eligibleIDs
            }
        }
        .onChange(of: eligibleIDs) { _, newIDs in
            if !selectedBudgetIDs.isSubset(of: newIDs) {
                selectedBudgetIDs.formIntersection(newIDs)
                budgetUnavailable = true
            }
        }
        .toolbar {
            if eligibleBudgets.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            } else {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        apply(preset, to: selectedBudgets)
                    } label: {
                        if selectedBudgets.count > 1 {
                            Text("Add to Budgets")
                        } else {
                            Text("Add to Budget")
                        }
                    }
                    .disabled(selectedBudgets.isEmpty)
                    .accessibilityIdentifier("applySavedPreset")
                }
                if eligibleBudgets.count > 1 {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button("Select All") { selectedBudgetIDs = eligibleIDs }
                            .disabled(selectedBudgetIDs == eligibleIDs)
                        Spacer()
                        Button("Deselect All") { selectedBudgetIDs.removeAll() }
                            .disabled(selectedBudgetIDs.isEmpty)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func budgetChecklist(for preset: Preset, budgets: [Budget]) -> some View {
        let query = budgetSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filteredBudgets = budgets.filter { query.isEmpty || $0.name.localizedStandardContains(query) }

        let checklist = List(selection: $selectedBudgetIDs) {
            budgetOfferGuidance(for: preset, hasEligibleBudgets: true)
            Section("Choose Budgets") {
                ForEach(filteredBudgets) { budget in
                    budgetLabel(budget)
                        .tag(budget.id)
                        .accessibilityValue(selectedBudgetIDs.contains(budget.id) ? Text("Selected") : Text("Not selected"))
                        .accessibilityIdentifier("presetOfferBudget")
                }
                if filteredBudgets.isEmpty {
                    ContentUnavailableView.search(text: query)
                        .selectionDisabled()
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .tint(.accentColor)
        if offerBudgetID == nil {
            checklist.searchable(text: $budgetSearchText, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search Budgets")
        } else {
            checklist
        }
    }

    private func budgetOfferGuidance(for preset: Preset, hasEligibleBudgets: Bool) -> some View {
        Section {
            Text("This preset is a reusable template. It hasn’t been added to a budget yet.")
                .selectionDisabled()
            if budgetUnavailable {
                Text("Budget availability changed. Review your selection and try again.")
                    .selectionDisabled()
            }
            if !hasEligibleBudgets {
                if offerBudgetID == nil {
                    Text("You can select this preset when you create a budget.")
                } else {
                    Text("This preset will be available in Linked Presets.")
                }
                if preset.frequency == .none {
                    Text("This preset doesn’t repeat, so it generates no scheduled bills.")
                }
            }
        }
    }

    private func budgetLabel(_ budget: Budget) -> some View {
        let format = Date.IntervalFormatStyle(date: .abbreviated, time: .omitted)
        let range = budget.startDate..<max(budget.startDate, budget.endDate)
        return VStack(alignment: .leading, spacing: 4) {
            Text(budget.name)
            Text(format.format(range))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func save() {
        guard savedPreset == nil, !trimmedTitle.isEmpty else { return }
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
        do {
            try WorkspaceProgressService.saveCompleting([.preset], in: workspace) {
                try modelContext.save()
            }
        } catch {
            modelContext.delete(preset)
            showingSaveError = true
            return
        }

        if offersBudgetAfterSave || (offerBudgetID != nil && !eligibleBudgets(for: preset).isEmpty) {
            savedPreset = preset
        } else {
            dismiss()
        }
    }

    private func apply(_ preset: Preset, to selectedBudgets: [Budget]) {
        do {
            let result = try BudgetPresetApplicationService.apply(
                preset, to: selectedBudgets, in: workspace, requiresMatchingCardAndDates: true, modelContext: modelContext
            )
            switch result {
            case .applied:
                Task {
                    await LocalNotificationService.syncFromUserDefaultsIfPossible(
                        modelContext: modelContext, workspaceID: workspace.id
                    )
                }
                dismiss()
            case .alreadyLinked:
                dismiss()
            case .ineligible:
                let remainingIDs = selectedBudgets.filter {
                    BudgetPresetApplicationService.isEligibleForOffer(preset, in: $0, workspace: workspace)
                }.map(\.id)
                selectedBudgetIDs.formIntersection(remainingIDs)
                budgetUnavailable = true
            }
        } catch {
            showingApplyError = true
        }
    }
}
