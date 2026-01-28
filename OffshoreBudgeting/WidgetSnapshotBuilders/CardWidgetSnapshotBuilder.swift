//
//  CardWidgetSnapshotBuilder.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/27/26.
//

import Foundation
import SwiftData

enum CardWidgetSnapshotBuilder {

    static func buildAndSaveAllPeriods(
        modelContext: ModelContext,
        workspaceID: UUID
    ) {
        let workspaceIDString = workspaceID.uuidString
        let now = Date()

        // Fetch all cards in this workspace.
        let wid = workspaceID
        let cardsDescriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { card in
                card.workspace?.id == wid
            },
            sortBy: [SortDescriptor(\Card.name, order: .forward)]
        )

        let cards = (try? modelContext.fetch(cardsDescriptor)) ?? []

        // Save card options so the widget AppEntity picker can work.
        let options: [CardWidgetSnapshotStore.CardOption] = cards.map {
            .init(
                id: $0.id.uuidString,
                name: $0.name,
                themeToken: $0.theme,
                effectToken: $0.effect
            )
        }
        CardWidgetSnapshotStore.saveCardOptions(options, workspaceID: workspaceIDString)

        let allPeriods: [CardWidgetPeriod] = [
            .period, .oneWeek, .oneMonth, .oneYear, .q1, .q2, .q3, .q4
        ]

        for card in cards {
            let cardIDString = card.id.uuidString

            for period in allPeriods {
                guard let snapshot = buildSnapshot(
                    modelContext: modelContext,
                    workspaceID: workspaceID,
                    card: card,
                    period: period,
                    now: now,
                    maxRecent: 3
                ) else { continue }

                CardWidgetSnapshotStore.save(
                    snapshot: snapshot,
                    workspaceID: workspaceIDString,
                    cardID: cardIDString,
                    periodToken: period.rawValue
                )
            }
        }

        CardWidgetSnapshotStore.reloadCardWidgetTimelines()
    }

    static func buildSnapshot(
        modelContext: ModelContext,
        workspaceID: UUID,
        card: Card,
        period: CardWidgetPeriod,
        now: Date,
        maxRecent: Int
    ) -> CardWidgetSnapshot? {

        let range = resolvedRange(
            modelContext: modelContext,
            workspaceID: workspaceID,
            period: period,
            now: now
        )

        let start = range.start
        let end = range.end

        let wid = workspaceID
        let cid = card.id

        // Planned
        let plannedDescriptor = FetchDescriptor<PlannedExpense>(
            predicate: #Predicate<PlannedExpense> { exp in
                exp.workspace?.id == wid &&
                exp.card?.id == cid &&
                exp.expenseDate >= start &&
                exp.expenseDate <= end
            },
            sortBy: [SortDescriptor(\PlannedExpense.expenseDate, order: .reverse)]
        )
        let planned = (try? modelContext.fetch(plannedDescriptor)) ?? []

        // Variable
        let variableDescriptor = FetchDescriptor<VariableExpense>(
            predicate: #Predicate<VariableExpense> { exp in
                exp.workspace?.id == wid &&
                exp.card?.id == cid &&
                exp.transactionDate >= start &&
                exp.transactionDate <= end
            },
            sortBy: [SortDescriptor(\VariableExpense.transactionDate, order: .reverse)]
        )
        let variable = (try? modelContext.fetch(variableDescriptor)) ?? []

        // Totals
        let plannedTotal = planned.reduce(0) { partial, exp in
            partial + (exp.actualAmount > 0 ? exp.actualAmount : exp.plannedAmount)
        }
        let variableTotal = variable.reduce(0) { $0 + $1.amount }
        let unifiedTotal = plannedTotal + variableTotal

        // Recent (merge planned + variable, then pick newest)
        struct RecentMergeItem {
            let name: String
            let amount: Double
            let date: Date
            let categoryHex: String?
        }

        let merged: [RecentMergeItem] =
            planned.map {
                RecentMergeItem(
                    name: $0.title,
                    amount: ($0.actualAmount > 0 ? $0.actualAmount : $0.plannedAmount),
                    date: $0.expenseDate,
                    categoryHex: $0.category?.hexColor
                )
            }
            + variable.map {
                RecentMergeItem(
                    name: $0.descriptionText,
                    amount: $0.amount,
                    date: $0.transactionDate,
                    categoryHex: $0.category?.hexColor
                )
            }

        let recentItems: [CardWidgetSnapshot.CardWidgetRecentItem] = merged
            .sorted(by: { $0.date > $1.date })
            .prefix(maxRecent)
            .map {
                .init(
                    name: $0.name,
                    amount: $0.amount,
                    date: $0.date,
                    categoryHex: $0.categoryHex
                )
            }

        return CardWidgetSnapshot(
            title: card.name,
            cardID: card.id.uuidString,
            themeToken: card.theme,
            effectToken: card.effect,
            periodToken: period.rawValue,
            rangeStart: start,
            rangeEnd: end,
            unifiedExpensesTotal: unifiedTotal,
            recentItems: recentItems.isEmpty ? nil : recentItems
        )
    }

    // MARK: - Range Resolution (mirrors Income widget rules)

    private static func resolvedRange(
        modelContext: ModelContext,
        workspaceID: UUID,
        period: CardWidgetPeriod,
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
                    budget.workspace?.id == wid &&
                    budget.startDate <= now &&
                    budget.endDate >= now
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
