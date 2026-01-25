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
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            cleanupOrphanLinks()
        }
        .alert("Delete?", isPresented: $showingUnlinkDeleteConfirm) {
            Button("Delete", role: .destructive) {
                pendingUnlinkDelete?()
                pendingUnlinkDelete = nil
            }
            Button("Cancel", role: .cancel) {
                pendingUnlinkDelete = nil
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
        guard canLink(preset) else { return }
        guard !isLinked(preset) else { return }

        let link = BudgetPresetLink(budget: budget, preset: preset)
        modelContext.insert(link)
    }

    private func unlink(_ preset: Preset) {
        // 1) Delete the join link(s)
        let matches = (budget.presetLinks ?? []).filter { $0.preset?.id == preset.id }
        for link in matches {
            modelContext.delete(link)
        }

        // 2) Delete planned expenses that were generated for THIS budget from THIS preset
        deleteGeneratedPlannedExpenses(budgetID: budget.id, presetID: preset.id)
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
                modelContext.delete(expense)
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
