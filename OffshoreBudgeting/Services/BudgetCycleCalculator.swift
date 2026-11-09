import Foundation

enum BudgetCycleCalculator {
    enum CalculationError: LocalizedError {
        case invalidInterval
        case invalidCount
        case invalidDate

        var errorDescription: String? {
            switch self {
            case .invalidInterval:
                String(localized: "Choose an interval from 1 to 52.")
            case .invalidCount:
                String(localized: "Choose between 1 and 52 budgets.")
            case .invalidDate:
                String(localized: "The budget cycle dates could not be calculated.")
            }
        }
    }

    /// Every boundary is calculated from the original anchor, never from a
    /// previously clamped date. A custom first end starts a new anchor for the
    /// remaining cycles on the following day. All ranges are inclusive.
    static func ranges(
        startDate: Date,
        period: BudgetingPeriod,
        interval: Int,
        count: Int,
        firstPeriodEndDate: Date? = nil,
        calendar: Calendar = .current
    ) throws -> [BudgetCycleRange] {
        guard (1...52).contains(interval) else { throw CalculationError.invalidInterval }
        guard (1...52).contains(count) else { throw CalculationError.invalidCount }
        guard startDate.timeIntervalSinceReferenceDate.isFinite else { throw CalculationError.invalidDate }

        let anchor = calendar.startOfDay(for: startDate)
        if let firstPeriodEndDate {
            guard firstPeriodEndDate.timeIntervalSinceReferenceDate.isFinite else {
                throw CalculationError.invalidDate
            }
            let end = calendar.startOfDay(for: firstPeriodEndDate)
            guard end >= anchor else { throw CalculationError.invalidDate }
            let first = BudgetCycleRange(startDate: anchor, endDate: end)
            guard count > 1 else { return [first] }
            guard let nextStart = calendar.date(byAdding: .day, value: 1, to: end) else {
                throw CalculationError.invalidDate
            }
            return [first] + (try ranges(
                startDate: nextStart, period: period, interval: interval,
                count: count - 1, calendar: calendar
            ))
        }
        let boundaries = try (0...count).map { index in
            try boundary(anchor: anchor, period: period, offset: index * interval, calendar: calendar)
        }
        return try (0..<count).map { index in
            let start = boundaries[index]
            let next = boundaries[index + 1]
            guard next > start,
                  let lastDay = calendar.date(byAdding: .day, value: -1, to: next) else {
                throw CalculationError.invalidDate
            }
            let end = calendar.startOfDay(for: lastDay)
            guard end >= start else { throw CalculationError.invalidDate }
            return BudgetCycleRange(startDate: start, endDate: end)
        }
    }

    private static func boundary(
        anchor: Date,
        period: BudgetingPeriod,
        offset: Int,
        calendar: Calendar
    ) throws -> Date {
        if offset == 0 { return anchor }
        let result: Date?
        switch period {
        case .daily:
            result = calendar.date(byAdding: .day, value: offset, to: anchor)
        case .weekly:
            result = calendar.date(byAdding: .day, value: offset * 7, to: anchor)
        case .monthly, .quarterly, .yearly:
            guard let anchorMonth = calendar.dateInterval(of: .month, for: anchor)?.start else {
                throw CalculationError.invalidDate
            }
            let component: Calendar.Component = period == .yearly ? .year : .month
            let units = period == .quarterly ? offset * 3 : offset
            guard let targetMonth = calendar.date(byAdding: component, value: units, to: anchorMonth),
                  let days = calendar.range(of: .day, in: .month, for: targetMonth) else {
                throw CalculationError.invalidDate
            }
            let clampedDay = min(calendar.component(.day, from: anchor), days.upperBound - 1)
            result = calendar.date(byAdding: .day, value: clampedDay - 1, to: targetMonth)
        }
        guard let result else { throw CalculationError.invalidDate }
        return calendar.startOfDay(for: result)
    }
}
