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
    
    @State private var showingUnlinkDeleteConfirm: Bool = false
    @State private var pendingUnlinkDelete: (() -> Void)? = nil
    @State private var showingApplyError = false
    
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
            if visiblePresets.isEmpty {
                ContentUnavailableView(
                    "No Presets",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Create a preset first, then you can link it to this budget.")
                )
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Section {
                    ForEach(visiblePresets) { preset in
                        Toggle(isOn: bindingForPreset(preset)) {
                            VStack(alignment: .leading, spacing: 6) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(preset.title)

                                        if preset.isArchived {
                                            Text("Archived")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    
                                    HStack(spacing: 8) {
                                        Text(preset.plannedAmount, format: CurrencyFormatter.currencyStyle())
                                        Text("•")
                                        Text(scheduleString(for: preset))
                                    }
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                }
                                
                                if linkedCardIDs.isEmpty {
                                    Text(presetRowFootnoteText)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                if isLinked(preset) && linkedCardIDs.isEmpty {
                                    Text("This preset will apply once a card is linked.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Color("AccentColor"))
                        .disabled(!canLink(preset) || (preset.isArchived && !isLinked(preset)) || (linkedCardIDs.isEmpty && !isLinked(preset)))
                    }
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
        .blocksAutomaticExpenseReview(while: showingUnlinkDeleteConfirm)
        .alert("Delete?", isPresented: $showingUnlinkDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingUnlinkDelete?()
                pendingUnlinkDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingUnlinkDelete = nil
            }
        }
        .blocksAutomaticExpenseReview(while: showingApplyError)
        .alert("Unable to Add Preset", isPresented: $showingApplyError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Try adding the preset again.")
        }
    }
    
    // MARK: - Guardrails
    
    private func canLink(_ preset: Preset) -> Bool {
        BudgetPresetApplicationService.canLink(preset, to: budget, in: workspace)
    }

    private var visiblePresets: [Preset] {
        presets.filter { preset in
            preset.isArchived == false || isLinked(preset)
        }
    }

    // MARK: - Link Helpers

    private func isLinked(_ preset: Preset) -> Bool {
        BudgetPresetApplicationService.isLinked(preset, to: budget)
    }
    
    private var linkedCardIDs: Set<UUID> {
        BudgetPlannedExpenseStore.linkedCardIDs(for: budget)
    }
    
    private func bindingForPreset(_ preset: Preset) -> Binding<Bool> {
        Binding(
            get: { isLinked(preset) },
            set: { newValue in
                guard canLink(preset) else { return }
                if newValue {
                    link(preset)
                } else {
                    if confirmBeforeDeleting {
                        pendingUnlinkDelete = {
                            unlink(preset)
                        }
                        showingUnlinkDeleteConfirm = true
                    } else {
                        unlink(preset)
                    }
                }
            }
        )
    }
    
    private func link(_ preset: Preset) {
        do {
            let result = try BudgetPresetApplicationService.apply(
                preset, to: budget, in: workspace, requiresMatchingCardAndDates: false, modelContext: modelContext
            )
            guard result == .applied else { return }
            Task {
                await LocalNotificationService.syncFromUserDefaultsIfPossible(
                    modelContext: modelContext, workspaceID: workspace.id
                )
            }
        } catch {
            showingApplyError = true
        }
    }
    
    private func unlink(_ preset: Preset) {
        // 1) Delete the join link(s)
        let matches = (budget.presetLinks ?? []).filter { $0.preset?.id == preset.id }
        for link in matches {
            modelContext.delete(link)
        }
        
        // 2) Delete planned expenses that were generated for THIS budget from THIS preset
        deleteGeneratedPlannedExpenses(budgetID: budget.id, presetID: preset.id)

        Task {
            await LocalNotificationService.syncFromUserDefaultsIfPossible(
                modelContext: modelContext,
                workspaceID: workspace.id
            )
        }
    }
    
    private func deleteGeneratedPlannedExpenses(budgetID: UUID, presetID: UUID) {
        let descriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate { expense in
                expense.sourceBudgetID == budgetID &&
                expense.sourcePresetID == presetID
            }
        )
        
        do {
            let matches = try modelContext.fetch(descriptor)
            for expense in matches {
                PlannedExpenseDeletionService.delete(expense, modelContext: modelContext)
            }
        } catch {
            // Intentionally ignore fetch errors for now.
        }
    }
    
    private func cleanupOrphanLinks() {
        let orphans = (budget.presetLinks ?? []).filter { $0.preset == nil || $0.budget == nil }
        for link in orphans {
            modelContext.delete(link)
        }
    }
    
    // MARK: - Display
    
    private var presetRowFootnoteText: String {
        let hasAnyCardsInSystem = (workspace.cards ?? []).isEmpty == false
        return hasAnyCardsInSystem ? "Card Unassigned" : "No Cards Available"
    }
    
    private func scheduleString(for preset: Preset) -> String {
        switch preset.frequency {
        case .none: return "This preset does not repeat."
            
        case .daily:
            return preset.interval == 1 ? "Daily" : "Every \(localizedInt(preset.interval)) days"
            
        case .weekly:
            let day = weekdayName(preset.weeklyWeekday)
            if preset.interval == 1 { return "Weekly • \(day)" }
            return "Every \(localizedInt(preset.interval)) weeks • \(day)"
            
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
            if preset.interval == 1 { return "Yearly • \(month) \(day)" }
            return "Every \(localizedInt(preset.interval)) years • \(month) \(day)"
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
        if Locale.current.identifier.hasPrefix("es") {
            return localizedInt(clamped)
        }
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = .current
        return formatter.string(from: NSNumber(value: clamped)) ?? localizedInt(clamped)
    }

    private func localizedInt(_ value: Int) -> String {
        AppNumberFormat.integer(value)
    }
}
