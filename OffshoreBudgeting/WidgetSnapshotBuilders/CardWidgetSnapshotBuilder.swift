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
            .period, .oneWeek, .oneMonth, .oneYear, .q
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
        let plannedIncluded = PlannedExpenseFuturePolicy.filteredForCalculations(
            planned,
            excludeFuture: defaultExcludeFuturePlannedExpensesFromSharedDefaults()
        )

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
        let variableIncluded = VariableExpenseFuturePolicy.filteredForCalculations(
            variable,
            excludeFuture: defaultExcludeFutureVariableExpensesFromSharedDefaults()
        )

        // Totals
        let plannedTotal = plannedIncluded.reduce(0) { partial, exp in
            partial + exp.effectiveAmount()
        }
        let variableTotal = variableIncluded.reduce(0) { $0 + $1.amount }
        let unifiedTotal = plannedTotal + variableTotal

        // Recent (merge planned + variable, then pick newest)
        struct RecentMergeItem {
            let name: String
            let amount: Double
            let date: Date
            let categoryHex: String?
        }

        let merged: [RecentMergeItem] =
            plannedIncluded.map {
                RecentMergeItem(
                    name: $0.title,
                    amount: $0.effectiveAmount(),
                    date: $0.expenseDate,
                    categoryHex: $0.category?.hexColor
                )
            }
            + variableIncluded.map {
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
        period: CardWidgetPeriod,
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
        let defaults = UserDefaults(suiteName: CardWidgetSnapshotStore.appGroupID)
        let raw = defaults?.string(forKey: "general_defaultBudgetingPeriod") ?? BudgetingPeriod.monthly.rawValue
        return BudgetingPeriod(rawValue: raw) ?? .monthly
    }

    private static func defaultExcludeFuturePlannedExpensesFromSharedDefaults() -> Bool {
        let defaults = UserDefaults(suiteName: CardWidgetSnapshotStore.appGroupID)
        return defaults?.bool(forKey: "general_excludeFuturePlannedExpensesFromCalculations") ?? false
    }

    private static func defaultExcludeFutureVariableExpensesFromSharedDefaults() -> Bool {
        let defaults = UserDefaults(suiteName: CardWidgetSnapshotStore.appGroupID)
        return defaults?.bool(forKey: "general_excludeFutureVariableExpensesFromCalculations") ?? false
    }

    private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
