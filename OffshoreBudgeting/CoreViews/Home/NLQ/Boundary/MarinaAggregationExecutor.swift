import Foundation

@MainActor
struct MarinaAggregationExecutor {
    private let queryEngine: HomeQueryEngine

    init(queryEngine: HomeQueryEngine? = nil) {
        self.queryEngine = queryEngine ?? HomeQueryEngine()
    }

    func execute(
        _ executablePlan: MarinaExecutableAggregationPlan,
        provider: MarinaDataProvider,
        now: Date = Date()
    ) -> MarinaAggregationResult {
        let expenses = provider.fetchAllExpenses()
        let answer = queryEngine.execute(
            query: executablePlan.homeQueryPlan.query,
            categories: provider.fetchAllCategories(),
            presets: provider.fetchAllPresets(),
            plannedExpenses: expenses.planned,
            variableExpenses: expenses.variable,
            incomes: provider.fetchAllIncomes(),
            savingsEntries: provider.fetchAllSavingsLedgerEntries(),
            now: now
        )

        return MarinaAggregationResultMapper().map(
            answer: answer,
            executablePlan: executablePlan
        )
    }

    func execute(
        outcome: MarinaPlanValidationOutcome,
        provider: MarinaDataProvider,
        now: Date = Date(),
        adapter: MarinaAggregationPlanHomeQueryAdapter? = nil
    ) -> MarinaAggregationResult {
        let adapter = adapter ?? MarinaAggregationPlanHomeQueryAdapter()
        switch adapter.executablePlan(from: outcome) {
        case .success(let executablePlan):
            return execute(executablePlan, provider: provider, now: now)
        case .failure(let unsupported):
            return .unsupported(unsupported)
        }
    }
}

struct MarinaAggregationResultMapper {
    func map(
        answer: HomeAnswer,
        executablePlan: MarinaExecutableAggregationPlan
    ) -> MarinaAggregationResult {
        switch answer.kind {
        case .metric:
            return .scalar(
                MarinaScalarAggregationResult(
                    title: answer.title,
                    renderedValue: answer.primaryValue,
                    amount: extractAmount(from: answer.primaryValue),
                    rows: rows(from: answer.rows),
                    sourceAnswer: answer
                )
            )
        case .comparison:
            if answer.rows.count >= 2 {
                return .comparison(
                    MarinaComparisonAggregationResult(
                        title: answer.title,
                        primaryLabel: answer.rows[0].title,
                        primaryRenderedValue: answer.rows[0].value,
                        primaryAmount: extractAmount(from: answer.rows[0].value),
                        comparisonLabel: answer.rows[1].title,
                        comparisonRenderedValue: answer.rows[1].value,
                        comparisonAmount: extractAmount(from: answer.rows[1].value),
                        deltaRenderedValue: answer.subtitle,
                        sourceAnswer: answer
                    )
                )
            }
            return .message(
                MarinaMessageAggregationResult(
                    title: answer.title,
                    message: answer.subtitle,
                    sourceAnswer: answer
                )
            )
        case .list:
            let result = MarinaListAggregationResult(
                title: answer.title,
                primaryRenderedValue: answer.primaryValue,
                rows: rows(from: answer.rows),
                sourceAnswer: answer
            )
            return executablePlan.aggregationPlan.responseShape == .groupedBreakdown
                ? .groupedBreakdown(result)
                : .rankedList(result)
        case .message:
            return .message(
                MarinaMessageAggregationResult(
                    title: answer.title,
                    message: answer.subtitle,
                    sourceAnswer: answer
                )
            )
        }
    }

    private func rows(from answerRows: [HomeAnswerRow]) -> [MarinaAggregationResultRow] {
        answerRows.map { row in
            MarinaAggregationResultRow(
                label: row.title,
                renderedValue: row.value,
                amount: extractAmount(from: row.value),
                percentage: extractPercentage(from: row.value)
            )
        }
    }

    private func extractAmount(from text: String?) -> Double? {
        guard let text else { return nil }

        let currencyFormatter = NumberFormatter()
        currencyFormatter.numberStyle = .currency
        currencyFormatter.locale = .autoupdatingCurrent
        if let number = currencyFormatter.number(from: text) {
            return number.doubleValue
        }

        guard text.contains("$") else { return nil }
        let cleaned = text.replacingOccurrences(of: "[^0-9.-]", with: "", options: .regularExpression)
        return Double(cleaned)
    }

    private func extractPercentage(from text: String?) -> Double? {
        guard let text,
              let percentRange = text.range(of: #"[-+]?\d+(?:\.\d+)?\s*%"#, options: .regularExpression) else {
            return nil
        }

        let cleaned = String(text[percentRange])
            .replacingOccurrences(of: "%", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(cleaned) else { return nil }
        return value / 100
    }
}
