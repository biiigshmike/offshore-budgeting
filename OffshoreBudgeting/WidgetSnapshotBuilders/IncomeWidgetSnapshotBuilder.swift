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
            .period, .oneWeek, .oneMonth, .oneYear, .q
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
        period: IncomeWidgetPeriod,
        now: Date
    ) -> (start: Date, end: Date) {

        let cal = Calendar.current

        switch period {
        case .oneWeek:
            let interval = cal.dateInterval(of: .weekOfYear, for: now)
            let start = interval?.start ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: DateComponents(day: 6), to: start) ?? now
            return (cal.startOfDay(for: start), endOfDay(end, calendar: cal))

        case .oneMonth:
            let interval = cal.dateInterval(of: .month, for: now)
            let start = interval?.start ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: start) ?? now
            return (cal.startOfDay(for: start), endOfDay(end, calendar: cal))

        case .oneYear:
            let interval = cal.dateInterval(of: .year, for: now)
            let start = interval?.start ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? now
            return (cal.startOfDay(for: start), endOfDay(end, calendar: cal))

        case .q:
            let interval = cal.dateInterval(of: .year, for: now)
            let start = interval?.start ?? cal.startOfDay(for: now)
            let end = cal.date(byAdding: DateComponents(year: 1, day: -1), to: start) ?? now
            return (cal.startOfDay(for: start), endOfDay(end, calendar: cal))

        case .period:
            let period = defaultBudgetingPeriodFromSharedDefaults()
            let range = period.defaultRange(containing: now, calendar: cal)
            return (cal.startOfDay(for: range.start), endOfDay(range.end, calendar: cal))
        }
    }

    private static func defaultBudgetingPeriodFromSharedDefaults() -> BudgetingPeriod {
        let defaults = UserDefaults(suiteName: IncomeWidgetSnapshotStore.appGroupID)
        let raw = defaults?.string(forKey: "general_defaultBudgetingPeriod") ?? BudgetingPeriod.monthly.rawValue
        return BudgetingPeriod(rawValue: raw) ?? .monthly
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
