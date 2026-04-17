//
//  HomeAssistantIntentBuilderTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 3/30/26.
//

import Foundation
import Testing
@testable import Offshore

@MainActor
struct HomeAssistantIntentBuilderTests {

    @Test func buildPlan_compareThisMonthToLastMonth_keepsExistingComparisonBehavior() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: .monthComparison,
                targetName: nil,
                targetSource: nil,
                dateRange: nil,
                comparisonDateRange: nil,
                comparisonDetected: true,
                rawPrompt: "Compare this month to last month"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .monthComparison)
        #expect(plan.targetName == nil)
        #expect(plan.confidenceBand == .high)
    }

    @Test func buildPlan_compareTransportationUpgradesToCategoryComparison() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: .monthComparison,
                targetName: "Transportation",
                targetSource: .matchedEntity,
                dateRange: monthRange(2026, 2),
                comparisonDateRange: nil,
                comparisonDetected: true,
                rawPrompt: "Compare transportation this month vs last month"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .categoryMonthComparison)
        #expect(plan.targetName == "Transportation")
        #expect(plan.confidenceBand == .high)
        #expect(plan.dateRange == monthRange(2026, 2))
    }

    @Test func buildPlan_compareAppleCardUpgradesToCardComparison() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: .monthComparison,
                targetName: "Apple Card",
                targetSource: .matchedEntity,
                dateRange: monthRange(2026, 2),
                comparisonDateRange: nil,
                comparisonDetected: true,
                rawPrompt: "Compare my Apple Card spending this month vs last month"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .cardMonthComparison)
        #expect(plan.targetName == "Apple Card")
        #expect(plan.confidenceBand == .high)
    }

    @Test func buildPlan_compareSpendingWithoutTarget_keepsGlobalComparison() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .spendTotal,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: nil,
                targetName: nil,
                targetSource: nil,
                dateRange: monthRange(2026, 2),
                comparisonDateRange: nil,
                comparisonDetected: true,
                rawPrompt: "Compare spending vs last month"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .monthComparison)
        #expect(plan.targetName == nil)
        #expect(plan.dateRange == monthRange(2026, 2))
        #expect(plan.confidenceBand == .high)
    }

    @Test func buildPlan_compareUnknownTarget_upgradesToMerchantComparison() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: nil,
                targetName: "Starbucks",
                targetSource: .inferredComparisonText,
                dateRange: monthRange(2026, 2),
                comparisonDateRange: nil,
                comparisonDetected: true,
                rawPrompt: "Compare Starbucks vs last month"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .merchantMonthComparison)
        #expect(plan.targetName == "Starbucks")
        #expect(plan.confidenceBand == .high)
    }

    @Test func buildPlan_compareExplicitPeriods_preservesBothRanges() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let january = monthRange(2026, 1)
        let february = monthRange(2026, 2)
        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: nil,
                targetName: nil,
                targetSource: nil,
                dateRange: january,
                comparisonDateRange: february,
                comparisonDetected: true,
                rawPrompt: "Compare spending from January 2026 to February 2026 across all categories"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .monthComparison)
        #expect(plan.dateRange == january)
        #expect(plan.comparisonDateRange == february)
        #expect(plan.confidenceBand == .high)
    }

    @Test func buildPlan_compareExplicitPeriodsMissingSecondRange_downgradesConfidence() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let january = monthRange(2026, 1)
        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: nil,
                targetName: nil,
                targetSource: nil,
                dateRange: january,
                comparisonDateRange: nil,
                comparisonDetected: true,
                rawPrompt: "Compare spending from January 2026 to"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .monthComparison)
        #expect(plan.dateRange == january)
        #expect(plan.comparisonDateRange == nil)
        #expect(plan.confidenceBand == .medium)
    }

    @Test func buildPlan_compareMonthToMonthPromptWithoutScopedTarget_staysGlobalAndMedium() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .spendTotal,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let february = monthRange(2026, 2)
        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: nil,
                targetName: nil,
                targetSource: nil,
                dateRange: february,
                comparisonDateRange: nil,
                comparisonDetected: true,
                rawPrompt: "Compare spending in February to March please"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .monthComparison)
        #expect(plan.targetName == nil)
        #expect(plan.dateRange == february)
        #expect(plan.comparisonDateRange == nil)
        #expect(plan.confidenceBand == .medium)
    }

    @Test func buildPlan_compareExplicitPeriodsWithInferredTarget_staysGlobal() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let february = monthRange(2026, 2)
        let march = monthRange(2026, 3)
        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: nil,
                targetName: "Spending",
                targetSource: .inferredComparisonText,
                dateRange: february,
                comparisonDateRange: march,
                comparisonDetected: true,
                rawPrompt: "Compare spending from February 2026 to March 2026 across all categories"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .monthComparison)
        #expect(plan.targetName == nil)
        #expect(plan.dateRange == february)
        #expect(plan.comparisonDateRange == march)
        #expect(plan.confidenceBand == .high)
    }

    @Test func buildPlan_genericSpendFallbackWithMerchantSignal_upgradesToMerchantSpend() throws {
        let builder = makeBuilder()
        let yearRange = HomeQueryDateRange(
            startDate: date(2026, 1, 1, 0, 0, 0),
            endDate: date(2026, 12, 31, 23, 59, 59)
        )
        let fallbackPlan = HomeQueryPlan(
            metric: .spendTotal,
            dateRange: yearRange,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: .merchantSpendTotal,
                targetName: "Starbucks",
                targetSource: .merchantPhrase,
                dateRange: yearRange,
                comparisonDateRange: nil,
                comparisonDetected: false,
                rawPrompt: "What is the amount I have spent on Starbucks so far this year?"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .merchantSpendTotal)
        #expect(plan.targetName == "Starbucks")
        #expect(plan.dateRange == yearRange)
    }

    @Test func buildPlan_compareMerchantFirstShorthand_upgradesToMerchantComparison() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let march = monthRange(2026, 3)
        let february = monthRange(2026, 2)
        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: .merchantMonthComparison,
                targetName: "Starbucks",
                targetSource: .merchantPhrase,
                dateRange: march,
                comparisonDateRange: february,
                comparisonDetected: true,
                rawPrompt: "Compare Starbucks spend from March to February please"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .merchantMonthComparison)
        #expect(plan.targetName == "Starbucks")
        #expect(plan.dateRange == march)
        #expect(plan.comparisonDateRange == february)
        #expect(plan.confidenceBand == .high)
    }

    @Test func buildPlan_compareWeakMerchantPrompt_requestsClarification() throws {
        let builder = makeBuilder()
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let march = monthRange(2026, 3)
        let february = monthRange(2026, 2)
        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: .merchantMonthComparison,
                targetName: nil,
                targetSource: .weakMerchantPhrase,
                dateRange: march,
                comparisonDateRange: february,
                comparisonDetected: true,
                rawPrompt: "Compare merchant spending from March to February"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .merchantMonthComparison)
        #expect(plan.targetName == nil)
        #expect(plan.confidenceBand == .medium)
    }

    @Test func buildPlan_explicitRelativeDates_overrideStaleFallbackRanges() throws {
        let builder = makeBuilder()
        let staleJanuary = monthRange(2025, 1)
        let staleFebruary = monthRange(2025, 2)
        let april = monthRange(2026, 4)
        let march = monthRange(2026, 3)
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: staleJanuary,
            comparisonDateRange: staleFebruary,
            resultLimit: nil,
            confidenceBand: .medium,
            targetName: "Groceries"
        )

        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: .monthComparison,
                targetName: "Groceries",
                targetSource: .matchedEntity,
                dateRange: april,
                comparisonDateRange: march,
                comparisonDetected: true,
                rawPrompt: "Compare groceries this month to last month"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .categoryMonthComparison)
        #expect(plan.targetName == "Groceries")
        #expect(plan.dateRange == april)
        #expect(plan.comparisonDateRange == march)
    }

    @Test func buildPlan_previousWeekSignals_overrideStaleFallbackRanges() throws {
        let builder = makeBuilder()
        let staleJanuary = monthRange(2025, 1)
        let staleFebruary = monthRange(2025, 2)
        let currentWeek = weekRange(2026, 4, 6)
        let previousWeek = weekRange(2026, 3, 30)
        let fallbackPlan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: staleJanuary,
            comparisonDateRange: staleFebruary,
            resultLimit: nil,
            confidenceBand: .medium
        )

        let plan = builder.buildPlan(
            from: HomeAssistantParsedSignals(
                metric: .monthComparison,
                targetName: nil,
                targetSource: nil,
                dateRange: currentWeek,
                comparisonDateRange: previousWeek,
                comparisonDetected: true,
                rawPrompt: "Compare last week to previous week"
            ),
            fallbackPlan: fallbackPlan
        )

        #expect(plan.metric == .monthComparison)
        #expect(plan.dateRange == currentWeek)
        #expect(plan.comparisonDateRange == previousWeek)
    }

    private func makeBuilder() -> HomeAssistantIntentBuilder {
        HomeAssistantIntentBuilder(
            categoryNames: ["Groceries", "Transportation"],
            cardNames: ["Apple Card", "Blue Card"],
            incomeSourceNames: ["Salary", "Freelance"]
        )
    }

    private func monthRange(_ year: Int, _ month: Int) -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(year, month, 1, 0, 0, 0),
            endDate: date(year, month, 28, 23, 59, 59)
        )
    }

    private func weekRange(_ year: Int, _ month: Int, _ day: Int) -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(year, month, day, 0, 0, 0),
            endDate: date(year, month, day + 6, 23, 59, 59)
        )
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
