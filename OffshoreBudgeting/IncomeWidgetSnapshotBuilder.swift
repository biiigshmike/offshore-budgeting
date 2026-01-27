//
//  IncomeWidgetSnapshotBuilder.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//


import Foundation
import SwiftData

enum IncomeWidgetSnapshotBuilder {

    static func buildAndSaveAllPeriods(
        modelContext: ModelContext,
        workspaceID: UUID
    ) {
        let workspaceIDString = workspaceID.uuidString
        let now = Date()

        let allPeriods: [IncomeWidgetPeriod] = [
            .period, .oneWeek, .oneMonth, .oneYear, .q1, .q2, .q3, .q4
        ]

        for period in allPeriods {
            guard let snapshot = buildSnapshot(
                modelContext: modelContext,
                workspaceID: workspaceID,
                period: period,
                now: now,
                maxRecent: 8
            ) else { continue }

            IncomeWidgetSnapshotStore.save(
                snapshot: snapshot,
                workspaceID: workspaceIDString,
                periodToken: period.rawValue
            )
        }

        IncomeWidgetSnapshotStore.reloadIncomeWidgetTimelines()
    }

    static func buildSnapshot(
        modelContext: ModelContext,
        workspaceID: UUID,
        period: IncomeWidgetPeriod,
        now: Date,
        maxRecent: Int
    ) -> IncomeWidgetSnapshot? {

        let range = resolvedRange(
            modelContext: modelContext,
            workspaceID: workspaceID,
            period: period,
            now: now
        )

        // Fetch incomes in range for this workspace.
        let start = range.start
        let end = range.end

        let wid = workspaceID
        let descriptor = FetchDescriptor<Income>(
            predicate: #Predicate<Income> { income in
                income.workspace?.id == wid &&
                income.date >= start &&
                income.date <= end
            },
            sortBy: [SortDescriptor(\Income.date, order: .reverse)]
        )

        let incomes = (try? modelContext.fetch(descriptor)) ?? []

        var plannedTotal: Double = 0
        var actualTotal: Double = 0

        for income in incomes {
            if income.isPlanned {
                plannedTotal += income.amount
            } else {
                actualTotal += income.amount
            }
        }

        let recentItems: [IncomeWidgetSnapshot.IncomeWidgetRecentItem] = incomes
            .prefix(maxRecent)
            .map {
                .init(
                    source: $0.source,
                    amount: $0.amount,
                    date: $0.date,
                    isPlanned: $0.isPlanned
                )
            }

        return IncomeWidgetSnapshot(
            title: "Income",
            periodToken: period.rawValue,
            rangeStart: start,
            rangeEnd: end,
            plannedTotal: plannedTotal,
            actualTotal: actualTotal,
            recentItems: recentItems.isEmpty ? nil : recentItems
        )
    }

    // MARK: - Range Resolution

    private static func resolvedRange(
        modelContext: ModelContext,
        workspaceID: UUID,
        period: IncomeWidgetPeriod,
        now: Date
    ) -> (start: Date, end: Date) {

        let cal = Calendar.current

        switch period {
        case .oneWeek:
            let start = cal.date(byAdding: .day, value: -6, to: now) ?? now
            return (cal.startOfDay(for: start), now)

        case .oneMonth:
            let start = cal.date(byAdding: .day, value: -29, to: now) ?? now
            return (cal.startOfDay(for: start), now)

        case .oneYear:
            let start = cal.date(byAdding: .day, value: -364, to: now) ?? now
            return (cal.startOfDay(for: start), now)

        case .q1, .q2, .q3, .q4:
            let year = cal.component(.year, from: now)
            let quarterIndex: Int
            switch period {
            case .q1: quarterIndex = 0
            case .q2: quarterIndex = 1
            case .q3: quarterIndex = 2
            case .q4: quarterIndex = 3
            default: quarterIndex = 0
            }

            let startMonth = (quarterIndex * 3) + 1
            var startComponents = DateComponents()
            startComponents.year = year
            startComponents.month = startMonth
            startComponents.day = 1
            let start = cal.date(from: startComponents) ?? now

            var endComponents = DateComponents()
            endComponents.year = year
            endComponents.month = startMonth + 3
            endComponents.day = 1
            let quarterEndStart = cal.date(from: endComponents) ?? now
            let end = cal.date(byAdding: .day, value: -1, to: quarterEndStart) ?? now

            return (cal.startOfDay(for: start), cal.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end)

        case .period:
            // Best-effort: use the "active budget" for this workspace if one exists.
            // Active = budget where startDate <= now <= endDate, pick the most recent startDate.
            let wid = workspaceID
            let descriptor = FetchDescriptor<Budget>(
                predicate: #Predicate<Budget> { budget in
                    budget.workspace?.id == wid &&
                    budget.startDate <= now &&
                    budget.endDate >= now
                },
                sortBy: [SortDescriptor(\Budget.startDate, order: .reverse)]
            )

            if let active = (try? modelContext.fetch(descriptor))?.first {
                return (active.startDate, active.endDate)
            }

            // Fallback if no active budget yet.
            let start = cal.date(byAdding: .day, value: -29, to: now) ?? now
            return (cal.startOfDay(for: start), now)
        }
    }
}
