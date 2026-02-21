import Foundation
import SwiftUI

enum DebugScreenshotFormDefaults {

    // MARK: - Gate

    static var isEnabled: Bool {
        #if DEBUG
        return DebugSeeder.isScreenshotModeEnabledForDebugTools
        #else
        return false
        #endif
    }

    // MARK: - Text Defaults

    static let workspaceName: String = "Personal Snapshot"
    static let categoryName: String = "Groceries Snapshot"
    static let cardName: String = "Daily Spend"
    static let accountName: String = "Alex Snapshot"
    static let expenseDescription: String = "Trader Joe's Run"
    static let incomeSource: String = "Paycheck"
    static let presetTitle: String = "Internet Bill"

    // MARK: - Amount Defaults

    static let expenseAmountText: String = "86.42"
    static let incomeAmountText: String = "1500.00"
    static let presetAmountText: String = "80.00"
    static let categoryLimitMinText: String = "100.00"
    static let categoryLimitMaxText: String = "500.00"
    static let splitAmountText: String = "24.00"
    static let offsetAmountText: String = "18.00"
    static let savingsOffsetAmountText: String = "15.00"
    static let plannedExpenseActualAmountText: String = "64.00"

    // MARK: - Lookups

    static func preferredCardID(in cards: [Card]) -> UUID? {
        preferredID(in: cards, preferredNames: ["Checking", "Apple Card", cardName]) { $0.name }
    }

    static func preferredCategoryID(in categories: [Category]) -> UUID? {
        preferredID(in: categories, preferredNames: ["Groceries", "Dining", categoryName]) { $0.name }
    }

    static func preferredAllocationAccountID(in accounts: [AllocationAccount]) -> UUID? {
        preferredID(in: accounts, preferredNames: ["Alex", "Jordan", accountName]) { $0.name }
    }

    private static func preferredID<T>(
        in values: [T],
        preferredNames: [String],
        name: (T) -> String
    ) -> UUID? where T: Identifiable, T.ID == UUID {
        for preferred in preferredNames {
            if let match = values.first(where: { normalized($0, name: name) == normalized(preferred) }) {
                return match.id
            }
        }
        return values.first?.id
    }

    private static func normalized<T>(_ value: T, name: (T) -> String) -> String {
        normalized(name(value))
    }

    private static func normalized(_ string: String) -> String {
        string
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}
