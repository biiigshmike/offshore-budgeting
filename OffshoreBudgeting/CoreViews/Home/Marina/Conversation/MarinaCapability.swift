import Foundation

/// Product capabilities shared by translation and execution. These identifiers describe
/// existing reads; they do not inspect user wording or select a model session.
nonisolated enum MarinaCapability: String, Codable, CaseIterable, Sendable {
    case expenses, transactions, largestExpense, smallestExpense, cardSummary
    case rankedSpending, categoryRanking, cardRanking, merchantRanking
    case spendingShares, spendingComparison, leaderComparison
    case spendingTrend, spendingPatterns, upcomingPresets, nextPlannedExpense
    case income, incomeTransactions, incomeGroups, incomeProgress, incomeTimeline, incomeTrend, incomeComparison
    case budgetOverview, budgetDetails, budgetPace, categoryAvailability
    case savingsOutlook, savingsTimeline, savingsTrend, linkedCards, linkedPresets
    case accountBalances, accountActivity, inventory

    var tool: MarinaDataRequest.Tool {
        switch self {
        case .expenses, .transactions, .largestExpense, .smallestExpense, .cardSummary,
             .rankedSpending, .categoryRanking, .cardRanking, .merchantRanking,
             .spendingShares, .spendingComparison, .leaderComparison,
             .spendingTrend, .spendingPatterns, .upcomingPresets, .nextPlannedExpense: .expenses
        case .income, .incomeTransactions, .incomeGroups, .incomeProgress, .incomeTimeline, .incomeTrend, .incomeComparison: .income
        case .budgetOverview, .budgetDetails, .budgetPace, .categoryAvailability,
             .savingsOutlook, .savingsTimeline, .savingsTrend, .linkedCards, .linkedPresets: .budgetSummary
        case .accountBalances, .accountActivity: .accounts
        case .inventory: .findRecords
        }
    }

    var summary: String {
        switch self {
        case .expenses: "Expense total, count or average."
        case .transactions: "Matching expense records, including kind, split and offset details."
        case .largestExpense: "Highest matching expense."
        case .smallestExpense: "Lowest matching expense."
        case .cardSummary: "One selected card's planned, variable and combined spending."
        case .rankedSpending: "Ordered category, card or merchant spending."
        case .categoryRanking: "Categories ordered by spending, including the highest or lowest category."
        case .cardRanking: "Cards ordered by spending, including the highest or lowest card."
        case .merchantRanking: "Merchants ordered by spending, including the highest or lowest merchant."
        case .spendingShares: "Category, card or merchant shares of spending."
        case .spendingComparison: "The same or explicitly selected spending subjects in two periods."
        case .leaderComparison: "Each period's leading category, card or merchant and their difference."
        case .spendingTrend: "Chronological spending totals per period."
        case .spendingPatterns: "Compact spending chart, peak, categories, merchants and purchase frequency."
        case .upcomingPresets: "Upcoming unrecorded preset occurrences."
        case .nextPlannedExpense: "Next scheduled expense using Home's rules."
        case .income: "Income total, count or average for planned, received or both states."
        case .incomeTransactions: "Matching income records."
        case .incomeGroups: "Income grouped by source or card."
        case .incomeProgress: "Received income against planned income."
        case .incomeTimeline: "Separate planned and received income timelines."
        case .incomeTrend: "Income totals per period for the requested state."
        case .incomeComparison: "Income subjects in two periods."
        case .budgetOverview: "Workspace or selected budget overview."
        case .budgetDetails: "Complete budget income, expense and savings components."
        case .budgetPace: "Budget pace, safe spending and projected spending."
        case .categoryAvailability: "Category goals, limits, spending, remaining amount and status."
        case .savingsOutlook: "Actual, projected and maximum savings, gap and progress."
        case .savingsTimeline: "Separate cumulative actual and projected savings timelines."
        case .savingsTrend: "Savings outcomes per period, not cumulative."
        case .linkedCards: "Cards linked to a selected budget."
        case .linkedPresets: "Preset schedules linked to a selected budget."
        case .accountBalances: "Savings or reconciliation account balances."
        case .accountActivity: "Savings or reconciliation ledger activity."
        case .inventory: "Workspace record discovery and inventories."
        }
    }

    var fixedGrouping: MarinaDataRequest.Grouping? {
        switch self {
        case .categoryRanking: .category
        case .cardRanking: .card
        case .merchantRanking: .merchant
        default: nil
        }
    }
    var usesGrouping: Bool { fixedGrouping != nil || [.rankedSpending, .spendingShares, .leaderComparison, .incomeGroups].contains(self) }
    var requiresGroupingSelection: Bool { usesGrouping && fixedGrouping == nil }
    var isComparison: Bool { [.spendingComparison, .leaderComparison, .incomeComparison].contains(self) }
    var usesPeriodUnit: Bool { [.spendingTrend, .spendingPatterns, .incomeTimeline, .incomeTrend, .savingsTimeline, .savingsTrend].contains(self) }

    /// Only metrics the existing service supplies for this capability. Conditional
    /// metrics (for example progress with a zero denominator) remain data-validated.
    var allowedMetrics: [MarinaDataRequest.MetricFocus] {
        switch self {
        case .largestExpense, .smallestExpense, .spendingComparison, .leaderComparison, .incomeComparison: [.total]
        case .rankedSpending, .categoryRanking, .cardRanking, .merchantRanking, .spendingShares, .incomeGroups:
            [.total, .count, .groupCount, .average, .share]
        case .expenses, .income, .spendingTrend, .incomeTrend: [.total, .count, .average, .averagePerPeriod, .share]
        case .transactions, .cardSummary, .spendingPatterns, .upcomingPresets, .nextPlannedExpense, .incomeTransactions:
            [.total, .count, .average, .share]
        case .incomeProgress: [.plannedIncome, .receivedIncome]
        case .incomeTimeline: [.plannedIncome, .receivedIncome]
        case .linkedCards, .linkedPresets, .inventory: [.count]
        case .accountBalances, .accountActivity: []
        case .budgetOverview, .budgetDetails, .budgetPace, .categoryAvailability, .savingsOutlook, .savingsTimeline, .savingsTrend:
            [.total, .count, .actualSavings, .projectedSavings, .maxSavings, .savingsGap, .savingsProgress,
             .remainingRoom, .safeSpend, .incomeCoverage, .recurringCommitments, .spendingRate, .projectedSpending,
             .plannedIncome, .receivedIncome, .plannedSpending, .recordedPlannedSpending, .effectivePlannedSpending, .variableSpending]
        }
    }

    static func matching(_ request: MarinaDataRequest) -> Self? {
        let purposes: [MarinaDataRequest.Purpose: Self] = [.cardSummary: .cardSummary, .spendingPatterns: .spendingPatterns,
            .upcomingPresets: .upcomingPresets, .nextPlannedExpense: .nextPlannedExpense, .incomeProgress: .incomeProgress,
            .incomeTimeline: .incomeTimeline, .budgetDetails: .budgetDetails, .budgetPace: .budgetPace,
            .categoryAvailability: .categoryAvailability, .savingsOutlook: .savingsOutlook,
            .savingsTimeline: .savingsTimeline, .budgetCards: .linkedCards, .budgetPresets: .linkedPresets]
        if let purpose = request.purpose, let capability = purposes[purpose], capability.tool == request.tool { return capability }
        switch request.tool {
        case .expenses:
            switch request.operation {
            case .transactions where request.limit == 1 && request.sort == .largest: return .largestExpense
            case .transactions where request.limit == 1 && request.sort == .smallest: return .smallestExpense
            case .transactions: return .transactions
            case .ranking:
                switch request.grouping {
                case .category: return .categoryRanking
                case .card: return .cardRanking
                case .merchant: return .merchantRanking
                default: return .rankedSpending
                }
            case .share: return .spendingShares
            case .comparison: return request.compareLeaders == true ? .leaderComparison : .spendingComparison
            case .trend: return .spendingTrend
            case .summary: return .expenses
            default: return nil
            }
        case .income:
            switch request.operation {
            case .transactions: return .incomeTransactions
            case .ranking, .share: return .incomeGroups
            case .trend: return .incomeTrend
            case .comparison: return .incomeComparison
            case .summary: return .income
            default: return nil
            }
        case .budgetSummary: return request.periodUnit == nil ? .budgetOverview : .savingsTrend
        case .accounts: return request.operation == .transactions ? .accountActivity : .accountBalances
        case .findRecords: return .inventory
        }
    }
}
