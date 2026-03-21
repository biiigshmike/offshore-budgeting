import Foundation
import Testing
@testable import Offshore

struct ReconciliationDetailSearchTests {

    @Test func reconciliationSearch_matchesChargeTitleAndCategory() {
        let row = AllocationLedgerService.LedgerRow(
            id: "charge-1",
            type: .charge,
            date: Self.makeDate(year: 2026, month: 3, day: 12),
            title: "Trader Joe's",
            subtitle: "Chase Sapphire • Groceries",
            amount: 42.13,
            settlementID: nil,
            allocationID: UUID(),
            linkedExpenseID: nil,
            isLinkedSettlement: false
        )

        let query = SearchQueryParser.parse("trader groceries")

        #expect(
            ReconciliationDetailSearch.matches(
                row: row,
                categoryName: "Groceries",
                query: query
            )
        )
    }

    @Test func reconciliationSearch_matchesSettlementAmountDigits() {
        let row = AllocationLedgerService.LedgerRow(
            id: "settlement-1",
            type: .settlement,
            date: Self.makeDate(year: 2026, month: 3, day: 12),
            title: "Venmo settle up",
            subtitle: "Apple Card • Travel",
            amount: -128.45,
            settlementID: UUID(),
            allocationID: nil,
            linkedExpenseID: nil,
            isLinkedSettlement: false
        )

        let query = SearchQueryParser.parse("12845")

        #expect(
            ReconciliationDetailSearch.matches(
                row: row,
                categoryName: "Travel",
                query: query
            )
        )
    }

    @Test func reconciliationSearch_matchesParsedDateWithinCurrentView() {
        let matchingRow = AllocationLedgerService.LedgerRow(
            id: "charge-2",
            type: .charge,
            date: Self.makeDate(year: 2026, month: 3, day: 12),
            title: "Gas Station",
            subtitle: "Freedom • Gas",
            amount: 60,
            settlementID: nil,
            allocationID: UUID(),
            linkedExpenseID: nil,
            isLinkedSettlement: false
        )
        let nonMatchingRow = AllocationLedgerService.LedgerRow(
            id: "charge-3",
            type: .charge,
            date: Self.makeDate(year: 2026, month: 3, day: 13),
            title: "Gas Station",
            subtitle: "Freedom • Gas",
            amount: 60,
            settlementID: nil,
            allocationID: UUID(),
            linkedExpenseID: nil,
            isLinkedSettlement: false
        )

        let query = SearchQueryParser.parse("03/12/2026")

        #expect(
            ReconciliationDetailSearch.matches(
                row: matchingRow,
                categoryName: "Gas",
                query: query
            )
        )
        #expect(
            ReconciliationDetailSearch.matches(
                row: nonMatchingRow,
                categoryName: "Gas",
                query: query
            ) == false
        )
    }

    @Test func reconciliationEmptyState_prefersSearchAwareMessaging() {
        #expect(
            ReconciliationDetailEmptyState.message(
                hasHistory: true,
                isSearching: true,
                selectedCategoryCount: 0
            ) == "No ledger entries match your search in this date range."
        )
        #expect(
            ReconciliationDetailEmptyState.message(
                hasHistory: true,
                isSearching: true,
                selectedCategoryCount: 2
            ) == "No ledger entries match your search and selected categories in this date range."
        )
        #expect(
            ReconciliationDetailEmptyState.message(
                hasHistory: false,
                isSearching: false,
                selectedCategoryCount: 0
            ) == "No ledger entries yet."
        )
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = year
        components.month = month
        components.day = day
        return components.date!
    }
}
