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
    }

    @Test func commandParser_addCardPrompt_extractsCardIntentAndName() throws {
        let command = makeCommandParser().parse("create card named Apple Card")
        #expect(command?.intent == .addCard)
        #expect(command?.entityName == "Apple Card")
    }

    @Test func commandParser_addCategoryPrompt_extractsCategoryIntentAndName() throws {
        let command = makeCommandParser().parse("add category groceries")
        #expect(command?.intent == .addCategory)
        #expect(command?.entityName == "groceries")
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
