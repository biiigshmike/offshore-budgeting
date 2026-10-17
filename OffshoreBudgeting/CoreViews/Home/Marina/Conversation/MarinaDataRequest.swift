import Foundation

/// A database request, never a natural-language interpretation or executable query.
struct MarinaDataRequest: Codable, Sendable {
    enum Tool: String, Codable, Sendable { case findRecords, expenses, income, budgetSummary, accounts }
    enum Scope: String, Codable, Sendable { case all, variable, planned, savings, reconciliation }
    enum State: String, Codable, Sendable { case all, actual, planned }
    enum Grouping: String, Codable, Sendable { case none, card, category, merchant, source }
    enum Sort: String, Codable, Sendable { case newest, oldest, largest, smallest }
    enum ExpenseMeasure: String, Codable, Sendable { case budgetImpact, ledger, spending, planned, actual }
    enum PeriodUnit: String, Codable, Sendable { case day, week, month, quarter, year }
    enum RelativePeriod: String, Codable, Sendable { case selectedPeriod, previousPeriod, currentMonth, previousMonth, yearToDate, nextSevenDays }
    var relativePeriod: RelativePeriod? = nil
    var periodUnit: PeriodUnit? = nil
    var tool: Tool
    var allTime: Bool = false
    var presetID: String? = nil
    var recordKind: String? = nil
    var expenseMeasure: ExpenseMeasure = .budgetImpact
    var includeFuture: Bool = false
    var startDate: String? = nil
    var endDate: String? = nil
    var cardID: String? = nil
    var categoryID: String? = nil
    var budgetID: String? = nil
    var accountID: String? = nil
    var search: String? = nil
    var scope: Scope = .all
    var state: State = .all
    var grouping: Grouping = .none
    var sort: Sort = .newest
    var offset: Int = 0
    var limit: Int = 20
    var comparisonAllTime: Bool = false
    var comparisonPeriod: RelativePeriod? = nil
    struct Filter: Codable, Sendable {
        var cardID: String? = nil
        var categoryID: String? = nil
        var budgetID: String? = nil
        var presetID: String? = nil
        var search: String? = nil
    }
    var comparisonFilter: Filter? = nil
    var comparisonStartDate: String? = nil
    var comparisonEndDate: String? = nil
    var hypotheticalSpending: Double? = nil
}
