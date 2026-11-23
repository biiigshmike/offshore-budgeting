import Foundation
import SwiftData
import Testing
@testable import Offshore

@MainActor
struct SavingsOutlookCalculatorTests {
    private func date(_ day: Int, hour: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @Test func receivedPaycheckPreservesTheRecurringPlanAndProjection() throws {
        let container = OffshoreBudgetingApp.makeModelContainer(useICloud: false, inMemoryOnly: true)
        let context = container.mainContext
        let workspace = Workspace(name: "Paycheck", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Other", hexColor: "#3B82F6")
        let series = IncomeSeries(
            source: "Payroll", amount: 1_500, isPlanned: true,
            frequencyRaw: RecurrenceFrequency.weekly.rawValue, interval: 1,
            weeklyWeekday: Calendar.current.component(.weekday, from: date(1)),
            monthlyDayOfMonth: 1, monthlyIsLastDay: false, yearlyMonth: 10, yearlyDayOfMonth: 1,
            startDate: date(1), endDate: date(8), workspace: workspace
        )
        let plan = Income(source: series.source, amount: series.amount, date: date(8),
                          isPlanned: true, workspace: workspace, series: series)
        let previousPlan = Income(source: series.source, amount: series.amount, date: date(1),
                                  isPlanned: true, workspace: workspace, series: series)
        context.insert(workspace)
        context.insert(otherWorkspace)
        context.insert(series)
        context.insert(plan)
        context.insert(previousPlan)

        let rent = PlannedExpense(title: "Rent", plannedAmount: 1_000, actualAmount: 1_000, expenseDate: date(8))
        let groceries = VariableExpense(descriptionText: "Groceries", amount: 45, transactionDate: date(8))
        func outlook(incomes: [Income]) -> SavingsOutlookCalculator.Summary {
            SavingsOutlookCalculator.totals(incomes: incomes, plannedExpenses: [rent],
                variableExpenses: [groceries], savingsEntries: [], startDate: date(8), endDate: date(14))
        }
        #expect(outlook(incomes: [previousPlan, plan]).projected == 500)

        let service = TransactionEntryService()
        try service.addIncome(source: plan.source, amount: 1_430, date: date(9), isPlanned: false,
            workspace: otherWorkspace, modelContext: context)
        let before = try service.possibleReceivedIncomeDuplicates(source: plan.source, amount: 1_430, date: date(9),
            workspaceID: workspace.id, modelContext: context)
        #expect(before.isEmpty)

        let receipt = try service.addIncome(source: plan.source, amount: 1_430, date: date(9, hour: 14),
            isPlanned: false, workspace: workspace, plannedIncome: plan, modelContext: context)
        let after = try service.possibleReceivedIncomeDuplicates(source: " payroll ", amount: 1_500, date: date(9),
            workspaceID: workspace.id, modelContext: context)
        #expect(after.map(\.id) == [receipt.id])
        let plannedDayMatches = try service.possibleReceivedIncomeDuplicates(source: plan.source, amount: 1_500, date: date(8),
            workspaceID: workspace.id, modelContext: context)
        #expect(plannedDayMatches.isEmpty)
        #expect(receipt.date == date(9))
        #expect(receipt.series == nil)
        #expect(receipt.sourcePlannedIncomeID == plan.id)
        #expect(throws: TransactionEntryService.ValidationError.receiptAlreadyRecorded) {
            try service.addIncome(source: "Other source", amount: 1_425, date: date(10), isPlanned: false,
                workspace: workspace, plannedIncome: plan, modelContext: context)
        }
        #expect(series.isPlanned && plan.isPlanned && previousPlan.isPlanned)
        #expect(Set((series.incomes ?? []).map(\.id)) == [previousPlan.id, plan.id])
        #expect(plan.date == date(8) && plan.amount == 1_500)
        #expect(outlook(incomes: [previousPlan, plan, receipt]) == .init(actual: 385, projected: 500))
    }

    @Test func sameDayAmountFlagsActualIncomeWithADifferentSource() throws {
        let container = OffshoreBudgetingApp.makeModelContainer(useICloud: false, inMemoryOnly: true)
        let context = container.mainContext
        let workspace = Workspace(name: "Paycheck", hexColor: "#3B82F6")
        context.insert(workspace)
        let service = TransactionEntryService()
        let existing = try service.addIncome(source: "My Actual Income", amount: 123.45, date: date(9),
            isPlanned: false, workspace: workspace, modelContext: context)
        try service.addIncome(source: "Other Income", amount: 123.45, date: date(10),
            isPlanned: false, workspace: workspace, modelContext: context)
        let matches = try service.possibleReceivedIncomeDuplicates(source: "My Planned Income", amount: 123.45,
            date: date(9, hour: 16), workspaceID: workspace.id, modelContext: context)
        #expect(matches.map(\.id) == [existing.id])
        #expect(existing.sourcePlannedIncomeID == nil)
    }

    @Test func linkingPriorDayDepositKeepsBothIncomeEntriesIntact() throws {
        let container = OffshoreBudgetingApp.makeModelContainer(useICloud: false, inMemoryOnly: true)
        let context = container.mainContext
        let workspace = Workspace(name: "Paycheck", hexColor: "#3B82F6")
        let otherWorkspace = Workspace(name: "Other", hexColor: "#3B82F6")
        context.insert(workspace)
        context.insert(otherWorkspace)
        let service = TransactionEntryService()
        let friday = try service.addIncome(source: "Expected paycheck", amount: 1_500, date: date(9),
            isPlanned: true, workspace: workspace, modelContext: context)
        let thursday = try service.addIncome(source: "Bank deposit", amount: 1_430, date: date(8),
            isPlanned: false, workspace: workspace, modelContext: context)
        let otherReceipt = try service.addIncome(source: "Bank deposit", amount: 1_430, date: date(8),
            isPlanned: false, workspace: otherWorkspace, modelContext: context)

        #expect(throws: TransactionEntryService.ValidationError.receivedIncomeUnavailable) {
            try service.linkReceivedIncome(otherReceipt, to: friday, workspaceID: workspace.id, modelContext: context)
        }
        try service.linkReceivedIncome(thursday, to: friday, workspaceID: workspace.id, modelContext: context)

        let freshContext = ModelContext(container)
        let allIncome = try freshContext.fetch(FetchDescriptor<Income>())
        let receipt = try #require(allIncome.first { $0.id == thursday.id })
        #expect(allIncome.filter { $0.workspace?.id == workspace.id }.count == 2)
        #expect(receipt.sourcePlannedIncomeID == friday.id)
        #expect(receipt.source == "Bank deposit" && receipt.amount == 1_430 && receipt.date == date(8))
        #expect(friday.isPlanned && friday.amount == 1_500 && friday.date == date(9))
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
