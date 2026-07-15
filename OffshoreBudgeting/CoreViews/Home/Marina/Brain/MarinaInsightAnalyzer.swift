import Foundation

struct MarinaInsightAnalyzer {
    private let moneyTolerance = 0.01
    private let tightDailySpendThreshold = 10.0
    private let recurringBurdenHighThreshold = 0.75
    private let recurringBurdenMediumThreshold = 0.40
    private let concentrationHighThreshold = 0.35
    private let concentrationMediumThreshold = 0.20

    private let followUpBuilder: MarinaFollowUpBuilder

    init(followUpBuilder: MarinaFollowUpBuilder = MarinaFollowUpBuilder()) {
        self.followUpBuilder = followUpBuilder
    }

    func insightBundle(
        for result: MarinaExecutionResult,
        plan: MarinaQueryPlan
    ) -> MarinaInsightBundle {
        let semanticContext = MarinaAnswerSemanticContext(plan: plan, result: result)
        let bundle = MarinaInsightBundle(
            headlineFact: headlineFact(for: result),
            meaning: meaning(for: result, plan: plan),
            signals: signals(for: result, plan: plan),
            followUps: followUpBuilder.followUps(for: semanticContext)
        )
        return bundle
    }

    // MARK: - Facts

    private func headlineFact(for result: MarinaExecutionResult) -> String? {
        if let primaryValue = trimmed(result.primaryValue) {
            return "\(result.title): \(primaryValue)"
        }

        guard let row = result.rows.first else { return nil }
        return "\(result.title): \(row.title) \(row.value)"
    }

    private func meaning(for result: MarinaExecutionResult, plan: MarinaQueryPlan) -> String? {
        guard result.kind != .message else { return nil }

        if let formulaMeaning = formulaMeaning(for: plan.measure) {
            return formulaMeaning
        }

        return MarinaL10n.format(
            "marina.insight.meaning.format",
            defaultValue: "This %@ answer reflects %@ %@ for %@.",
            comment: "Deterministic meaning sentence for a Marina answer.",
            result.kind.rawValue,
            entityLabel(plan.entity),
            operationLabel(plan.operation),
            dateRangeLabel(plan.dateRange)
        )
    }

    private func signals(for result: MarinaExecutionResult, plan: MarinaQueryPlan) -> [MarinaInsightSignal] {
        guard result.kind != .message else { return [] }

        var signals: [MarinaInsightSignal] = []
        signals.append(contentsOf: genericContextSignals(for: result, plan: plan))
        signals.append(contentsOf: budgetFormulaSignals(for: result, plan: plan))
        signals.append(contentsOf: incomeSignals(for: result, plan: plan))
        signals.append(contentsOf: categorySignals(for: result, plan: plan))
        signals.append(contentsOf: recurringBurdenSignals(for: result, plan: plan))

        return uniqued(signals)
    }

    private func genericContextSignals(for result: MarinaExecutionResult, plan: MarinaQueryPlan) -> [MarinaInsightSignal] {
        var signals: [MarinaInsightSignal] = []
        if let row = result.rows.first {
            signals.append(
                MarinaInsightSignal(
                    kind: .context,
                    title: MarinaL10n.string("marina.insight.signal.primaryDetail.title", defaultValue: "Primary detail", comment: "Insight signal title for the first answer row."),
                    detail: "\(row.title): \(row.value)"
                )
            )
        }

        if result.rows.count > 1 {
            signals.append(
                MarinaInsightSignal(
                    kind: .context,
                    title: MarinaL10n.string("marina.insight.signal.evidenceRows.title", defaultValue: "Evidence rows", comment: "Insight signal title for answer row count."),
                    detail: MarinaL10n.format("marina.insight.signal.evidenceRows.detailFormat", defaultValue: "%d rows are available in this answer.", comment: "Insight signal detail for answer row count.", result.rows.count)
                )
            )
        }

        if let comparisonDateRange = plan.comparisonDateRange {
            signals.append(
                MarinaInsightSignal(
                    kind: .context,
                    title: MarinaL10n.string("marina.insight.signal.comparisonPeriod.title", defaultValue: "Comparison period", comment: "Insight signal title for comparison period availability."),
                    detail: dateRangeLabel(comparisonDateRange)
                )
            )
        }

        return signals
    }

    private func budgetFormulaSignals(for result: MarinaExecutionResult, plan: MarinaQueryPlan) -> [MarinaInsightSignal] {
        guard let measure = plan.measure else { return [] }

        switch measure {
        case .safeDailySpend:
            guard let safePerDay = rowAmount("Safe per day", in: result) else { return [] }
            if safePerDay <= moneyTolerance {
                return [
                    MarinaInsightSignal(
                        kind: .caution,
                        title: MarinaL10n.string("marina.insight.signal.safeDaily.usedUp.title", defaultValue: "Daily room is used up", comment: "Insight signal title when safe daily spend is zero or below."),
                        detail: MarinaL10n.string("marina.insight.signal.safeDaily.usedUp.detail", defaultValue: "There is no safe daily room left for this period.", comment: "Insight signal detail when safe daily spend is zero or below.")
                    )
                ]
            }
            if safePerDay <= tightDailySpendThreshold {
                return [
                    MarinaInsightSignal(
                        kind: .caution,
                        title: MarinaL10n.string("marina.insight.signal.safeDaily.tight.title", defaultValue: "Daily room is tight", comment: "Insight signal title when safe daily spend is low."),
                        detail: MarinaL10n.string("marina.insight.signal.safeDaily.tight.detail", defaultValue: "The remaining room is spread thin across the days left in this period.", comment: "Insight signal detail when safe daily spend is low.")
                    )
                ]
            }
            return [
                MarinaInsightSignal(
                    kind: .opportunity,
                    title: MarinaL10n.string("marina.insight.signal.safeDaily.available.title", defaultValue: "Daily room is available", comment: "Insight signal title when safe daily spend is available."),
                    detail: MarinaL10n.string("marina.insight.signal.safeDaily.available.detail", defaultValue: "There is still room to spend carefully each day this period.", comment: "Insight signal detail when safe daily spend is available.")
                )
            ]
        case .paceDifference:
            guard let paceDifference = rowAmount("Pace difference", in: result) else { return [] }
            if paceDifference > moneyTolerance {
                return [
                    MarinaInsightSignal(
                        kind: .caution,
                        title: MarinaL10n.string("marina.insight.signal.pace.ahead.title", defaultValue: "Spending is ahead of pace", comment: "Insight signal title when spending is ahead of pace."),
                        detail: MarinaL10n.string("marina.insight.signal.pace.ahead.detail", defaultValue: "Actual spending is higher than the expected spend for this point in the period.", comment: "Insight signal detail when spending is ahead of pace.")
                    )
                ]
            }
            if paceDifference < -moneyTolerance {
                return [
                    MarinaInsightSignal(
                        kind: .celebration,
                        title: MarinaL10n.string("marina.insight.signal.pace.behind.title", defaultValue: "Spending is behind pace", comment: "Insight signal title when spending is behind pace."),
                        detail: MarinaL10n.string("marina.insight.signal.pace.behind.detail", defaultValue: "Actual spending is below the expected spend for this point in the period.", comment: "Insight signal detail when spending is behind pace.")
                    )
                ]
            }
            return [
                MarinaInsightSignal(
                    kind: .context,
                    title: MarinaL10n.string("marina.insight.signal.pace.close.title", defaultValue: "Spending is close to pace", comment: "Insight signal title when spending is close to expected pace."),
                    detail: MarinaL10n.string("marina.insight.signal.pace.close.detail", defaultValue: "Actual spending is close to the expected spend for this point in the period.", comment: "Insight signal detail when spending is close to expected pace.")
                )
            ]
        case .projectedSpend:
            return [
                MarinaInsightSignal(
                    kind: .context,
                    title: MarinaL10n.string("marina.insight.signal.projectedSpend.title", defaultValue: "Projection uses planned remaining spend", comment: "Insight signal title for projected spend."),
                    detail: MarinaL10n.string("marina.insight.signal.projectedSpend.detail", defaultValue: "This adds actual spend so far to planned spending still remaining in the selected period.", comment: "Insight signal detail for projected spend.")
                )
            ]
        case .burnRate:
            return [
                MarinaInsightSignal(
                    kind: .context,
                    title: MarinaL10n.string("marina.insight.signal.burnRate.title", defaultValue: "Spending pace", comment: "Insight signal title for burn rate."),
                    detail: MarinaL10n.string("marina.insight.signal.burnRate.detail", defaultValue: "This is the average daily spend based on spending so far in the selected period.", comment: "Insight signal detail for burn rate.")
                )
            ]
        case .amount, .plannedAmount, .actualAmount, .effectiveAmount, .budgetImpact, .savingsTotal, .incomeAmount, .reconciliationBalance, .categoryAvailability, .remainingRoom, .coverageRatio, .recurringBurden, .concentration, .color, .name:
            return []
        }
    }

    private func incomeSignals(for result: MarinaExecutionResult, plan: MarinaQueryPlan) -> [MarinaInsightSignal] {
        guard plan.measure == .coverageRatio,
              let difference = rowAmount("Difference", in: result) else {
            return []
        }

        if difference < -moneyTolerance {
            return [
                MarinaInsightSignal(
                    kind: .caution,
                    title: MarinaL10n.string("marina.insight.signal.coverage.short.title", defaultValue: "Income does not fully cover planned expenses", comment: "Insight signal title when income does not cover planned expenses."),
                    detail: MarinaL10n.string("marina.insight.signal.coverage.short.detail", defaultValue: "Planned expenses are higher than income for this period.", comment: "Insight signal detail when income does not cover planned expenses.")
                )
            ]
        }

        if abs(difference) <= moneyTolerance {
            return [
                MarinaInsightSignal(
                    kind: .context,
                    title: MarinaL10n.string("marina.insight.signal.coverage.close.title", defaultValue: "Income roughly matches planned expenses", comment: "Insight signal title when income roughly matches planned expenses."),
                    detail: MarinaL10n.string("marina.insight.signal.coverage.close.detail", defaultValue: "Income and planned expenses are close for this period.", comment: "Insight signal detail when income roughly matches planned expenses.")
                )
            ]
        }

        return [
            MarinaInsightSignal(
                kind: .opportunity,
                title: MarinaL10n.string("marina.insight.signal.coverage.covers.title", defaultValue: "Income covers planned expenses", comment: "Insight signal title when income covers planned expenses."),
                detail: MarinaL10n.string("marina.insight.signal.coverage.covers.detail", defaultValue: "Income is higher than planned expenses for this period.", comment: "Insight signal detail when income covers planned expenses.")
            )
        ]
    }

    private func categorySignals(for result: MarinaExecutionResult, plan: MarinaQueryPlan) -> [MarinaInsightSignal] {
        guard plan.measure == .concentration,
              let concentration = rowAmount("Concentration", in: result) else {
            return []
        }

        if concentration >= concentrationHighThreshold {
            return [
                MarinaInsightSignal(
                    kind: .caution,
                    title: MarinaL10n.string("marina.insight.signal.concentration.high.title", defaultValue: "One category is carrying a large share", comment: "Insight signal title for high category concentration."),
                    detail: MarinaL10n.string("marina.insight.signal.concentration.high.detail", defaultValue: "This category makes up a large share of spending for the period.", comment: "Insight signal detail for high category concentration.")
                )
            ]
        }

        if concentration >= concentrationMediumThreshold {
            return [
                MarinaInsightSignal(
                    kind: .context,
                    title: MarinaL10n.string("marina.insight.signal.concentration.medium.title", defaultValue: "Category share is noticeable", comment: "Insight signal title for medium category concentration."),
                    detail: MarinaL10n.string("marina.insight.signal.concentration.medium.detail", defaultValue: "This category is a meaningful share of spending.", comment: "Insight signal detail for medium category concentration.")
                )
            ]
        }

        return [
            MarinaInsightSignal(
                kind: .opportunity,
                title: MarinaL10n.string("marina.insight.signal.concentration.low.title", defaultValue: "Spending is more spread out", comment: "Insight signal title for low category concentration."),
                detail: MarinaL10n.string("marina.insight.signal.concentration.low.detail", defaultValue: "No single category appears to dominate spending from this result.", comment: "Insight signal detail for low category concentration.")
            )
        ]
    }

    private func recurringBurdenSignals(for result: MarinaExecutionResult, plan: MarinaQueryPlan) -> [MarinaInsightSignal] {
        guard plan.measure == .recurringBurden,
              let burden = rowAmount("Recurring burden", in: result) else {
            return []
        }

        if burden >= recurringBurdenHighThreshold {
            return [
                MarinaInsightSignal(
                    kind: .caution,
                    title: MarinaL10n.string("marina.insight.signal.recurring.high.title", defaultValue: "Most planned expenses are recurring", comment: "Insight signal title for high recurring burden."),
                    detail: MarinaL10n.string("marina.insight.signal.recurring.high.detail", defaultValue: "Recurring items make up most of the planned expense total.", comment: "Insight signal detail for high recurring burden.")
                )
            ]
        }

        if burden >= recurringBurdenMediumThreshold {
            return [
                MarinaInsightSignal(
                    kind: .context,
                    title: MarinaL10n.string("marina.insight.signal.recurring.medium.title", defaultValue: "Recurring expenses are a major share", comment: "Insight signal title for medium recurring burden."),
                    detail: MarinaL10n.string("marina.insight.signal.recurring.medium.detail", defaultValue: "Recurring items are a meaningful part of the planned expense total.", comment: "Insight signal detail for medium recurring burden.")
                )
            ]
        }

        return [
            MarinaInsightSignal(
                kind: .opportunity,
                title: MarinaL10n.string("marina.insight.signal.recurring.low.title", defaultValue: "Recurring expenses leave flexibility", comment: "Insight signal title for low recurring burden."),
                detail: MarinaL10n.string("marina.insight.signal.recurring.low.detail", defaultValue: "Recurring items are not taking up most of the planned expense total.", comment: "Insight signal detail for low recurring burden.")
            )
        ]
    }

    // MARK: - Helpers

    private func formulaMeaning(for measure: MarinaSemanticMeasure?) -> String? {
        guard let measure else { return nil }

        switch measure {
        case .safeDailySpend:
            return MarinaL10n.string("marina.insight.meaning.safeDailySpend", defaultValue: "This shows how much room remains per day for the rest of the selected period.", comment: "Meaning sentence for safe daily spend.")
        case .paceDifference:
            return MarinaL10n.string("marina.insight.meaning.paceDifference", defaultValue: "This compares actual spending so far against the amount expected by this point in the period.", comment: "Meaning sentence for pace difference.")
        case .coverageRatio:
            return MarinaL10n.string("marina.insight.meaning.coverageRatio", defaultValue: "This shows whether income covers planned expenses for the selected period.", comment: "Meaning sentence for coverage ratio.")
        case .recurringBurden:
            return MarinaL10n.string("marina.insight.meaning.recurringBurden", defaultValue: "This shows how much of planned expenses come from recurring items.", comment: "Meaning sentence for recurring burden.")
        case .concentration:
            return MarinaL10n.string("marina.insight.meaning.concentration", defaultValue: "This shows how much of total spending is concentrated in one category.", comment: "Meaning sentence for category concentration.")
        case .projectedSpend:
            return MarinaL10n.string("marina.insight.meaning.projectedSpend", defaultValue: "This projects total spending from actual spend so far plus planned spending still remaining in the selected period.", comment: "Meaning sentence for projected spend.")
        case .burnRate:
            return MarinaL10n.string("marina.insight.meaning.burnRate", defaultValue: "This shows average daily spending based on the selected period so far.", comment: "Meaning sentence for burn rate.")
        case .amount, .plannedAmount, .actualAmount, .effectiveAmount, .budgetImpact, .savingsTotal, .incomeAmount, .reconciliationBalance, .categoryAvailability, .remainingRoom, .color, .name:
            return nil
        }
    }

    private func rowAmount(_ title: String, in result: MarinaExecutionResult) -> Double? {
        result.rows.first { row in
            row.title.localizedCaseInsensitiveCompare(title) == .orderedSame
        }?.amount
    }

    private func uniqued(_ signals: [MarinaInsightSignal]) -> [MarinaInsightSignal] {
        var seen: Set<String> = []
        var result: [MarinaInsightSignal] = []
        for signal in signals {
            let key = "\(signal.kind.rawValue)|\(signal.title)|\(signal.detail)"
            guard seen.insert(key).inserted else { continue }
            result.append(signal)
        }
        return result
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func entityLabel(_ entity: MarinaSemanticEntity) -> String {
        switch entity {
        case .workspace:
            return MarinaL10n.common("workspace", defaultValue: "workspace", comment: "Common label for workspace.")
        case .budget:
            return MarinaL10n.common("budget", defaultValue: "budget", comment: "Common label for budget.")
        case .card:
            return MarinaL10n.common("card", defaultValue: "card", comment: "Common label for card.")
        case .plannedExpense:
            return MarinaL10n.common("plannedExpense", defaultValue: "planned expense", comment: "Common label for planned expense.")
        case .variableExpense:
            return MarinaL10n.common("expense", defaultValue: "expense", comment: "Common label for expense.")
        case .reconciliationAccount:
            return MarinaL10n.common("reconciliationAccount", defaultValue: "reconciliation account", comment: "Common label for reconciliation account.")
        case .savingsAccount:
            return MarinaL10n.common("savingsAccount", defaultValue: "savings account", comment: "Common label for savings account.")
        case .income:
            return MarinaL10n.common("income", defaultValue: "income", comment: "Common label for income.")
        case .category:
            return MarinaL10n.common("category", defaultValue: "category", comment: "Common label for category.")
        case .preset:
            return MarinaL10n.common("preset", defaultValue: "preset", comment: "Common label for preset.")
        }
    }

    private func operationLabel(_ operation: MarinaSemanticOperation) -> String {
        operation.rawValue
    }

    private func dateRangeLabel(_ range: HomeQueryDateRange?) -> String {
        guard let range else {
            return MarinaL10n.string("marina.answer.range.allTime", defaultValue: "All time", comment: "Date range label for all time.")
        }
        return "\(shortDate(range.startDate)) - \(shortDate(range.endDate))"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
