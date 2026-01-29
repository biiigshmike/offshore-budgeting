//
//  ManagePresetsForBudgetSheet.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/21/26.
//

import SwiftUI
import SwiftData

struct ManagePresetsForBudgetSheet: View {
    let workspace: Workspace
    let budget: Budget

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @AppStorage("general_confirmBeforeDeleting") private var confirmBeforeDeleting: Bool = true

    @State private var showingRemovePresetConfirm: Bool = false
    @State private var showingRemovePresetWithRecordedConfirm: Bool = false

    @State private var pendingPresetForUnlink: Preset? = nil

    @State private var showingReviewRecordedPresetExpenses: Bool = false
    @State private var reviewPreset: Preset? = nil

    @Query private var presets: [Preset]

    init(workspace: Workspace, budget: Budget) {
        self.workspace = workspace
        self.budget = budget

        let workspaceID = workspace.id
        _presets = Query(
            filter: #Predicate<Preset> { $0.workspace?.id == workspaceID },
            sort: [SortDescriptor(\Preset.title, order: .forward)]
        )
    }

    var body: some View {
        List {
            if presets.isEmpty {
                ContentUnavailableView(
                    "No Presets",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create a preset first, then you can link it to this budget.")
                )
            } else {
                ForEach(presets) { preset in
                    Toggle(isOn: bindingForPreset(preset)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.title)

                            HStack(spacing: 8) {
                                Text(preset.plannedAmount, format: CurrencyFormatter.currencyStyle())
                                Text("•")
                                Text(scheduleString(for: preset))
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(!canLink(preset))
                }
            }
        }
        .navigationTitle("Linked Presets")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
        }
        .onAppear {
            cleanupOrphanLinks()
        }

        // MARK: - Confirm remove preset (no recorded spending)

        .alert("Remove Preset From Budget?", isPresented: $showingRemovePresetConfirm) {
            Button("Remove", role: .destructive) {
                guard let preset = pendingPresetForUnlink else { return }
                unlinkPresetApplyingGuardrails(preset, presentReviewIfNeeded: true)
                pendingPresetForUnlink = nil
            }
            Button("Cancel", role: .cancel) {
                pendingPresetForUnlink = nil
            }
        } message: {
            Text("Expenses with recorded spending are kept.")
        }

        // MARK: - Confirm remove preset (recorded spending exists)

        .alert("Remove Preset From Budget?", isPresented: $showingRemovePresetWithRecordedConfirm) {
            Button("Review Recorded Expenses") {
                guard let preset = pendingPresetForUnlink else { return }
                unlinkPresetApplyingGuardrails(preset, presentReviewIfNeeded: true)
                pendingPresetForUnlink = nil
            }

            Button("Remove Preset Only") {
                guard let preset = pendingPresetForUnlink else { return }
                unlinkPresetApplyingGuardrails(preset, presentReviewIfNeeded: false)
                pendingPresetForUnlink = nil
            }

            Button("Cancel", role: .cancel) {
                pendingPresetForUnlink = nil
            }
        } message: {
            Text("This preset has expenses with recorded spending.")
        }

        // MARK: - Review recorded expenses (preset + budget)

        .sheet(isPresented: $showingReviewRecordedPresetExpenses) {
            if let reviewPreset {
                NavigationStack {
                    PresetRecordedPlannedExpensesReviewView(
                        workspace: workspace,
                        budget: budget,
                        preset: reviewPreset,
                        onDone: {
                            showingReviewRecordedPresetExpenses = false
                        }
                    )
                }
            }
        }
    }

    // MARK: - Guardrails

    private func canLink(_ preset: Preset) -> Bool {
        guard let budgetWorkspaceID = budget.workspace?.id else { return false }
        guard let presetWorkspaceID = preset.workspace?.id else { return false }
        return budgetWorkspaceID == workspace.id && presetWorkspaceID == workspace.id
    }

    // MARK: - Link Helpers

    private func isLinked(_ preset: Preset) -> Bool {
        (budget.presetLinks ?? []).contains { $0.preset?.id == preset.id }
    }

    private var linkedCardIDs: Set<UUID> {
        Set((budget.cardLinks ?? []).compactMap { $0.card?.id })
    }

    private func bindingForPreset(_ preset: Preset) -> Binding<Bool> {
        Binding(
            get: { isLinked(preset) },
            set: { newValue in
                guard canLink(preset) else { return }

                if newValue {
                    link(preset)
                } else {
                    handleToggleOff(preset)
                }
            }
        )
    }

    private func handleToggleOff(_ preset: Preset) {
        // If nothing was generated for this budget+preset, unlink quietly.
        if !hasAnyGeneratedPlannedExpenses(budget: budget, preset: preset) {
            unlinkPresetApplyingGuardrails(preset, presentReviewIfNeeded: false)
            return
        }

        let recordedCount = countRecordedGeneratedPlannedExpenses(budget: budget, preset: preset)

        pendingPresetForUnlink = preset

        if recordedCount > 0 {
            showingRemovePresetWithRecordedConfirm = true
        } else {
            if confirmBeforeDeleting {
                showingRemovePresetConfirm = true
            } else {
                unlinkPresetApplyingGuardrails(preset, presentReviewIfNeeded: false)
                pendingPresetForUnlink = nil
            }
        }
    }

    private func link(_ preset: Preset) {
        guard canLink(preset) else { return }
        guard !isLinked(preset) else { return }

        let link = BudgetPresetLink(budget: budget, preset: preset)
        modelContext.insert(link)

        materializePlannedExpenses(
            for: budget,
            selectedPresets: [preset],
            selectedCardIDs: linkedCardIDs
        )
    }

    // MARK: - Unlink policy D

    private func unlinkPresetApplyingGuardrails(_ preset: Preset, presentReviewIfNeeded: Bool) {
        // 1) Delete the join link(s)
        let matches = (budget.presetLinks ?? []).filter { $0.preset?.id == preset.id }
        for link in matches {
            modelContext.delete(link)
        }

        // 2) Delete ONLY unspent generated planned expenses for this budget+preset
        _ = deleteUnspentGeneratedPlannedExpenses(budget: budget, preset: preset)

        // 3) If recorded generated exist, offer review
        let recordedCount = countRecordedGeneratedPlannedExpenses(budget: budget, preset: preset)
        if presentReviewIfNeeded, recordedCount > 0 {
            reviewPreset = preset
            showingReviewRecordedPresetExpenses = true
        }
    }

    private func hasAnyGeneratedPlannedExpenses(budget: Budget, preset: Preset) -> Bool {
        let budgetID: UUID? = budget.id
        let presetID: UUID? = preset.id

        var descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID &&
                expense.sourcePresetID == presetID
            }
        )
        descriptor.fetchLimit = 1

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        return !matches.isEmpty
    }

    private func deleteUnspentGeneratedPlannedExpenses(budget: Budget, preset: Preset) -> Int {
        let budgetID: UUID? = budget.id
        let presetID: UUID? = preset.id

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID &&
                expense.sourcePresetID == presetID &&
                expense.actualAmount == 0
            }
        )

        let matches = (try? modelContext.fetch(descriptor)) ?? []
        for expense in matches {
            modelContext.delete(expense)
        }
        return matches.count
    }

    private func countRecordedGeneratedPlannedExpenses(budget: Budget, preset: Preset) -> Int {
        let budgetID: UUID? = budget.id
        let presetID: UUID? = preset.id

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetID &&
                expense.sourcePresetID == presetID &&
                expense.actualAmount > 0
            }
        )

        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    private func cleanupOrphanLinks() {
        let orphans = (budget.presetLinks ?? []).filter { $0.preset == nil || $0.budget == nil }
        for link in orphans {
            modelContext.delete(link)
        }
    }

    // MARK: - Materialize (copied from AddBudgetView behavior)

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
        let budgetIDOpt: UUID? = budgetID
        let presetIDOpt: UUID? = presetID
        let day = Calendar.current.startOfDay(for: date)

        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { expense in
                expense.sourceBudgetID == budgetIDOpt &&
                expense.sourcePresetID == presetIDOpt &&
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
        case .none: return "This preset does not repeat."

        case .daily:
            return preset.interval == 1 ? "Daily" : "Every \(preset.interval) days"

        case .weekly:
            let day = weekdayName(preset.weeklyWeekday)
            if preset.interval == 1 { return "Weekly • \(day)" }
            return "Every \(preset.interval) weeks • \(day)"

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
            if preset.interval == 1 { return "Yearly • \(month) \(day)" }
            return "Every \(preset.interval) years • \(month) \(day)"
        }
    }

    private func weekdayName(_ weekday: Int) -> String {
        let clamped = min(7, max(1, weekday))
        let symbols = Calendar.current.weekdaySymbols
        return symbols[clamped - 1]
    }

    private func monthName(_ month: Int) -> String {
        let clamped = min(12, max(1, month))
        let symbols = Calendar.current.monthSymbols
        return symbols[clamped - 1]
    }

    private func ordinalDay(_ day: Int) -> String {
        let clamped = min(31, max(1, day))
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: clamped)) ?? "\(clamped)"
    }
}
