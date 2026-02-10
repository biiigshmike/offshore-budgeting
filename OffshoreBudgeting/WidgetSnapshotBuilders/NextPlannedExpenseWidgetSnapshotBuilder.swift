//
//  NextPlannedExpenseWidgetSnapshotBuilder.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import Foundation
import SwiftData

enum NextPlannedExpenseWidgetSnapshotBuilder {

    static func buildAndSaveAllPeriods(
        modelContext: ModelContext,
        workspaceID: UUID
    ) {
        let workspaceIDString = workspaceID.uuidString
        let now = Date()

        let wid = workspaceID
        let cardsDescriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { card in
                card.workspace?.id == wid
            },
            sortBy: [SortDescriptor(\Card.name, order: .forward)]
        )

        let cards = (try? modelContext.fetch(cardsDescriptor)) ?? []

        let options: [NextPlannedExpenseWidgetSnapshotStore.CardOption] = cards.map {
            .init(
                id: $0.id.uuidString,
                name: $0.name,
                themeToken: $0.theme,
                effectToken: $0.effect
            )
        }
        NextPlannedExpenseWidgetSnapshotStore.saveCardOptions(options, workspaceID: workspaceIDString)

        for period in NextPlannedExpenseWidgetPeriod.allCases {
            if let allCardsSnapshot = buildSnapshot(
                modelContext: modelContext,
                workspaceID: workspaceID,
                period: period,
                cardID: nil,
                now: now,
                maxItems: 4
            ) {
                NextPlannedExpenseWidgetSnapshotStore.save(
                    snapshot: allCardsSnapshot,
                    workspaceID: workspaceIDString,
                    cardID: nil,
                    periodToken: period.rawValue
                )
            }

            for card in cards {
                let cardIDString = card.id.uuidString

                if let snapshot = buildSnapshot(
                    modelContext: modelContext,
                    workspaceID: workspaceID,
                    period: period,
                    cardID: card.id,
                    now: now,
                    maxItems: 4
                ) {
                    NextPlannedExpenseWidgetSnapshotStore.save(
                        snapshot: snapshot,
                        workspaceID: workspaceIDString,
                        cardID: cardIDString,
                        periodToken: period.rawValue
                    )
                }
            }
        }

        NextPlannedExpenseWidgetSnapshotStore.reloadTimelines()
    }

    static func buildSnapshot(
        modelContext: ModelContext,
        workspaceID: UUID,
        period: NextPlannedExpenseWidgetPeriod,
        cardID: UUID?,
        now: Date,
        maxItems: Int
    ) -> NextPlannedExpenseWidgetSnapshot? {

        let range = resolvedRange(
            period: period,
            now: now
        )

        let start = range.start
        let end = range.end
        let todayStart = Calendar.current.startOfDay(for: now)

        let wid = workspaceID
        let plannedExpenses: [PlannedExpense]

        if let cardID {
            let descriptor = FetchDescriptor<PlannedExpense>(
                predicate: #Predicate<PlannedExpense> { expense in
                    expense.workspace?.id == wid
                    && expense.card?.id == cardID
                    && expense.expenseDate >= start
                    && expense.expenseDate <= end
                    && expense.sourceBudgetID != nil
                },
                sortBy: [SortDescriptor(\PlannedExpense.expenseDate, order: .forward)]
            )
            plannedExpenses = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            let descriptor = FetchDescriptor<PlannedExpense>(
                predicate: #Predicate<PlannedExpense> { expense in
                    expense.workspace?.id == wid
                    && expense.expenseDate >= start
                    && expense.expenseDate <= end
                    && expense.sourceBudgetID != nil
                },
                sortBy: [SortDescriptor(\PlannedExpense.expenseDate, order: .forward)]
            )
            plannedExpenses = (try? modelContext.fetch(descriptor)) ?? []
        }

        let upcoming = plannedExpenses
            .filter { $0.expenseDate >= todayStart }
            .prefix(maxItems)

        let items: [NextPlannedExpenseWidgetSnapshot.Item] = upcoming.map {
            .init(
                expenseID: $0.id.uuidString,
                expenseTitle: $0.title,
                cardName: $0.card?.name ?? "Card",
                cardThemeToken: $0.card?.theme ?? "graphite",
                cardEffectToken: $0.card?.effect ?? "plastic",
                expenseDate: $0.expenseDate,
                plannedAmount: $0.plannedAmount,
                actualAmount: $0.effectiveAmount()
            )
        }

        guard !items.isEmpty else { return nil }

        return NextPlannedExpenseWidgetSnapshot(
            title: "Next Planned Expense",
            periodToken: period.rawValue,
            rangeStart: start,
            rangeEnd: end,
            items: items
        )
    }

    // MARK: - Range Resolution

    private static func resolvedRange(
        period: NextPlannedExpenseWidgetPeriod,
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
        let defaults = UserDefaults(suiteName: NextPlannedExpenseWidgetSnapshotStore.appGroupID)
        let raw = defaults?.string(forKey: "general_defaultBudgetingPeriod") ?? BudgetingPeriod.monthly.rawValue
        return BudgetingPeriod(rawValue: raw) ?? .monthly
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
