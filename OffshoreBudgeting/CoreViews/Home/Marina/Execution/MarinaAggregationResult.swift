import Foundation

struct MarinaAggregationResultRow: Codable, Equatable, Identifiable {
    let id: UUID
    let label: String
    let renderedValue: String
    let amount: Double?
    let percentage: Double?

    init(
        id: UUID = UUID(),
        label: String,
        renderedValue: String,
        amount: Double? = nil,
        percentage: Double? = nil
    ) {
        self.id = id
        self.label = label
        self.renderedValue = renderedValue
        self.amount = amount
        self.percentage = percentage
    }
}

struct MarinaScalarAggregationResult: Codable, Equatable {
    let title: String
    let renderedValue: String?
    let amount: Double?
    let rows: [MarinaAggregationResultRow]
    let sourceAnswer: HomeAnswer
}

struct MarinaComparisonAggregationResult: Codable, Equatable {
    let title: String
    let primaryLabel: String
    let primaryRenderedValue: String
    let primaryAmount: Double?
    let comparisonLabel: String
    let comparisonRenderedValue: String
    let comparisonAmount: Double?
    let deltaRenderedValue: String?
    let sourceAnswer: HomeAnswer
}

struct MarinaListAggregationResult: Codable, Equatable {
    let title: String
    let primaryRenderedValue: String?
    let rows: [MarinaAggregationResultRow]
    let sourceAnswer: HomeAnswer
}

struct MarinaMessageAggregationResult: Codable, Equatable {
    let title: String
    let message: String?
    let sourceAnswer: HomeAnswer
}

struct MarinaNoDataAggregationResult: Codable, Equatable {
    let title: String
    let message: String
    let sourceAnswer: HomeAnswer
}

enum MarinaAggregationResult: Codable, Equatable {
    case scalar(MarinaScalarAggregationResult)
    case comparison(MarinaComparisonAggregationResult)
    case rankedList(MarinaListAggregationResult)
    case groupedBreakdown(MarinaListAggregationResult)
    case workspaceCard(MarinaWorkspaceAggregationCard)
    case message(MarinaMessageAggregationResult)
    case noData(MarinaNoDataAggregationResult)
    case unsupported(MarinaTypedUnsupportedResponse)

    var sourceAnswer: HomeAnswer? {
        switch self {
        case .scalar(let result):
            return result.sourceAnswer
        case .comparison(let result):
            return result.sourceAnswer
        case .rankedList(let result), .groupedBreakdown(let result):
            return result.sourceAnswer
        case .workspaceCard:
            return nil
        case .message(let result):
            return result.sourceAnswer
        case .noData(let result):
            return result.sourceAnswer
        case .unsupported:
            return nil
        }
    }
}

@MainActor
struct MarinaInsightContextBuilder {
    func enrich(
        answer: HomeAnswer,
        result: MarinaAggregationResult,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        provider: MarinaDataProvider,
        now: Date
    ) -> HomeAnswer {
        guard let intent = candidate.insightIntent else { return answer }

        let rows = insightRows(
            intent: intent,
            result: result,
            candidate: candidate,
            resolved: resolved,
            semanticResolved: semanticResolved,
            provider: provider,
            now: now,
            existingRows: answer.rows
        )
        guard rows.isEmpty == false else { return answer }

        return HomeAnswer(
            id: answer.id,
            queryID: answer.queryID,
            kind: answer.kind,
            userPrompt: answer.userPrompt,
            title: answer.title,
            subtitle: answer.subtitle,
            primaryValue: answer.primaryValue,
            rows: answer.rows + rows,
            attachment: answer.attachment,
            explanation: answer.explanation,
            generatedAt: answer.generatedAt
        )
    }

    private func insightRows(
        intent: MarinaInsightIntent,
        result: MarinaAggregationResult,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        provider: MarinaDataProvider,
        now: Date,
        existingRows: [HomeAnswerRow]
    ) -> [HomeAnswerRow] {
        var rows: [HomeAnswerRow] = []
        var usedTitles = Set(existingRows.map { normalized($0.title) })

        func append(_ title: String, _ value: String?) {
            guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
                  value.isEmpty == false,
                  usedTitles.contains(normalized(title)) == false else { return }
            rows.append(HomeAnswerRow(title: title, value: value))
            usedTitles.insert(normalized(title))
        }

        let comparison = comparisonSummary(
            result: result,
            candidate: candidate,
            resolved: resolved,
            semanticResolved: semanticResolved,
            provider: provider,
            now: now
        )
        let contributor = mainContributor(
            result: result,
            resolved: resolved,
            semanticResolved: semanticResolved,
            provider: provider,
            dateRange: resolved.primaryDateRange ?? semanticResolved?.primaryDateRange ?? monthRange(containing: now)
        )

        switch intent {
        case .changeSummary:
            append("Status", comparison?.status)
            append("Compared With", comparison?.comparedWith)
            append("Pattern", comparison?.pattern)
        case .contributorAnalysis:
            append("Main Driver", contributor)
            append("Pattern", contributor.map { $0.contains("(") ? "concentrated" : "thin-data" })
        case .normalityCheck:
            append("Status", comparison?.status ?? "OK: not enough baseline to call this unusual")
            append("Compared With", comparison?.comparedWith)
            append("Pattern", comparison?.pattern ?? (contributor == nil ? "thin-data" : "visible contributor"))
            append("Main Driver", contributor)
        case .watchOuts:
            append("Status", comparison?.status)
            append("Watch", watchSummary(comparison: comparison, contributor: contributor))
        case .explainBudgeting:
            append("Pattern", comparison?.pattern ?? "Marina is reading deterministic spend rows, not estimating.")
            append("Main Driver", contributor)
        case .multiPartContributors:
            append("Main Driver", contributor)
            append("Pattern", comparison?.pattern ?? (contributor == nil ? "thin-data" : "contributor-led"))
        }

        return rows
    }

    private struct ComparisonSummary {
        let status: String
        let comparedWith: String
        let pattern: String
    }

    private func comparisonSummary(
        result: MarinaAggregationResult,
        candidate: MarinaQueryPlanCandidate,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        provider: MarinaDataProvider,
        now: Date
    ) -> ComparisonSummary? {
        if case .comparison(let comparison) = result,
           let current = comparison.primaryAmount,
           let previous = comparison.comparisonAmount {
            return comparisonSummary(
                current: current,
                previous: previous,
                previousLabel: comparison.comparisonLabel,
                previousRenderedValue: comparison.comparisonRenderedValue
            )
        }

        guard let current = amount(from: result) else { return nil }
        let primaryRange = resolved.primaryDateRange ?? semanticResolved?.primaryDateRange ?? monthRange(containing: now)
        let previousRange = resolved.comparisonDateRange
            ?? semanticResolved?.comparisonDateRange
            ?? previousEquivalentRange(to: primaryRange)
        let previous = spendTotal(
            provider: provider,
            dateRange: previousRange,
            targets: targets(resolved: resolved, semanticResolved: semanticResolved)
        )

        return comparisonSummary(
            current: current,
            previous: previous,
            previousLabel: "Previous period",
            previousRenderedValue: CurrencyFormatter.string(from: previous)
        )
    }

    private func comparisonSummary(
        current: Double,
        previous: Double,
        previousLabel: String,
        previousRenderedValue: String
    ) -> ComparisonSummary {
        let status: String
        let pattern: String
        if previous == 0, current == 0 {
            status = "OK: no spend in either period"
            pattern = "thin-data"
        } else if previous == 0 {
            status = "Watch: spending appeared where the prior period had none"
            pattern = "rising"
        } else {
            let ratio = current / previous
            if ratio >= 1.05 {
                status = "Watch: spending is above the comparison period"
                pattern = "rising"
            } else if ratio <= 0.95 {
                status = "Good: spending improved vs the comparison period"
                pattern = "falling"
            } else {
                status = "OK: spending is relatively stable"
                pattern = "stable"
            }
        }
        return ComparisonSummary(
            status: status,
            comparedWith: "\(previousLabel): \(previousRenderedValue)",
            pattern: pattern
        )
    }

    private func mainContributor(
        result: MarinaAggregationResult,
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?,
        provider: MarinaDataProvider,
        dateRange: HomeQueryDateRange
    ) -> String? {
        if let row = rankedRows(from: result).first {
            return "\(row.label): \(row.renderedValue)"
        }

        let targetList = targets(resolved: resolved, semanticResolved: semanticResolved)
        let expenses = provider.fetchAllVariableExpenses()
            .filter { contains($0.transactionDate, in: dateRange) }
            .filter { matches($0, targets: targetList) }
            .filter { $0.spendingAmount() > 0 }
        guard expenses.isEmpty == false else { return nil }

        let groupByDescription = targetList.contains { $0.entityType == .category || $0.entityType == .card || $0.entityType == .merchant }
        let grouped = Dictionary(grouping: expenses) { expense in
            if groupByDescription {
                return expense.descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank ?? "Transaction"
            }
            return expense.category?.name.nilIfBlank ?? "Uncategorized"
        }
        guard let top = grouped
            .map({ (label: $0.key, total: $0.value.reduce(0) { $0 + $1.spendingAmount() }) })
            .max(by: { $0.total < $1.total }) else {
            return nil
        }

        return "\(top.label) (\(CurrencyFormatter.string(from: top.total)))"
    }

    private func watchSummary(comparison: ComparisonSummary?, contributor: String?) -> String? {
        if comparison?.pattern == "rising" {
            if let contributor {
                return "Rising vs baseline; start with \(contributor)."
            }
            return "Rising vs baseline."
        }
        if let contributor {
            return "Largest visible driver is \(contributor)."
        }
        return nil
    }

    private struct InsightTarget {
        let entityType: MarinaCandidateEntityTypeHint
        let displayName: String
        let sourceID: UUID?
    }

    private func targets(
        resolved: MarinaResolvedQueryCandidate,
        semanticResolved: MarinaResolvedSemanticQuery?
    ) -> [InsightTarget] {
        let compatibilityTargets = resolved.resolvedTargets.map {
            InsightTarget(entityType: $0.entityType, displayName: $0.displayName, sourceID: $0.sourceID)
        }
        let semanticTargets = (semanticResolved?.resolvedFilters ?? []).map {
            InsightTarget(entityType: $0.entityType, displayName: $0.displayName, sourceID: $0.sourceID)
        }
        return compatibilityTargets.isEmpty ? semanticTargets : compatibilityTargets
    }

    private func spendTotal(
        provider: MarinaDataProvider,
        dateRange: HomeQueryDateRange,
        targets: [InsightTarget]
    ) -> Double {
        provider.fetchAllVariableExpenses()
            .filter { contains($0.transactionDate, in: dateRange) }
            .filter { matches($0, targets: targets) }
            .reduce(0) { $0 + $1.spendingAmount() }
    }

    private func matches(_ expense: VariableExpense, targets: [InsightTarget]) -> Bool {
        guard targets.isEmpty == false else { return true }
        return targets.allSatisfy { target in
            switch target.entityType {
            case .category:
                if let sourceID = target.sourceID {
                    return expense.category?.id == sourceID
                }
                return normalized(expense.category?.name ?? "") == normalized(target.displayName)
            case .card:
                if let sourceID = target.sourceID {
                    return expense.card?.id == sourceID
                }
                return normalized(expense.card?.name ?? "") == normalized(target.displayName)
            case .merchant, .expense, .transaction:
                return normalized(expense.descriptionText).contains(normalized(target.displayName))
            default:
                return true
            }
        }
    }

    private func amount(from result: MarinaAggregationResult) -> Double? {
        switch result {
        case .scalar(let scalar):
            return scalar.amount
        case .comparison(let comparison):
            return comparison.primaryAmount
        case .rankedList(let list), .groupedBreakdown(let list):
            return list.rows.first?.amount
        case .workspaceCard(let card):
            return card.rows.first?.amount
        case .message, .noData, .unsupported:
            return nil
        }
    }

    private func rankedRows(from result: MarinaAggregationResult) -> [MarinaAggregationResultRow] {
        switch result {
        case .rankedList(let list), .groupedBreakdown(let list):
            return list.rows
        case .workspaceCard(let card):
            return card.rows.map {
                MarinaAggregationResultRow(label: $0.label, renderedValue: $0.value, amount: $0.amount)
            }
        default:
            return []
        }
    }

    private func contains(_ date: Date, in range: HomeQueryDateRange) -> Bool {
        date >= range.startDate && date <= range.endDate
    }

    private func previousEquivalentRange(to range: HomeQueryDateRange) -> HomeQueryDateRange {
        let duration = max(range.endDate.timeIntervalSince(range.startDate), 0)
        let previousEnd = range.startDate.addingTimeInterval(-1)
        let previousStart = previousEnd.addingTimeInterval(-duration)
        return HomeQueryDateRange(startDate: previousStart, endDate: previousEnd)
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func normalized(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
