import Foundation
import Testing
@testable import Offshore

@MainActor
struct SavingsOutlookCalculatorTests {
    private func date(_ day: Int, hour: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func reversedRangeIncludesBothBoundaryDates() {
        let range = SavingsOutlookDateRange(startDate: date(2), endDate: date(1))
        let incomes = [
            Income(source: "First day", amount: 100, date: date(1), isPlanned: false),
            Income(source: "Last day", amount: 200, date: date(2), isPlanned: false),
            Income(source: "Outside", amount: 400, date: date(3), isPlanned: false)
        ]
        let points = SavingsOutlookCalculator.cumulativePoints(
            ranges: [range], incomes: incomes, plannedExpenses: [], variableExpenses: [], savingsEntries: []
        )
        #expect(points.first?.startDate == date(1))
        #expect(points.first?.endDate == date(2))
        #expect(points.first?.actual == 300)
    }

    @Test func cumulativeSavingsEndAtTheSameTotalIncludingManualAdjustments() throws {
        let incomes = [
            Income(source: "Expected", amount: 1_000, date: date(1), isPlanned: true),
            Income(source: "Received", amount: 800, date: date(1), isPlanned: false)
        ]
        let planned = [PlannedExpense(title: "Rent", plannedAmount: 200, actualAmount: 150, expenseDate: date(1))]
        let variable = [VariableExpense(descriptionText: "Food", amount: 50, transactionDate: date(2))]
        let entries = [
            SavingsLedgerEntry(date: date(2, hour: 23), amount: 75, note: "Adjustment", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue),
            SavingsLedgerEntry(date: date(2), amount: 500, note: "Period close", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue),
            SavingsLedgerEntry(date: date(3), amount: 100, note: "Outside", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue)
        ]
        let end = date(3).addingTimeInterval(-0.001)
        let ranges = [SavingsOutlookDateRange(startDate: date(1), endDate: date(2).addingTimeInterval(-0.001)),
                      SavingsOutlookDateRange(startDate: date(2), endDate: end)]
        let points = SavingsOutlookCalculator.cumulativePoints(ranges: ranges, incomes: incomes,
            plannedExpenses: planned, variableExpenses: variable, savingsEntries: entries)
        let total = SavingsOutlookCalculator.totals(incomes: incomes, plannedExpenses: planned,
            variableExpenses: variable, savingsEntries: entries, startDate: date(1), endDate: end)
        #expect(points.count == 2)
        #expect(points.first?.actual == 650)
        #expect(points.last?.actual == 675)
        #expect(points.last?.projected == 800)
        #expect(points.last?.actual == total.actual)
        #expect(points.last?.projected == total.projected)
        #expect(total.gap == -125)
    }

    @Test func progressPreservesTrueRatiosAndOnlyClampsTheGauge() {
        let over = SavingsOutlookCalculator.progress(projected: 100, actual: 150)
        #expect(over.mode == .projection && over.ratio == 1.5 && over.gaugeValue == 1)
        let negative = SavingsOutlookCalculator.progress(projected: 100, actual: -50)
        #expect(negative.ratio == -0.5 && negative.gaugeValue == 0)
        let breakEven = SavingsOutlookCalculator.progress(projected: -100, actual: 25)
        #expect(breakEven.mode == .breakEven && breakEven.ratio == 1.25 && breakEven.gaugeValue == 1)
        let unavailable = SavingsOutlookCalculator.progress(projected: 0, actual: 20)
        #expect(unavailable.mode == .unavailable && unavailable.ratio == nil)
    }

    @Test func cumulativeSavingsPreserveEmptyBucketsAndSignedActivity() {
        let credit = VariableExpense(descriptionText: "Refund", amount: 20, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: date(2))
        let adjustment = VariableExpense(descriptionText: "Ledger adjustment", amount: 500, kindRaw: VariableExpenseKind.adjustment.rawValue, transactionDate: date(2))
        let ranges = [SavingsOutlookDateRange(startDate: date(1), endDate: date(2).addingTimeInterval(-0.001)),
                      SavingsOutlookDateRange(startDate: date(2), endDate: date(3).addingTimeInterval(-0.001))]
        let points = SavingsOutlookCalculator.cumulativePoints(ranges: ranges, incomes: [],
            plannedExpenses: [], variableExpenses: [credit, adjustment], savingsEntries: [])
        #expect(points.map(\.actual) == [0, 20])
        #expect(points.map(\.projected) == [0, 0])
    }
}
