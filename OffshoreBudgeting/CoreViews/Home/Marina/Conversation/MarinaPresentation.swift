import Foundation

/// Immutable display values saved with a conversation; never live SwiftData models.
struct MarinaPresentation: Codable, Equatable, Sendable, Identifiable {
    struct IncomeProgressSnapshot: Codable, Equatable, Sendable {
        let actual: Double
        let planned: Double
    }
    struct BudgetPaceSnapshot: Codable, Equatable, Sendable {
        let actual: Double
        let expected: Double
        let planned: Double
        let difference: Double
        let elapsedPercent: Double
    }
    struct PresetSnapshot: Codable, Equatable, Sendable {
        let id: String
        let title: String
        let plannedAmount: Double
        let schedule: String
        let assignedBudgetCount: Int
    }
    struct CardSnapshot: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let theme: String
        let effect: String
    }
    struct Record: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let kind: String
        let title: String
        var date: String? = nil
        var amount: Double? = nil
        var detail: String? = nil
        var categoryName: String? = nil
        var categoryColorHex: String? = nil
        var cardName: String? = nil
        var plannedAmount: Double? = nil
        var actualAmount: Double? = nil
        var preset: PresetSnapshot? = nil
    }
    struct ChartSlice: Codable, Equatable, Sendable {
        let name: String
        let colorHex: String
        let amount: Double
    }
    struct ChartPoint: Codable, Equatable, Sendable, Identifiable {
        let id: String
        let label: String
        let value: Double
        var colorHex: String? = nil
        var date: String? = nil
        var slices: [ChartSlice]? = nil
    }
    struct Pagination: Codable, Equatable, Sendable {
        let workspaceID: UUID
        var request: MarinaDataRequest
        var visibleCount: Int
        var calculationDate: Date = Date()
        var excludeFuturePlanned: Bool = false
        var excludeFutureVariable: Bool = false
    }
    var id: String
    var purpose: MarinaDataRequest.Purpose? = nil
    var forcePresentation: Bool? = nil
    var identityKey: String? = nil
    var topicKey: String? = nil
    var incomeProgress: IncomeProgressSnapshot? = nil
    var budgetPace: BudgetPaceSnapshot? = nil
    var operation: MarinaDataRequest.Operation
    var title: String
    var scopeLabel: String
    var qualifier: String? = nil
    var metrics: [MarinaDataResult.Metric] = []
    var records: [Record] = []
    var chartPoints: [ChartPoint] = []
    var card: CardSnapshot? = nil
    var totalCount: Int = 0
    var pagination: Pagination? = nil
    var isEmpty: Bool = false
    var isUpdated: Bool = false
}
