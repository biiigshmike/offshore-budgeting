//
//  HomeAssistantModelsTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeAssistantModelsTests {

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

    // MARK: - Command Plan Updates

    @Test func commandPlanUpdating_cardName_preservesParsedAttributes() throws {
        let original = HomeAssistantCommandPlan(
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
        let original = HomeAssistantCommandPlan(
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

    @Test func followUpAnchorResolver_matchesLatestRelevantAnswer() throws {
        let resolver = HomeAssistantFollowUpAnchorResolver()
        let context = HomeAssistantAnswerContext(
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
        let resolver = HomeAssistantFollowUpAnchorResolver()
        let older = HomeAssistantAnswerContext(
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
        let latest = HomeAssistantAnswerContext(
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
        let resolver = HomeAssistantFollowUpAnchorResolver()
        let first = HomeAssistantAnswerContext(
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
        let second = HomeAssistantAnswerContext(
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
}
