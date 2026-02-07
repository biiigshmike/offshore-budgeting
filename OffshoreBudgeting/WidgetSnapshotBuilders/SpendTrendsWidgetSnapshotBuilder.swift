//
//  SpendTrendsWidgetSnapshotBuilder.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 2/7/26.
//

import Foundation
import SwiftData

enum SpendTrendsWidgetSnapshotBuilder {

    private enum Granularity {
        case day
        case month
        case monthRanges
    }

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

        let cardOptions: [SpendTrendsWidgetSnapshotStore.CardOption] = cards.map {
            .init(id: $0.id.uuidString, name: $0.name, themeToken: $0.theme, effectToken: $0.effect)
        }
        SpendTrendsWidgetSnapshotStore.saveCardOptions(cardOptions, workspaceID: workspaceIDString)

        for period in SpendTrendsWidgetPeriod.allCases {
            if let allCardsSnapshot = buildSnapshot(
                modelContext: modelContext,
                workspaceID: workspaceID,
                period: period,
                cardID: nil,
                now: now,
                topN: 12
            ) {
                SpendTrendsWidgetSnapshotStore.save(
                    snapshot: allCardsSnapshot,
                    workspaceID: workspaceIDString,
                    cardID: nil,
                    periodToken: period.rawValue
                )
            }

            for card in cards {
                if let snapshot = buildSnapshot(
                    modelContext: modelContext,
                    workspaceID: workspaceID,
                    period: period,
                    cardID: card.id,
                    now: now,
                    topN: 12
                ) {
                    SpendTrendsWidgetSnapshotStore.save(
                        snapshot: snapshot,
                        workspaceID: workspaceIDString,
                        cardID: card.id.uuidString,
                        periodToken: period.rawValue
                    )
                }
            }
        }

        SpendTrendsWidgetSnapshotStore.reloadTimelines()
    }

    private static func buildSnapshot(
        modelContext: ModelContext,
        workspaceID: UUID,
        period: SpendTrendsWidgetPeriod,
        cardID: UUID?,
        now: Date,
        topN: Int
    ) -> SpendTrendsWidgetSnapshot? {
        let resolved = resolvedRange(
            modelContext: modelContext,
            workspaceID: workspaceID,
            period: period,
            now: now
        )

        let start = resolved.start
        let end = resolved.end

        let wid = workspaceID

        let plannedExpenses: [PlannedExpense]
        if let cardID {
            let descriptor = FetchDescriptor<PlannedExpense>(
                predicate: #Predicate<PlannedExpense> { expense in
                    expense.workspace?.id == wid
                    && expense.card?.id == cardID
                    && expense.expenseDate >= start
                    && expense.expenseDate <= end
                }
            )
            plannedExpenses = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            let descriptor = FetchDescriptor<PlannedExpense>(
                predicate: #Predicate<PlannedExpense> { expense in
                    expense.workspace?.id == wid
                    && expense.expenseDate >= start
                    && expense.expenseDate <= end
                }
            )
            plannedExpenses = (try? modelContext.fetch(descriptor)) ?? []
        }

        let variableExpenses: [VariableExpense]
        if let cardID {
            let descriptor = FetchDescriptor<VariableExpense>(
                predicate: #Predicate<VariableExpense> { expense in
                    expense.workspace?.id == wid
                    && expense.card?.id == cardID
                    && expense.transactionDate >= start
                    && expense.transactionDate <= end
                }
            )
            variableExpenses = (try? modelContext.fetch(descriptor)) ?? []
        } else {
            let descriptor = FetchDescriptor<VariableExpense>(
                predicate: #Predicate<VariableExpense> { expense in
                    expense.workspace?.id == wid
                    && expense.transactionDate >= start
                    && expense.transactionDate <= end
                }
            )
            variableExpenses = (try? modelContext.fetch(descriptor)) ?? []
        }

        let categoryLookup = buildCategoryLookup(
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )

        let overallTotals = categoryTotals(
            plannedExpenses: plannedExpenses,
            variableExpenses: variableExpenses
        )

        let totalSpent = overallTotals.values.reduce(0, +)
        guard totalSpent > 0 else { return nil }

        let topCategoryKeys = overallTotals
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(max(1, topN))
            .map { $0.key }

        let buckets = makeBuckets(start: start, end: end, granularity: resolved.granularity)

        let spansMultipleMonths: Bool = {
            let cal = Calendar.current
            let startYM = cal.dateComponents([.year, .month], from: start)
            let endYM = cal.dateComponents([.year, .month], from: end)
            return startYM.year != endYM.year || startYM.month != endYM.month
        }()

        var bucketSnapshots: [SpendTrendsWidgetSnapshot.Bucket] = []
        bucketSnapshots.reserveCapacity(buckets.count)

        for bucket in buckets {
            let bucketPlanned = plannedExpenses.filter { $0.expenseDate >= bucket.start && $0.expenseDate <= bucket.end }
            let bucketVariable = variableExpenses.filter { $0.transactionDate >= bucket.start && $0.transactionDate <= bucket.end }

            let bucketTotals = categoryTotals(plannedExpenses: bucketPlanned, variableExpenses: bucketVariable)
            let slices = buildBucketSlices(
                totals: bucketTotals,
                categoryLookup: categoryLookup,
                topCategoryKeys: topCategoryKeys
            )
            let bucketTotal = slices.reduce(0) { $0 + $1.amount }

            bucketSnapshots.append(
                .init(
                    id: bucket.start.timeIntervalSince1970.formatted(.number.precision(.fractionLength(0))),
                    label: bucketLabel(
                        start: bucket.start,
                        end: bucket.end,
                        granularity: resolved.granularity,
                        spansMultipleMonths: spansMultipleMonths
                    ),
                    total: bucketTotal,
                    slices: slices
                )
            )
        }

        let highestBucket: SpendTrendsWidgetSnapshot.HighestBucket? = {
            guard let highest = bucketSnapshots.filter({ $0.total > 0 }).max(by: { $0.total < $1.total }) else {
                return nil
            }

            guard let topSlice = highest.slices.max(by: { $0.amount < $1.amount }) else {
                return nil
            }

            return .init(
                label: highest.label,
                amount: highest.total,
                topCategoryName: topSlice.name,
                topCategoryAmount: topSlice.amount,
                topCategoryPercentOfBucket: topSlice.amount / max(0.000_1, highest.total)
            )
        }()

        let topCategories: [SpendTrendsWidgetSnapshot.TopCategory] = overallTotals
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .prefix(topN)
            .map { key, amount in
                let categoryName = categoryLookup[key]?.name ?? "Uncategorized"
                let categoryHex = categoryLookup[key]?.hexColor
                let id = key?.uuidString ?? "uncategorized"

                return .init(
                    id: id,
                    name: categoryName,
                    hexColor: categoryHex,
                    amount: amount,
                    percentOfTotal: amount / max(0.000_1, totalSpent)
                )
            }

        return SpendTrendsWidgetSnapshot(
            title: "Spend Trends",
            periodToken: period.rawValue,
            rangeStart: start,
            rangeEnd: end,
            totalSpent: totalSpent,
            buckets: bucketSnapshots,
            highestBucket: highestBucket,
            topCategories: topCategories
        )
    }

    // MARK: - Range resolution

    private static func resolvedRange(
        modelContext: ModelContext,
        workspaceID: UUID,
        period: SpendTrendsWidgetPeriod,
        now: Date
    ) -> (start: Date, end: Date, granularity: Granularity) {
        let cal = Calendar.current

        switch period {
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

            let baseStart: Date
            let baseEnd: Date

            if let active = (try? modelContext.fetch(descriptor))?.first {
                baseStart = active.startDate
                baseEnd = active.endDate
            } else {
                let fallbackStart = cal.date(byAdding: .day, value: -29, to: now) ?? now
                baseStart = startOfDay(fallbackStart)
                baseEnd = endOfDay(now)
            }

            let days = max(1, cal.dateComponents([.day], from: baseStart, to: baseEnd).day ?? 1)
            let granularity: Granularity
            if days <= 10 {
                granularity = .day
            } else if days <= 45 {
                granularity = .monthRanges
            } else {
                granularity = .month
            }

            return (startOfDay(baseStart), endOfDay(baseEnd), granularity)

        case .oneWeek:
            let start = cal.date(byAdding: .day, value: -6, to: now) ?? now
            return (startOfDay(start), endOfDay(now), .day)

        case .oneMonth:
            let start = cal.date(byAdding: .day, value: -29, to: now) ?? now
            return (startOfDay(start), endOfDay(now), .monthRanges)

        case .oneYear:
            let start = cal.date(byAdding: .month, value: -11, to: now) ?? now
            let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: start)) ?? start
            return (startOfDay(monthStart), endOfDay(now), .month)

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
            let start = cal.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? now

            let endMonth = startMonth + 2
            let endStart = cal.date(from: DateComponents(year: year, month: endMonth, day: 1)) ?? now
            let end = cal.date(byAdding: DateComponents(month: 1, day: -1), to: endStart) ?? now

            return (startOfDay(start), endOfDay(end), .month)
        }
    }

    // MARK: - Category totals

    private static func categoryTotals(
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> [UUID?: Double] {
        var totals: [UUID?: Double] = [:]

        for expense in plannedExpenses {
            let amount = expense.effectiveAmount()
            totals[expense.category?.id, default: 0] += amount
        }

        for expense in variableExpenses {
            totals[expense.category?.id, default: 0] += expense.amount
        }

        return totals
    }

    private static func buildCategoryLookup(
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> [UUID?: (name: String, hexColor: String?)] {
        var lookup: [UUID?: (name: String, hexColor: String?)] = [
            nil: (name: "Uncategorized", hexColor: nil)
        ]

        for expense in plannedExpenses {
            if let category = expense.category {
                lookup[category.id] = (name: category.name, hexColor: category.hexColor)
            }
        }

        for expense in variableExpenses {
            if let category = expense.category {
                lookup[category.id] = (name: category.name, hexColor: category.hexColor)
            }
        }

        return lookup
    }

    private static func buildBucketSlices(
        totals: [UUID?: Double],
        categoryLookup: [UUID?: (name: String, hexColor: String?)],
        topCategoryKeys: [UUID?]
    ) -> [SpendTrendsWidgetSnapshot.Slice] {
        var topSlices: [SpendTrendsWidgetSnapshot.Slice] = []
        var otherTotal: Double = 0
        var otherDominant: (key: UUID?, amount: Double)? = nil
        let uncategorizedTotal = totals[nil, default: 0]

        for key in topCategoryKeys {
            let amount = totals[key, default: 0]
            guard amount > 0 else { continue }

            let meta = categoryLookup[key] ?? (name: "Uncategorized", hexColor: nil)
            let id = key?.uuidString ?? "uncategorized"

            topSlices.append(
                .init(
                    id: id,
                    name: meta.name,
                    hexColor: meta.hexColor,
                    amount: amount
                )
            )
        }

        for (key, value) in totals where value > 0 {
            if key == nil { continue }
            if topCategoryKeys.contains(where: { $0 == key }) { continue }

            otherTotal += value

            if let current = otherDominant {
                if value > current.amount {
                    otherDominant = (key: key, amount: value)
                }
            } else {
                otherDominant = (key: key, amount: value)
            }
        }

        var slices: [SpendTrendsWidgetSnapshot.Slice] = []

        if uncategorizedTotal > 0 {
            slices.append(
                .init(
                    id: "uncategorized",
                    name: "Uncategorized",
                    hexColor: nil,
                    amount: uncategorizedTotal
                )
            )
        }

        slices.append(contentsOf: topSlices)

        if otherTotal > 0 {
            let otherHex = otherDominant.flatMap { dominant in
                categoryLookup[dominant.key]?.hexColor
            }

            slices.append(
                .init(
                    id: "other",
                    name: "Other",
                    hexColor: otherHex,
                    amount: otherTotal
                )
            )
        }

        return slices.sorted { $0.amount > $1.amount }
    }

    // MARK: - Buckets

    private static func makeBuckets(start: Date, end: Date, granularity: Granularity) -> [(start: Date, end: Date)] {
        switch granularity {
        case .day:
            return makeDayBuckets(start: start, end: end)
        case .month:
            return makeMonthBuckets(start: start, end: end)
        case .monthRanges:
            return makeMonthRangeBuckets(start: start, end: end)
        }
    }

    private static func makeDayBuckets(start: Date, end: Date) -> [(start: Date, end: Date)] {
        let cal = Calendar.current
        var buckets: [(start: Date, end: Date)] = []

        var cursor = startOfDay(start)
        while cursor <= end {
            let next = cal.date(byAdding: .day, value: 1, to: cursor) ?? cursor
            let bucketEnd = min(endOfDay(cal.date(byAdding: .second, value: -1, to: next) ?? cursor), end)
            buckets.append((start: cursor, end: bucketEnd))
            cursor = next
        }

        return buckets
    }

    private static func makeMonthBuckets(start: Date, end: Date) -> [(start: Date, end: Date)] {
        let cal = Calendar.current
        var buckets: [(start: Date, end: Date)] = []

        var cursor = startOfMonth(containing: start)
        while cursor <= end {
            let next = cal.date(byAdding: .month, value: 1, to: cursor) ?? cursor
            let bucketStart = max(cursor, start)
            let bucketEnd = min(endOfDay(cal.date(byAdding: DateComponents(second: -1), to: next) ?? cursor), end)
            buckets.append((start: bucketStart, end: bucketEnd))
            cursor = next
        }

        return buckets
    }

    private static func makeMonthRangeBuckets(start: Date, end: Date) -> [(start: Date, end: Date)] {
        let cal = Calendar.current
        var results: [(start: Date, end: Date)] = []

        var monthCursor = startOfMonth(containing: start)
        let endMonth = startOfMonth(containing: end)

        while monthCursor <= endMonth {
            let range = cal.range(of: .day, in: .month, for: monthCursor) ?? 1..<32
            let lastDay = range.count

            let segments: [(Int, Int)] = [
                (1, min(4, lastDay)),
                (5, min(11, lastDay)),
                (12, min(18, lastDay)),
                (19, min(25, lastDay)),
                (26, lastDay)
            ]

            let year = cal.component(.year, from: monthCursor)
            let month = cal.component(.month, from: monthCursor)

            for (startDay, endDay) in segments where startDay <= endDay {
                let segStart = cal.date(from: DateComponents(year: year, month: month, day: startDay)) ?? monthCursor
                let segEnd = cal.date(from: DateComponents(year: year, month: month, day: endDay)) ?? monthCursor

                let clampedStart = max(startOfDay(segStart), start)
                let clampedEnd = min(endOfDay(segEnd), end)

                if clampedStart <= clampedEnd {
                    results.append((start: clampedStart, end: clampedEnd))
                }
            }

            monthCursor = cal.date(byAdding: .month, value: 1, to: monthCursor) ?? monthCursor
        }

        return results
    }

    // MARK: - Labels

    private static func bucketLabel(
        start: Date,
        end: Date,
        granularity: Granularity,
        spansMultipleMonths: Bool
    ) -> String {
        let cal = Calendar.current

        switch granularity {
        case .day:
            return start.formatted(.dateTime.month(.abbreviated).day())
        case .month:
            return start.formatted(.dateTime.month(.abbreviated))
        case .monthRanges:
            let startDay = cal.component(.day, from: start)
            let endDay = cal.component(.day, from: end)

            if spansMultipleMonths {
                let month = start.formatted(.dateTime.month(.abbreviated))
                return "\(month) \(startDay)-\(endDay)"
            } else {
                return "\(startDay)-\(endDay)"
            }
        }
    }

    // MARK: - Date helpers

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func endOfDay(_ date: Date) -> Date {
        let cal = Calendar.current
        let start = cal.startOfDay(for: date)
        return cal.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private static func startOfMonth(containing date: Date) -> Date {
        let cal = Calendar.current
        return cal.date(from: cal.dateComponents([.year, .month], from: date)) ?? date
    }
}
