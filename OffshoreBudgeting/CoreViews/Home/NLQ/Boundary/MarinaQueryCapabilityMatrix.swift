import Foundation

enum MarinaQueryCapability: String, Codable, Equatable, CaseIterable, Sendable {
    case lookupDetails
    case listRows
    case total
    case average
    case rank
    case compare
    case groupedBreakdown
    case linkedObjectSummary
    case unsupportedWithClarification
}

struct MarinaQueryCapabilityMatrix {
    static func capabilities(for type: MarinaLookupObjectType) -> Set<MarinaQueryCapability> {
        switch type {
        case .workspace:
            return [.lookupDetails, .linkedObjectSummary]
        case .budget:
            return [.lookupDetails, .listRows, .total, .compare, .linkedObjectSummary]
        case .card:
            return [.lookupDetails, .listRows, .total, .average, .rank, .compare, .groupedBreakdown, .linkedObjectSummary]
        case .category:
            return [.lookupDetails, .listRows, .total, .average, .rank, .compare, .groupedBreakdown, .linkedObjectSummary]
        case .preset:
            return [.lookupDetails, .listRows, .total, .rank, .groupedBreakdown, .linkedObjectSummary]
        case .variableExpense, .plannedExpense:
            return [.lookupDetails, .listRows, .rank, .compare]
        case .income:
            return [.lookupDetails, .listRows, .total, .average, .rank, .compare, .groupedBreakdown]
        case .incomeSeries:
            return [.lookupDetails, .listRows, .linkedObjectSummary]
        case .savingsAccount:
            return [.lookupDetails, .listRows, .total, .rank, .linkedObjectSummary]
        case .savingsLedgerEntry:
            return [.lookupDetails, .listRows, .rank, .compare]
        case .reconciliationAccount:
            return [.lookupDetails, .listRows, .total, .rank, .linkedObjectSummary]
        case .reconciliationItem, .expenseAllocation:
            return [.lookupDetails, .listRows, .rank, .compare]
        case .importMerchantRule, .assistantAliasRule:
            return [.lookupDetails, .listRows]
        case .unknown:
            return [.unsupportedWithClarification]
        }
    }
}
