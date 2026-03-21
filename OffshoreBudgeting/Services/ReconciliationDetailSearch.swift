import Foundation

enum ReconciliationDetailSearch {

    static func matches(
        row: AllocationLedgerService.LedgerRow,
        categoryName: String?,
        query: SearchQuery
    ) -> Bool {
        if !SearchMatch.matchesDateRange(query, date: row.date) { return false }
        if !SearchMatch.matchesTextTerms(query, in: [row.title, row.subtitle, row.type.rawValue, categoryName]) {
            return false
        }
        if !SearchMatch.matchesAmountDigitTerms(query, amounts: [row.amount]) { return false }
        return true
    }
}

enum ReconciliationDetailEmptyState {

    static func message(
        hasHistory: Bool,
        isSearching: Bool,
        selectedCategoryCount: Int
    ) -> String {
        if isSearching {
            if selectedCategoryCount == 1 {
                return "No ledger entries match your search and selected category in this date range."
            }
            if selectedCategoryCount > 1 {
                return "No ledger entries match your search and selected categories in this date range."
            }
            if hasHistory {
                return "No ledger entries match your search in this date range."
            }
            return "No ledger entries match your search."
        }

        if selectedCategoryCount == 1 {
            return "No ledger entries match the selected category in this date range."
        }
        if selectedCategoryCount > 1 {
            return "No ledger entries match the selected categories in this date range."
        }
        if hasHistory {
            return "No ledger entries yet for this date range."
        }
        return "No ledger entries yet."
    }
}
