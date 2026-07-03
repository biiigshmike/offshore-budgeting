import Foundation

struct MarinaFollowUpBuilder {
    func followUps(
        for context: MarinaAnswerSemanticContext
    ) -> [MarinaFollowUpSuggestion] {
        guard context.request.expectedAnswerShape != .clarification,
              context.request.expectedAnswerShape != .unsupported else {
            return []
        }

        if context.answerKind == .message {
            return emptyMessageFollowUps(for: context)
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
                executionMode: .executable,
                request: previousRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.category.biggest.title", defaultValue: "Show biggest expenses in this category", comment: "Follow-up title for biggest category expenses."),
                prompt: MarinaL10n.format("marina.followUp.category.biggest.promptFormat", defaultValue: "Show biggest expenses in %@.", comment: "Follow-up prompt for biggest category expenses.", categoryPhrase),
                reason: .inspectRows,
                executionMode: .executable,
                request: expenseRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.category.share.title", defaultValue: "Show category share", comment: "Follow-up title for category spend share."),
                prompt: MarinaL10n.string("marina.followUp.category.share.prompt", defaultValue: "Show category share.", comment: "Follow-up prompt for category spend share."),
                reason: .breakdown,
                executionMode: .executable,
                request: shareRequest
            )
        ]
    }

    private func budgetRoomFollowUps(for context: MarinaAnswerSemanticContext) -> [MarinaFollowUpSuggestion] {
        let safeSpendRequest = MarinaSemanticRequest(
            entity: .budget,
            operation: .forecast,
            measure: .safeDailySpend,
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
                executionMode: .executable,
                request: safeSpendRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.budget.whatIf50.title", defaultValue: "What if I spend $50?", comment: "Follow-up title for a fifty dollar what-if."),
                prompt: MarinaL10n.string("marina.followUp.budget.whatIf50.prompt", defaultValue: "What if I spend $50?", comment: "Follow-up prompt for a fifty dollar what-if."),
                reason: .whatIf,
                executionMode: .executable,
                request: whatIfRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.budget.categoryRoom.title", defaultValue: "Which categories still have room?", comment: "Follow-up title for category availability."),
                prompt: MarinaL10n.string("marina.followUp.budget.categoryRoom.prompt", defaultValue: "Which categories still have room?", comment: "Follow-up prompt for category availability."),
                reason: .breakdown,
                executionMode: .executable,
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

        let coverageRequest = MarinaSemanticRequest(
            entity: .income,
            operation: .share,
            measure: .coverageRatio,
            dimensions: context.request.dimensions,
            dateRangeToken: context.request.dateRangeToken,
            targetName: context.request.targetName,
            incomeState: context.request.incomeState,
            expectedAnswerShape: .metric
        )

        var suggestions = [
            suggestion(
                title: MarinaL10n.string("marina.followUp.income.expected.title", defaultValue: "What income is still expected?", comment: "Follow-up title for expected income."),
                prompt: MarinaL10n.string("marina.followUp.income.expected.prompt", defaultValue: "What income is still expected?", comment: "Follow-up prompt for expected income."),
                reason: .forecast,
                executionMode: .executable,
                request: expectedRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.income.coverage.title", defaultValue: "Does income cover planned expenses?", comment: "Follow-up title for income coverage."),
                prompt: MarinaL10n.string("marina.followUp.income.coverage.prompt", defaultValue: "Does income cover planned expenses?", comment: "Follow-up prompt for income coverage."),
                reason: .forecast,
                executionMode: .executable,
                request: coverageRequest
            )
        ]

        if shouldOfferPreviousPeriodComparison(for: context) {
            suggestions.append(suggestion(
                title: MarinaL10n.string("marina.followUp.income.previous.title", defaultValue: "Compare income to last period", comment: "Follow-up title for income previous-period comparison."),
                prompt: MarinaL10n.string("marina.followUp.income.previous.prompt", defaultValue: "Compare income to last period.", comment: "Follow-up prompt for income previous-period comparison."),
                reason: .comparePreviousPeriod,
                executionMode: .executable,
                request: comparisonRequest
            ))
        }

        return suggestions
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
                title: MarinaL10n.string("marina.followUp.card.largest.title", defaultValue: "Show largest expenses on this card", comment: "Follow-up title for largest card expenses."),
                prompt: MarinaL10n.format("marina.followUp.card.largest.promptFormat", defaultValue: "Show largest expenses on %@.", comment: "Follow-up prompt for largest card expenses.", cardPhrase),
                reason: .inspectRows,
                executionMode: .executable,
                request: largestRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.card.compare.title", defaultValue: "Compare this card to another card", comment: "Follow-up title for comparing cards."),
                prompt: MarinaL10n.format("marina.followUp.card.compare.promptFormat", defaultValue: "Compare %@ to another card.", comment: "Follow-up prompt for comparing cards.", cardPhrase),
                reason: .comparePreviousPeriod,
                executionMode: .clarificationRequired
            )
        ]
    }

    private func listFollowUps(for context: MarinaAnswerSemanticContext) -> [MarinaFollowUpSuggestion] {
        var suggestions: [MarinaFollowUpSuggestion] = []
        let displayedCount = context.displayedRowCount ?? context.rowReferences.count
        let remainingCount = context.totalRowCount.map { max($0 - displayedCount, 0) }
        // TODO(Marina pagination): future long-result cards should show the first
        // 8-10 rows, keep the full total visible, include "Showing 10 of 22",
        // support Show more, avoid duplicate rows, and keep totals stable.
        if remainingCount == nil || (remainingCount ?? 0) > 0 {
            var moreRequest = context.request
            moreRequest.expectedAnswerShape = .list
            moreRequest.resultLimit = min(max((context.request.resultLimit ?? displayedCount) + 5, 10), HomeQuery.maxResultLimit)
            suggestions.append(
                suggestion(
                    title: MarinaL10n.string("marina.followUp.list.more.title", defaultValue: "Show more", comment: "Follow-up title for showing more rows."),
                    prompt: MarinaL10n.string("marina.followUp.list.more.prompt", defaultValue: "Show more.", comment: "Follow-up prompt for showing more rows."),
                    reason: .showMore,
                    executionMode: .executable,
                    request: moreRequest,
                    remainingResultCount: remainingCount
                )
            )
        }

        if shouldOfferPreviousPeriodComparison(for: context) {
            var previousRequest = context.request
            previousRequest.dateRangeToken = .previousPeriod
            previousRequest.expectedAnswerShape = context.request.expectedAnswerShape
            suggestions.append(
                suggestion(
                    title: MarinaL10n.string("marina.followUp.list.previous.title", defaultValue: "Compare to last period", comment: "Follow-up title for previous-period list follow-up."),
                    prompt: MarinaL10n.string("marina.followUp.list.previous.prompt", defaultValue: "Show last period.", comment: "Follow-up prompt for previous-period list follow-up."),
                    reason: .comparePreviousPeriod,
                    executionMode: .executable,
                    request: previousRequest
                )
            )
        }

        if let inspectRowsRequest = inspectRowsRequest(for: context) {
            suggestions.append(
                suggestion(
                    title: MarinaL10n.string("marina.followUp.list.inspectRows.title", defaultValue: "Show biggest expenses behind this", comment: "Follow-up title for showing expense rows behind an aggregate list."),
                    prompt: MarinaL10n.string("marina.followUp.list.inspectRows.prompt", defaultValue: "Show biggest expenses behind this.", comment: "Follow-up prompt for showing expense rows behind an aggregate list."),
                    reason: .inspectRows,
                    executionMode: .executable,
                    request: inspectRowsRequest
                )
            )
        }

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
                    executionMode: .executable,
                    request: breakdownRequest
                )
            )
        }

        return suggestions
    }

    private func emptyMessageFollowUps(for context: MarinaAnswerSemanticContext) -> [MarinaFollowUpSuggestion] {
        guard context.request.expectedAnswerShape == .list,
              context.request.dateRangeToken != .allTime,
              let target = displayTarget(in: context),
              isExpenseRequest(context.request) else {
            return []
        }

        var allTimeRequest = context.request
        allTimeRequest.dateRangeToken = .allTime
        allTimeRequest.expectedAnswerShape = .list

        var previousRequest = context.request
        previousRequest.dateRangeToken = .previousPeriod
        previousRequest.expectedAnswerShape = .list

        return [
            suggestion(
                title: MarinaL10n.string("marina.followUp.emptyList.previous.title", defaultValue: "Check last period", comment: "Follow-up title for a previous-period empty list search."),
                prompt: MarinaL10n.string("marina.followUp.emptyList.previous.prompt", defaultValue: "Check last period.", comment: "Follow-up prompt for previous-period empty expense search."),
                reason: .comparePreviousPeriod,
                executionMode: .executable,
                request: previousRequest
            ),
            suggestion(
                title: MarinaL10n.string("marina.followUp.emptyList.allTime.title", defaultValue: "Search all time", comment: "Follow-up title for an all-time empty list search."),
                prompt: MarinaL10n.format("marina.followUp.emptyList.allTime.promptFormat", defaultValue: "Search all %@ expenses.", comment: "Follow-up prompt for all-time expense search.", target),
                reason: .searchAllTime,
                executionMode: .executable,
                request: allTimeRequest
            )
        ]
    }

    // MARK: - Helpers

    private func suggestion(
        title: String,
        prompt: String,
        reason: MarinaFollowUpSuggestion.Reason,
        executionMode: MarinaFollowUpExecutionMode,
        request: MarinaSemanticRequest? = nil,
        remainingResultCount: Int? = nil
    ) -> MarinaFollowUpSuggestion {
        MarinaFollowUpSuggestion(
            title: title,
            prompt: prompt,
            reason: reason,
            executionMode: executionMode,
            semanticRequest: request,
            remainingResultCount: remainingResultCount
        )
    }

    private func displayTarget(in context: MarinaAnswerSemanticContext) -> String? {
        trimmed(context.request.targetDisplayName) ?? trimmed(context.request.targetName) ?? trimmed(context.request.textQuery)
    }

    private func isExpenseRequest(_ request: MarinaSemanticRequest) -> Bool {
        switch request.entity {
        case .variableExpense, .plannedExpense:
            return true
        case .workspace, .budget, .card, .reconciliationAccount, .savingsAccount, .income, .category, .preset:
            return false
        }
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

    private func inspectRowsRequest(for context: MarinaAnswerSemanticContext) -> MarinaSemanticRequest? {
        guard isAggregateSpendList(context),
              context.rowReferences.contains(where: { $0.objectType == .plannedExpense || $0.objectType == .variableExpense }) == false else {
            return nil
        }

        return MarinaSemanticRequest(
            entity: .variableExpense,
            operation: .list,
            measure: .budgetImpact,
            dimensions: expenseRowDimensions(from: context.request),
            dateRangeToken: context.request.dateRangeToken,
            targetName: context.request.targetName,
            textQuery: context.request.textQuery,
            targetDisplayName: context.request.targetDisplayName,
            resultLimit: 5,
            sort: .amountDescending,
            expenseScope: context.request.expenseScope ?? .unified,
            expectedAnswerShape: .list
        )
    }

    private func isAggregateSpendList(_ context: MarinaAnswerSemanticContext) -> Bool {
        guard context.request.measure == .budgetImpact,
              context.request.operation == .group else {
            return false
        }

        switch context.request.entity {
        case .category, .variableExpense, .plannedExpense, .budget, .card:
            return true
        case .workspace, .reconciliationAccount, .savingsAccount, .income, .preset:
            return false
        }
    }

    private func expenseRowDimensions(from request: MarinaSemanticRequest) -> [MarinaSemanticDimension] {
        var dimensions: [MarinaSemanticDimension] = []

        if request.dimensions.contains(.merchantText), trimmed(request.textQuery) != nil {
            dimensions.append(.merchantText)
        }
        if request.dimensions.contains(.card), trimmed(request.targetName) != nil {
            dimensions.append(.card)
        }
        if request.dimensions.contains(.category), trimmed(request.targetName) != nil {
            dimensions.append(.category)
        }
        if request.dimensions.contains(.reconciliationAccount), trimmed(request.targetName) != nil {
            dimensions.append(.reconciliationAccount)
        }

        return dimensions
    }

    private func shouldOfferPreviousPeriodComparison(for context: MarinaAnswerSemanticContext) -> Bool {
        guard context.request.operation != .compare,
              context.comparisonDateRange == nil else {
            return false
        }

        switch context.request.dateRangeToken {
        case .previousPeriod, .previousMonth:
            return false
        case .currentPeriod, .currentMonth, .yearToDate, .nextSevenDays, .allTime:
            return true
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
