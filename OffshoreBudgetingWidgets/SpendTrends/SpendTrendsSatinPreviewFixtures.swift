#if DEBUG
import Foundation

/// Fixed dates and amounts keep visual comparisons independent of today's date or stored data.
enum SpendTrendsSatinPreviewFixtures {
    static let monthLabels = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static var widgetScenarios: [(name: String, snapshot: SpendTrendsWidgetSnapshot)] {
        [
            ("P · daily", snapshot(token: "P", labels: (1...7).map { "Oct \($0)" }, start: date(2026, 10, 1), end: date(2026, 10, 7))),
            ("P · month ranges", monthly),
            ("P · monthly", snapshot(token: "P", labels: ["Jul", "Aug", "Sep", "Oct"], start: date(2026, 7, 1), end: date(2026, 10, 31))),
            ("P · partial month", snapshot(token: "P", labels: ["9–11", "12–18", "19–25", "26–29"], start: date(2026, 10, 9), end: date(2026, 10, 29))),
            ("P · cross-month", snapshot(token: "P", labels: ["Sep 26–30", "Oct 1–4", "Oct 5–11"], start: date(2026, 9, 26), end: date(2026, 10, 11))),
            ("P · 18 months, 12 visible", longRange),
            ("1W · daily", snapshot(token: "1W", labels: (18...24).map { "Oct \($0)" }, start: date(2026, 10, 18), end: date(2026, 10, 24))),
            ("1M · month ranges", snapshot(token: "1M", labels: ["1–4", "5–11", "12–18", "19–25", "26–31"], start: date(2026, 10, 1), end: date(2026, 10, 31))),
            ("1Y · twelve months", yearly),
            ("Q · current quarter", snapshot(token: "Q", labels: ["Q4"], start: date(2026, 10, 1), end: date(2026, 12, 31)))
        ]
    }

    static var appScenarios: [(name: String, snapshot: SpendTrendsWidgetSnapshot)] {
        widgetScenarios.filter { $0.snapshot.periodToken != "Q" } + [
            ("Q · four quarters", snapshot(token: "Q", labels: ["Q1", "Q2", "Q3", "Q4"], start: date(2026, 1, 1), end: date(2026, 12, 31)))
        ]
    }

    static var monthly: SpendTrendsWidgetSnapshot {
        snapshot(token: "P", labels: ["1–4", "5–11", "12–18", "19–25", "26–31"], start: date(2026, 10, 1), end: date(2026, 10, 31))
    }

    static var yearly: SpendTrendsWidgetSnapshot {
        snapshot(token: "1Y", labels: monthLabels, start: date(2026, 1, 1), end: date(2026, 12, 31))
    }

    static var longRange: SpendTrendsWidgetSnapshot {
        snapshot(token: "P", labels: Array(monthLabels.suffix(6)) + monthLabels, start: date(2025, 7, 1), end: date(2026, 12, 31))
    }

    static var entry: SpendTrendsWidgetEntry {
        SpendTrendsWidgetEntry(date: date(2026, 10, 31), periodToken: monthly.periodToken, cardID: nil, snapshot: monthly)
    }

    private static func snapshot(token: String, labels: [String], start: Date, end: Date) -> SpendTrendsWidgetSnapshot {
        let amounts: [Double] = [1539.52, 0.75, 0, 1180, 960, 645, 430, 875, 1120, 550, 790, 320]
        let names = ["Bills & Utilities", "Food & Drink", "Subscriptions", "Shopping", "Transport", "Travel", "Health", "Entertainment", "Gifts", "Other", "Education", "Uncategorized"]
        let colors: [String?] = ["#007D97", "#FF9500", "#FF88D8", "#9135FF", "#92D454", "#397AFF", "#00A79D", "#FFD600", "#FA6668", "#AC8FFF", "#49B5E8", nil]
        let weights: [Double] = [0.60, 0.22, 0.10, 0.045, 0.02, 0.008, 0.004, 0.0015, 0.0008, 0.0004, 0.0002, 0.0001]
        let buckets = labels.enumerated().map { index, label in
            let amount = amounts[index % amounts.count]
            let selectedWeights = index % 6 == 5 ? [1.0] : weights
            let denominator = selectedWeights.reduce(0, +)
            let slices: [SpendTrendsWidgetSnapshot.Slice] = amount > 0 ? selectedWeights.enumerated().map { offset, weight in
                let categoryIndex = (offset + index) % names.count
                return .init(id: "category-\(categoryIndex)", name: names[categoryIndex], hexColor: colors[categoryIndex], amount: amount * weight / denominator)
            } : []
            return SpendTrendsWidgetSnapshot.Bucket(id: "bucket-\(index)", label: label, total: amount, slices: slices)
        }
        let total = buckets.reduce(0) { $0 + $1.total }
        let highest = buckets.max { $0.total < $1.total }
        let topCategories = names.indices.compactMap { index -> SpendTrendsWidgetSnapshot.TopCategory? in
            let amount = buckets.flatMap(\.slices).filter { $0.id == "category-\(index)" }.reduce(0) { $0 + $1.amount }
            guard amount > 0 else { return nil }
            return .init(id: "category-\(index)", name: names[index], hexColor: colors[index], amount: amount, percentOfTotal: amount / total)
        }
        return SpendTrendsWidgetSnapshot(
            title: "Spend Trends", periodToken: token, rangeStart: start, rangeEnd: end, totalSpent: total, buckets: buckets,
            highestBucket: highest.flatMap { bucket in
                bucket.slices.first.map { slice in
                    .init(label: bucket.label, amount: bucket.total, topCategoryName: slice.name, topCategoryAmount: slice.amount, topCategoryPercentOfBucket: slice.amount / bucket.total)
                }
            },
            topCategories: topCategories
        )
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
#endif
