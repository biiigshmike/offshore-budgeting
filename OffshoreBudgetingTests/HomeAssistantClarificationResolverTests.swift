//
//  HomeAssistantClarificationResolverTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Foundation
import Testing
@testable import Offshore

struct HomeAssistantClarificationResolverTests {

    @Test func resolve_lowConfidenceOverview_requiresClarificationBeforeRun() throws {
        let resolver = makeResolver()
        let plan = HomeQueryPlan(
            metric: .overview,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .low
        )

        let decision = resolver.resolve(
            plan: plan,
            rawPrompt: "Maybe how am I doing?",
            now: fixedNow
        )

        #expect(decision != nil)
        #expect(decision?.shouldRunBestEffort == false)
        #expect(decision?.reasons.contains(.lowConfidenceLanguage) == true)
        #expect(decision?.reasons.contains(.missingDate) == true)
        #expect(decision?.reasons.contains(.broadPrompt) == true)
        #expect(decision?.suggestions.isEmpty == false)
    }

    @Test func resolve_mediumConfidenceCategoryShare_returnsDateAndCategoryClarifiers() throws {
        let resolver = makeResolver()
        let plan = HomeQueryPlan(
            metric: .categorySpendShare,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let decision = resolver.resolve(
            plan: plan,
            rawPrompt: "What share is groceries?",
            now: fixedNow
        )

        #expect(decision != nil)
        #expect(decision?.shouldRunBestEffort == true)
        #expect(decision?.reasons.contains(.missingDate) == true)
        #expect(decision?.reasons.contains(.missingCategoryTarget) == true)
        #expect(decision?.suggestions.contains(where: { $0.title == "Use this month" }) == true)
        #expect(decision?.suggestions.contains(where: { $0.title == "All categories" }) == true)
    }

    @Test func resolve_mediumConfidenceWithClearScope_returnsNil() throws {
        let resolver = makeResolver()
        let plan = HomeQueryPlan(
            metric: .categorySpendShare,
            dateRange: HomeQueryDateRange(
                startDate: date(2026, 2, 1, 0, 0, 0),
                endDate: date(2026, 2, 28, 23, 59, 59)
            ),
            resultLimit: nil,
            confidenceBand: .medium,
            targetName: "Groceries"
        )

        let decision = resolver.resolve(
            plan: plan,
            rawPrompt: "What share is groceries this month?",
            now: fixedNow
        )

        #expect(decision == nil)
    }

    @Test func resolve_mediumConfidenceBroadOverview_addsBroadPromptSuggestions() throws {
        let resolver = makeResolver()
        let plan = HomeQueryPlan(
            metric: .overview,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let decision = resolver.resolve(
            plan: plan,
            rawPrompt: "How am I doing?",
            now: fixedNow
        )

        #expect(decision != nil)
        #expect(decision?.shouldRunBestEffort == true)
        #expect(decision?.reasons.contains(.broadPrompt) == true)
        #expect(decision?.suggestions.contains(where: { $0.title == "Compare with last month" }) == true)
    }

    // MARK: - Helpers

    private var fixedNow: Date {
        date(2026, 2, 15, 12, 0, 0)
    }

    private func makeResolver() -> HomeAssistantClarificationResolver {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return HomeAssistantClarificationResolver(calendar: calendar)
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 12,
        _ minute: Int = 0,
        _ second: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = second

        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}
