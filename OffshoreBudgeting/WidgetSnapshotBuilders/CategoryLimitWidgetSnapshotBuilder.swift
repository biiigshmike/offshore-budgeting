import Foundation
import SwiftData

@MainActor
enum CategoryLimitWidgetSnapshotBuilder {
    private static let dailyTimelineHorizon = 35

    static func buildAndSave(
        modelContext: ModelContext,
        workspaceID: UUID,
        now: Date = .now,
        shouldReloadTimelines: Bool = true
    ) {
        let descriptor = FetchDescriptor<Workspace>(
            predicate: #Predicate<Workspace> { $0.id == workspaceID }
        )
        guard let workspace = try? modelContext.fetch(descriptor).first else {
            CategoryLimitWidgetSnapshotStore.save(
                CategoryLimitWidgetSnapshotSet(days: []),
                workspaceID: workspaceID
            )
            if shouldReloadTimelines {
                CategoryLimitWidgetSnapshotStore.reloadTimelines()
            }
            return
        }

        let defaults = LockScreenWidgetWorkspace.defaults
        let excludeFuturePlanned = defaults?.bool(forKey: "general_excludeFuturePlannedExpensesFromCalculations") ?? false
        let excludeFutureVariable = defaults?.bool(forKey: "general_excludeFutureVariableExpensesFromCalculations") ?? false
        let snapshots = makeSnapshots(
            workspace: workspace,
            now: now,
            excludeFuturePlanned: excludeFuturePlanned,
            excludeFutureVariable: excludeFutureVariable
        )
        CategoryLimitWidgetSnapshotStore.save(CategoryLimitWidgetSnapshotSet(days: snapshots), workspaceID: workspaceID)
        if shouldReloadTimelines {
            CategoryLimitWidgetSnapshotStore.reloadTimelines()
        }
    }

    static func publishPickerOptions(workspace: Workspace) {
        CategoryLimitWidgetSnapshotStore.savePickerOptions(
            makePickerOptions(workspace: workspace),
            workspaceID: workspace.id
        )
    }

    static func makePickerOptions(
        workspace: Workspace,
        calendar: Calendar = .current
    ) -> CategoryLimitWidgetPickerOptions {
        let categoryNames = Dictionary(
            (workspace.categories ?? []).map { ($0.id, $0.name) },
            uniquingKeysWith: { name, _ in name }
        )
        let budgets = (workspace.budgets ?? []).sorted { lhs, rhs in
            if lhs.startDate != rhs.startDate { return lhs.startDate > rhs.startDate }
            return lhs.id.uuidString < rhs.id.uuidString
        }.compactMap { budget -> CategoryLimitWidgetPickerBudget? in
            let range = DateRange(start: budget.startDate, end: budget.endDate, calendar: calendar)
            guard let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: range.end)) else {
                return nil
            }

            // Match the availability aggregator's handling of repeated limits.
            var eligible = Set<UUID>()
            for limit in budget.categoryLimits ?? [] {
                guard let id = limit.category?.id, categoryNames[id] != nil else { continue }
                if let maximum = limit.maxAmount, maximum.isFinite, maximum > 0 {
                    eligible.insert(id)
                } else {
                    eligible.remove(id)
                }
            }

            return CategoryLimitWidgetPickerBudget(
                start: range.start, end: end, categoryIDs: eligible
            )
        }
        return CategoryLimitWidgetPickerOptions(budgets: budgets, categoryNames: categoryNames)
    }

    static func makeSnapshots(
        workspace: Workspace,
        now: Date,
        excludeFuturePlanned: Bool,
        excludeFutureVariable: Bool,
        calendar: Calendar = .current
    ) -> [CategoryLimitWidgetSnapshot] {
        let budgets = (workspace.budgets ?? []).sorted { $0.id.uuidString < $1.id.uuidString }
        let categories = workspace.categories ?? []
        let existingBudgetIDs = Set(budgets.map(\.id))
        let planned = (workspace.plannedExpenses ?? []).filter { expense in
            guard let sourceBudgetID = expense.sourceBudgetID else { return true }
            return existingBudgetIDs.contains(sourceBudgetID)
        }
        let variable = workspace.variableExpenses ?? []
        let todayStart = calendar.startOfDay(for: now)

        return (0...dailyTimelineHorizon).compactMap { offset in
            guard let dayStart = calendar.date(byAdding: .day, value: offset, to: todayStart) else { return nil }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
            let today = DateRange(start: dayStart, end: dayStart, calendar: calendar)
            let budget = BudgetRangeOverlap.pickActiveBudget(from: budgets, for: today, calendar: calendar)
            let metrics = budget.map { budget in
                HomeCategoryLimitsAggregator.build(
                    budgets: [budget],
                    categories: categories,
                    plannedExpenses: PlannedExpenseFuturePolicy.filteredForCalculations(
                        planned, excludeFuture: excludeFuturePlanned, now: dayStart, calendar: calendar
                    ),
                    variableExpenses: VariableExpenseFuturePolicy.filteredForCalculations(
                        variable, excludeFuture: excludeFutureVariable, now: dayStart, calendar: calendar
                    ),
                    rangeStart: budget.startDate,
                    rangeEnd: budget.endDate,
                    inclusionPolicy: .limitsOnly,
                    calendar: calendar
                ).metrics.compactMap { metric -> CategoryLimitWidgetMetric? in
                    guard let fraction = metric.percentUsed(for: .all), fraction.isFinite else { return nil }
                    return CategoryLimitWidgetMetric(
                        id: metric.categoryID, name: metric.name, fractionUsed: fraction,
                        limitAmount: metric.maxAmount, spentAmount: metric.spent(for: .all)
                    )
                }
            } ?? []
            return CategoryLimitWidgetSnapshot(date: dayStart, validUntil: nextDay, metrics: metrics)
        }
    }
}
