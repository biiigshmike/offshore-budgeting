import Foundation

struct MarinaAggregationResponseBridge {
    func responseCompatibleAnswer(from outcome: MarinaPlanValidationOutcome) -> HomeAnswer? {
        switch outcome {
        case .executable:
            return nil
        case .clarification(let clarification):
            return responseCompatibleAnswer(from: clarification)
        case .unsupported(let unsupported):
            return responseCompatibleAnswer(from: MarinaAggregationResult.unsupported(unsupported))
        }
    }

    func responseCompatibleAnswer(from clarification: MarinaTypedClarification) -> HomeAnswer {
        HomeAnswer(
            queryID: clarification.id,
            kind: .message,
            title: "Marina Needs Clarification",
            subtitle: clarification.message,
            primaryValue: nil,
            rows: clarification.choices.map { choice in
                HomeAnswerRow(title: choice.title, value: choice.rawValue ?? choice.entityTypeHint?.rawValue ?? "")
            }
        )
    }

    func responseCompatibleAnswer(from result: MarinaAggregationResult) -> HomeAnswer {
        switch result {
        case .scalar(let result):
            return result.sourceAnswer
        case .comparison(let result):
            return result.sourceAnswer
        case .rankedList(let result), .groupedBreakdown(let result):
            return result.sourceAnswer
        case .workspaceCard(let card):
            return MarinaWorkspaceAggregationResponseBridge().responseCompatibleAnswer(from: card)
        case .message(let result):
            return result.sourceAnswer
        case .unsupported(let unsupported):
            return HomeAnswer(
                queryID: unsupported.id,
                kind: .message,
                title: "Unsupported Marina Query",
                subtitle: unsupported.message,
                primaryValue: nil,
                rows: [
                    HomeAnswerRow(title: "Reason", value: unsupported.kind.rawValue)
                ]
            )
        }
    }

    func summary(from result: MarinaAggregationResult) -> String {
        let answer = responseCompatibleAnswer(from: result)
        let primary = answer.primaryValue.map { " primary=\($0)" } ?? ""
        let rows = answer.rows.isEmpty ? "" : " rows=\(answer.rows.count)"
        return "\(answer.kind.rawValue): \(answer.title)\(primary)\(rows)"
    }
}
