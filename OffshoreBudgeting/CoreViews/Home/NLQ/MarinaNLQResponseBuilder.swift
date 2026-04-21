import Foundation

struct MarinaNLQResponseBuilder {
    func build(
        from aggregation: MarinaNLQAggregationResult,
        queryID: UUID = UUID(),
        userPrompt: String
    ) -> HomeAnswer {
        if aggregation.isUnresolved {
            return HomeAnswer(
                queryID: queryID,
                kind: .message,
                userPrompt: userPrompt,
                title: "Quick clarification",
                subtitle: aggregation.unresolvedMessage ?? "I need one more detail.",
                rows: warningRows(aggregation.warnings)
            )
        }

        if let comparison = aggregation.comparison {
            return HomeAnswer(
                queryID: queryID,
                kind: .comparison,
                userPrompt: userPrompt,
                title: "Comparison",
                subtitle: nil,
                primaryValue: nil,
                rows: [
                    HomeAnswerRow(title: comparison.currentLabel, value: CurrencyFormatter.string(from: comparison.currentValue)),
                    HomeAnswerRow(title: comparison.previousLabel, value: CurrencyFormatter.string(from: comparison.previousValue))
                ] + warningRows(aggregation.warnings)
            )
        }

        if let value = aggregation.value {
            let breakdownRows = (aggregation.breakdown ?? []).map {
                HomeAnswerRow(title: $0.label, value: CurrencyFormatter.string(from: $0.value))
            }

            return HomeAnswer(
                queryID: queryID,
                kind: breakdownRows.isEmpty ? .metric : .list,
                userPrompt: userPrompt,
                title: "Result",
                subtitle: nil,
                primaryValue: CurrencyFormatter.string(from: value),
                rows: breakdownRows + warningRows(aggregation.warnings)
            )
        }

        return HomeAnswer(
            queryID: queryID,
            kind: .message,
            userPrompt: userPrompt,
            title: "Result",
            subtitle: "No data available for that range.",
            rows: warningRows(aggregation.warnings)
        )
    }

    private func warningRows(_ warnings: [String]?) -> [HomeAnswerRow] {
        guard let warnings, warnings.isEmpty == false else { return [] }
        return warnings.map { HomeAnswerRow(title: "Warning", value: $0) }
    }
}
