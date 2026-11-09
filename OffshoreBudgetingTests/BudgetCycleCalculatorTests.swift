import Foundation
import Testing
@testable import Offshore

@MainActor
struct BudgetCycleCalculatorTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    @Test func dailyRangesNormalizeTimesAndCrossSpringDST() throws {
        let ranges = try BudgetCycleCalculator.ranges(
            startDate: date(2026, 3, 7, hour: 15), period: .daily, interval: 1, count: 3, calendar: calendar
        )
        #expect(ranges.map(\.startDate) == [date(2026, 3, 7), date(2026, 3, 8), date(2026, 3, 9)])
        #expect(ranges.allSatisfy { $0.startDate == $0.endDate })
        #expect(ranges[2].startDate.timeIntervalSince(ranges[1].startDate) == 23 * 60 * 60)
    }

    @Test func biweeklyRangesHaveFourteenInclusiveDays() throws {
        let ranges = try BudgetCycleCalculator.ranges(
            startDate: date(2026, 10, 25), period: .weekly, interval: 2, count: 2, calendar: calendar
        )
        #expect(ranges == [
            BudgetCycleRange(startDate: date(2026, 10, 25), endDate: date(2026, 11, 7)),
            BudgetCycleRange(startDate: date(2026, 11, 8), endDate: date(2026, 11, 21))
        ])
    }

    @Test func monthlyClampingDoesNotDrift() throws {
        let ranges = try BudgetCycleCalculator.ranges(
            startDate: date(2026, 1, 31), period: .monthly, interval: 1, count: 3, calendar: calendar
        )
        #expect(ranges == [
            BudgetCycleRange(startDate: date(2026, 1, 31), endDate: date(2026, 2, 27)),
            BudgetCycleRange(startDate: date(2026, 2, 28), endDate: date(2026, 3, 30)),
            BudgetCycleRange(startDate: date(2026, 3, 31), endDate: date(2026, 4, 29))
        ])
    }

    @Test func quarterlyCyclesPreserveTheAnchorDay() throws {
        let ranges = try BudgetCycleCalculator.ranges(
            startDate: date(2026, 1, 31), period: .quarterly, interval: 1, count: 3, calendar: calendar
        )
        #expect(ranges.map(\.startDate) == [date(2026, 1, 31), date(2026, 4, 30), date(2026, 7, 31)])
        #expect(ranges.last?.endDate == date(2026, 10, 30))
    }

    @Test func yearlyCyclesRecoverLeapDay() throws {
        let ranges = try BudgetCycleCalculator.ranges(
            startDate: date(2024, 2, 29), period: .yearly, interval: 1, count: 5, calendar: calendar
        )
        #expect(ranges[1].startDate == date(2025, 2, 28))
        #expect(ranges[4].startDate == date(2028, 2, 29))
        #expect(ranges[3].endDate == date(2028, 2, 28))
    }

    @Test func allCyclesAreContiguousAndRespectIntervals() throws {
        for period in BudgetingPeriod.allCases {
            let ranges = try BudgetCycleCalculator.ranges(
                startDate: date(2024, 2, 29), period: period, interval: 2, count: 52, calendar: calendar
            )
            #expect(ranges.count == 52)
            for pair in zip(ranges, ranges.dropFirst()) {
                #expect(calendar.date(byAdding: .day, value: 1, to: pair.0.endDate) == pair.1.startDate)
                #expect(pair.0.startDate <= pair.0.endDate)
            }
        }
        let everyTwoMonths = try BudgetCycleCalculator.ranges(
            startDate: date(2026, 1, 15), period: .monthly, interval: 2, count: 2, calendar: calendar
        )
        #expect(everyTwoMonths[0].endDate == date(2026, 3, 14))
        #expect(everyTwoMonths[1].startDate == date(2026, 3, 15))
    }

    @Test func customFirstEndShortensOrExtendsOnlyTheFirstPeriod() throws {
        for end in [date(2026, 1, 10), date(2026, 2, 10)] {
            let ranges = try BudgetCycleCalculator.ranges(
                startDate: date(2026, 1, 1), period: .monthly, interval: 1, count: 3,
                firstPeriodEndDate: end, calendar: calendar
            )
            let next = calendar.date(byAdding: .day, value: 1, to: end)!
            #expect(ranges.first == BudgetCycleRange(startDate: date(2026, 1, 1), endDate: end))
            #expect(Array(ranges.dropFirst()) == (try BudgetCycleCalculator.ranges(
                startDate: next, period: .monthly, interval: 1, count: 2, calendar: calendar
            )))
            for pair in zip(ranges, ranges.dropFirst()) {
                #expect(calendar.date(byAdding: .day, value: 1, to: pair.0.endDate) == pair.1.startDate)
            }
        }
    }

    @Test func customFirstEndRetainsLaterMonthEndAnchor() throws {
        let ranges = try BudgetCycleCalculator.ranges(
            startDate: date(2026, 1, 1), period: .monthly, interval: 1, count: 4,
            firstPeriodEndDate: date(2026, 1, 30), calendar: calendar
        )
        #expect(ranges.map(\.startDate) == [date(2026, 1, 1), date(2026, 1, 31), date(2026, 2, 28), date(2026, 3, 31)])
        #expect(ranges.map(\.endDate) == [date(2026, 1, 30), date(2026, 2, 27), date(2026, 3, 30), date(2026, 4, 29)])
    }

    @Test func singleCustomPeriodAndInvalidEnds() throws {
        let ranges = try BudgetCycleCalculator.ranges(
            startDate: date(2026, 3, 7), period: .daily, interval: 1, count: 1,
            firstPeriodEndDate: date(2026, 3, 9, hour: 15), calendar: calendar
        )
        #expect(ranges == [BudgetCycleRange(startDate: date(2026, 3, 7), endDate: date(2026, 3, 9))])
        for end in [date(2026, 3, 6), Date(timeIntervalSinceReferenceDate: .infinity)] {
            #expect(throws: BudgetCycleCalculator.CalculationError.self) {
                try BudgetCycleCalculator.ranges(
                    startDate: date(2026, 3, 7), period: .weekly, interval: 1, count: 2,
                    firstPeriodEndDate: end, calendar: calendar
                )
            }
        }
    }

    @Test func invalidInputsThrowInsteadOfProducingPartialBatches() {
        for interval in [0, 53] {
            #expect(throws: BudgetCycleCalculator.CalculationError.self) {
                try BudgetCycleCalculator.ranges(
                    startDate: date(2026, 1, 1), period: .monthly, interval: interval, count: 2, calendar: calendar
                )
            }
        }
        for count in [0, 53] {
            #expect(throws: BudgetCycleCalculator.CalculationError.self) {
                try BudgetCycleCalculator.ranges(
                    startDate: date(2026, 1, 1), period: .monthly, interval: 1, count: count, calendar: calendar
                )
            }
        }
    }
}
