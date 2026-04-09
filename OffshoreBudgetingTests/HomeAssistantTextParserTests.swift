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

    @Test func parse_comparePrompt_withThisMonthToLastMonthPhrase_keepsExistingIntent() throws {
        let query = makeParser().parse("Compare this month to last month")

        #expect(query?.intent == .compareThisMonthToPreviousMonth)
    }

    @Test func parse_largestTransactionsPrompt_withPurchasesKeyword_mapsToLargestIntent() throws {
        let query = makeParser().parse("What are my biggest purchases this month?")

        #expect(query?.intent == .largestRecentTransactions)
    }

    @Test func parse_expenseListPrompt_withYesterday_mapsToLargestTransactionsIntent() throws {
        let query = makeParser().parse("list expenses yesterday")

        #expect(query?.intent == .largestRecentTransactions)
        #expect(query?.dateRange?.startDate == date(2026, 2, 14, 0, 0, 0))
        #expect(query?.dateRange?.endDate == date(2026, 2, 14, 23, 59, 59))
    }

    @Test func parse_purchaseListPrompt_withYesterday_mapsToLargestTransactionsIntent() throws {
        let query = makeParser().parse("what were the purchases yesterday")

        #expect(query?.intent == .largestRecentTransactions)
        #expect(query?.dateRange?.startDate == date(2026, 2, 14, 0, 0, 0))
        #expect(query?.dateRange?.endDate == date(2026, 2, 14, 23, 59, 59))
    }

    @Test func parse_spendListPrompt_withToday_mapsToLargestTransactionsIntent() throws {
        let query = makeParser().parse("What did I spend my money on today")

        #expect(query?.intent == .largestRecentTransactions)
        #expect(query?.dateRange?.startDate == date(2026, 2, 15, 0, 0, 0))
        #expect(query?.dateRange?.endDate == date(2026, 2, 15, 23, 59, 59))
    }

    @Test func parse_spendPrompt_withHowMuchToday_staysSpendIntent() throws {
        let query = makeParser().parse("How much did I spend today?")

        #expect(query?.intent == .spendThisMonth)
        #expect(query?.dateRange?.startDate == date(2026, 2, 15, 0, 0, 0))
        #expect(query?.dateRange?.endDate == date(2026, 2, 15, 23, 59, 59))
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

    @Test func parse_safeSpendTodayPrompt_mapsToSafeSpendIntent() throws {
        let query = makeParser().parse("What is my safe spend today?")

        #expect(query?.intent == .safeSpendToday)
    }

    @Test func parse_forecastSavingsPrompt_mapsToForecastSavingsIntent() throws {
        let query = makeParser().parse("What are my projected savings for April?")

        #expect(query?.intent == .forecastSavings)
    }

    @Test func parse_nextPlannedExpensePrompt_mapsToNextPlannedExpenseIntent() throws {
        let query = makeParser().parse("What is my next planned expense?")

        #expect(query?.intent == .nextPlannedExpense)
    }

    @Test func parse_spendTrendsPrompt_mapsToSpendTrendsIntent() throws {
        let query = makeParser().parse("Show my spending trend this month")

        #expect(query?.intent == .spendTrendsSummary)
    }

    @Test func parse_cardSnapshotPrompt_mapsToCardSnapshotIntent() throws {
        let query = makeParser().parse("How is my Apple Card doing this month?")

        #expect(query?.intent == .cardSnapshotSummary)
    }

    @Test func parse_merchantSpendPrompt_mapsToMerchantSpendIntent() throws {
        let query = makeParser().parse("How much did I spend at Starbucks this month?")

        #expect(query?.intent == .merchantSpendTotal)
    }

    @Test func parse_merchantSpendOnPrompt_mapsToMerchantSpendIntent() throws {
        let query = makeParser().parse("What is the amount I have spent on Starbucks so far this year?")

        #expect(query?.intent == .merchantSpendTotal)
        #expect(query?.dateRange != nil)
    }

    @Test func parse_spendAveragePrompt_mapsToSpendAverageIntent() throws {
        let query = makeParser().parse("What is my average spend per month?")

        #expect(query?.intent == .spendAveragePerPeriod)
        #expect(query?.periodUnit == .month)
    }

    @Test func parse_merchantAveragePrompt_mapsToMerchantSummaryIntent() throws {
        let query = makeParser().parse("What is my average spend per month at Target?")

        #expect(query?.intent == .merchantSpendSummary)
        #expect(query?.periodUnit == .month)
    }

    @Test func parse_merchantSummaryPrompt_mapsToMerchantSummaryIntent() throws {
        let query = makeParser().parse("Summarize my Target spending")

        #expect(query?.intent == .merchantSpendSummary)
    }

    @Test func parse_topMerchantsPrompt_mapsToTopMerchantsIntent() throws {
        let query = makeParser().parse("Top merchants this month")

        #expect(query?.intent == .topMerchantsThisMonth)
    }

    @Test func parse_storeDiscoveryPrompt_withToday_mapsToTopMerchantsIntent() throws {
        let query = makeParser().parse("Which stores did I shop at today?")

        #expect(query?.intent == .topMerchantsThisMonth)
        #expect(query?.dateRange?.startDate == date(2026, 2, 15, 0, 0, 0))
        #expect(query?.dateRange?.endDate == date(2026, 2, 15, 23, 59, 59))
    }

    @Test func parse_whereDidIShopPrompt_withToday_mapsToTopMerchantsIntent() throws {
        let query = makeParser().parse("Where did I shop today?")

        #expect(query?.intent == .topMerchantsThisMonth)
        #expect(query?.dateRange?.startDate == date(2026, 2, 15, 0, 0, 0))
        #expect(query?.dateRange?.endDate == date(2026, 2, 15, 23, 59, 59))
    }

    @Test func parse_whereDidISpendMoneyPrompt_withYesterday_mapsToTopMerchantsIntent() throws {
        let query = makeParser().parse("Where did I spend money yesterday?")

        #expect(query?.intent == .topMerchantsThisMonth)
        #expect(query?.dateRange?.startDate == date(2026, 2, 14, 0, 0, 0))
        #expect(query?.dateRange?.endDate == date(2026, 2, 14, 23, 59, 59))
    }

    @Test func parse_topCategoryChangesPrompt_mapsToTopCategoryChangesIntent() throws {
        let query = makeParser().parse("Which categories changed most vs last month?")

        #expect(query?.intent == .topCategoryChangesThisMonth)
    }

    @Test func parse_topCardChangesPrompt_mapsToTopCardChangesIntent() throws {
        let query = makeParser().parse("Which cards changed most vs last month?")

        #expect(query?.intent == .topCardChangesThisMonth)
    }

    @Test func coverageMatrix_existingFinanceFamilies_keepExpectedRouting() throws {
        let cases: [IntentPhraseCase] = [
            .init(prompt: "Walk me through my spending this month", expectedIntent: .spendThisMonth),
            .init(prompt: "What did I pay for today?", expectedIntent: .largestRecentTransactions),
            .init(prompt: "Where's my money going this month?", expectedIntent: .topCategoriesThisMonth),
            .init(prompt: "Which vendors got most of my money this month?", expectedIntent: .topMerchantsThisMonth),
            .init(prompt: "How much went to Starbucks this month?", expectedIntent: .merchantSpendTotal),
            .init(prompt: "What did I spend with Starbucks this month?", expectedIntent: .merchantSpendTotal),
            .init(prompt: "What is my average purchase at Starbucks?", expectedIntent: .merchantSpendSummary),
            .init(prompt: "Which envelopes have money left?", expectedIntent: .topCategoriesThisMonth),
            .init(prompt: "What got deposited this month?", expectedIntent: .incomeAverageActual),
            .init(prompt: "When was my last paycheck?", expectedIntent: .incomeAverageActual),
            .init(prompt: "Which card am I leaning on most?", expectedIntent: .cardSnapshotSummary),
            .init(prompt: "What did I put on Apple Card this month?", expectedIntent: .cardSpendTotal),
            .init(prompt: "Am I on track to save this month?", expectedIntent: .forecastSavings),
            .init(prompt: "Why am I saving less this month?", expectedIntent: .savingsStatus),
            .init(prompt: "What changed in my spending this month?", expectedIntent: .topCategoryChangesThisMonth)
        ]

        for testCase in cases {
            let query = makeParser().parse(testCase.prompt)
            #expect(query?.intent == testCase.expectedIntent)
        }
    }

    @Test func coverageMatrix_falsePositiveNeighbors_whatIfMerchantPrompt_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("What if I spent $25/week at Starbucks?") == nil)
    }

    @Test func coverageMatrix_falsePositiveNeighbors_affordabilityPrompt_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("Can I afford Starbucks this month?") == nil)
    }

    @Test func coverageMatrix_falsePositiveNeighbors_appStoragePrompt_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("How much storage is the app using?") == nil)
    }

    @Test func coverageMatrix_falsePositiveNeighbors_cardStylePrompt_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("Which card style looks best?") == nil)
    }

    @Test func coverageMatrix_falsePositiveNeighbors_dataPrompt_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("Where did my data go?") == nil)
    }

    @Test func coverageMatrix_falsePositiveNeighbors_storeLocatorPrompt_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("Which stores support Apple Pay near me?") == nil)
    }

    @Test func parse_compareMerchantPrompt_mapsToMerchantComparisonIntent() throws {
        let query = makeParser().parse("Compare merchant Starbucks this month vs last month")

        #expect(query?.intent == .compareMerchantThisMonthToPreviousMonth)
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

    @Test func phrasePack_homeParityQuestionFamilies_mapToExpectedIntent() throws {
        let parser = makeParser()
        let cases: [IntentPhraseCase] = [
            IntentPhraseCase(prompt: "How much did I spend today and where?", expectedIntent: .spendThisMonth),
            IntentPhraseCase(prompt: "Where did I spend today?", expectedIntent: .topMerchantsThisMonth),
            IntentPhraseCase(prompt: "Where did my money go yesterday?", expectedIntent: .topMerchantsThisMonth),
            IntentPhraseCase(prompt: "What did I buy today?", expectedIntent: .largestRecentTransactions),
            IntentPhraseCase(prompt: "What were my purchases this week?", expectedIntent: .largestRecentTransactions),
            IntentPhraseCase(prompt: "What is my average spend per month?", expectedIntent: .spendAveragePerPeriod),
            IntentPhraseCase(prompt: "Average spending this month", expectedIntent: .spendAveragePerPeriod),
            IntentPhraseCase(prompt: "What is my average spend per month at Target?", expectedIntent: .merchantSpendSummary),
            IntentPhraseCase(prompt: "Summarize my Target spending", expectedIntent: .merchantSpendSummary),
            IntentPhraseCase(prompt: "Where am I spending the most this month?", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "What category is driving my spending this month?", expectedIntent: .topCategoryChangesThisMonth),
            IntentPhraseCase(prompt: "Which categories are over budget this month?", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "Where do I still have room in my budget?", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "Which categories have money left?", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "When did I spend the most this month?", expectedIntent: .spendThisMonth),
            IntentPhraseCase(prompt: "Why did spending spike this month?", expectedIntent: .topCategoryChangesThisMonth),
            IntentPhraseCase(prompt: "Which card did I use the most this month?", expectedIntent: .cardSnapshotSummary),
            IntentPhraseCase(prompt: "Which card has the most activity?", expectedIntent: .cardSnapshotSummary),
            IntentPhraseCase(prompt: "How much did I spend on Apple Card this month?", expectedIntent: .cardSpendTotal),
            IntentPhraseCase(prompt: "What income came in this month?", expectedIntent: .incomeAverageActual),
            IntentPhraseCase(prompt: "Who paid me this month?", expectedIntent: .incomeAverageActual),
            IntentPhraseCase(prompt: "When did I get paid this month?", expectedIntent: .incomeAverageActual),
            IntentPhraseCase(prompt: "How much actual income came in this month?", expectedIntent: .incomeAverageActual),
            IntentPhraseCase(prompt: "What are my projected savings this month?", expectedIntent: .forecastSavings),
            IntentPhraseCase(prompt: "Why am I behind on savings this month?", expectedIntent: .savingsStatus),
            IntentPhraseCase(prompt: "When is my next planned expense?", expectedIntent: .nextPlannedExpense),
            IntentPhraseCase(prompt: "What bill is coming up next?", expectedIntent: .nextPlannedExpense),
            IntentPhraseCase(prompt: "What recurring payment is coming up next?", expectedIntent: .presetDueSoon),
            IntentPhraseCase(prompt: "Who did I pay the most this month?", expectedIntent: .topMerchantsThisMonth),
            IntentPhraseCase(prompt: "How much did I spend at Target today?", expectedIntent: .merchantSpendTotal),
            IntentPhraseCase(prompt: "What is my budget status this month?", expectedIntent: .periodOverview),
            IntentPhraseCase(prompt: "Why does my budget feel tight?", expectedIntent: .topCategoryChangesThisMonth)
        ]

        for phraseCase in cases {
            let query = parser.parse(phraseCase.prompt)
            #expect(query?.intent == phraseCase.expectedIntent)
        }
    }

    @Test func phrasePack_homeParityUnsupportedQuestions_doNotFalsePositive() throws {
        let parser = makeParser()
        let prompts = [
            "Where is the settings screen?",
            "Why is the app slow?",
            "Who created this budget?",
            "What model is Marina using?",
            "How much storage is the app using?",
            "What is the average temperature this month?",
            "Which vendors support refunds?",
            "How much headroom does the API have?"
        ]

        for prompt in prompts {
            let query = parser.parse(prompt)
            if query != nil {
                fatalError("Shipping false-positive prompt mismatch: \(prompt) -> \(String(describing: query?.intent))")
            }
        }
    }

    // MARK: - Phrase Packs

    @Test func phrasePack_naturalLanguageVariants_mapToExpectedIntent() throws {
        let parser = makeParser()
        let cases: [IntentPhraseCase] = [
            IntentPhraseCase(prompt: "How am I doing?", expectedIntent: .periodOverview),
            IntentPhraseCase(prompt: "Budget health check this month", expectedIntent: .periodOverview),
            IntentPhraseCase(prompt: "Give me a quick spending summary", expectedIntent: .periodOverview),
            IntentPhraseCase(prompt: "What did I spend this month?", expectedIntent: .spendThisMonth),
            IntentPhraseCase(prompt: "Total expenses so far", expectedIntent: .spendThisMonth),
            IntentPhraseCase(prompt: "Show my top 3 categories this month", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "Where do I spend the most?", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "Compare this month versus last month", expectedIntent: .compareThisMonthToPreviousMonth),
            IntentPhraseCase(prompt: "Month over month change", expectedIntent: .compareThisMonthToPreviousMonth),
            IntentPhraseCase(prompt: "Largest 5 purchases this month", expectedIntent: .largestRecentTransactions),
            IntentPhraseCase(prompt: "Top transactions this month", expectedIntent: .largestRecentTransactions),
            IntentPhraseCase(prompt: "For all cards, what was total spent this month?", expectedIntent: .cardSpendTotal),
            IntentPhraseCase(prompt: "Help me learn my card spending patterns", expectedIntent: .cardVariableSpendingHabits),
            IntentPhraseCase(prompt: "Average actual income each month", expectedIntent: .incomeAverageActual),
            IntentPhraseCase(prompt: "How am I doing with savings?", expectedIntent: .savingsStatus),
            IntentPhraseCase(prompt: "Last 6 periods average savings", expectedIntent: .savingsAverageRecentPeriods),
            IntentPhraseCase(prompt: "What portion of income comes from salary?", expectedIntent: .incomeSourceShare),
            IntentPhraseCase(prompt: "Over the last 4 months, what portion of income is salary?", expectedIntent: .incomeSourceShareTrend),
            IntentPhraseCase(prompt: "What share of spending is groceries?", expectedIntent: .categorySpendShare),
            IntentPhraseCase(prompt: "Past 3 months, what share of spending is groceries?", expectedIntent: .categorySpendShareTrend),
            IntentPhraseCase(prompt: "Any recurring payments due soon?", expectedIntent: .presetDueSoon),
            IntentPhraseCase(prompt: "Which recurring payment is most expensive?", expectedIntent: .presetHighestCost),
            IntentPhraseCase(prompt: "Which category has the most recurring charges?", expectedIntent: .presetTopCategory),
            IntentPhraseCase(prompt: "How much do I spend per month on groceries recurring payments?", expectedIntent: .presetCategorySpend),
            IntentPhraseCase(prompt: "If I cut groceries, what could I save?", expectedIntent: .categoryPotentialSavings),
            IntentPhraseCase(prompt: "If I reduce groceries, how should I rebalance other categories?", expectedIntent: .categoryReallocationGuidance)
        ]

        for phraseCase in cases {
            let query = parser.parse(phraseCase.prompt)
            #expect(query?.intent == phraseCase.expectedIntent)
        }
    }

    @Test func phrasePack_bankerLanguageVariants_mapToExpectedIntent() throws {
        let parser = makeParser()
        let cases: [IntentPhraseCase] = [
            IntentPhraseCase(prompt: "Which budgets still have headroom this month?", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "How much room do I have left this month?", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "What got deposited this month?", expectedIntent: .incomeAverageActual),
            IntentPhraseCase(prompt: "How much did I bring in this month?", expectedIntent: .incomeAverageActual),
            IntentPhraseCase(prompt: "How much went to Starbucks this month?", expectedIntent: .merchantSpendTotal),
            IntentPhraseCase(prompt: "Which vendors got most of my money this month?", expectedIntent: .topMerchantsThisMonth),
            IntentPhraseCase(prompt: "What did I put on Apple Card this month?", expectedIntent: .cardSpendTotal),
            IntentPhraseCase(prompt: "Am I on track to save this month?", expectedIntent: .forecastSavings)
        ]

        for phraseCase in cases {
            let query = parser.parse(phraseCase.prompt)
            #expect(query?.intent == phraseCase.expectedIntent)
        }
    }

    @Test func phrasePack_casualAdvisorVariants_mapToExpectedIntent() throws {
        let parser = makeParser()
        let cases: [IntentPhraseCase] = [
            IntentPhraseCase(prompt: "What do I usually spend in a month?", expectedIntent: .spendAveragePerPeriod),
            IntentPhraseCase(prompt: "What do I usually spend at Starbucks?", expectedIntent: .merchantSpendSummary),
            IntentPhraseCase(prompt: "What places did I spend at today?", expectedIntent: .topMerchantsThisMonth),
            IntentPhraseCase(prompt: "Which day cost me the most this month?", expectedIntent: .spendThisMonth),
            IntentPhraseCase(prompt: "What's eating my budget this month?", expectedIntent: .topCategoryChangesThisMonth),
            IntentPhraseCase(prompt: "What card saw the most action?", expectedIntent: .cardSnapshotSummary),
            IntentPhraseCase(prompt: "How tight is my budget right now?", expectedIntent: .periodOverview)
        ]

        for phraseCase in cases {
            let query = parser.parse(phraseCase.prompt)
            #expect(query?.intent == phraseCase.expectedIntent)
        }
    }

    @Test func phrasePack_adversarialCollisions_preferExpectedIntent() throws {
        let parser = makeParser()
        let cases: [IntentPhraseCase] = [
            IntentPhraseCase(prompt: "What percentage of my income comes from salary this month?", expectedIntent: .incomeSourceShare),
            IntentPhraseCase(prompt: "What percentage of my spending is groceries this month?", expectedIntent: .categorySpendShare),
            IntentPhraseCase(prompt: "For all cards what was my total spent last month?", expectedIntent: .cardSpendTotal),
            IntentPhraseCase(prompt: "Top 5 purchases this month", expectedIntent: .largestRecentTransactions),
            IntentPhraseCase(prompt: "Top 5 categories this month", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "How am I doing this month with savings?", expectedIntent: .savingsStatus),
            IntentPhraseCase(prompt: "Last 4 months what share of income comes from paycheck?", expectedIntent: .incomeSourceShareTrend),
            IntentPhraseCase(prompt: "Last 4 months what share of spending is groceries?", expectedIntent: .categorySpendShareTrend),
            IntentPhraseCase(prompt: "How much do I spend on groceries preset recurring each month?", expectedIntent: .presetCategorySpend),
            IntentPhraseCase(prompt: "Recurring payments due soon this month", expectedIntent: .presetDueSoon)
        ]

        for phraseCase in cases {
            let query = parser.parse(phraseCase.prompt)
            #expect(query?.intent == phraseCase.expectedIntent)
        }
    }

    @Test func phrasePack_timeGrammarVariants_extractExpectedRangesAndLookbacks() throws {
        let parser = makeParser()
        let rangeCases: [DateRangePhraseCase] = [
            DateRangePhraseCase(
                prompt: "How did I do in December?",
                expectedIntent: .periodOverview,
                expectedStart: date(2025, 12, 1, 0, 0, 0),
                expectedEnd: date(2025, 12, 31, 23, 59, 59)
            ),
            DateRangePhraseCase(
                prompt: "How did I do from 2026-01-01 to 2026-01-31?",
                expectedIntent: .periodOverview,
                expectedStart: date(2026, 1, 1, 0, 0, 0),
                expectedEnd: date(2026, 1, 31, 23, 59, 59)
            ),
            DateRangePhraseCase(
                prompt: "What did I spend on 2026-02-05?",
                expectedIntent: .spendThisMonth,
                expectedStart: date(2026, 2, 5, 0, 0, 0),
                expectedEnd: date(2026, 2, 5, 23, 59, 59)
            )
        ]

        for phraseCase in rangeCases {
            let query = parser.parse(phraseCase.prompt)
            #expect(query?.intent == phraseCase.expectedIntent)
            #expect(query?.dateRange?.startDate == phraseCase.expectedStart)
            #expect(query?.dateRange?.endDate == phraseCase.expectedEnd)
        }

        let lookbackCases: [LookbackPhraseCase] = [
            LookbackPhraseCase(
                prompt: "For the last 6 periods, what is my average savings?",
                expectedIntent: .savingsAverageRecentPeriods,
                expectedLimit: 6
            ),
            LookbackPhraseCase(
                prompt: "For the past 4 months, what share of my income comes from salary?",
                expectedIntent: .incomeSourceShareTrend,
                expectedLimit: 4
            ),
            LookbackPhraseCase(
                prompt: "Over the last 3 months, what share of spending is groceries?",
                expectedIntent: .categorySpendShareTrend,
                expectedLimit: 3
            )
        ]

        for phraseCase in lookbackCases {
            let query = parser.parse(phraseCase.prompt)
            #expect(query?.intent == phraseCase.expectedIntent)
            #expect(query?.resultLimit == phraseCase.expectedLimit)
        }
    }

    @Test func phrasePack_noisyFormattingAndCase_stillMapsToExpectedIntent() throws {
        let parser = makeParser()
        let cases: [IntentPhraseCase] = [
            IntentPhraseCase(prompt: "hOw Am I dOiNg???", expectedIntent: .periodOverview),
            IntentPhraseCase(prompt: "TOP categories THIS month!!!", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "compare THIS month VS last month...", expectedIntent: .compareThisMonthToPreviousMonth),
            IntentPhraseCase(prompt: "largest purchases -- this month", expectedIntent: .largestRecentTransactions),
            IntentPhraseCase(prompt: "any recurring payments due soon???", expectedIntent: .presetDueSoon)
        ]

        for phraseCase in cases {
            let query = parser.parse(phraseCase.prompt)
            #expect(query?.intent == phraseCase.expectedIntent)
        }
    }

    @Test func phrasePack_noisyTyposAndShorthand_stillMapsToExpectedIntent() throws {
        let parser = makeParser()
        let cases: [IntentPhraseCase] = [
            IntentPhraseCase(prompt: "wht did i spnd last month", expectedIntent: .spendThisMonth),
            IntentPhraseCase(prompt: "what % of my incom comes from salery", expectedIntent: .incomeSourceShare),
            IntentPhraseCase(prompt: "what % of my spnding is groceries", expectedIntent: .categorySpendShare),
            IntentPhraseCase(prompt: "any recuring paymnts due soon", expectedIntent: .presetDueSoon),
            IntentPhraseCase(prompt: "if i cut grocereis what can i save", expectedIntent: .categoryPotentialSavings)
        ]

        for phraseCase in cases {
            let query = parser.parse(phraseCase.prompt)
            #expect(query?.intent == phraseCase.expectedIntent)
        }
    }

    @Test func phrasePack_noisyAmbiguousLanguage_setsLowConfidencePlan() throws {
        let parser = makeParser()
        let cases: [PlanConfidenceCase] = [
            PlanConfidenceCase(prompt: "maybe top categories this month i guess", expectedMetric: .topCategories),
            PlanConfidenceCase(prompt: "roughly how am i doing", expectedMetric: .overview),
            PlanConfidenceCase(prompt: "kind of what % of my income is salary", expectedMetric: .incomeSourceShare)
        ]

        for confidenceCase in cases {
            let plan = parser.parsePlan(confidenceCase.prompt)
            #expect(plan?.metric == confidenceCase.expectedMetric)
            #expect(plan?.confidenceBand == .low)
        }
    }

    @Test func phrasePack_shippingCoverageMatrix_mapToExpectedIntent() throws {
        let parser = makeParser()
        let cases: [IntentPhraseCase] = [
            IntentPhraseCase(prompt: "Walk me through my spending this month", expectedIntent: .spendThisMonth),
            IntentPhraseCase(prompt: "Which day cost me the most this month?", expectedIntent: .spendThisMonth),
            IntentPhraseCase(prompt: "What did I pay for today?", expectedIntent: .largestRecentTransactions),
            IntentPhraseCase(prompt: "Which vendors got most of my money this month?", expectedIntent: .topMerchantsThisMonth),
            IntentPhraseCase(prompt: "What did I spend with Starbucks this month?", expectedIntent: .merchantSpendTotal),
            IntentPhraseCase(prompt: "What is my typical spend at Starbucks?", expectedIntent: .merchantSpendSummary),
            IntentPhraseCase(prompt: "Which budget buckets are almost full?", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "Which envelopes have money left?", expectedIntent: .topCategoriesThisMonth),
            IntentPhraseCase(prompt: "What got deposited this month?", expectedIntent: .incomeAverageActual),
            IntentPhraseCase(prompt: "Where is my income coming from this month?", expectedIntent: .incomeAverageActual),
            IntentPhraseCase(prompt: "What card carries most of my spending?", expectedIntent: .cardSnapshotSummary),
            IntentPhraseCase(prompt: "Show me my Apple Card activity", expectedIntent: .cardSnapshotSummary),
            IntentPhraseCase(prompt: "Am I on track to save this month?", expectedIntent: .forecastSavings),
            IntentPhraseCase(prompt: "What changed in my spending this month?", expectedIntent: .topCategoryChangesThisMonth),
            IntentPhraseCase(prompt: "Where am I leaking money?", expectedIntent: .topCategoryChangesThisMonth)
        ]

        for phraseCase in cases {
            let query = parser.parse(phraseCase.prompt)
            #expect(query?.intent == phraseCase.expectedIntent)
        }
    }

    @Test func phrasePack_shippingCoverageFalsePositiveNeighbors_whatIfGroceries_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("What if I spend more on groceries?") == nil)
    }

    @Test func phrasePack_shippingCoverageFalsePositiveNeighbors_affordabilityCadence_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("Can I afford Starbucks every week?") == nil)
    }

    @Test func phrasePack_shippingCoverageFalsePositiveNeighbors_cardSettings_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("Where is my Apple Card settings page?") == nil)
    }

    @Test func phrasePack_shippingCoverageFalsePositiveNeighbors_vendorPlatformPrompt_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("What vendor powers Marina?") == nil)
    }

    @Test func phrasePack_shippingCoverageFalsePositiveNeighbors_appChangesPrompt_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("What changed in the app this month?") == nil)
    }

    @Test func phrasePack_shippingCoverageFalsePositiveNeighbors_designEnvelopePrompt_staysNil() throws {
        let parser = makeParser()
        #expect(parser.parse("Which envelopes does the design use?") == nil)
    }

    // MARK: - Command Parsing

    @Test func commandParser_addExpensePrompt_extractsAmountAndNotes() throws {
        let command = makeCommandParser().parse("Marina, log $25 for Starbucks")

        #expect(command?.intent == .addExpense)
        #expect(command?.amount == 25)
        #expect(command?.notes == "Starbucks")
    }

    @Test func commandParser_editIncomeFromToPrompt_extractsAmountsAndDate() throws {
        let command = makeCommandParser().parse("edit my income entry on 2/1/2026 from 1,000 to 1,250")

        #expect(command?.intent == .editIncome)
        #expect(command?.originalAmount == 1000)
        #expect(command?.amount == 1250)
        #expect(command?.date == date(2026, 2, 1, 0, 0, 0))
    }

    @Test func commandParser_deleteCardPrompt_flaggedAsCardCrud() throws {
        let parser = makeCommandParser()
        #expect(parser.isCardCrudPrompt("delete my card Apple Card") == true)
        let command = parser.parse("delete my card Apple Card")
        #expect(command?.intent == .deleteCard)
        #expect(command?.entityName == "Apple Card")
    }

    @Test func commandParser_addCardPrompt_extractsCardIntentAndName() throws {
        let command = makeCommandParser().parse("create card named Apple Card")
        #expect(command?.intent == .addCard)
        #expect(command?.entityName == "Apple Card")
    }

    @Test func commandParser_addCardPrompt_withThemeAndEffect_stopsNameBeforeStyleTokens() throws {
        let command = makeCommandParser().parse("Create card named New Account theme sunset effect glass")
        #expect(command?.intent == .addCard)
        #expect(command?.entityName == "New Account")
        #expect(command?.cardThemeRaw == "sunset")
        #expect(command?.cardEffectRaw == "glass")
    }

    @Test func commandParser_addCardPrompt_withQuotedName_preservesStyleWordsInsideName() throws {
        let command = makeCommandParser().parse("create card named \"Sunset Glass\" theme ruby effect metal")
        #expect(command?.intent == .addCard)
        #expect(command?.entityName == "Sunset Glass")
        #expect(command?.cardThemeRaw == "ruby")
        #expect(command?.cardEffectRaw == "metal")
    }

    @Test func commandParser_editCardPrompt_extractsCardIntentAndStyle() throws {
        let command = makeCommandParser().parse("edit card named New Account theme aqua")
        #expect(command?.intent == .editCard)
        #expect(command?.entityName == "New Account")
        #expect(command?.cardThemeRaw == "aqua")
    }

    @Test func commandParser_deleteCardPrompt_extractsDeleteIntent() throws {
        let command = makeCommandParser().parse("remove card named New Account")
        #expect(command?.intent == .deleteCard)
        #expect(command?.entityName == "New Account")
    }

    @Test func commandParser_addCategoryPrompt_extractsCategoryIntentAndName() throws {
        let command = makeCommandParser().parse("add category groceries")
        #expect(command?.intent == .addCategory)
        #expect(command?.entityName == "groceries")
    }

    @Test func commandParser_addCategoryPrompt_withColor_stopsNameBeforeColor() throws {
        let command = makeCommandParser().parse("add category named Dining color green")
        #expect(command?.intent == .addCategory)
        #expect(command?.entityName == "Dining")
        #expect(command?.categoryColorHex == "#22C55E")
    }

    @Test func commandParser_addPresetPrompt_extractsPresetIntentAmount() throws {
        let command = makeCommandParser().parse("create preset rent 1500")
        #expect(command?.intent == .addPreset)
        #expect(command?.amount == 1500)
        #expect(command?.entityName == "rent")
    }

    @Test func commandParser_addPresetPrompt_withCardPhrase_staysPresetIntent() throws {
        let command = makeCommandParser().parse("create preset rent 1500 on Apple Card")
        #expect(command?.intent == .addPreset)
        #expect(command?.cardName != nil)
    }

    @Test func commandParser_addPresetPrompt_withWeeklySchedule_extractsRecurrenceFields() throws {
        let command = makeCommandParser().parse("create preset rent 1500 weekly on friday on Apple Card")
        #expect(command?.intent == .addPreset)
        #expect(command?.recurrenceFrequencyRaw == RecurrenceFrequency.weekly.rawValue)
        #expect(command?.weeklyWeekday == 6)
    }

    @Test func commandParser_addPresetPrompt_withIntervalSchedule_extractsIntervalAndFrequency() throws {
        let command = makeCommandParser().parse("create preset gym 45 every 2 weeks on Apple Card")
        #expect(command?.intent == .addPreset)
        #expect(command?.recurrenceFrequencyRaw == RecurrenceFrequency.weekly.rawValue)
        #expect(command?.recurrenceInterval == 2)
    }

    @Test func commandParser_addPresetPrompt_withBiweeklySchedule_extractsIntervalAndFrequency() throws {
        let command = makeCommandParser().parse("create preset daycare 400 biweekly on Apple Card")
        #expect(command?.intent == .addPreset)
        #expect(command?.recurrenceFrequencyRaw == RecurrenceFrequency.weekly.rawValue)
        #expect(command?.recurrenceInterval == 2)
    }

    @Test func commandParser_addPresetPrompt_withEveryOtherWeekSchedule_extractsIntervalAndFrequency() throws {
        let command = makeCommandParser().parse("create preset tutoring 120 every other week on Apple Card")
        #expect(command?.intent == .addPreset)
        #expect(command?.recurrenceFrequencyRaw == RecurrenceFrequency.weekly.rawValue)
        #expect(command?.recurrenceInterval == 2)
    }

    @Test func commandParser_addBudgetPrompt_extractsBudgetIntent() throws {
        let command = makeCommandParser().parse("create budget for March 2026")
        #expect(command?.intent == .addBudget)
    }

    @Test func commandParser_addIncomePrompt_stripsIncomeKindFromSource() throws {
        let command = makeCommandParser().parse("log income $1250 from paycheck actual")
        #expect(command?.intent == .addIncome)
        #expect(command?.source == "paycheck")
        #expect(command?.isPlannedIncome == false)
    }

    @Test func commandParser_addCategoryPrompt_extractsMappedColor() throws {
        let command = makeCommandParser().parse("add category cafes color perriwinkle")
        #expect(command?.intent == .addCategory)
        #expect(command?.categoryColorHex == "#8FA6FF")
    }

    @Test func commandParser_addIncomePrompt_fromPhrase_stripsAmountFromSource() throws {
        let command = makeCommandParser().parse("Add income from Paycheck $1250")
        #expect(command?.intent == .addIncome)
        #expect(command?.source == "Paycheck")
    }

    @Test func commandParser_addIncomePrompt_infersSourceWithoutFromKeyword() throws {
        let command = makeCommandParser().parse("Add income work $1250")
        #expect(command?.intent == .addIncome)
        #expect(command?.source == "work")
        #expect(command?.amount == 1250)
    }

    @Test func commandParser_addIncomePrompt_fromPhrase_withPlannedAndDate_stopsSourceBeforeAttributes() throws {
        let command = makeCommandParser().parse("create income from paycheck planned on 2/1/2026 $1250")
        #expect(command?.intent == .addIncome)
        #expect(command?.source == "paycheck")
        #expect(command?.isPlannedIncome == true)
        #expect(command?.date == date(2026, 2, 1, 0, 0, 0))
        #expect(command?.amount == 1250)
    }

    @Test func commandParser_addIncomePrompt_withQuotedSource_preservesKeywordWords() throws {
        let command = makeCommandParser().parse("create income from \"Planned Growth Fund\" actual $900")
        #expect(command?.intent == .addIncome)
        #expect(command?.source == "Planned Growth Fund")
        #expect(command?.isPlannedIncome == false)
        #expect(command?.amount == 900)
    }

    @Test func commandParser_addIncomePrompt_forPhrase_stopsSourceBeforeDate() throws {
        let command = makeCommandParser().parse("log income $700 for Side Hustle on 2026-02-01")
        #expect(command?.intent == .addIncome)
        #expect(command?.source == "Side Hustle")
        #expect(command?.date == date(2026, 2, 1, 0, 0, 0))
        #expect(command?.amount == 700)
    }

    @Test func commandParser_addIncomePrompt_fallbackPath_stopsSourceBeforeAttributes() throws {
        let command = makeCommandParser().parse("add income side gig planned 1250")
        #expect(command?.intent == .addIncome)
        #expect(command?.source == "side gig")
        #expect(command?.isPlannedIncome == true)
        #expect(command?.amount == 1250)
    }

    @Test func commandParser_markIncomeReceivedPrompt_mapsToIntent() throws {
        let command = makeCommandParser().parse("Mark income as received")
        #expect(command?.intent == .markIncomeReceived)
    }

    @Test func commandParser_moveExpenseCategoryPrompt_mapsToIntentAndCategory() throws {
        let command = makeCommandParser().parse("Move expense $45 to groceries category")
        #expect(command?.intent == .moveExpenseCategory)
        #expect(command?.categoryName == "groceries")
    }

    @Test func commandParser_updatePlannedExpenseAmountPrompt_mapsToIntent() throws {
        let command = makeCommandParser().parse("Update rent to $1450")
        #expect(command?.intent == .updatePlannedExpenseAmount)
        #expect(command?.amount == 1450)
        #expect(command?.plannedExpenseAmountTarget == nil)
    }

    @Test func commandParser_updatePlannedExpenseAmountPrompt_withActualTarget_extractsTarget() throws {
        let command = makeCommandParser().parse("Update planned expense rent actual to $1450")
        #expect(command?.intent == .updatePlannedExpenseAmount)
        #expect(command?.plannedExpenseAmountTarget == .actual)
    }

    @Test func commandParser_deleteLastExpensePrompt_mapsToIntent() throws {
        let command = makeCommandParser().parse("Delete my last expense")
        #expect(command?.intent == .deleteLastExpense)
    }

    @Test func commandParser_deleteLastIncomePrompt_mapsToIntent() throws {
        let command = makeCommandParser().parse("Delete my last income")
        #expect(command?.intent == .deleteLastIncome)
    }

    // MARK: - Helpers

    private struct IntentPhraseCase {
        let prompt: String
        let expectedIntent: HomeQueryIntent
    }

    private struct DateRangePhraseCase {
        let prompt: String
        let expectedIntent: HomeQueryIntent
        let expectedStart: Date
        let expectedEnd: Date
    }

    private struct LookbackPhraseCase {
        let prompt: String
        let expectedIntent: HomeQueryIntent
        let expectedLimit: Int
    }

    private struct PlanConfidenceCase {
        let prompt: String
        let expectedMetric: HomeQueryMetric
    }

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

    private func makeCommandParser() -> HomeAssistantCommandParser {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        let queryParser = HomeAssistantTextParser(
            calendar: calendar,
            nowProvider: { fixedNow }
        )

        return HomeAssistantCommandParser(parser: queryParser)
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
