import Foundation

/// The persisted period for default date ranges. Budget Repeat uses its own interval.
nonisolated struct DefaultBudgetingPeriod {
    static let weeklyIntervalBounds = 1...52

    let period: BudgetingPeriod
    let weeklyInterval: Int

    init(_ period: BudgetingPeriod, weeklyInterval: Int = 1) {
        self.period = period
        self.weeklyInterval = period == .weekly && Self.weeklyIntervalBounds.contains(weeklyInterval)
            ? weeklyInterval : 1
    }

    init(rawValue: String?) {
        if let rawValue, rawValue.hasPrefix("weekly:") {
            self.init(.weekly, weeklyInterval: Int(rawValue.dropFirst("weekly:".count)) ?? 1)
        } else {
            self.init(rawValue.flatMap(BudgetingPeriod.init(rawValue:)) ?? .monthly)
        }
    }

    var rawValue: String {
        weeklyInterval > 1 ? "weekly:\(weeklyInterval)" : period.rawValue
    }

    func defaultRange(
        containing date: Date, calendar: Calendar = .current
    ) -> (start: Date, end: Date) {
        period.defaultRange(containing: date, calendar: calendar, weeklyInterval: weeklyInterval)
    }
}
