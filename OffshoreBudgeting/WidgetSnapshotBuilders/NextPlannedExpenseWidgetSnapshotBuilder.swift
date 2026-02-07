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
            modelContext: modelContext,
            workspaceID: workspaceID,
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
        modelContext: ModelContext,
        workspaceID: UUID,
        period: NextPlannedExpenseWidgetPeriod,
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

            return (
                cal.startOfDay(for: start),
                cal.date(bySettingHour: 23, minute: 59, second: 59, of: end) ?? end
            )

        case .period:
            let wid = workspaceID
            let descriptor = FetchDescriptor<Budget>(
                predicate: #Predicate<Budget> { budget in
                    budget.workspace?.id == wid
                    && budget.startDate <= now
                    && budget.endDate >= now
                },
                sortBy: [SortDescriptor(\Budget.startDate, order: .reverse)]
            )

            if let active = (try? modelContext.fetch(descriptor))?.first {
                return (active.startDate, active.endDate)
            }

            let start = cal.date(byAdding: .day, value: -29, to: now) ?? now
            return (cal.startOfDay(for: start), now)
        }
    }
}
