import Foundation
import SwiftData
import WidgetKit

@MainActor
enum ForecastSavingsWidgetSnapshotBuilder {
    private static let appGroupID = "group.com.mb.offshore-budgeting"
    private static let selectedWorkspaceKey = "selectedWorkspaceID"
    private static let widgetKind = "ForecastSavingsWidget"

    private struct Snapshot: Codable {
        let title: String
        let rangeStart: Date
        let rangeEnd: Date
        let projectedSavings: Double?
        let actualSavings: Double?
        let gapToProjected: Double?
        let statusLine: String
        let message: String?
    }

    static func buildAndSave(
        modelContext: ModelContext,
        workspaceID: UUID,
        now: Date = .now,
        shouldReloadTimelines: Bool = true
    ) {
        guard let snapshot = buildSnapshot(
            modelContext: modelContext,
            workspaceID: workspaceID,
            now: now
        ) else {
            return
        }

        save(
            snapshot: snapshot,
            workspaceID: workspaceID.uuidString
        )

        if shouldReloadTimelines {
            reloadTimelines()
        }
    }

    private static func buildSnapshot(
        modelContext: ModelContext,
        workspaceID: UUID,
        now: Date
    ) -> Snapshot? {
        let workspaceDescriptor = FetchDescriptor<Workspace>(
            predicate: #Predicate<Workspace> { workspace in
                workspace.id == workspaceID
            }
        )

        guard let workspace = try? modelContext.fetch(workspaceDescriptor).first else {
            return nil
        }

        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let monthEnd = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: monthStart) ?? monthStart

        let totals = savingsTotals(
            startDate: monthStart,
            endDate: monthEnd,
            incomes: workspace.incomes ?? [],
            plannedExpenses: workspace.plannedExpenses ?? [],
            variableExpenses: workspace.variableExpenses ?? [],
            savingsEntries: (workspace.savingsAccounts ?? []).flatMap { $0.entries ?? [] }
        )

        let actualSavings = totals.actualSavings
        let projectedSavings = totals.projectedSavings
        let gap = actualSavings - projectedSavings

        let statusLine: String
        if projectedSavings < 0 {
            statusLine = "Overspending forecast this month."
        } else if actualSavings < 0 {
            statusLine = "Current actual savings are negative."
        } else {
            statusLine = "Forecast is currently on track."
        }

        return Snapshot(
            title: "Forecast Savings",
            rangeStart: monthStart,
            rangeEnd: monthEnd,
            projectedSavings: projectedSavings,
            actualSavings: actualSavings,
            gapToProjected: gap,
            statusLine: statusLine,
            message: nil
        )
    }

    static func reloadTimelines() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func setSelectedWorkspaceID(_ workspaceID: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(workspaceID, forKey: selectedWorkspaceKey)
    }

    private static func save(snapshot: Snapshot, workspaceID: String) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        setSelectedWorkspaceID(workspaceID)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey(workspaceID: workspaceID))
    }

    private static func snapshotKey(workspaceID: String) -> String {
        "forecastSavingsWidget.snapshot.\(workspaceID)"
    }

    private static func savingsTotals(
        startDate: Date,
        endDate: Date,
        incomes: [Income],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        savingsEntries: [SavingsLedgerEntry]
    ) -> (projectedSavings: Double, actualSavings: Double) {
        let plannedIncomeTotal = incomes
            .filter { $0.isPlanned && $0.date >= startDate && $0.date <= endDate }
            .reduce(0.0) { $0 + $1.amount }

        let actualIncomeTotal = incomes
            .filter { !$0.isPlanned && $0.date >= startDate && $0.date <= endDate }
            .reduce(0.0) { $0 + $1.amount }

        let plannedExpensesPlannedTotal = plannedExpenses
            .filter { $0.expenseDate >= startDate && $0.expenseDate <= endDate }
            .reduce(0.0) { $0 + SavingsMathService.plannedProjectedBudgetImpactAmount(for: $1) }

        let plannedExpensesEffectiveActualTotal = plannedExpenses
            .filter { $0.expenseDate >= startDate && $0.expenseDate <= endDate }
            .reduce(0.0) { $0 + SavingsMathService.plannedBudgetImpactAmount(for: $1) }

        let variableExpensesTotal = variableExpenses
            .filter { $0.transactionDate >= startDate && $0.transactionDate <= endDate }
            .reduce(0.0) { $0 + SavingsMathService.variableBudgetImpactAmount(for: $1) }

        let actualSavingsAdjustments = SavingsMathService.actualSavingsAdjustmentTotal(
            from: savingsEntries,
            startDate: startDate,
            endDate: endDate
        )

        let projectedSavings = plannedIncomeTotal - plannedExpensesPlannedTotal
        let actualSavings = actualIncomeTotal - (plannedExpensesEffectiveActualTotal + variableExpensesTotal) + actualSavingsAdjustments
        return (projectedSavings, actualSavings)
    }
}
