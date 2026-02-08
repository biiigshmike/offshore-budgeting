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

    // MARK: - Unknown Prompt

    @Test func parse_unknownPrompt_returnsNil() throws {
        let query = makeParser().parse("Do I have budget leaks by weekday?")

        #expect(query == nil)
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
