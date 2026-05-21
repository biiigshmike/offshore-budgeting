//
//  MarinaModelsTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct MarinaModelsTests {

    @Test func marinaTurnOutcomeEvaluator_executableQueryOverridesRecovery() throws {
        let outcome = MarinaTurnOutcomeEvaluator.outcome(
            hasExecutableQuery: true,
            requiredFieldsMissing: false,
            clarificationIsActionable: false,
            shouldRecover: true
        )

        #expect(outcome == .answer)
    }

    @Test func marinaTurnOutcomeEvaluator_actionableClarificationWithoutExecutableQuery_isClarification() throws {
        let outcome = MarinaTurnOutcomeEvaluator.outcome(
            hasExecutableQuery: false,
            requiredFieldsMissing: true,
            clarificationIsActionable: true,
            shouldRecover: false
        )

        #expect(outcome == .clarification)
    }

    @Test func marinaTurnOutcomeEvaluator_noExecutableAndNonActionableClarification_isUnresolved() throws {
        let outcome = MarinaTurnOutcomeEvaluator.outcome(
            hasExecutableQuery: false,
            requiredFieldsMissing: false,
            clarificationIsActionable: false,
            shouldRecover: false
        )

        #expect(outcome == .unresolved)
    }

    @Test func marinaTurnOutcomeEvaluator_lowConfidencePath_isRecovery() throws {
        let outcome = MarinaTurnOutcomeEvaluator.outcome(
            hasExecutableQuery: false,
            requiredFieldsMissing: false,
            clarificationIsActionable: false,
            shouldRecover: true
        )

        #expect(outcome == .recovery)
    }









    @Test func executedQueryAnswerNormalizer_emptySpendQuery_becomesMetricCard() throws {
        let normalizer = MarinaExecutedQueryAnswerNormalizer()
        let query = HomeQuery(
            intent: .spendThisMonth,
            dateRange: weekRange(2026, 4, 6)
        )
        let raw = HomeAnswer(
            queryID: query.id,
            kind: .message,
            title: "Spend This Month",
            subtitle: "No spending in this range yet.",
            primaryValue: nil,
            rows: []
        )

        let normalized = normalizer.normalize(raw, for: query)

        #expect(normalized.kind == .metric)
        #expect(normalized.primaryValue == CurrencyFormatter.string(from: 0))
        #expect(normalized.rows.count == 1)
        #expect(normalized.rows.first?.title == "Total")
        #expect(normalized.rows.first?.value == CurrencyFormatter.string(from: 0))
        #expect(normalized.subtitle?.contains("2026") == true)
    }

    @Test func executedQueryAnswerNormalizer_emptySpendQueryExplicitRange_becomesMetricCard() throws {
        let normalizer = MarinaExecutedQueryAnswerNormalizer()
        let query = HomeQuery(
            intent: .spendThisMonth,
            dateRange: HomeQueryDateRange(
                startDate: date(2026, 4, 1, 0, 0, 0),
                endDate: date(2026, 4, 7, 0, 0, 0)
            )
        )
        let raw = HomeAnswer(
            queryID: query.id,
            kind: .message,
            title: "Spend This Month",
            subtitle: "No spending in this range yet.",
            primaryValue: nil,
            rows: []
        )

        let normalized = normalizer.normalize(raw, for: query)

        #expect(normalized.kind == .metric)
        #expect(normalized.primaryValue == CurrencyFormatter.string(from: 0))
        #expect(normalized.rows.count == 1)
        #expect(normalized.rows.first?.title == "Total")
        #expect(normalized.rows.first?.value == CurrencyFormatter.string(from: 0))
        #expect(normalized.subtitle?.contains("Apr") == true || normalized.subtitle?.contains("2026") == true)
    }

    @Test func suggestionSectionBuilder_prioritizesClarificationRecoveryThenFollowUps() throws {
        let clarification = [
            MarinaSuggestion(title: "Clarify", query: HomeQuery(intent: .spendThisMonth))
        ]
        let recovery = [
            MarinaRecoverySuggestion(
                suggestion: MarinaSuggestion(title: "Recover", query: HomeQuery(intent: .topCategoriesThisMonth)),
                confidenceScore: 0.4,
                reasoning: "Fallback"
            )
        ]
        let followUps = [
            MarinaSuggestion(title: "Follow up", query: HomeQuery(intent: .compareThisMonthToPreviousMonth))
        ]

        let sections = MarinaSuggestionSectionBuilder.build(
            clarificationSuggestions: clarification,
            clarificationReasonCount: 1,
            recoverySuggestions: recovery,
            followUpSuggestions: followUps
        )

        #expect(sections.map(\.title) == ["Clarification (1)", "Recovery", "Follow-Up Suggestions"])
        #expect(sections[0].suggestions.first?.title == "Clarify")
    }

    // MARK: - HomeQueryDateRange

    @Test func queryDateRange_reordersWhenInputIsDescending() throws {
        let later = Date(timeIntervalSince1970: 2_000)
        let earlier = Date(timeIntervalSince1970: 1_000)

        let range = HomeQueryDateRange(startDate: later, endDate: earlier)

        #expect(range.startDate == earlier)
        #expect(range.endDate == later)
    }

    @Test func queryDateRange_keepsOrderWhenInputIsAscending() throws {
        let start = Date(timeIntervalSince1970: 1_000)
        let end = Date(timeIntervalSince1970: 2_000)

        let range = HomeQueryDateRange(startDate: start, endDate: end)

        #expect(range.startDate == start)
        #expect(range.endDate == end)
    }

    // MARK: - HomeQuery limits

    @Test func query_defaultLimit_matchesIntentDefaults() throws {
        let overview = HomeQuery(intent: .periodOverview)
        let topCategories = HomeQuery(intent: .topCategoriesThisMonth)
        let recentTransactions = HomeQuery(intent: .largestRecentTransactions)
        let cardSpend = HomeQuery(intent: .cardSpendTotal)
        let cardHabits = HomeQuery(intent: .cardVariableSpendingHabits)
        let incomeAverage = HomeQuery(intent: .incomeAverageActual)
        let savingsStatus = HomeQuery(intent: .savingsStatus)
        let savingsAverage = HomeQuery(intent: .savingsAverageRecentPeriods)
        let incomeShare = HomeQuery(intent: .incomeSourceShare)
        let categoryShare = HomeQuery(intent: .categorySpendShare)
        let incomeShareTrend = HomeQuery(intent: .incomeSourceShareTrend)
        let categoryShareTrend = HomeQuery(intent: .categorySpendShareTrend)
        let presetDueSoon = HomeQuery(intent: .presetDueSoon)
        let presetHighestCost = HomeQuery(intent: .presetHighestCost)
        let presetTopCategory = HomeQuery(intent: .presetTopCategory)
        let presetCategorySpend = HomeQuery(intent: .presetCategorySpend)
        let categoryPotentialSavings = HomeQuery(intent: .categoryPotentialSavings)
        let categoryReallocationGuidance = HomeQuery(intent: .categoryReallocationGuidance)
        let spend = HomeQuery(intent: .spendThisMonth)
        let comparison = HomeQuery(intent: .compareThisMonthToPreviousMonth)

        #expect(overview.resultLimit == 1)
        #expect(topCategories.resultLimit == HomeQuery.defaultTopCategoryLimit)
        #expect(recentTransactions.resultLimit == HomeQuery.defaultRecentTransactionsLimit)
        #expect(cardSpend.resultLimit == 1)
        #expect(cardHabits.resultLimit == 3)
        #expect(incomeAverage.resultLimit == 1)
        #expect(savingsStatus.resultLimit == 1)
        #expect(savingsAverage.resultLimit == 3)
        #expect(incomeShare.resultLimit == 1)
        #expect(categoryShare.resultLimit == 1)
        #expect(incomeShareTrend.resultLimit == 3)
        #expect(categoryShareTrend.resultLimit == 3)
        #expect(presetDueSoon.resultLimit == 3)
        #expect(presetHighestCost.resultLimit == 3)
        #expect(presetTopCategory.resultLimit == 3)
        #expect(presetCategorySpend.resultLimit == 1)
        #expect(categoryPotentialSavings.resultLimit == 3)
        #expect(categoryReallocationGuidance.resultLimit == 3)
        #expect(spend.resultLimit == 1)
        #expect(comparison.resultLimit == 1)
    }

    @Test func query_limit_clampsToAllowedBounds() throws {
        let low = HomeQuery(intent: .topCategoriesThisMonth, resultLimit: 0)
        let high = HomeQuery(intent: .largestRecentTransactions, resultLimit: 500)
        let valid = HomeQuery(intent: .largestRecentTransactions, resultLimit: 12)

        #expect(low.resultLimit == 1)
        #expect(high.resultLimit == HomeQuery.maxResultLimit)
        #expect(valid.resultLimit == 12)
    }

    // MARK: - HomeQueryPlan

    @Test func queryPlan_mapsMetricToIntentAndLimit() throws {
        let range = HomeQueryDateRange(
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 2_000)
        )

        let topCategoriesPlan = HomeQueryPlan(
            metric: .topCategories,
            dateRange: range,
            resultLimit: 4,
            confidenceBand: .high
        )

        let overviewPlan = HomeQueryPlan(
            metric: .overview,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        #expect(topCategoriesPlan.query.intent == .topCategoriesThisMonth)
        #expect(topCategoriesPlan.query.resultLimit == 4)
        #expect(topCategoriesPlan.query.dateRange == range)

        #expect(overviewPlan.query.intent == .periodOverview)
        #expect(overviewPlan.query.resultLimit == 1)
        #expect(overviewPlan.query.dateRange == nil)
    }

    // MARK: - Codable

    @Test func query_codableRoundTrip_preservesPayload() throws {
        let range = HomeQueryDateRange(
            startDate: Date(timeIntervalSince1970: 1_000),
            endDate: Date(timeIntervalSince1970: 5_000)
        )
        let original = HomeQuery(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            intent: .largestRecentTransactions,
            dateRange: range,
            resultLimit: 9
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeQuery.self, from: encoded)

        #expect(decoded == original)
    }

    @Test func answer_codableRoundTrip_preservesRowsAndMetadata() throws {
        let queryID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let generatedAt = Date(timeIntervalSince1970: 12_345)

        let original = HomeAnswer(
            id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            queryID: queryID,
            kind: .list,
            title: "Top Categories",
            subtitle: "This Month",
            primaryValue: "$1,250.00",
            rows: [
                HomeAnswerRow(
                    id: UUID(uuidString: "12345678-1234-1234-1234-123456789012")!,
                    title: "Food",
                    value: "$500.00"
                ),
                HomeAnswerRow(
                    id: UUID(uuidString: "87654321-4321-4321-4321-210987654321")!,
                    title: "Travel",
                    value: "$300.00"
                )
            ],
            generatedAt: generatedAt
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeAnswer.self, from: encoded)

        #expect(decoded == original)
    }

    @Test func answer_codableRoundTrip_preservesInlineCreateFormAttachment() throws {
        let original = HomeAnswer(
            id: UUID(uuidString: "AAAAAAAA-8888-7777-6666-555555555555")!,
            queryID: UUID(uuidString: "BBBBBBBB-2222-3333-4444-555555555555")!,
            kind: .message,
            title: "Create Expense",
            subtitle: nil,
            rows: [],
            attachment: .inlineCreateForm(
                MarinaInlineCreateForm(
                    entity: .expense,
                    summary: nil,
                    amountText: "18.50",
                    date: Date(timeIntervalSince1970: 5_000),
                    notesText: "Coffee",
                    selectedCardID: UUID(uuidString: "CCCCCCCC-1111-2222-3333-444444444444")!
                )
            ),
            generatedAt: Date(timeIntervalSince1970: 12_346)
        )

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HomeAnswer.self, from: encoded)

        #expect(decoded == original)
    }

    // MARK: - Command Plan Updates

    @Test func commandPlanUpdating_cardName_preservesParsedAttributes() throws {
        let original = MarinaCommandPlan(
            intent: .addPreset,
            confidenceBand: .high,
            rawPrompt: "create preset rent 1500 every 2 weeks on Apple Card",
            amount: 1500,
            notes: "rent",
            cardName: "Old Card",
            categoryName: "Housing",
            entityName: "rent",
            cardThemeRaw: "sunset",
            cardEffectRaw: "glass",
            recurrenceFrequencyRaw: RecurrenceFrequency.weekly.rawValue,
            recurrenceInterval: 2,
            weeklyWeekday: 6
        )

        let updated = original.updating(cardName: "Apple Card")

        #expect(updated.cardName == "Apple Card")
        #expect(updated.entityName == "rent")
        #expect(updated.cardThemeRaw == "sunset")
        #expect(updated.cardEffectRaw == "glass")
        #expect(updated.recurrenceFrequencyRaw == RecurrenceFrequency.weekly.rawValue)
        #expect(updated.recurrenceInterval == 2)
        #expect(updated.weeklyWeekday == 6)
    }

    @Test func commandPlanUpdating_incomeKindAndRecurrence_preservesOtherFields() throws {
        let original = MarinaCommandPlan(
            intent: .addIncome,
            confidenceBand: .high,
            rawPrompt: "log income from side gig 1200",
            amount: 1200,
            date: Date(timeIntervalSince1970: 1_700_000_000),
            source: "Side Gig",
            isPlannedIncome: nil,
            recurrenceFrequencyRaw: nil,
            recurrenceInterval: nil
        )

        let updated = original.updating(
            isPlannedIncome: false,
            recurrenceFrequencyRaw: RecurrenceFrequency.monthly.rawValue,
            recurrenceInterval: 1
        )

        #expect(updated.amount == 1200)
        #expect(updated.source == "Side Gig")
        #expect(updated.date == original.date)
        #expect(updated.isPlannedIncome == false)
        #expect(updated.recurrenceFrequencyRaw == RecurrenceFrequency.monthly.rawValue)
        #expect(updated.recurrenceInterval == 1)
    }

    // MARK: - Follow-up Anchoring

    @Test func clarificationChoiceResolver_resolvesExactChipTitle() throws {
        let card = MarinaClarificationChoice(
            title: "Apple Card",
            entityTypeHint: .card,
            patchSlot: .target,
            rawValue: "Apple Card",
            sourceID: UUID()
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Apple?",
            choices: [card]
        )

        let result = MarinaClarificationChoiceResolver().resolve(
            reply: "Apple Card (card)",
            clarification: clarification
        )

        #expect(result == .resolved(card))
    }

    @Test func clarificationChoiceResolver_resolvesUniqueTypeAlias() throws {
        let category = MarinaClarificationChoice(
            title: "Groceries",
            entityTypeHint: .category,
            patchSlot: .target,
            rawValue: "Groceries",
            sourceID: UUID()
        )
        let expense = MarinaClarificationChoice(
            title: "Groceries",
            entityTypeHint: .expense,
            patchSlot: .target,
            rawValue: "Groceries",
            sourceID: UUID()
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Groceries?",
            choices: [category, expense]
        )

        let result = MarinaClarificationChoiceResolver().resolve(
            reply: "category",
            clarification: clarification
        )

        #expect(result == .resolved(category))
    }

    @Test func clarificationChoiceResolver_returnsAmbiguousForRepeatedTypeAlias() throws {
        let first = MarinaClarificationChoice(
            title: "Apple Watch",
            entityTypeHint: .expense,
            patchSlot: .target,
            rawValue: "Apple Watch",
            sourceID: UUID()
        )
        let second = MarinaClarificationChoice(
            title: "Apple Store",
            entityTypeHint: .expense,
            patchSlot: .target,
            rawValue: "Apple Store",
            sourceID: UUID()
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Apple?",
            choices: [first, second]
        )

        let result = MarinaClarificationChoiceResolver().resolve(
            reply: "expense",
            clarification: clarification
        )

        #expect(result == .ambiguous([first, second]))
    }

    @Test func clarificationChoiceResolver_doesNotFabricateUnmatchedTargetChoice() throws {
        let choice = MarinaClarificationChoice(
            title: "Groceries",
            entityTypeHint: .category,
            patchSlot: .target,
            rawValue: "Groceries",
            sourceID: UUID()
        )
        let clarification = MarinaTypedClarification(
            kind: .ambiguousTarget,
            message: "Which Groceries?",
            choices: [choice]
        )

        let result = MarinaClarificationChoiceResolver().resolve(
            reply: "category(category) category",
            clarification: clarification
        )

        #expect(result == .unresolved)
    }

    @Test func promptTurnClassifier_compareToLastMonthIsFollowUp() throws {
        let classifier = MarinaPromptTurnClassifier()

        #expect(classifier.classify("Compare to last month", defaultPeriodUnit: .month) == .followUp)
        #expect(classifier.classify("Compare this to last month", defaultPeriodUnit: .month) == .followUp)
    }

    @Test func promptTurnClassifier_whatIfIsFreshFoundationPrompt() throws {
        let classifier = MarinaPromptTurnClassifier()

        #expect(classifier.classify("What if I saved 200 more this month?", defaultPeriodUnit: .month) == .freshQuestion)
    }

    @Test func followUpAnchorResolver_matchesLatestRelevantAnswer() throws {
        let resolver = MarinaFollowUpAnchorResolver()
        let context = MarinaAnswerContext(
            query: HomeQuery(
                intent: .categoryReallocationGuidance,
                dateRange: HomeQueryDateRange(
                    startDate: Date(timeIntervalSince1970: 1_000),
                    endDate: Date(timeIntervalSince1970: 2_000)
                ),
                targetName: "Bills & Utilities"
            ),
            answerTitle: "Reallocation Guidance (Bills & Utilities)",
            answerKind: .list,
            userPrompt: "Category reallocation guidance",
            targetName: "Bills & Utilities",
            targetType: .category,
            rowTitles: ["Current Bills & Utilities", "Reduce other categories by", "Shopping"],
            rowValues: ["$2,399.94", "$239.99", "$106.30 (from $261.50)"],
            scenarioPercent: 10
        )

        let decision = resolver.resolve(
            prompt: "Reduce bills by 10% will save me 239.99?",
            recentContexts: [context]
        )

        #expect(decision == .matched(context))
    }

    @Test func followUpAnchorResolver_usesRecentFallbackWhenLatestIsWeakMatch() throws {
        let resolver = MarinaFollowUpAnchorResolver()
        let older = MarinaAnswerContext(
            query: HomeQuery(intent: .merchantSpendTotal, targetName: "Starbucks"),
            answerTitle: "Merchant Spend (Starbucks)",
            answerKind: .message,
            userPrompt: "What did I spend at Starbucks this year?",
            targetName: "Starbucks",
            targetType: .merchant,
            rowTitles: ["Transactions", "Latest activity", "Total"],
            rowValues: ["17", "Mar 27, 2026", "$425.00"],
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let latest = MarinaAnswerContext(
            query: HomeQuery(intent: .periodOverview),
            answerTitle: "Budget Overview",
            answerKind: .message,
            userPrompt: "How am I doing this month?",
            rowTitles: ["Total spend"],
            rowValues: ["$1,234.00"],
            generatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let decision = resolver.resolve(
            prompt: "What about Starbucks instead?",
            recentContexts: [older, latest]
        )

        #expect(decision == .matched(older))
    }

    @Test func followUpAnchorResolver_returnsAmbiguousWhenTwoRecentAnswersFit() throws {
        let resolver = MarinaFollowUpAnchorResolver()
        let first = MarinaAnswerContext(
            query: HomeQuery(intent: .categoryPotentialSavings, targetName: "Groceries"),
            answerTitle: "Potential Savings (Groceries)",
            answerKind: .list,
            userPrompt: "If I cut groceries, what could I save?",
            targetName: "Groceries",
            targetType: .category,
            rowTitles: ["Current spend"],
            rowValues: ["$500.00"],
            scenarioPercent: 10,
            generatedAt: Date(timeIntervalSince1970: 1_000)
        )
        let second = MarinaAnswerContext(
            query: HomeQuery(intent: .categoryPotentialSavings, targetName: "Dining"),
            answerTitle: "Potential Savings (Dining)",
            answerKind: .list,
            userPrompt: "If I cut dining, what could I save?",
            targetName: "Dining",
            targetType: .category,
            rowTitles: ["Current spend"],
            rowValues: ["$420.00"],
            scenarioPercent: 10,
            generatedAt: Date(timeIntervalSince1970: 2_000)
        )

        let decision = resolver.resolve(
            prompt: "Will that save me 10%?",
            recentContexts: [first, second]
        )

        if case let .ambiguous(contexts) = decision {
            #expect(contexts.count == 2)
        } else {
            Issue.record("Expected ambiguous follow-up anchor decision")
        }
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = hour
        comps.minute = minute
        comps.second = second
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        return calendar.date(from: comps) ?? .distantPast
    }

    private func dayRange(_ year: Int, _ month: Int, _ day: Int) -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(year, month, day, 0, 0, 0),
            endDate: date(year, month, day, 23, 59, 59)
        )
    }

    private func monthRange(_ year: Int, _ month: Int) -> HomeQueryDateRange {
        let start = date(year, month, 1, 0, 0, 0)
        let endDay = calendar.range(of: .day, in: .month, for: start)?.count ?? 28
        return HomeQueryDateRange(
            startDate: start,
            endDate: date(year, month, endDay, 23, 59, 59)
        )
    }

    private func weekRange(_ year: Int, _ month: Int, _ day: Int) -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(year, month, day, 0, 0, 0),
            endDate: date(year, month, day + 6, 23, 59, 59)
        )
    }

    private func makePriorQueryContext(
        metric: HomeQueryMetric,
        targetName: String?,
        targetType: MarinaAnswerTargetType?,
        dateRange: HomeQueryDateRange,
        resultLimit: Int? = nil,
        periodUnit: HomeQueryPeriodUnit = .month,
        lastQueryPlan: HomeQueryPlan? = nil
    ) -> MarinaPriorQueryContext {
        let plan = lastQueryPlan ?? HomeQueryPlan(
            metric: metric,
            dateRange: dateRange,
            resultLimit: resultLimit,
            confidenceBand: .high,
            targetName: targetName,
            periodUnit: periodUnit
        )

        return MarinaPriorQueryContext(
            lastQueryPlan: plan,
            lastMetric: metric,
            lastTargetName: targetName,
            lastTargetType: targetType,
            lastDateRange: dateRange,
            lastResultLimit: resultLimit,
            lastPeriodUnit: periodUnit
        )
    }

    private func makeRouterContext(
        priorQueryContext: MarinaPriorQueryContext
    ) -> MarinaInterpretationContext {
        MarinaInterpretationContext(
            workspaceName: "Test Workspace",
            defaultPeriodUnit: .month,
            sessionContext: MarinaSessionContext(),
            priorQueryContext: priorQueryContext,
            cardNames: [],
            categoryNames: ["Groceries"],
            incomeSourceNames: [],
            presetTitles: [],
            budgetNames: [],
            aliasSummaries: [],
            now: date(2026, 4, 15, 12, 0, 0)
        )
    }

    private func emptyPriorQueryContext() -> MarinaPriorQueryContext {
        MarinaPriorQueryContext(
            lastQueryPlan: nil,
            lastMetric: nil,
            lastTargetName: nil,
            lastTargetType: nil,
            lastDateRange: nil,
            lastResultLimit: nil,
            lastPeriodUnit: nil
        )
    }

}

private struct StubAvailability: MarinaModelAvailabilityProviding {
    let status: MarinaModelAvailability.Status

    func currentStatus() -> MarinaModelAvailability.Status {
        status
    }
}

private struct StubStructuredInterpreter: MarinaStructuredIntentInterpreting {
    let result: Result<MarinaStructuredIntent, Error>

    func interpret(
        prompt: String,
        context: MarinaInterpretationContext
    ) async throws -> MarinaStructuredIntent {
        try result.get()
    }
}
