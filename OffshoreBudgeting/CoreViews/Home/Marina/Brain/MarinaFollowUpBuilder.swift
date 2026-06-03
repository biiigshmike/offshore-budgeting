import Foundation

struct MarinaFollowUpBuilder {
    func followUps(
        for context: MarinaAnswerSemanticContext
    ) -> [MarinaFollowUpSuggestion] {
        guard context.answerKind != .message,
              context.request.expectedAnswerShape != .clarification,
              context.request.expectedAnswerShape != .unsupported else {
            return []
        }

        var suggestions: [MarinaFollowUpSuggestion] = []

        switch context.request.entity {
        case .category:
            if context.answerKind == .metric {
                suggestions.append(contentsOf: categoryMetricFollowUps(for: context))
            }
        case .budget:
            if context.request.measure == .remainingRoom {
                suggestions.append(contentsOf: budgetRoomFollowUps(for: context))
            }
        case .income:
            suggestions.append(contentsOf: incomeFollowUps(for: context))
        case .card:
            suggestions.append(contentsOf: cardFollowUps(for: context))
        case .workspace, .plannedExpense, .variableExpense, .reconciliationAccount, .savingsAccount, .preset:
            break
        }

        if context.answerKind == .list {
            suggestions.append(contentsOf: listFollowUps(for: context))
        }

        return uniqued(suggestions)
    }

    // MARK: - Entity follow-ups

    private func categoryMetricFollowUps(for context: MarinaAnswerSemanticContext) -> [MarinaFollowUpSuggestion] {
        let target = displayTarget(in: context)
        let categoryPhrase = target ?? MarinaL10n.common("category", defaultValue: "category", comment: "Common lowercase label for category.")

        var previousRequest = context.request
        previousRequest.dateRangeToken = .previousPeriod
        previousRequest.expectedAnswerShape = .metric

        let expenseRequest = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: context.request.dateRangeToken,
            targetName: context.request.targetName,
            targetDisplayName: context.request.targetDisplayName,
            resultLimit: 5,
            sort: .amountDescending,
            expenseScope: .unified,
            expectedAnswerShape: .list
        )

        let shareRequest = MarinaSemanticRequest(
            entity: .category,
            operation: .group,
            measure: .budgetImpact,
            dimensions: [.category],
            dateRangeToken: context.request.dateRangeToken,
            resultLimit: 5,
            sort: .amountDescending,
            expenseScope: .unified,
            expectedAnswerShape: .list
        )

        return [
            suggestion(
                title: MarinaL10n.string("marina.followUp.category.previous.title", defaultValue: "Compare this category to previous period", comment: "Follow-up title for comparing a category to the previous period."),
                prompt: target.map { MarinaL10n.format("marina.followUp.category.previous.promptFormat", defaultValue: "Show %@ for the previous period.", comment: "Follow-up prompt for a category previous period metric.", $0) }
                    ?? MarinaL10n.string("marina.followUp.category.previous.prompt", defaultValue: "Show this category for the previous period.", comment: "Follow-up prompt for a category previous period metric."),
                reason: .comparePreviousPeriod,
                request: previousRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.category.biggest.title", defaultValue: "Show biggest expenses in this category", comment: "Follow-up title for biggest category expenses."),
                prompt: MarinaL10n.format("marina.followUp.category.biggest.promptFormat", defaultValue: "Show biggest expenses in %@.", comment: "Follow-up prompt for biggest category expenses.", categoryPhrase),
                reason: .inspectRows,
                request: expenseRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.category.share.title", defaultValue: "Show category share", comment: "Follow-up title for category spend share."),
                prompt: MarinaL10n.string("marina.followUp.category.share.prompt", defaultValue: "Show category share.", comment: "Follow-up prompt for category spend share."),
                reason: .breakdown,
                request: shareRequest
            )
        ]
    }

    private func budgetRoomFollowUps(for context: MarinaAnswerSemanticContext) -> [MarinaFollowUpSuggestion] {
        let safeSpendRequest = MarinaSemanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .remainingRoom,
            dateRangeToken: context.request.dateRangeToken,
            targetName: context.request.targetName,
            expectedAnswerShape: .metric
        )

        let whatIfRequest = MarinaSemanticRequest(
            entity: .budget,
            operation: .whatIf,
            measure: .remainingRoom,
            dateRangeToken: context.request.dateRangeToken,
            targetName: context.request.targetName,
            whatIfAmount: 50,
            expectedAnswerShape: .comparison
        )

        let availabilityRequest = MarinaSemanticRequest(
            entity: .category,
            operation: .list,
            measure: .categoryAvailability,
            dimensions: [.category],
            dateRangeToken: context.request.dateRangeToken,
            resultLimit: 5,
            categoryAvailabilityFilter: .underLimit,
            expectedAnswerShape: .list
        )

        return [
            suggestion(
                title: MarinaL10n.string("marina.followUp.budget.safeDaily.title", defaultValue: "What can I spend per day?", comment: "Follow-up title for safe daily spend."),
                prompt: MarinaL10n.string("marina.followUp.budget.safeDaily.prompt", defaultValue: "What can I spend per day?", comment: "Follow-up prompt for safe daily spend."),
                reason: .safeDailySpend,
                request: safeSpendRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.budget.whatIf50.title", defaultValue: "What if I spend $50?", comment: "Follow-up title for a fifty dollar what-if."),
                prompt: MarinaL10n.string("marina.followUp.budget.whatIf50.prompt", defaultValue: "What if I spend $50?", comment: "Follow-up prompt for a fifty dollar what-if."),
                reason: .whatIf,
                request: whatIfRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.budget.categoryRoom.title", defaultValue: "Which categories still have room?", comment: "Follow-up title for category availability."),
                prompt: MarinaL10n.string("marina.followUp.budget.categoryRoom.prompt", defaultValue: "Which categories still have room?", comment: "Follow-up prompt for category availability."),
                reason: .breakdown,
                request: availabilityRequest
            )
        ]
    }

    private func incomeFollowUps(for context: MarinaAnswerSemanticContext) -> [MarinaFollowUpSuggestion] {
        let expectedRequest = MarinaSemanticRequest(
            entity: .income,
            operation: .list,
            measure: .incomeAmount,
            dimensions: context.request.dimensions,
            dateRangeToken: context.request.dateRangeToken,
            targetName: context.request.targetName,
            resultLimit: 5,
            sort: .dateAscending,
            incomeState: .planned,
            expectedAnswerShape: .list
        )

        let comparisonRequest = MarinaSemanticRequest(
            entity: .income,
            operation: .compare,
            measure: .incomeAmount,
            dimensions: context.request.dimensions,
            dateRangeToken: context.request.dateRangeToken,
            targetName: context.request.targetName,
            incomeState: context.request.incomeState ?? .actual,
            expectedAnswerShape: .comparison
        )

        return [
            suggestion(
                title: MarinaL10n.string("marina.followUp.income.expected.title", defaultValue: "What income is still expected?", comment: "Follow-up title for expected income."),
                prompt: MarinaL10n.string("marina.followUp.income.expected.prompt", defaultValue: "What income is still expected?", comment: "Follow-up prompt for expected income."),
                reason: .forecast,
                request: expectedRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.income.coverage.title", defaultValue: "Does income cover planned expenses?", comment: "Follow-up title for income coverage."),
                prompt: MarinaL10n.string("marina.followUp.income.coverage.prompt", defaultValue: "Does income cover planned expenses?", comment: "Follow-up prompt for income coverage."),
                reason: .forecast
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.income.previous.title", defaultValue: "Compare income to last period", comment: "Follow-up title for income previous-period comparison."),
                prompt: MarinaL10n.string("marina.followUp.income.previous.prompt", defaultValue: "Compare income to last period.", comment: "Follow-up prompt for income previous-period comparison."),
                reason: .comparePreviousPeriod,
                request: comparisonRequest
            )
        ]
    }

    private func cardFollowUps(for context: MarinaAnswerSemanticContext) -> [MarinaFollowUpSuggestion] {
        let cardPhrase = displayTarget(in: context) ?? MarinaL10n.common("card", defaultValue: "card", comment: "Common lowercase label for card.")
        let largestRequest = MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dimensions: [.card],
            dateRangeToken: context.request.dateRangeToken,
            targetName: context.request.targetName,
            targetDisplayName: context.request.targetDisplayName,
            resultLimit: 5,
            sort: .amountDescending,
            expenseScope: .unified,
            expectedAnswerShape: .list
        )

        return [
            suggestion(
                title: MarinaL10n.string("marina.followUp.card.categoryBreakdown.title", defaultValue: "Break this card down by category", comment: "Follow-up title for card category breakdown."),
                prompt: MarinaL10n.format("marina.followUp.card.categoryBreakdown.promptFormat", defaultValue: "Break %@ down by category.", comment: "Follow-up prompt for card category breakdown.", cardPhrase),
                reason: .breakdown
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.card.largest.title", defaultValue: "Show largest expenses on this card", comment: "Follow-up title for largest card expenses."),
                prompt: MarinaL10n.format("marina.followUp.card.largest.promptFormat", defaultValue: "Show largest expenses on %@.", comment: "Follow-up prompt for largest card expenses.", cardPhrase),
                reason: .inspectRows,
                request: largestRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.card.compare.title", defaultValue: "Compare this card to another card", comment: "Follow-up title for comparing cards."),
                prompt: MarinaL10n.format("marina.followUp.card.compare.promptFormat", defaultValue: "Compare %@ to another card.", comment: "Follow-up prompt for comparing cards.", cardPhrase),
                reason: .comparePreviousPeriod
            )
        ]
    }

    private func listFollowUps(for context: MarinaAnswerSemanticContext) -> [MarinaFollowUpSuggestion] {
        var suggestions: [MarinaFollowUpSuggestion] = []
        var moreRequest = context.request
        moreRequest.expectedAnswerShape = .list
        moreRequest.resultLimit = min(max((context.request.resultLimit ?? context.rowReferences.count) + 5, 10), HomeQuery.maxResultLimit)
        suggestions.append(
            suggestion(
                title: MarinaL10n.string("marina.followUp.list.more.title", defaultValue: "Show more", comment: "Follow-up title for showing more rows."),
                prompt: MarinaL10n.string("marina.followUp.list.more.prompt", defaultValue: "Show more.", comment: "Follow-up prompt for showing more rows."),
                reason: .inspectRows,
                request: moreRequest
            )
        )

        var previousRequest = context.request
        previousRequest.dateRangeToken = .previousPeriod
        previousRequest.expectedAnswerShape = context.request.expectedAnswerShape
        suggestions.append(
            suggestion(
                title: MarinaL10n.string("marina.followUp.list.previous.title", defaultValue: "Compare to last period", comment: "Follow-up title for previous-period list follow-up."),
                prompt: MarinaL10n.string("marina.followUp.list.previous.prompt", defaultValue: "Show last period.", comment: "Follow-up prompt for previous-period list follow-up."),
                reason: .comparePreviousPeriod,
                request: previousRequest
            )
        )

        if supportsCategoryBreakdown(context) {
            let breakdownRequest = MarinaSemanticRequest(
                entity: .category,
                operation: .group,
                measure: .budgetImpact,
                dimensions: [.category],
                dateRangeToken: context.request.dateRangeToken,
                resultLimit: 5,
                sort: .amountDescending,
                expenseScope: .unified,
                expectedAnswerShape: .list
            )
            suggestions.append(
                suggestion(
                    title: MarinaL10n.string("marina.followUp.list.breakdown.title", defaultValue: "Show related breakdown", comment: "Follow-up title for a related breakdown."),
                    prompt: MarinaL10n.string("marina.followUp.list.breakdown.prompt", defaultValue: "Show category breakdown.", comment: "Follow-up prompt for a related category breakdown."),
                    reason: .breakdown,
                    request: breakdownRequest
                )
            )
        }

        return suggestions
    }

    // MARK: - Helpers

    private func suggestion(
        title: String,
        prompt: String,
        reason: MarinaFollowUpSuggestion.Reason,
        request: MarinaSemanticRequest? = nil
    ) -> MarinaFollowUpSuggestion {
        MarinaFollowUpSuggestion(
            title: title,
            prompt: prompt,
            reason: reason,
            semanticRequest: request
        )
    }

    private func displayTarget(in context: MarinaAnswerSemanticContext) -> String? {
        trimmed(context.request.targetDisplayName) ?? trimmed(context.request.targetName)
    }

    private func trimmed(_ value: String?) -> String? {
        let trimmed = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func supportsCategoryBreakdown(_ context: MarinaAnswerSemanticContext) -> Bool {
        switch context.request.entity {
        case .variableExpense, .plannedExpense, .card:
            return context.request.dimensions.contains(.category) == false
        case .category:
            return context.request.operation != .group
        case .workspace, .budget, .reconciliationAccount, .savingsAccount, .income, .preset:
            return false
        }
    }

    private func uniqued(_ suggestions: [MarinaFollowUpSuggestion]) -> [MarinaFollowUpSuggestion] {
        var seen: Set<String> = []
        var result: [MarinaFollowUpSuggestion] = []
        for suggestion in suggestions {
            let key = "\(suggestion.reason.rawValue)|\(suggestion.title)|\(suggestion.prompt)"
            guard seen.insert(key).inserted else { continue }
            result.append(suggestion)
        }
        return result
    }
}
