import Foundation

/// Optional, immutable report facts shared by the tool, narration and saved visual.
/// Every amount is calculated before pagination; no model arithmetic is required.
struct MarinaReport: Codable, Equatable, Sendable {
    struct Group: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var title: String
        var amount: Double
        var colorHex: String? = nil
        var plannedAmount: Double? = nil
        var variableAmount: Double? = nil
        var count: Int? = nil
        var sharePercent: Double? = nil
    }
    struct CategoryAvailability: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var name: String
        var colorHex: String
        var minimum: Double? = nil
        var maximum: Double? = nil
        var planned: Double
        var variable: Double
        var available: Double? = nil
        var percentUsed: Double? = nil
        var status: String
    }
    struct Transaction: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var transactionKind: String? = nil
        var grossAmount: Double
        var recordedAmount: Double? = nil
        var effectiveAmount: Double
        var splitAmount: Double = 0
        var reconciliationOffset: Double = 0
        var savingsOffset: Double = 0
        var budgetImpact: Double
        var accountName: String? = nil
        var sourcePresetID: String? = nil
        var sourcePresetName: String? = nil
        var sourceBudgetID: String? = nil
        var sourceBudgetName: String? = nil
    }
    struct Point: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var label: String
        var date: String? = nil
        var value: Double
    }
    struct Series: Codable, Equatable, Sendable, Identifiable {
        var id: String
        var label: String
        var points: [Point]
    }
    struct Peak: Codable, Equatable, Sendable {
        var startDate: String
        var endDate: String
        var amount: Double
        var leadingCategory: String? = nil
        var leadingCategoryAmount: Double? = nil
        var contributors: [Group]? = nil
        var transactionIDs: [String]? = nil
        var drilldownRequest: MarinaDataRequest? = nil
    }
    struct Leader: Codable, Equatable, Sendable {
        var scope: String
        var title: String?
        var amount: Double?
        var tiedCount: Int = 1
    }
    struct CalculationPolicy: Codable, Equatable, Sendable {
        var excludesFuturePlanned: Bool
        var excludesFutureVariable: Bool
        var excludedPlannedCount: Int
        var excludedVariableCount: Int
        var dateBudgetName: String? = nil
    }
    var categories: [CategoryAvailability]? = nil
    var groups: [Group]? = nil
    var merchants: [Group]? = nil
    var frequentMerchants: [Group]? = nil
    var transactions: [Transaction]? = nil
    var series: [Series]? = nil
    var cumulative: Bool? = nil
    var peak: Peak? = nil
    var leaders: [Leader]? = nil
    var policy: CalculationPolicy? = nil
    var budgetName: String? = nil
    var progressMode: String? = nil
}
