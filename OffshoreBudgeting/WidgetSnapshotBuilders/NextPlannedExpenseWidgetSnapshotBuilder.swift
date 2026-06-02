//
//  NextPlannedExpenseWidgetSnapshotBuilder.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import Foundation
import SwiftData

enum NextPlannedExpenseWidgetSnapshotBuilder {
    nonisolated private static let futureTimelineHorizon = 3
    nonisolated private static let dailyTimelineHorizon = 14

    nonisolated static func buildAndSaveAllPeriods(
        modelContext: ModelContext,
        workspaceID: UUID,
        now: Date = Date(),
        shouldReloadTimelines: Bool = true
    ) {
        let workspaceIDString = workspaceID.uuidString

        let wid = workspaceID
        let cardsDescriptor = FetchDescriptor<Card>(
            predicate: #Predicate<Card> { card in
                card.workspace?.id == wid
            },
            sortBy: [SortDescriptor(\Card.name, order: .forward)]
        )

        let cards = (try? modelContext.fetch(cardsDescriptor)) ?? []
        let currentCardIDs = Set(cards.map { $0.id.uuidString })
        NextPlannedExpenseWidgetSnapshotStore.pruneSnapshots(
            workspaceID: workspaceIDString,
            validCardIDs: currentCardIDs,
            periodTokens: NextPlannedExpenseWidgetPeriod.allCases.map(\.rawValue)
        )

        let options: [NextPlannedExpenseWidgetSnapshotStore.CardOption] = cards.map {
            .init(
                id: $0.id.uuidString,
                name: $0.name,
                themeToken: WidgetCardVisualTheme.resolve($0.theme).rawValue,
                effectToken: WidgetCardVisualEffect.resolve($0.effect).rawValue
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
                NextPlannedExpenseWidgetSnapshotStore.replaceTimelineSnapshots(
                    futureTimelineSnapshots(
                        currentSnapshot: allCardsSnapshot,
                        now: now
                    ) { entryDate in
                        buildSnapshot(
                            modelContext: modelContext,
                            workspaceID: workspaceID,
                            period: period,
                            cardID: nil,
                            now: entryDate,
                            maxItems: 4
                        )
                    },
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
                    NextPlannedExpenseWidgetSnapshotStore.replaceTimelineSnapshots(
                        futureTimelineSnapshots(
                            currentSnapshot: snapshot,
                            now: now
                        ) { entryDate in
                            buildSnapshot(
                                modelContext: modelContext,
                                workspaceID: workspaceID,
                                period: period,
                                cardID: card.id,
                                now: entryDate,
                                maxItems: 4
                            )
                        },
                        workspaceID: workspaceIDString,
                        cardID: cardIDString,
                        periodToken: period.rawValue
                    )
                }
            }
        }

        if shouldReloadTimelines {
            NextPlannedExpenseWidgetSnapshotStore.reloadTimelines()
        }
    }

    nonisolated static func buildSnapshot(
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
                    cardName: $0.card?.name ?? NSLocalizedString("Card", comment: "Fallback card title in widget snapshots."),
                    cardThemeToken: WidgetCardVisualTheme.resolve($0.card?.theme ?? "").rawValue,
                    cardEffectToken: WidgetCardVisualEffect.resolve($0.card?.effect ?? "").rawValue,
                    expenseDate: $0.expenseDate,
                plannedAmount: $0.plannedAmount,
                actualAmount: $0.effectiveAmount()
            )
        }

        return NextPlannedExpenseWidgetSnapshot(
            title: NSLocalizedString("Next Planned Expense", comment: "Next planned expense widget title."),
            periodToken: period.rawValue,
            rangeStart: start,
            rangeEnd: end,
            items: items
        )
    }

    // MARK: - Range Resolution

    nonisolated private static func resolvedRange(
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
            let range = BudgetingPeriod.quarterly.defaultRange(containing: now, calendar: cal)
            return (cal.startOfDay(for: range.start), endOfDay(range.end, calendar: cal))

        case .period:
            let period = defaultBudgetingPeriodFromSharedDefaults()
            let range = period.defaultRange(containing: now, calendar: cal)
            return (cal.startOfDay(for: range.start), endOfDay(range.end, calendar: cal))
        }
    }

    nonisolated private static func defaultBudgetingPeriodFromSharedDefaults() -> BudgetingPeriod {
        let defaults = UserDefaults(suiteName: NextPlannedExpenseWidgetSnapshotStore.appGroupID)
        let raw = defaults?.string(forKey: "general_defaultBudgetingPeriod") ?? BudgetingPeriod.monthly.rawValue
        return BudgetingPeriod(rawValue: raw) ?? .monthly
    }

    nonisolated private static func futureTimelineSnapshots(
        currentSnapshot: NextPlannedExpenseWidgetSnapshot,
        now: Date,
        build: (Date) -> NextPlannedExpenseWidgetSnapshot?
    ) -> [(date: Date, snapshot: NextPlannedExpenseWidgetSnapshot)] {
        var keyed: [Int64: (date: Date, snapshot: NextPlannedExpenseWidgetSnapshot)] = [:]

        func append(date: Date) {
            guard let snapshot = build(date) else { return }
            let key = Int64(date.timeIntervalSinceReferenceDate.rounded(.down))
            keyed[key] = (date, snapshot)
        }

        var rangeEnd = currentSnapshot.rangeEnd
        for _ in 0..<futureTimelineHorizon {
            let entryDate = WidgetTimelineSchedule.nextEntryDate(afterRangeEnd: rangeEnd, now: now)
            append(date: entryDate)
            rangeEnd = keyed[Int64(entryDate.timeIntervalSinceReferenceDate.rounded(.down))]?.snapshot.rangeEnd ?? rangeEnd
        }

        for entryDate in WidgetTimelineSchedule.dailyEntryDates(after: now, count: dailyTimelineHorizon) {
            append(date: entryDate)
        }

        return keyed.values.sorted { $0.date < $1.date }
    }

    nonisolated private static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}
