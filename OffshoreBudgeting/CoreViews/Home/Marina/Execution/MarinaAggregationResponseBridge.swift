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
        guard clarification.actionableChoices.count > 1 else {
            return HomeAnswer(
                queryID: clarification.id,
                kind: .message,
                title: "I need a clearer target",
                subtitle: "I could not turn that into a safe choice, so Offshore did not query your financial data.",
                primaryValue: nil,
                rows: [
                    HomeAnswerRow(title: "Data safety", value: "Offshore did not query or change your financial records."),
                    HomeAnswerRow(title: "Try", value: "Ask again with a named card, budget, category, merchant, income source, savings account, or reconciliation account.")
                ]
            )
        }

        return HomeAnswer(
            queryID: clarification.id,
            kind: .message,
            title: "I need one choice first",
            subtitle: clarification.message,
            primaryValue: nil,
            rows: clarification.choices.map { choice in
                HomeAnswerRow(
                    title: typedChoiceTitle(choice),
                    value: typedChoiceValue(choice),
                    sourceID: choice.sourceID,
                    objectType: lookupObjectType(from: choice.entityTypeHint)
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
        case .noData(let result):
            return result.sourceAnswer
        case .unsupported(let unsupported):
            return HomeAnswer(
                queryID: unsupported.id,
                kind: .message,
                title: recoveryPolicy.unsupportedTitle(for: unsupported),
                subtitle: unsupported.message,
                primaryValue: nil,
                rows: [
                    HomeAnswerRow(title: "Status", value: "Marina cannot run that exact question yet."),
                    HomeAnswerRow(title: "Try", value: "Ask for a total, list, comparison, or named budget item.")
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
        MarinaClarificationChoiceResolver.displayTitle(for: choice)
    }

    private func typedChoiceValue(_ choice: MarinaClarificationChoice) -> String {
        if let subtitle = choice.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines),
           subtitle.isEmpty == false {
            return subtitle
        }
        if let type = choice.entityTypeHint {
            return displayName(for: type)
        }
        return choice.rawValue ?? ""
    }

    private func displayName(for type: MarinaCandidateEntityTypeHint) -> String {
        switch type {
        case .allocationAccount:
            return "Reconciliation account"
        case .incomeSource:
            return "Income source"
        case .savingsAccount:
            return "Savings account"
        case .expense:
            return "Expense"
        case .transaction:
            return "Transaction"
        default:
            return type.rawValue.prefix(1).uppercased() + type.rawValue.dropFirst()
        }
    }

    private func lookupObjectType(from type: MarinaCandidateEntityTypeHint?) -> MarinaLookupObjectType? {
        switch type {
        case .budget:
            return .budget
        case .category:
            return .category
        case .card:
            return .card
        case .preset:
            return .preset
        case .expense:
            return .variableExpense
        case .transaction:
            return .variableExpense
        case .incomeSource:
            return .income
        case .savingsAccount:
            return .savingsAccount
        case .allocationAccount:
            return .reconciliationAccount
        case .merchant, .workspace, nil:
            return nil
        }
    }
}
