import Foundation

/// A database request, never a natural-language interpretation or executable query.
nonisolated struct MarinaDataRequest: Codable, Equatable, Sendable {
    enum Tool: String, Codable, Equatable, Sendable { case findRecords, expenses, income, budgetSummary, accounts }
    enum Scope: String, Codable, Equatable, Sendable { case all, variable, planned, savings, reconciliation }
    enum State: String, Codable, Equatable, Sendable { case all, actual, planned }
    enum Grouping: String, Codable, Equatable, Sendable { case none, card, category, merchant, source }
    enum Sort: String, Codable, Equatable, Sendable { case newest, oldest, largest, smallest }
    enum ExpenseMeasure: String, Codable, Equatable, Sendable { case budgetImpact, ledger, spending, planned, actual }
    enum PeriodUnit: String, Codable, Equatable, Sendable { case day, week, month, quarter, year }
    enum ChartIntent: String, Codable, Equatable, Sendable { case periodComparison, movementOverTime }
    enum RelativePeriod: String, Codable, Equatable, Sendable { case selectedPeriod, previousPeriod, currentMonth, previousMonth, yearToDate, nextSevenDays }
    enum Operation: String, Codable, Equatable, Sendable { case summary, transactions, ranking, comparison, trend, share, inventory }
    enum Purpose: String, Codable, Equatable, Sendable {
        case budgetPace, incomeProgress, upcomingPresets
        case cardSummary, budgetDetails, categoryAvailability, nextPlannedExpense
        case spendingPatterns, incomeTimeline, savingsOutlook, savingsTimeline, budgetCards, budgetPresets
    }
    enum MetricFocus: String, Codable, Equatable, Sendable {
        case total, count, groupCount, average, averagePerPeriod, share, actualSavings, projectedSavings, maxSavings, savingsGap, savingsProgress
        case remainingRoom, safeSpend, incomeCoverage, recurringCommitments, spendingRate, projectedSpending
        case plannedIncome, receivedIncome, plannedSpending, recordedPlannedSpending, effectivePlannedSpending, variableSpending
    }
    enum AvailabilityFilter: String, Codable, Equatable, Sendable { case all, over, near, overOrNear, ok, unlimited }
    enum TransactionFilter: String, Codable, Equatable, Sendable { case all, debit, credit, adjustment, split, reconciliationOffset, savingsOffset }
    var metric: MetricFocus? = nil
    var chartIntent: ChartIntent? = nil
    /// Canonical, exact merchant selected from a workspace lookup. `search` remains broad discovery.
    var merchantName: String? = nil
    var availabilityFilter: AvailabilityFilter? = nil
    var transactionFilter: TransactionFilter? = nil
    var categoryIDs: [String]? = nil
    /// A budget used only to resolve dates, never to restrict the financial population.
    var periodBudgetID: String? = nil
    var positiveOnly: Bool? = nil
    var compareLeaders: Bool? = nil
    var purpose: Purpose? = nil
    var forcePresentation: Bool? = nil
    var operation: Operation = .summary
    var relativePeriod: RelativePeriod? = nil
    var periodUnit: PeriodUnit? = nil
    var tool: Tool
    var allTime: Bool = false
    var presetID: String? = nil
    var recordKind: String? = nil
    var exactRecordName: Bool? = nil
    var expectedRecordID: String? = nil
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
    nonisolated struct Filter: Codable, Equatable, Sendable {
        var cardID: String? = nil
        var categoryID: String? = nil
        var categoryIDs: [String]? = nil
        var budgetID: String? = nil
        var presetID: String? = nil
        var search: String? = nil
        var merchantName: String? = nil
    }
    var comparisonFilter: Filter? = nil
    var comparisonStartDate: String? = nil
    var comparisonEndDate: String? = nil
    var hypotheticalSpending: Double? = nil
}
