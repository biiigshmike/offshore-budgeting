//
//  HomeSpendTrendsAggregator.swift
//  OffshoreBudgeting
//
//  Created by Michael Brown on 1/26/26.
//

import Foundation
import SwiftUI

struct HomeSpendTrendsAggregator {

    // MARK: - Period

    enum Period: String, CaseIterable, Identifiable {
        case period = "P"
        case oneWeek = "1W"
        case oneMonth = "1M"
        case oneYear = "1Y"
        case q1 = "Q1"
        case q2 = "Q2"
        case q3 = "Q3"
        case q4 = "Q4"

        var id: String { rawValue }
    }

    // MARK: - Public models

    struct Result {
        let resolvedStart: Date
        let resolvedEnd: Date

        let totalSpent: Double

        /// IMPORTANT: includes zero buckets so charts render placeholders consistently.
        let buckets: [Bucket]

        let topCategoryOverall: Slice?

        /// Highest calculations should ignore empty buckets.
        let highestBucket: Bucket?
        let topCategoryInHighestBucket: Slice?
    }

    struct Bucket: Identifiable {
        let id = UUID()
        let label: String
        let start: Date
        let end: Date
        let total: Double
        let slices: [Slice]
    }

    struct Slice: Identifiable {
        let id = UUID()
        let categoryID: UUID?
        let name: String
        let hexColor: String?
        let amount: Double
    }

    // MARK: - Internal

    private enum Granularity {
        case day
        case month
        case monthRanges
    }

    // MARK: - Entry point

    static func calculate(
        period: Period,
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense],
        rangeStart: Date,
        rangeEnd: Date,
        cardFilter: Card?,
        topN: Int = 6
    ) -> Result {

        let resolved = resolvedRange(
            for: period,
            startDate: rangeStart,
            endDate: rangeEnd
        )

        let filteredPlanned = plannedExpenses
            .filter { $0.expenseDate >= resolved.start && $0.expenseDate <= resolved.end }
            .filter { cardFilter == nil ? true : ($0.card?.id == cardFilter?.id) }

        let filteredVariable = variableExpenses
            .filter { $0.transactionDate >= resolved.start && $0.transactionDate <= resolved.end }
            .filter { cardFilter == nil ? true : ($0.card?.id == cardFilter?.id) }

        // Overall category totals (used to pick topN and for the “Top category overall”)
        let overallCategoryTotals = categoryTotals(
            categories: categories,
            plannedExpenses: filteredPlanned,
            variableExpenses: filteredVariable
        )

        let topCategoryIDs: [UUID] = overallCategoryTotals
            .filter { $0.key != nil }
            .sorted { $0.value > $1.value }
            .prefix(max(1, topN))
            .compactMap { $0.key }

        let totalSpent: Double = overallCategoryTotals.values.reduce(0, +)

        // Buckets
        let buckets = makeBuckets(
            start: resolved.start,
            end: resolved.end,
            granularity: resolved.granularity
        )

        let spansMultipleMonths: Bool = {
            let calendar = Calendar.current
            let startYM = calendar.dateComponents([.year, .month], from: resolved.start)
            let endYM = calendar.dateComponents([.year, .month], from: resolved.end)
            return startYM.year != endYM.year || startYM.month != endYM.month
        }()

        var bucketResults: [Bucket] = []
        bucketResults.reserveCapacity(buckets.count)

        for bucket in buckets {
            let label = bucketLabel(
                start: bucket.start,
                end: bucket.end,
                granularity: resolved.granularity,
                spansMultipleMonths: spansMultipleMonths
            )

            let bucketTotals = categoryTotals(
                categories: categories,
                plannedExpenses: filteredPlanned.filter { $0.expenseDate >= bucket.start && $0.expenseDate <= bucket.end },
                variableExpenses: filteredVariable.filter { $0.transactionDate >= bucket.start && $0.transactionDate <= bucket.end }
            )

            let slices = buildSlices(
                totals: bucketTotals,
                categories: categories,
                topCategoryIDs: topCategoryIDs
            )

            let bucketTotal = slices.reduce(0) { $0 + $1.amount }

            bucketResults.append(
                Bucket(
                    label: label,
                    start: bucket.start,
                    end: bucket.end,
                    total: bucketTotal,
                    slices: slices
                )
            )
        }

        // Highest bucket + top category in it (ignore empty buckets)
        let nonZeroBuckets = bucketResults.filter { $0.total > 0 }

        let highestBucket = nonZeroBuckets.max { a, b in
            if a.total == b.total { return a.start > b.start }
            return a.total < b.total
        }

        let topCategoryInHighest: Slice? = {
            guard let highestBucket else { return nil }
            return highestBucket.slices.max { $0.amount < $1.amount }
        }()

        // Top category overall
        let topCategoryOverall: Slice? = {
            let topOverall = overallCategoryTotals.max { $0.value < $1.value }
            guard let topOverall else { return nil }
            return sliceFromTotalsKey(
                key: topOverall.key,
                amount: topOverall.value,
                categories: categories
            )
        }()

        return Result(
            resolvedStart: resolved.start,
            resolvedEnd: resolved.end,
            totalSpent: totalSpent,
            buckets: bucketResults, // keep zero buckets
            topCategoryOverall: topCategoryOverall,
            highestBucket: highestBucket,
            topCategoryInHighestBucket: topCategoryInHighest
        )
    }

    // MARK: - Range resolution

    private static func resolvedRange(
        for period: Period,
        startDate: Date,
        endDate: Date
    ) -> (start: Date, end: Date, granularity: Granularity) {

        let calendar = Calendar.current
        let anchorEnd = endDate

        switch period {
        case .period:
            let days = max(1, calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1)

            if days <= 10 {
                return (startOfDay(startDate), endOfDay(endDate), .day)
            }

            if days <= 45 {
                return (startOfDay(startDate), endOfDay(endDate), .monthRanges)
            }

            return (startOfDay(startDate), endOfDay(endDate), .month)

        case .oneWeek:
            let start = calendar.date(byAdding: .day, value: -6, to: anchorEnd) ?? anchorEnd
            return (startOfDay(start), endOfDay(anchorEnd), .day)

        case .oneMonth:
            let start = calendar.date(byAdding: .day, value: -29, to: anchorEnd) ?? anchorEnd
            return (startOfDay(start), endOfDay(anchorEnd), .monthRanges)

        case .oneYear:
            let start = calendar.date(byAdding: .month, value: -11, to: anchorEnd) ?? anchorEnd
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: start)) ?? start
            return (startOfDay(monthStart), endOfDay(anchorEnd), .month)

        case .q1, .q2, .q3, .q4:
            let year = calendar.component(.year, from: anchorEnd)

            let quarterIndex: Int = {
                switch period {
                case .q1: return 0
                case .q2: return 1
                case .q3: return 2
                case .q4: return 3
                default: return 0
                }
            }()

            let startMonth = (quarterIndex * 3) + 1
            let start = calendar.date(from: DateComponents(year: year, month: startMonth, day: 1)) ?? anchorEnd
            let endMonth = startMonth + 2
            let endStart = calendar.date(from: DateComponents(year: year, month: endMonth, day: 1)) ?? anchorEnd
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: endStart) ?? anchorEnd

            return (startOfDay(start), endOfDay(end), .month)
        }
    }

    // MARK: - Buckets

    private static func makeBuckets(
        start: Date,
        end: Date,
        granularity: Granularity
    ) -> [(start: Date, end: Date)] {

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
        let calendar = Calendar.current
        var buckets: [(start: Date, end: Date)] = []

        var current = startOfDay(start)
        while current <= end {
            let next = calendar.date(byAdding: .day, value: 1, to: current) ?? current
            let bucketEnd = min(endOfDay(calendar.date(byAdding: .second, value: -1, to: next) ?? current), end)
            buckets.append((start: current, end: bucketEnd))
            current = next
        }

        return buckets
    }

    private static func makeMonthBuckets(start: Date, end: Date) -> [(start: Date, end: Date)] {
        let calendar = Calendar.current
        var buckets: [(start: Date, end: Date)] = []

        var current = startOfMonth(containing: start)
        while current <= end {
            let next = calendar.date(byAdding: .month, value: 1, to: current) ?? current
            let bucketStart = max(current, start)
            let bucketEnd = min(endOfDay(calendar.date(byAdding: DateComponents(second: -1), to: next) ?? current), end)
            buckets.append((start: bucketStart, end: bucketEnd))
            current = next
        }

        return buckets
    }

    /// ranges inside a month: 1–4, 5–11, 12–18, 19–25, 26–endOfMonth
    private static func makeMonthRangeBuckets(start: Date, end: Date) -> [(start: Date, end: Date)] {
        let calendar = Calendar.current
        var results: [(start: Date, end: Date)] = []

        var monthCursor = startOfMonth(containing: start)
        let endMonth = startOfMonth(containing: end)

        while monthCursor <= endMonth {
            let range = calendar.range(of: .day, in: .month, for: monthCursor) ?? 1..<32
            let lastDay = range.count

            let segments: [(Int, Int)] = [
                (1, min(4, lastDay)),
                (5, min(11, lastDay)),
                (12, min(18, lastDay)),
                (19, min(25, lastDay)),
                (26, lastDay)
            ]

            for (sDay, eDay) in segments {
                guard sDay <= eDay else { continue }

                let segStart = calendar.date(from: DateComponents(
                    year: calendar.component(.year, from: monthCursor),
                    month: calendar.component(.month, from: monthCursor),
                    day: sDay
                )) ?? monthCursor

                let segEnd = calendar.date(from: DateComponents(
                    year: calendar.component(.year, from: monthCursor),
                    month: calendar.component(.month, from: monthCursor),
                    day: eDay
                )) ?? monthCursor

                let segStartClamped = max(startOfDay(segStart), start)
                let segEndClamped = min(endOfDay(segEnd), end)

                if segStartClamped <= segEndClamped {
                    results.append((start: segStartClamped, end: segEndClamped))
                }
            }

            monthCursor = calendar.date(byAdding: .month, value: 1, to: monthCursor) ?? monthCursor
        }

        return results
    }

    // MARK: - Category totals + slices

    /// Key: categoryID (nil for Uncategorized)
    private static func categoryTotals(
        categories: [Category],
        plannedExpenses: [PlannedExpense],
        variableExpenses: [VariableExpense]
    ) -> [UUID?: Double] {

        var totals: [UUID?: Double] = [:]

        for expense in plannedExpenses {
            let amount = (expense.actualAmount > 0) ? expense.actualAmount : expense.plannedAmount
            let id = expense.category?.id
            totals[id, default: 0] += amount
        }

        for expense in variableExpenses {
            let id = expense.category?.id
            totals[id, default: 0] += expense.amount
        }

        for category in categories {
            _ = totals[category.id, default: 0]
        }

        return totals
    }

    private static func buildSlices(
        totals: [UUID?: Double],
        categories: [Category],
        topCategoryIDs: [UUID]
    ) -> [Slice] {

        var topSlices: [Slice] = []
        var otherTotal: Double = 0
        var otherDominant: (id: UUID, amount: Double)? = nil
        let uncategorizedTotal: Double = totals[nil, default: 0]

        for id in topCategoryIDs {
            let amount = totals[id, default: 0]
            guard amount > 0 else { continue }

            if let category = categories.first(where: { $0.id == id }) {
                topSlices.append(
                    Slice(
                        categoryID: id,
                        name: category.name,
                        hexColor: category.hexColor,
                        amount: amount
                    )
                )
            }
        }

        for (key, value) in totals {
            guard let key else { continue }
            guard value > 0 else { continue }
            guard !topCategoryIDs.contains(key) else { continue }
            otherTotal += value

            if let current = otherDominant {
                if value > current.amount {
                    otherDominant = (id: key, amount: value)
                }
            } else {
                otherDominant = (id: key, amount: value)
            }
        }

        var slices: [Slice] = []

        if uncategorizedTotal > 0 {
            slices.append(
                Slice(
                    categoryID: nil,
                    name: "Uncategorized",
                    hexColor: nil,
                    amount: uncategorizedTotal
                )
            )
        }

        slices.append(contentsOf: topSlices)

        if otherTotal > 0 {
            // color "Other" using the biggest contributor outside the topN.
            // This avoids the "mystery gray" segment when everything is categorized.
            let otherHex: String? = {
                guard let dominant = otherDominant else { return nil }
                return categories.first(where: { $0.id == dominant.id })?.hexColor
            }()

            slices.append(
                Slice(
                    categoryID: UUID(uuidString: "00000000-0000-0000-0000-000000000001"),
                    name: "Other",
                    hexColor: otherHex,
                    amount: otherTotal
                )
            )
        }

        slices.sort { $0.amount > $1.amount }
        return slices
    }

    private static func sliceFromTotalsKey(
        key: UUID?,
        amount: Double,
        categories: [Category]
    ) -> Slice? {
        guard amount > 0 else { return nil }

        if let key, let category = categories.first(where: { $0.id == key }) {
            return Slice(categoryID: key, name: category.name, hexColor: category.hexColor, amount: amount)
        }

        if key == nil {
            return Slice(categoryID: nil, name: "Uncategorized", hexColor: nil, amount: amount)
        }

        return Slice(categoryID: key, name: "Other", hexColor: nil, amount: amount)
    }

    // MARK: - Labels

    private static func bucketLabel(
        start: Date,
        end: Date,
        granularity: Granularity,
        spansMultipleMonths: Bool
    ) -> String {

        let calendar = Calendar.current

        switch granularity {
        case .day:
            return start.formatted(.dateTime.month(.abbreviated).day())

        case .month:
            return start.formatted(.dateTime.month(.abbreviated))

        case .monthRanges:
            let sDay = calendar.component(.day, from: start)
            let eDay = calendar.component(.day, from: end)

            if spansMultipleMonths {
                let month = start.formatted(.dateTime.month(.abbreviated))
                return "\(month) \(sDay)–\(eDay)"
            } else {
                return "\(sDay)–\(eDay)"
            }
        }
    }

    // MARK: - Date helpers

    private static func startOfDay(_ date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    private static func endOfDay(_ date: Date) -> Date {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }

    private static func startOfMonth(containing date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }
}
