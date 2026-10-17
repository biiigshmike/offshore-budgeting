import Foundation
import FoundationModels

@available(iOS 26.0, macOS 26.0, *)
@Generable
enum MarinaDomain: String, Codable, Sendable { case expenses, plannedExpenses, income, budgets, savings, reconciliation }
@available(iOS 26.0, macOS 26.0, *)
@Generable
enum MarinaMetric: String, Codable, Sendable { case total, count, average, balance, ledger, budgetImpact, owned, categoryBreakdown, timeTrend, comparison, projectedSavings, actualSurplus }
@available(iOS 26.0, macOS 26.0, *)
@Generable
enum MarinaRecordState: String, Codable, Sendable { case all, actual, planned }
@available(iOS 26.0, macOS 26.0, *)
@Generable
enum MarinaEntityKind: String, Codable, Sendable { case card, category, budget, savingsAccount, reconciliationAccount }

@available(iOS 26.0, macOS 26.0, *)
@Generable
struct MarinaEntityRequest: Sendable {
    var kind: MarinaEntityKind
    @Guide(description: "Exact entity name explicitly requested, not a date or ordinary question text. Empty string lists available names of this kind.")
    var name: String
}

@available(iOS 26.0, macOS 26.0, *)
struct MarinaQueryRequest: Codable, Sendable {
    var domain: MarinaDomain = .expenses
    var metric: MarinaMetric = .total
    var startDate: String? = nil
    var endDate: String? = nil
    var cardID: String? = nil
    var categoryID: String? = nil
    var accountID: String? = nil
    var budgetID: String? = nil
    var cardName: String? = nil
    var categoryName: String? = nil
    var accountName: String? = nil
    var budgetName: String? = nil
    var text: String? = nil
    var minAmount: Double? = nil
    var maxAmount: Double? = nil
    var state: MarinaRecordState = .all
    var includeFuture: Bool? = nil
    var comparisonStartDate: String? = nil
    var comparisonEndDate: String? = nil
}

@available(iOS 26.0, macOS 26.0, *)
struct MarinaRecord: Codable, Sendable, Identifiable {
    var id: UUID
    var domain: MarinaDomain
    var title: String
    var date: Date
    var amount: Double
    var subtitle: String
}
@available(iOS 26.0, macOS 26.0, *)
struct MarinaChartPoint: Codable, Sendable, Identifiable {
    var id: String
    var label: String
    var value: Double
    var date: Date?
}
@available(iOS 26.0, macOS 26.0, *)
struct MarinaResult: Codable, Sendable, Identifiable {
    var id: String
    var title: String
    var detail: String
    var createdAt: Date
    var records: [MarinaRecord]
    var points: [MarinaChartPoint]
    var total: Double?
    var count: Int
    var metric: MarinaMetric? = nil
    var valueKind: String? = nil
    var chartKind: String? = nil
}

enum MarinaQueryError: LocalizedError {
    case invalid(String)
    case toolLimitExceeded
    var errorDescription: String? {
        switch self {
        case .invalid(let message): message
        case .toolLimitExceeded: "Marina could not resolve this request within the tool-call limit."
        }
    }
}
