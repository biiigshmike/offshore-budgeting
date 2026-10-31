import Foundation
import Testing
@testable import Offshore

@MainActor
struct SavingsCalculationExplanationTests {
    private let start = Date(timeIntervalSince1970: 1_000)
    private let end = Date(timeIntervalSince1970: 2_000)

    @Test func outlookExplainsUnrecordedBillsRefundsAndMoneyPaidFromSavings() throws {
        let expected = Income(source: "Expected", amount: 1_200, date: start, isPlanned: true)
        let received = Income(source: "Received", amount: 1_000, date: end, isPlanned: false)
        let outside = Income(source: "Outside", amount: 9_999, date: end.addingTimeInterval(1), isPlanned: false)
        let bill = PlannedExpense(title: "Upcoming bill", plannedAmount: 100, actualAmount: 0, expenseDate: start)
        let purchase = VariableExpense(descriptionText: "Purchase", amount: 100, transactionDate: start)
        purchase.savingsLedgerEntry = SavingsLedgerEntry(
            date: start, amount: -40, note: "Covered", kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue
        )
        let refund = VariableExpense(
            descriptionText: "Refund", amount: 20, kindRaw: VariableExpenseKind.credit.rawValue, transactionDate: start
        )
        let adjustment = VariableExpense(
            descriptionText: "Ledger adjustment", amount: 5_000,
            kindRaw: VariableExpenseKind.adjustment.rawValue, transactionDate: start
        )
        let entries = [
            SavingsLedgerEntry(date: start, amount: -50, note: "Set aside", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue),
            SavingsLedgerEntry(date: start, amount: 999, note: "Closed period", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue)
        ]

        let sections = SavingsCalculationExplanation.outlook(
            incomes: [expected, received, outside], plannedExpenses: [bill],
            variableExpenses: [purchase, refund, adjustment], savingsEntries: entries,
            startDate: start, endDate: end
        )
        let projected = try #require(sections.first { $0.id == "projected" })
        let actual = try #require(sections.first { $0.id == "actual" })
        #expect(projected.rows.last?.amount == 1_100)
        #expect(actual.rows.last?.amount == 810)
        #expect(actual.rows.first { $0.id == "planned" }?.amount == -100)
        #expect(actual.rows.first { $0.id == "variable" }?.amount == -40)
        for section in sections {
            let result = try #require(section.rows.first { $0.isTotal })
            #expect(section.rows.filter { !$0.isTotal }.reduce(0) { $0 + $1.amount } == result.amount)
        }
    }

    @Test func runningTotalShowsAllDatesAndExcludesLegacyReconciliationMirrors() throws {
        let entries = [
            SavingsLedgerEntry(date: start, amount: 500, note: "Closed period", kindRaw: SavingsLedgerEntryKind.periodClose.rawValue),
            SavingsLedgerEntry(date: end, amount: -40, note: "Purchase", kindRaw: SavingsLedgerEntryKind.expenseOffset.rawValue),
            SavingsLedgerEntry(date: end, amount: -200, note: "Set aside", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue),
            SavingsLedgerEntry(date: end.addingTimeInterval(100), amount: 10, note: "Adjustment", kindRaw: SavingsLedgerEntryKind.manualAdjustment.rawValue),
            SavingsLedgerEntry(date: start, amount: 999, note: "Legacy mirror", kindRaw: SavingsLedgerEntryKind.reconciliationSettlement.rawValue)
        ]
        let section = try #require(SavingsCalculationExplanation.runningTotal(entries: entries).first)
        #expect(section.rows.last?.amount == 270)
        #expect(section.rows.first { $0.id == "adjustments" }?.amount == -190)
        #expect(section.rows.filter { !$0.isTotal }.reduce(0) { $0 + $1.amount } == 270)
    }
}
