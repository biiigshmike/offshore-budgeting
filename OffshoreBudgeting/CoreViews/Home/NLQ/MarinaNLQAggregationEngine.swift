import Foundation

struct MarinaNLQAggregationEngine {
    private let queryEngine: HomeQueryEngine

    init(queryEngine: HomeQueryEngine = HomeQueryEngine()) {
        self.queryEngine = queryEngine
    }

    func aggregate(
        intent: NormalizedQueryIntent,
        metric: MarinaNormalizedMetric,
        resolvedTargets: MarinaNLQResolvedTargets,
        provider: MarinaDataProvider,
        activeBudgetPeriod: HomeQueryDateRange?,
        now: Date = Date()
    ) -> MarinaNLQAggregationResult {
        MarinaTraceRecorder.shared.recordAggregation(path: "marina_nlq_aggregation_engine", summary: nil)
        let warnings = prefixWarnings(for: resolvedTargets)
        guard let mapping = mappedQuery(
            intent: intent,
            metric: metric,
            resolvedTargets: resolvedTargets,
            activeBudgetPeriod: activeBudgetPeriod,
            now: now
        ) else {
            MarinaDebugLogger.log("[MarinaNLQ] aggregation unsupported metric=\(metric.rawValue)")
            MarinaTraceRecorder.shared.recordAggregation(
                path: "marina_nlq_aggregation_engine",
                summary: "unsupported metric=\(metric.rawValue)"
            )
            return .unresolved("That query metric isn't implemented yet.", warnings: warnings)
        }

        let inputs = provider.fetchAllExpenses()
        let categories = provider.fetchAllCategories()
        let presets = provider.fetchAllPresets()
        let incomes = provider.fetchAllIncomes()
        let savingsEntries = provider.fetchAllSavingsLedgerEntries()

        switch mapping {
        case .single(let query):
            MarinaDebugLogger.log("[MarinaNLQ] aggregation executing single query intent=\(query.intent.rawValue) target=\(query.targetName ?? "nil")")
            MarinaTraceRecorder.shared.recordAggregation(
                path: "single_home_query_engine",
                summary: "intent=\(query.intent.rawValue),target=\(query.targetName ?? "nil")"
            )
            let answer = queryEngine.execute(
                query: query,
                categories: categories,
                presets: presets,
                plannedExpenses: inputs.planned,
                variableExpenses: inputs.variable,
                incomes: incomes,
                savingsEntries: savingsEntries,
                now: now
            )
            return convert(answer: answer, warnings: warnings)

        case .multi(let queries):
            MarinaDebugLogger.log("[MarinaNLQ] aggregation executing multi-target query count=\(queries.count)")
            MarinaTraceRecorder.shared.recordAggregation(
                path: "multi_home_query_engine",
                summary: "count=\(queries.count),intent=\(queries.first?.intent.rawValue ?? "nil")"
            )
            let perTarget: [(query: HomeQuery, answer: HomeAnswer)] = queries.map { query in
                let answer = queryEngine.execute(
                    query: query,
                    categories: categories,
                    presets: presets,
                    plannedExpenses: inputs.planned,
                    variableExpenses: inputs.variable,
                    incomes: incomes,
                    savingsEntries: savingsEntries,
                    now: now
                )
                return (query: query, answer: answer)
            }

            return aggregateMultiTarget(perTarget, warnings: warnings)
        }
    }

    private enum QueryMapping {
        case single(HomeQuery)
        case multi([HomeQuery])
    }

    private func mappedQuery(
        intent: NormalizedQueryIntent,
        metric: MarinaNormalizedMetric,
        resolvedTargets: MarinaNLQResolvedTargets,
        activeBudgetPeriod: HomeQueryDateRange?,
        now: Date
    ) -> QueryMapping? {
        let effectiveDateRange = resolvedDateRange(
            explicitDateRange: intent.dateRange,
            policy: metric.definition.dateFallbackPolicy,
            activeBudgetPeriod: activeBudgetPeriod,
            now: now
        )

        let targetNames = resolvedTargets.matches.map(\.displayValue)
        let resolvedTargetType = resolvedTargets.targetType ?? inferredTargetType(from: intent)
        let comparisonDateRange = intent.comparisonDateRange

        let homeMetric: HomeQueryMetric
        switch metric {
        case .spendTotal:
            if intent.modifiers.contains("breakdown_by_category"), resolvedTargetType == nil {
                homeMetric = .categorySpendShare
            } else if intent.modifiers.contains("breakdown_by_merchant"), resolvedTargetType == nil {
                homeMetric = .topMerchants
            } else if intent.modifiers.contains("breakdown_by_card"), resolvedTargetType == nil {
                homeMetric = .cardSnapshotSummary
            } else {
                switch resolvedTargetType {
                case .category:
                    homeMetric = .categorySpendTotal
                case .merchant:
                    homeMetric = .merchantSpendTotal
                case .card:
                    homeMetric = .cardSpendTotal
                default:
                    homeMetric = .spendTotal
                }
            }
        case .categorySpendTotal:
            homeMetric = .categorySpendTotal
        case .categorySpendShare:
            homeMetric = .categorySpendShare
        case .merchantSpendTotal:
            homeMetric = .merchantSpendTotal
        case .topCategories:
            homeMetric = .topCategories
        case .topMerchants:
            homeMetric = .topMerchants
        case .monthComparison:
            switch resolvedTargetType {
            case .category:
                homeMetric = .categoryMonthComparison
            case .merchant:
                homeMetric = .merchantMonthComparison
            case .card:
                homeMetric = .cardMonthComparison
            case .incomeSource:
                homeMetric = .incomeSourceMonthComparison
            default:
                homeMetric = .monthComparison
            }
        case .categoryMonthComparison:
            homeMetric = .categoryMonthComparison
        case .largestTransactions:
            homeMetric = .largestTransactions
        case .mostFrequentTransactions:
            homeMetric = .mostFrequentTransactions
        case .spendAveragePerPeriod:
            homeMetric = .spendAveragePerPeriod
        case .incomeAverageActual:
            homeMetric = .incomeAverageActual
        case .presetDueSoon:
            homeMetric = .presetDueSoon
        }

        let baseQuery = HomeQuery(
            intent: homeMetric.intent,
            dateRange: effectiveDateRange,
            comparisonDateRange: comparisonDateRange,
            resultLimit: intent.resultLimit,
            targetName: targetNames.first,
            periodUnit: nil
        )

        if targetNames.count <= 1 {
            return .single(baseQuery)
        }

        switch metric.definition.withinTypeAggregationPolicy {
        case .clarifyDistinct:
            return nil
        case .aggregateDistinct:
            let queries = targetNames.map { target in
                HomeQuery(
                    intent: homeMetric.intent,
                    dateRange: effectiveDateRange,
                    comparisonDateRange: comparisonDateRange,
                    resultLimit: intent.resultLimit,
                    targetName: target,
                    periodUnit: nil
                )
            }
            return .multi(queries)
        }
    }

    private func inferredTargetType(from intent: NormalizedQueryIntent) -> MarinaNLQTargetType? {
        switch intent.queryShape.grouping {
        case .category:
            return .category
        case .merchant:
            return .merchant
        case .some(.none):
            if intent.rawPrompt.lowercased().contains(" card") {
                return .card
            }
            return nil
        case .transaction, .preset, .incomeSource, nil:
            return nil
        }
    }

    private func resolvedDateRange(
        explicitDateRange: HomeQueryDateRange?,
        policy: MarinaNLQDateFallbackPolicy,
        activeBudgetPeriod: HomeQueryDateRange?,
        now: Date
    ) -> HomeQueryDateRange {
        switch policy {
        case .userThenActiveBudgetThenCurrentMonth:
            if let explicitDateRange {
                return explicitDateRange
            }
            if let activeBudgetPeriod {
                return activeBudgetPeriod
            }
            return monthRange(containing: now)
        }
    }

    private func monthRange(containing date: Date) -> HomeQueryDateRange {
        let calendar = Calendar.current
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: DateComponents(month: 1, second: -1), to: start) ?? start
        return HomeQueryDateRange(startDate: start, endDate: end)
    }

    private func aggregateMultiTarget(
        _ perTarget: [(query: HomeQuery, answer: HomeAnswer)],
        warnings: [String]
    ) -> MarinaNLQAggregationResult {
        if let comparisonAggregate = aggregateComparisonTargets(perTarget, warnings: warnings) {
            return comparisonAggregate
        }

        let breakdown = perTarget.compactMap { pair -> MarinaNLQBreakdownItem? in
            guard let amount = extractAmount(from: pair.answer.primaryValue) else { return nil }
            return MarinaNLQBreakdownItem(
                label: pair.query.targetName ?? "Target",
                value: amount,
                renderedValue: nil
            )
        }

        if breakdown.isEmpty {
            return .unresolved("I couldn't safely aggregate those targets.", warnings: warnings)
        }

        let total = breakdown.reduce(0) { $0 + ($1.value ?? 0) }
        return MarinaNLQAggregationResult(
            value: total,
            breakdown: breakdown,
            comparison: nil,
            warnings: warnings.isEmpty ? nil : warnings,
            isUnresolved: false,
            unresolvedMessage: nil
        )
    }

    private func aggregateComparisonTargets(
        _ perTarget: [(query: HomeQuery, answer: HomeAnswer)],
        warnings: [String]
    ) -> MarinaNLQAggregationResult? {
        let aggregates = perTarget.compactMap { pair -> MarinaNLQComparisonResult? in
            guard pair.answer.kind == .comparison,
                  pair.answer.rows.count >= 2,
                  let current = extractAmount(from: pair.answer.rows[0].value),
                  let previous = extractAmount(from: pair.answer.rows[1].value) else {
                return nil
            }
            return MarinaNLQComparisonResult(
                currentValue: current,
                previousValue: previous,
                currentLabel: pair.answer.rows[0].title,
                previousLabel: pair.answer.rows[1].title
            )
        }

        guard aggregates.count == perTarget.count, aggregates.isEmpty == false else {
            return nil
        }

        let currentTotal = aggregates.reduce(0) { $0 + $1.currentValue }
        let previousTotal = aggregates.reduce(0) { $0 + $1.previousValue }
        let label = aggregates.first

        return MarinaNLQAggregationResult(
            value: nil,
            breakdown: nil,
            comparison: MarinaNLQComparisonResult(
                currentValue: currentTotal,
                previousValue: previousTotal,
                currentLabel: label?.currentLabel ?? "Current",
                previousLabel: label?.previousLabel ?? "Previous"
            ),
            warnings: warnings.isEmpty ? nil : warnings,
            isUnresolved: false,
            unresolvedMessage: nil
        )
    }

    private func convert(answer: HomeAnswer, warnings: [String]) -> MarinaNLQAggregationResult {
        if answer.kind == .comparison,
           answer.rows.count >= 2,
           let current = extractAmount(from: answer.rows[0].value),
           let previous = extractAmount(from: answer.rows[1].value)
        {
            return MarinaNLQAggregationResult(
                value: nil,
                breakdown: nil,
                comparison: MarinaNLQComparisonResult(
                    currentValue: current,
                    previousValue: previous,
                    currentLabel: answer.rows[0].title,
                    previousLabel: answer.rows[1].title
                ),
                warnings: warnings.isEmpty ? nil : warnings,
                isUnresolved: false,
                unresolvedMessage: nil
            )
        }

        let value = extractAmount(from: answer.primaryValue)
        let breakdown: [MarinaNLQBreakdownItem]? = answer.rows.isEmpty ? nil : answer.rows.compactMap { row in
            MarinaNLQBreakdownItem(
                label: row.title,
                value: extractAmount(from: row.value),
                renderedValue: row.value
            )
        }

        return MarinaNLQAggregationResult(
            value: value,
            breakdown: breakdown,
            comparison: nil,
            warnings: warnings.isEmpty ? nil : warnings,
            isUnresolved: false,
            unresolvedMessage: nil
        )
    }

    private func extractAmount(from text: String?) -> Double? {
        guard let text else { return nil }

        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.locale = .autoupdatingCurrent
        if let number = currencyFormatter.number(from: text) {
            return number.doubleValue
        }

        let cleaned = text
            .replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        return Double(cleaned)
    }

    private func prefixWarnings(for targets: MarinaNLQResolvedTargets) -> [String] {
        targets.prefixWarningTargets.map { target in
            "Used a prefix match for \(target)."
        }
    }
}
