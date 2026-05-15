import Foundation

struct MarinaAggregationResponseBridge {
    private let recoveryPolicy = MarinaQueryRecoveryPolicy()

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
            title: "I need one choice first",
            subtitle: clarification.message,
            primaryValue: nil,
            rows: clarification.choices.map { choice in
                HomeAnswerRow(
                    title: typedChoiceTitle(choice),
                    value: choice.subtitle ?? choice.rawValue ?? choice.entityTypeHint?.rawValue ?? ""
                )
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
                title: recoveryPolicy.unsupportedTitle(for: unsupported),
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

    private func typedChoiceTitle(_ choice: MarinaClarificationChoice) -> String {
        guard let type = choice.entityTypeHint else { return choice.title }
        return "\(choice.title) (\(type.rawValue))"
    }
}
