#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaRecordMetric: String { case total, count, groupCount, average, averagePerPeriod, share }

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaMetricFocus: String {
    case total, count, average, share, actualSavings, projectedSavings, maxSavings, savingsGap, savingsProgress
    case remainingRoom, safeSpend, incomeCoverage, recurringCommitments, spendingRate, projectedSpending
    case plannedIncome, receivedIncome, plannedSpending, recordedPlannedSpending, effectivePlannedSpending, variableSpending
}

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaAvailabilityFilter: String { case all, over, near, overOrNear, ok, unlimited }

@available(iOS 26.0, macCatalyst 26.0, *)
@Generable enum MarinaTransactionFilter: String { case all, debit, credit, adjustment, split, reconciliationOffset, savingsOffset }
#endif
