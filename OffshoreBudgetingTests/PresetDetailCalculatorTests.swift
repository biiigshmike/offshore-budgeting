import Foundation
import Testing
@testable import Offshore

@MainActor
struct PresetDetailCalculatorTests {
    private let workspaceID = UUID()
    private let presetID = UUID()
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    @Test func pendingOccurrencesStayInHistoryWithoutAffectingComparisons() {
        let result = calculate([
            occurrence(day: 1, planned: 100, actual: 120),
            occurrence(day: 2, planned: 90, actual: 60),
            occurrence(day: 3, planned: 80, actual: 80),
            occurrence(day: 20, planned: 1_000, actual: 0),
            occurrence(day: 5, planned: 1_000, actual: -1)
        ])
        #expect(result.history.count == 5)
        #expect(result.recordedCount == 3)
        #expect(result.plannedTotal == 270)
        #expect(result.effectiveTotal == 260)
        #expect(result.totalVariance == -10)
        #expect(result.averageEffectiveAmount == 260.0 / 3)
        #expect(result.averageVariance == -10.0 / 3)
        #expect(result.abovePlanCount == 1)
        #expect(result.belowPlanCount == 1)
        #expect(result.onPlanCount == 1)
        #expect(result.history.first?.recordedAmount == nil)
        #expect(result.history.first?.variance == nil)
        #expect(result.periods.first?.plannedAmount == 270)
        #expect(result.periods.first?.effectiveAmount == 260)
        #expect(result.periods.first?.recordedCount == 3)
    }

    @Test func workspaceAndPresetBoundariesExcludeUnrelatedAndUnownedRecords() {
        let valid = occurrence(day: 1, planned: 10, actual: 12)
        let wrongWorkspace = occurrence(day: 1, planned: 100, actual: 120, workspace: UUID())
        let wrongPreset = occurrence(day: 1, planned: 100, actual: 120, preset: UUID())
        let unowned = PresetDetailCalculator.Occurrence(
            id: UUID(), workspaceID: nil, sourcePresetID: presetID, sourceBudgetID: nil,
            date: date(day: 1), plannedAmount: 100, actualAmount: 120
        )
        let result = calculate([valid, wrongWorkspace, wrongPreset, unowned])
        #expect(result.history.map(\.id) == [valid.id])
        #expect(result.effectiveTotal == 12)
    }

    @Test func inclusiveDatesRetainEntireEndDayAndSortNewestFirst() {
        let early = occurrence(day: 1, planned: 10, actual: 12)
        let late = occurrence(day: 31, planned: 10, actual: 12, hour: 23)
        let nextMonth = occurrence(day: 1, planned: 10, actual: 12, month: 2)
        let previousMonth = occurrence(day: 31, planned: 10, actual: 12, month: 12, year: 2025)
        let result = calculate([early, nextMonth, late, previousMonth])
        #expect(result.history.map(\.id) == [late.id, early.id])
        #expect(result.recordedCount == 2)
    }

    @Test func futureVisibilityAndCalculationsRemainIndependentAndTodayIsNotFuture() {
        let today = occurrence(day: 15, planned: 10, actual: 12, hour: 23)
        let future = occurrence(day: 16, planned: 20, actual: 24)
        let hiddenOnly = calculate([today, future], hideFuture: true)
        #expect(hiddenOnly.history.map(\.id) == [today.id])
        #expect(hiddenOnly.hiddenFutureCount == 1)
        #expect(hiddenOnly.effectiveTotal == 36)
        let excludedOnly = calculate([today, future], excludeFuture: true)
        #expect(excludedOnly.history.count == 2)
        #expect(excludedOnly.hiddenFutureCount == 0)
        #expect(excludedOnly.effectiveTotal == 12)
        #expect(excludedOnly.periods.first?.recordedCount == 1)
        let both = calculate([today, future], hideFuture: true, excludeFuture: true)
        #expect(both.history.count == 1)
        #expect(both.recordedCount == 1)
    }

    @Test func overlappingBudgetsAndMissingBudgetReferencesPreserveEveryOccurrence() {
        let first = occurrence(day: 1, planned: 10, actual: 12, budget: UUID())
        let second = occurrence(day: 1, planned: 10, actual: 12, budget: UUID())
        let orphan = occurrence(day: 1, planned: 10, actual: 12)
        let result = calculate([first, second, orphan])
        #expect(result.history.count == 3)
        #expect(Set(result.history.map(\.id)) == Set([first.id, second.id, orphan.id]))
        #expect(result.recordedCount == 3)
        #expect(result.effectiveTotal == 36)
    }

    @Test func emptyAndSingleRecordedResultsDoNotInventObservations() {
        let empty = calculate([])
        #expect(empty.history.isEmpty)
        #expect(empty.periods.isEmpty)
        #expect(empty.averageEffectiveAmount == nil)
        #expect(empty.averageVariance == nil)
        #expect(empty.totalVariance == 0)
        let single = calculate([occurrence(day: 1, planned: 10, actual: 12)])
        #expect(single.periods.count == 1)
        #expect(single.averageEffectiveAmount == 12)
        #expect(single.averageVariance == 2)
    }

    @Test func monthlyTotalsCompareSameRecordedOccurrencesAcrossMonths() {
        let result = PresetDetailCalculator.calculate(
            workspaceID: workspaceID, presetID: presetID,
            occurrences: [
                occurrence(day: 1, planned: 10, actual: 12),
                occurrence(day: 2, planned: 20, actual: 24, month: 2),
                occurrence(day: 3, planned: 1_000, actual: 0, month: 2)
            ],
            startDate: date(day: 1), endDate: date(day: 28, month: 2),
            now: date(day: 1, month: 2), calendar: calendar
        )
        #expect(result.periods.map(\.startDate) == [date(day: 1), date(day: 1, month: 2)])
        #expect(result.periods.map(\.plannedAmount) == [10, 20])
        #expect(result.periods.map(\.effectiveAmount) == [12, 24])
    }

    @Test func planCountsUseCurrencyPrecisionRatherThanFloatingPointResidue() {
        let result = calculate([occurrence(day: 1, planned: 0.1 + 0.2, actual: 0.3)])
        #expect(result.onPlanCount == 1)
        #expect(result.abovePlanCount == 0)
        #expect(result.belowPlanCount == 0)
        let yen = PresetDetailCalculator.calculate(
            workspaceID: workspaceID, presetID: presetID,
            occurrences: [occurrence(day: 1, planned: 100.1, actual: 100.2)],
            startDate: date(day: 1), endDate: date(day: 31), currencyCode: "JPY", calendar: calendar
        )
        #expect(yen.onPlanCount == 1)
    }

    @Test func rebuildingSnapshotsReflectsEditedRecordedAmounts() {
        let original = occurrence(day: 1, planned: 10, actual: 0)
        let edited = PresetDetailCalculator.Occurrence(
            id: original.id, workspaceID: workspaceID, sourcePresetID: presetID,
            sourceBudgetID: nil, date: original.date, plannedAmount: 10, actualAmount: 15
        )
        #expect(calculate([original]).recordedCount == 0)
        #expect(calculate([edited]).totalVariance == 5)
    }

    @Test func pastBlankUsesPlannedWhileTodayAndFutureBlankRemainPending() {
        let past = occurrence(day: 14, planned: 10, actual: 0)
        let today = occurrence(day: 15, planned: 20, actual: 0)
        let future = occurrence(day: 16, planned: 30, actual: 0)
        let result = calculate([past, today, future])
        #expect(result.history.count == 3)
        #expect(result.recordedCount == 0)
        #expect(result.assumedCount == 1)
        #expect(result.includedCount == 1)
        #expect(result.plannedTotal == 10)
        #expect(result.effectiveTotal == 10)
        #expect(result.averageEffectiveAmount == 10)
        #expect(result.totalVariance == 0)
        #expect(result.onPlanCount == 1)
        #expect(past.recordedAmount == nil)
        #expect(past.isAssumed(now: date(day: 15), calendar: calendar))
        #expect(today.effectiveAmount(now: date(day: 15, hour: 23), calendar: calendar) == nil)
        #expect(future.effectiveAmount(now: date(day: 15), calendar: calendar) == nil)
    }

    @Test func mixedRecordedAndAssumedAmountsUseSamePopulationForTotalsAndAverages() {
        let result = calculate([
            occurrence(day: 1, planned: 10, actual: 12),
            occurrence(day: 2, planned: 20, actual: 0),
            occurrence(day: 3, planned: 30, actual: 25),
            occurrence(day: 20, planned: 40, actual: 0)
        ])
        #expect(result.recordedCount == 2)
        #expect(result.assumedCount == 1)
        #expect(result.includedCount == 3)
        #expect(result.plannedTotal == 60)
        #expect(result.effectiveTotal == 57)
        #expect(result.totalVariance == -3)
        #expect(result.averageEffectiveAmount == 19)
        #expect(result.averageVariance == -1)
        #expect(result.abovePlanCount == 1)
        #expect(result.belowPlanCount == 1)
        #expect(result.onPlanCount == 1)
        #expect(result.periods.first?.includedCount == 3)
        #expect(result.periods.first?.recordedCount == 2)
        #expect(result.periods.first?.assumedCount == 1)
        #expect(result.periods.first?.plannedAmount == 60)
        #expect(result.periods.first?.effectiveAmount == 57)
    }

    @Test func pastBlankDoesNotRequireSurvivingBudgetOrCardRelationships() {
        let unlinked = occurrence(day: 1, planned: 10, actual: 0)
        let orphan = occurrence(day: 1, planned: 20, actual: 0, budget: UUID())
        let result = calculate([unlinked, orphan])
        #expect(result.assumedCount == 2)
        #expect(result.effectiveTotal == 30)
        #expect(result.history.count == 2)
        #expect(unlinked.effectiveVariance(now: date(day: 15), calendar: calendar) == 0)
    }

    @Test func explicitActualOverridesAssumptionAndNegativeActualRemainsPending() {
        let explicit = occurrence(day: 1, planned: 10, actual: 15)
        let invalid = occurrence(day: 1, planned: 20, actual: -1)
        let result = calculate([explicit, invalid])
        #expect(result.recordedCount == 1)
        #expect(result.assumedCount == 0)
        #expect(result.includedCount == 1)
        #expect(result.effectiveTotal == 15)
        #expect(result.totalVariance == 5)
        #expect(!explicit.isAssumed(now: date(day: 15), calendar: calendar))
        #expect(!invalid.isAssumed(now: date(day: 15), calendar: calendar))
        #expect(invalid.effectiveAmount(now: date(day: 15), calendar: calendar) == nil)
    }

    @Test func assumptionStartsAtNextCalendarDayRatherThanAfterElapsedHours() {
        let lateYesterday = occurrence(day: 14, planned: 10, actual: 0, hour: 23)
        let earlyToday = occurrence(day: 15, planned: 20, actual: 0)
        #expect(lateYesterday.isAssumed(now: date(day: 15), calendar: calendar))
        #expect(!earlyToday.isAssumed(now: date(day: 15, hour: 23), calendar: calendar))
        #expect(earlyToday.isAssumed(now: date(day: 16), calendar: calendar))
    }

    @Test func initialRangesIncludeConfiguredNumberOfCalendarPeriodsThroughToday() {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        mondayCalendar.minimumDaysInFirstWeek = 4
        let now = date(day: 7, month: 11, hour: 12)
        let cases: [(BudgetingPeriod, Date)] = [
            (.daily, date(day: 9, month: 10)),
            (.weekly, date(day: 17, month: 8)),
            (.monthly, date(day: 1, month: 12, year: 2025)),
            (.quarterly, date(day: 1, month: 1, year: 2025)),
            (.yearly, date(day: 1, month: 1, year: 2022))
        ]
        for (grouping, expectedStart) in cases {
            let range = PresetDetailCalculator.initialRange(
                workspaceID: workspaceID, presetID: presetID, occurrences: [],
                grouping: grouping, now: now, calendar: mondayCalendar
            )
            #expect(range.start == expectedStart)
            #expect(range.end == date(day: 7, month: 11))
        }
    }

    @Test func weeklyInitialRangeRespectsCalendarFirstWeekday() {
        var sundayCalendar = calendar
        sundayCalendar.firstWeekday = 1
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let now = date(day: 7, month: 11)
        let sunday = PresetDetailCalculator.initialRange(
            workspaceID: workspaceID, presetID: presetID, occurrences: [],
            grouping: .weekly, now: now, calendar: sundayCalendar
        )
        let monday = PresetDetailCalculator.initialRange(
            workspaceID: workspaceID, presetID: presetID, occurrences: [],
            grouping: .weekly, now: now, calendar: mondayCalendar
        )
        #expect(sunday.start == date(day: 16, month: 8))
        #expect(monday.start == date(day: 17, month: 8))
    }

    @Test func periodTotalsRespectEveryGroupingBoundaryAndInclusiveEndDate() {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        let cases: [(grouping: BudgetingPeriod, first: Date, second: Date,
                     firstStart: Date, firstEnd: Date, secondStart: Date, secondEnd: Date)] = [
            (.daily, date(day: 1, hour: 23), date(day: 2),
             date(day: 1), date(day: 1), date(day: 2), date(day: 2)),
            (.weekly, date(day: 4), date(day: 5),
             date(day: 29, month: 12, year: 2025), date(day: 4), date(day: 5), date(day: 11)),
            (.monthly, date(day: 31), date(day: 1, month: 2),
             date(day: 1), date(day: 31), date(day: 1, month: 2), date(day: 28, month: 2)),
            (.quarterly, date(day: 31, month: 3), date(day: 1, month: 4),
             date(day: 1), date(day: 31, month: 3), date(day: 1, month: 4), date(day: 30, month: 6)),
            (.yearly, date(day: 31, month: 12, year: 2025), date(day: 1),
             date(day: 1, year: 2025), date(day: 31, month: 12, year: 2025),
             date(day: 1), date(day: 31, month: 12))
        ]
        for value in cases {
            let result = PresetDetailCalculator.calculate(
                workspaceID: workspaceID, presetID: presetID,
                occurrences: [snapshot(at: value.first, planned: 10, actual: 12),
                              snapshot(at: value.second, planned: 20, actual: 0)],
                startDate: value.first, endDate: value.second, grouping: value.grouping,
                now: date(day: 1, year: 2027), calendar: mondayCalendar
            )
            #expect(result.periods.map(\.startDate) == [value.firstStart, value.secondStart])
            #expect(result.periods.map(\.endDate) == [value.firstEnd, value.secondEnd])
            #expect(result.periods.map(\.plannedAmount) == [10, 20])
            #expect(result.periods.map(\.effectiveAmount) == [12, 20])
            #expect(result.recordedCount == 1)
            #expect(result.assumedCount == 1)
            #expect(result.effectiveTotal == 32)
            #expect(result.totalVariance == 2)
        }
    }

    @Test func occurrencesWithinEachGroupingAggregateWithoutChangingFinancialMath() {
        let cases: [(BudgetingPeriod, Date, Date)] = [
            (.daily, date(day: 1, hour: 1), date(day: 1, hour: 23)),
            (.weekly, date(day: 6), date(day: 7)),
            (.monthly, date(day: 1), date(day: 31)),
            (.quarterly, date(day: 1), date(day: 31, month: 3)),
            (.yearly, date(day: 1), date(day: 31, month: 12))
        ]
        for (grouping, first, second) in cases {
            let result = PresetDetailCalculator.calculate(
                workspaceID: workspaceID, presetID: presetID,
                occurrences: [snapshot(at: first, planned: 10, actual: 12),
                              snapshot(at: second, planned: 20, actual: 0)],
                startDate: first, endDate: second, grouping: grouping,
                now: date(day: 1, year: 2027), calendar: calendar
            )
            #expect(result.periods.count == 1)
            #expect(result.periods.first?.plannedAmount == 30)
            #expect(result.periods.first?.effectiveAmount == 32)
            #expect(result.periods.first?.recordedCount == 1)
            #expect(result.periods.first?.assumedCount == 1)
            #expect(result.averageEffectiveAmount == 16)
            #expect(result.averageVariance == 1)
        }
    }

    @Test func emptyWindowExtendsToLatestOlderEligiblePeriodForEveryGrouping() {
        let older = occurrence(day: 15, planned: 10, actual: 12, month: 6, year: 2020)
        let latest = occurrence(day: 17, planned: 20, actual: 0, month: 9, year: 2021)
        for grouping in BudgetingPeriod.allCases {
            let range = PresetDetailCalculator.initialRange(
                workspaceID: workspaceID, presetID: presetID, occurrences: [older, latest],
                grouping: grouping, now: date(day: 7, month: 11), calendar: calendar
            )
            #expect(range.start == grouping.defaultRange(containing: latest.date, calendar: calendar).start)
            #expect(range.end == date(day: 7, month: 11))
        }
    }

    @Test func eligibleOccurrenceInDefaultWindowPreventsUnnecessaryExtension() {
        let older = occurrence(day: 1, planned: 10, actual: 12, year: 2020)
        let recent = occurrence(day: 6, planned: 20, actual: 0, month: 11)
        let range = PresetDetailCalculator.initialRange(
            workspaceID: workspaceID, presetID: presetID, occurrences: [older, recent],
            now: date(day: 7, month: 11), calendar: calendar
        )
        #expect(range.start == date(day: 1, month: 12, year: 2025))
        #expect(range.end == date(day: 7, month: 11))
    }

    @Test func pendingFutureAndUnrelatedHistoryDoNotInfluenceInitialWindow() {
        let pendingToday = occurrence(day: 7, planned: 20, actual: 0, month: 11)
        let recordedFuture = occurrence(day: 8, planned: 20, actual: 22, month: 11)
        let negative = occurrence(day: 1, planned: 20, actual: -1, year: 2021)
        let otherWorkspace = occurrence(day: 1, planned: 20, actual: 22, year: 2021, workspace: UUID())
        let otherPreset = occurrence(day: 1, planned: 20, actual: 22, year: 2021, preset: UUID())
        let unrelated = [pendingToday, recordedFuture, negative, otherWorkspace, otherPreset]
        let empty = PresetDetailCalculator.initialRange(
            workspaceID: workspaceID, presetID: presetID, occurrences: unrelated,
            now: date(day: 7, month: 11), calendar: calendar
        )
        #expect(empty.start == date(day: 1, month: 12, year: 2025))
        let older = occurrence(day: 15, planned: 10, actual: 12, month: 9, year: 2024)
        let extended = PresetDetailCalculator.initialRange(
            workspaceID: workspaceID, presetID: presetID, occurrences: unrelated + [older],
            now: date(day: 7, month: 11), calendar: calendar
        )
        #expect(extended.start == date(day: 1, month: 9, year: 2024))
    }

    private func snapshot(at date: Date, planned: Double, actual: Double) -> PresetDetailCalculator.Occurrence {
        .init(id: UUID(), workspaceID: workspaceID, sourcePresetID: presetID, sourceBudgetID: nil,
              date: date, plannedAmount: planned, actualAmount: actual)
    }

    private func calculate(
        _ values: [PresetDetailCalculator.Occurrence],
        hideFuture: Bool = false,
        excludeFuture: Bool = false
    ) -> PresetDetailCalculator.Result {
        PresetDetailCalculator.calculate(
            workspaceID: workspaceID, presetID: presetID, occurrences: values,
            startDate: date(day: 1), endDate: date(day: 31),
            hideFuturePlanned: hideFuture, excludeFuturePlanned: excludeFuture,
            now: date(day: 15, hour: 10), calendar: calendar
        )
    }

    private func occurrence(
        day: Int, planned: Double, actual: Double, month: Int = 1, year: Int = 2026,
        hour: Int = 0, workspace: UUID? = nil, preset: UUID? = nil, budget: UUID? = nil
    ) -> PresetDetailCalculator.Occurrence {
        .init(
            id: UUID(), workspaceID: workspace ?? workspaceID, sourcePresetID: preset ?? presetID,
            sourceBudgetID: budget, date: date(day: day, month: month, year: year, hour: hour),
            plannedAmount: planned, actualAmount: actual
        )
    }

    private func date(day: Int, month: Int = 1, year: Int = 2026, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}
