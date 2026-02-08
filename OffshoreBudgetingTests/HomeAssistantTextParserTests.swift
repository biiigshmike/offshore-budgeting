//
//  HomeAssistantTextParserTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeAssistantTextParserTests {

    // MARK: - Intent Matching

    @Test func parse_overviewPrompt_withBroadLanguage_mapsToOverviewIntent() throws {
        let query = makeParser().parse("How am I doing this month?")

        #expect(query?.intent == .periodOverview)
        #expect(query?.dateRange != nil)
    }

    @Test func parsePlan_overviewPrompt_defaultsToMediumConfidence() throws {
        let plan = makeParser().parsePlan("How am I doing this month?")

        #expect(plan?.metric == .overview)
        #expect(plan?.confidenceBand == .medium)
        #expect(plan?.query.intent == .periodOverview)
    }

    @Test func parse_spendPrompt_withoutExplicitRange_mapsToSpendIntent() throws {
        let query = makeParser().parse("How much have I spent?")

        #expect(query?.intent == .spendThisMonth)
        #expect(query?.dateRange == nil)
    }

    @Test func parse_topCategoriesPrompt_withNaturalLanguage_mapsToTopCategoriesIntent() throws {
        let query = makeParser().parse("Where am I spending the most this month?")

        #expect(query?.intent == .topCategoriesThisMonth)
    }

    @Test func parse_comparePrompt_withMonthOverMonthPhrase_mapsToCompareIntent() throws {
        let query = makeParser().parse("Show my month over month change")

        #expect(query?.intent == .compareThisMonthToPreviousMonth)
    }

    @Test func parse_largestTransactionsPrompt_withPurchasesKeyword_mapsToLargestIntent() throws {
        let query = makeParser().parse("What are my biggest purchases this month?")

        #expect(query?.intent == .largestRecentTransactions)
    }

    @Test func parse_cardSpendPrompt_mapsToCardSpendIntent() throws {
        let query = makeParser().parse("For all cards, what was the total spent last month?")

        #expect(query?.intent == .cardSpendTotal)
        #expect(query?.dateRange != nil)
    }

    @Test func parse_cardSpendingHabitsPrompt_mapsToCardHabitsIntent() throws {
        let query = makeParser().parse("Help me learn about my variable spending habits.")

        #expect(query?.intent == .cardVariableSpendingHabits)
    }

    @Test func parse_incomeAveragePrompt_mapsToIncomeAverageIntent() throws {
        let query = makeParser().parse("What is my average actual income each month?")

        #expect(query?.intent == .incomeAverageActual)
    }

    @Test func parse_savingsStatusPrompt_mapsToSavingsStatusIntent() throws {
        let query = makeParser().parse("How am I doing this month with my savings?")

        #expect(query?.intent == .savingsStatus)
    }

    @Test func parse_savingsAveragePrompt_mapsToSavingsAverageIntent() throws {
        let query = makeParser().parse("For the last 4 periods, what was my average savings?")

        #expect(query?.intent == .savingsAverageRecentPeriods)
        #expect(query?.resultLimit == 4)
        #expect(query?.periodUnit == .month)
    }

    @Test func parse_savingsAveragePrompt_withWeeklyDefaultPeriod_mapsToWeeklyPeriodUnit() throws {
        let query = makeParser().parse(
            "For the last 4 periods, what was my average savings?",
            defaultPeriodUnit: .week
        )

        #expect(query?.intent == .savingsAverageRecentPeriods)
        #expect(query?.resultLimit == 4)
        #expect(query?.periodUnit == .week)
    }

    @Test func parse_incomeSourceSharePrompt_mapsToIncomeSourceShareIntent() throws {
        let query = makeParser().parse("How much of my income comes from paycheck this month?")

        #expect(query?.intent == .incomeSourceShare)
    }

    @Test func parse_incomeSourceShareTrendPrompt_mapsToTrendIntent() throws {
        let query = makeParser().parse("For the last 6 months, how much of my income comes from paycheck?")

        #expect(query?.intent == .incomeSourceShareTrend)
        #expect(query?.resultLimit == 6)
    }

    @Test func parse_categorySpendSharePrompt_mapsToCategorySpendShareIntent() throws {
        let query = makeParser().parse("What share of my spending is groceries this month?")

        #expect(query?.intent == .categorySpendShare)
    }

    @Test func parse_categorySpendShareTrendPrompt_mapsToTrendIntent() throws {
        let query = makeParser().parse("Over the last 4 months, what share of my spending is groceries?")

        #expect(query?.intent == .categorySpendShareTrend)
        #expect(query?.resultLimit == 4)
        #expect(query?.periodUnit == .month)
    }

    @Test func parse_presetDuePrompt_mapsToPresetDueIntent() throws {
        let query = makeParser().parse("Do I have any presets coming up that are due?")

        #expect(query?.intent == .presetDueSoon)
    }

    @Test func parse_presetHighestCostPrompt_mapsToPresetHighestCostIntent() throws {
        let query = makeParser().parse("Which preset costs me the most each period?")

        #expect(query?.intent == .presetHighestCost)
    }

    @Test func parse_presetTopCategoryPrompt_mapsToPresetTopCategoryIntent() throws {
        let query = makeParser().parse("Which category is assigned to the most presets?")

        #expect(query?.intent == .presetTopCategory)
    }

    @Test func parse_presetCategorySpendPrompt_mapsToPresetCategorySpendIntent() throws {
        let query = makeParser().parse("How much money do I spend per period on groceries presets?")

        #expect(query?.intent == .presetCategorySpend)
    }

    @Test func parse_categoryPotentialSavingsPrompt_mapsToPotentialSavingsIntent() throws {
        let query = makeParser().parse("If I reduce spending in groceries category, what could my potential savings be?")

        #expect(query?.intent == .categoryPotentialSavings)
    }

    @Test func parse_categoryReallocationPrompt_mapsToReallocationIntent() throws {
        let query = makeParser().parse("If I spend money on this category what could I realistically spend on the other categories for the period?")

        #expect(query?.intent == .categoryReallocationGuidance)
    }

    // MARK: - Limit Extraction

    @Test func parse_topCategoriesPrompt_withLimit_extractsLimit() throws {
        let query = makeParser().parse("Show my top 4 categories this month")

        #expect(query?.intent == .topCategoriesThisMonth)
        #expect(query?.resultLimit == 4)
    }

    @Test func parse_largestTransactionsPrompt_withLimit_extractsLimit() throws {
        let query = makeParser().parse("List my largest 6 transactions")

        #expect(query?.intent == .largestRecentTransactions)
        #expect(query?.resultLimit == 6)
    }

    // MARK: - Range Extraction

    @Test func parse_lastMonthPrompt_extractsLastMonthRange() throws {
        let query = makeParser().parse("What did I spend last month?")

        let expectedStart = date(2026, 1, 1, 0, 0, 0)
        let expectedEnd = date(2026, 1, 31, 23, 59, 59)

        #expect(query?.intent == .spendThisMonth)
        #expect(query?.dateRange?.startDate == expectedStart)
        #expect(query?.dateRange?.endDate == expectedEnd)
    }

    @Test func parse_thisYearPrompt_extractsYearRange() throws {
        let query = makeParser().parse("total expenses this year")

        let expectedStart = date(2026, 1, 1, 0, 0, 0)
        let expectedEnd = date(2026, 12, 31, 23, 59, 59)

        #expect(query?.intent == .spendThisMonth)
        #expect(query?.dateRange?.startDate == expectedStart)
        #expect(query?.dateRange?.endDate == expectedEnd)
    }

    @Test func parse_pastDaysPrompt_extractsRollingRange() throws {
        let query = makeParser().parse("Top categories for last 30 days")

        let expectedStart = date(2026, 1, 17, 0, 0, 0)
        let expectedEnd = fixedNow

        #expect(query?.intent == .topCategoriesThisMonth)
        #expect(query?.dateRange?.startDate == expectedStart)
        #expect(query?.dateRange?.endDate == expectedEnd)
    }

    @Test func parse_monthNamePrompt_withoutYear_usesMostRecentPastMonth() throws {
        let query = makeParser().parse("How did I do in december?")

        let expectedStart = date(2025, 12, 1, 0, 0, 0)
        let expectedEnd = date(2025, 12, 31, 23, 59, 59)

        #expect(query?.intent == .periodOverview)
        #expect(query?.dateRange?.startDate == expectedStart)
        #expect(query?.dateRange?.endDate == expectedEnd)
    }

    @Test func parse_monthNamePrompt_withExplicitYear_extractsMonthRange() throws {
        let query = makeParser().parse("How did I do in december 2024?")

        let expectedStart = date(2024, 12, 1, 0, 0, 0)
        let expectedEnd = date(2024, 12, 31, 23, 59, 59)

        #expect(query?.intent == .periodOverview)
        #expect(query?.dateRange?.startDate == expectedStart)
        #expect(query?.dateRange?.endDate == expectedEnd)
    }

    @Test func parse_explicitDateRangePrompt_extractsCustomRange() throws {
        let query = makeParser().parse("How did I do from 2026-01-10 to 2026-01-20?")

        let expectedStart = date(2026, 1, 10, 0, 0, 0)
        let expectedEnd = date(2026, 1, 20, 23, 59, 59)

        #expect(query?.intent == .periodOverview)
        #expect(query?.dateRange?.startDate == expectedStart)
        #expect(query?.dateRange?.endDate == expectedEnd)
    }

    @Test func parse_specificDatePrompt_extractsSingleDayRange() throws {
        let query = makeParser().parse("What did I spend on 2026-02-05?")

        let expectedStart = date(2026, 2, 5, 0, 0, 0)
        let expectedEnd = date(2026, 2, 5, 23, 59, 59)

        #expect(query?.intent == .spendThisMonth)
        #expect(query?.dateRange?.startDate == expectedStart)
        #expect(query?.dateRange?.endDate == expectedEnd)
    }

    // MARK: - Unknown Prompt

    @Test func parse_summaryPrompt_withPunctuation_mapsToOverviewIntent() throws {
        let query = makeParser().parse("Budget summary!!! this month...")

        #expect(query?.intent == .periodOverview)
        #expect(query?.dateRange != nil)
    }

    @Test func parse_unknownPrompt_returnsNil() throws {
        let query = makeParser().parse("Do I have budget leaks by weekday?")

        #expect(query == nil)
    }

    @Test func parse_overviewPrompt_withFinancesLookingLanguage_mapsToOverviewIntent() throws {
        let query = makeParser().parse("How are my finances looking?")

        #expect(query?.intent == .periodOverview)
    }

    @Test func parse_incomeSourceSharePrompt_withPortionLanguage_mapsToIncomeSourceShareIntent() throws {
        let query = makeParser().parse("What portion of my income comes from salary this month?")

        #expect(query?.intent == .incomeSourceShare)
    }

    @Test func parse_categorySpendSharePrompt_withPortionLanguage_mapsToCategorySpendShareIntent() throws {
        let query = makeParser().parse("What portion of my spending is groceries this month?")

        #expect(query?.intent == .categorySpendShare)
    }

    @Test func parse_presetDuePrompt_withRecurringLanguage_mapsToPresetDueIntent() throws {
        let query = makeParser().parse("Do I have any recurring payments due soon?")

        #expect(query?.intent == .presetDueSoon)
    }

    @Test func parse_presetHighestCostPrompt_withRecurringLanguage_mapsToPresetHighestCostIntent() throws {
        let query = makeParser().parse("Which recurring payment is most expensive each month?")

        #expect(query?.intent == .presetHighestCost)
    }

    @Test func parse_presetTopCategoryPrompt_withRecurringLanguage_mapsToPresetTopCategoryIntent() throws {
        let query = makeParser().parse("Which category has the most recurring charges?")

        #expect(query?.intent == .presetTopCategory)
    }

    @Test func parse_presetCategorySpendPrompt_withRecurringLanguage_mapsToPresetCategorySpendIntent() throws {
        let query = makeParser().parse("How much do I spend per month on groceries recurring payments?")

        #expect(query?.intent == .presetCategorySpend)
    }

    @Test func parse_categoryPotentialSavingsPrompt_withoutCategoryWord_mapsToPotentialSavingsIntent() throws {
        let query = makeParser().parse("If I cut groceries, how much could I save?")

        #expect(query?.intent == .categoryPotentialSavings)
    }

    @Test func parse_categoryReallocationPrompt_withRebalanceLanguage_mapsToReallocationIntent() throws {
        let query = makeParser().parse("If I spend less on groceries, how should I rebalance across other categories?")

        #expect(query?.intent == .categoryReallocationGuidance)
    }

    @Test func parsePlan_uncertainPrompt_setsLowConfidence() throws {
        let plan = makeParser().parsePlan("Maybe top categories this month, not sure")

        #expect(plan?.metric == .topCategories)
        #expect(plan?.confidenceBand == .low)
    }

    // MARK: - Helpers

    private var fixedNow: Date {
        date(2026, 2, 15, 12, 0, 0)
    }

    private func makeParser() -> HomeAssistantTextParser {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        return HomeAssistantTextParser(
            calendar: calendar,
            nowProvider: { fixedNow }
        )
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        _ second: Int
    ) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second
        components.timeZone = TimeZone(secondsFromGMT: 0)

        return Calendar(identifier: .gregorian).date(from: components) ?? .distantPast
    }
}
