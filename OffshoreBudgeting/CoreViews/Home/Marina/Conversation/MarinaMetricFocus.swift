import Foundation

extension MarinaDataRequest.MetricFocus {
    var metricLabel: String {
        switch self {
        case .total: "Total"
        case .count: "Count"
        case .groupCount: "Group count"
        case .average: "Average per record"
        case .averagePerPeriod: "Average per period"
        case .share: "Share of unfiltered period total percent"
        case .actualSavings: "Actual savings"
        case .projectedSavings: "Projected savings"
        case .maxSavings: "Max savings"
        case .savingsGap: "Gap to projected savings"
        case .savingsProgress: "Savings progress percent"
        case .remainingRoom: "Remaining room"
        case .safeSpend: "Safe spend today"
        case .incomeCoverage: "Income coverage percent"
        case .recurringCommitments: "Recurring commitments"
        case .spendingRate: "Spending per elapsed day"
        case .projectedSpending: "Projected spending at current pace"
        case .plannedIncome: "Planned income"
        case .receivedIncome: "Actual income"
        case .plannedSpending: "Planned spending"
        case .recordedPlannedSpending: "Recorded planned expenses"
        case .effectivePlannedSpending: "Effective planned spending"
        case .variableSpending: "Variable spending"
        }
    }
}
