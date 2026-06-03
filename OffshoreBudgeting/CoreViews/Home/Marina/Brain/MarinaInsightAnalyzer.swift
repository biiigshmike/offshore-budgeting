import Foundation

struct MarinaInsightAnalyzer {
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

    // MARK: - Helpers

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
