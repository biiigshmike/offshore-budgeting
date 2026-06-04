import Foundation

struct MarinaQueryPlanner {
    private let calendar: Calendar

    init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    func plan(
        request: MarinaSemanticRequest,
        ambientDateRange: HomeQueryDateRange?,
        defaultBudgetingPeriod: BudgetingPeriod,
        now: Date = Date(),
        clarificationChoices: MarinaClarificationChoices? = nil
    ) -> MarinaQueryPlan {
        let resolvedRange = dateRange(
            for: request.dateRangeToken,
            ambientDateRange: ambientDateRange,
            defaultBudgetingPeriod: defaultBudgetingPeriod,
            now: now
        )
        let comparisonRange = comparisonDateRange(
            for: request,
            primaryRange: resolvedRange,
            defaultBudgetingPeriod: defaultBudgetingPeriod,
            now: now
        )

        return MarinaQueryPlan(
            id: UUID(),
            semanticRequest: request,
            dateRange: resolvedRange,
            comparisonDateRange: comparisonRange,
            now: now,
            clarificationChoices: clarificationChoices
        )
    }

    private func dateRange(
        for token: MarinaSemanticDateRangeToken,
        ambientDateRange: HomeQueryDateRange?,
        defaultBudgetingPeriod: BudgetingPeriod,
        now: Date
    ) -> HomeQueryDateRange? {
        switch token {
        case .currentPeriod:
            if let ambientDateRange {
                return ambientDateRange
            }
            let range = defaultBudgetingPeriod.defaultRange(containing: now, calendar: calendar)
            return HomeQueryDateRange(startDate: range.start, endDate: range.end)
        case .previousPeriod:
            let currentRange = dateRange(
                for: .currentPeriod,
                ambientDateRange: ambientDateRange,
                defaultBudgetingPeriod: defaultBudgetingPeriod,
                now: now
            )
            return currentRange.map(previousEquivalentRange)
        case .currentMonth:
            if let ambientDateRange {
                return ambientDateRange
            }
            let range = BudgetingPeriod.monthly.defaultRange(containing: now, calendar: calendar)
            return HomeQueryDateRange(startDate: range.start, endDate: range.end)
        case .previousMonth:
            let current = BudgetingPeriod.monthly.defaultRange(containing: now, calendar: calendar)
            let previousEnd = calendar.date(byAdding: .day, value: -1, to: current.start) ?? current.start
            let previous = BudgetingPeriod.monthly.defaultRange(containing: previousEnd, calendar: calendar)
            return HomeQueryDateRange(startDate: previous.start, endDate: previous.end)
        case .nextSevenDays:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            return HomeQueryDateRange(startDate: start, endDate: end)
        case .allTime:
            return nil
        }
    }

    private func comparisonDateRange(
        for request: MarinaSemanticRequest,
        primaryRange: HomeQueryDateRange?,
        defaultBudgetingPeriod: BudgetingPeriod,
        now: Date
    ) -> HomeQueryDateRange? {
        guard request.operation == .compare || request.operation == .whatIf else { return nil }
        if request.comparisonTargetName != nil {
            return primaryRange
        }

        switch request.dateRangeToken {
        case .previousPeriod, .previousMonth:
            return nil
        case .currentPeriod:
            return primaryRange.map(previousEquivalentRange)
        case .currentMonth:
            return primaryRange.map(previousEquivalentRange)
        case .nextSevenDays, .allTime:
            return primaryRange.map(previousEquivalentRange)
        }
    }

    private func previousEquivalentRange(_ range: HomeQueryDateRange) -> HomeQueryDateRange {
        let start = calendar.startOfDay(for: range.startDate)
        let end = calendar.startOfDay(for: range.endDate)
        let dayCount = max(1, (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1)
        let previousEnd = calendar.date(byAdding: .day, value: -1, to: start) ?? start
        let previousStart = calendar.date(byAdding: .day, value: -(dayCount - 1), to: previousEnd) ?? previousEnd
        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }
}
