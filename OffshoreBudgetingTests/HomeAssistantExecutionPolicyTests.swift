//
//  HomeAssistantExecutionPolicyTests.swift
//  OffshoreBudgetingTests
//
//  Created by OpenAI Codex on 4/21/26.
//

import Foundation
import Testing
@testable import Offshore

struct HomeAssistantExecutionPolicyTests {

    @Test func broadSummaryPolicies_areConfiguredForTargetlessExecution() throws {
        let topMerchants = HomeQueryMetric.topMerchants.executionPolicy
        let topCategories = HomeQueryMetric.topCategories.executionPolicy
        let largest = HomeQueryMetric.largestTransactions.executionPolicy
        let spend = HomeQueryMetric.spendTotal.executionPolicy

        #expect(topMerchants.requiresTarget == false)
        #expect(topMerchants.supportsBroadExecution == true)
        #expect(topMerchants.requiresDateScope == true)

        #expect(topCategories.requiresTarget == false)
        #expect(topCategories.supportsBroadExecution == true)
        #expect(topCategories.requiresDateScope == true)

        #expect(largest.requiresTarget == false)
        #expect(largest.supportsBroadExecution == true)
        #expect(largest.requiresDateScope == true)

        #expect(spend.requiresTarget == false)
        #expect(spend.supportsBroadExecution == true)
        #expect(spend.requiresDateScope == true)
    }

    @Test func targetRequiredPolicy_missingTarget_isUnresolved() throws {
        let plan = HomeQueryPlan(
            metric: .merchantSpendTotal,
            dateRange: monthRange(2026, 4),
            resultLimit: nil,
            confidenceBand: .low,
            targetName: nil
        )
        let eligibility = HomeAssistantExecutionEligibilityEvaluator.evaluate(
            plan: plan,
            normalizedPrompt: normalize("What did I spend this month?"),
            activeBudgetDateRange: nil,
            now: date(2026, 4, 21)
        )

        #expect(eligibility.unresolvedRequirements.contains(.target))
    }

    @Test func broadSummaryPrompt_top3MerchantsThisMonth_isExecutableEvenAtLowConfidence() throws {
        let prompt = "Top 3 merchants this month"
        let plan = makeLowConfidencePlan(prompt)
        let eligibility = HomeAssistantExecutionEligibilityEvaluator.evaluate(
            plan: plan,
            normalizedPrompt: normalize(prompt),
            activeBudgetDateRange: nil,
            now: date(2026, 4, 21)
        )

        #expect(plan.metric == .topMerchants)
        #expect(plan.targetName == nil)
        #expect(plan.resultLimit == 3)
        #expect(eligibility.unresolvedRequirements.isEmpty)
    }

    @Test func broadSummaryPrompt_top3ExpensesThisMonth_isExecutableEvenAtLowConfidence() throws {
        let prompt = "Top 3 expenses this month?"
        let plan = makeLowConfidencePlan(prompt)
        let eligibility = HomeAssistantExecutionEligibilityEvaluator.evaluate(
            plan: plan,
            normalizedPrompt: normalize(prompt),
            activeBudgetDateRange: nil,
            now: date(2026, 4, 21)
        )

        #expect(plan.metric == .largestTransactions)
        #expect(plan.targetName == nil)
        #expect(plan.resultLimit == 3)
        #expect(eligibility.unresolvedRequirements.isEmpty)
    }

    @Test func broadSummaryPrompt_topMerchantThisPeriod_isExecutableEvenAtLowConfidence() throws {
        let prompt = "What is my top merchant this period"
        let plan = makeLowConfidencePlan(prompt)
        let eligibility = HomeAssistantExecutionEligibilityEvaluator.evaluate(
            plan: plan,
            normalizedPrompt: normalize(prompt),
            activeBudgetDateRange: nil,
            now: date(2026, 4, 21)
        )

        #expect(plan.metric == .topMerchants)
        #expect(plan.targetName == nil)
        #expect(eligibility.unresolvedRequirements.isEmpty)
    }

    @Test func comparisonFamilyPrompt_missingRequiredSecondScope_isUnresolved() throws {
        let plan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: monthRange(2026, 1),
            comparisonDateRange: nil,
            resultLimit: nil,
            confidenceBand: .medium
        )
        let eligibility = HomeAssistantExecutionEligibilityEvaluator.evaluate(
            plan: plan,
            normalizedPrompt: normalize("Compare spending from January 2026 to"),
            activeBudgetDateRange: nil,
            now: date(2026, 4, 21)
        )

        #expect(eligibility.comparisonSecondScopeRequired == true)
        #expect(eligibility.unresolvedRequirements.contains(.comparisonDateScope))
    }

    @Test func comparisonFamilyPrompt_withSecondScope_isExecutable() throws {
        let plan = HomeQueryPlan(
            metric: .monthComparison,
            dateRange: monthRange(2026, 1),
            comparisonDateRange: monthRange(2025, 12),
            resultLimit: nil,
            confidenceBand: .medium
        )
        let eligibility = HomeAssistantExecutionEligibilityEvaluator.evaluate(
            plan: plan,
            normalizedPrompt: normalize("Compare spending from January 2026 to December 2025"),
            activeBudgetDateRange: nil,
            now: date(2026, 4, 21)
        )

        #expect(eligibility.comparisonSecondScopeRequired == true)
        #expect(eligibility.unresolvedRequirements.isEmpty)
    }

    private func makeLowConfidencePlan(_ prompt: String) -> HomeQueryPlan {
        let parser = HomeAssistantTextParser(
            nowProvider: { date(2026, 4, 21) }
        )
        let parsed = parser.parsePlan(prompt, defaultPeriodUnit: .month)
        guard let parsed else {
            Issue.record("Expected parser to produce a plan for: \(prompt)")
            return HomeQueryPlan(metric: .overview, dateRange: nil, resultLimit: nil, confidenceBand: .low)
        }

        return HomeQueryPlan(
            metric: parsed.metric,
            dateRange: parsed.dateRange,
            comparisonDateRange: parsed.comparisonDateRange,
            resultLimit: parsed.resultLimit,
            confidenceBand: .low,
            targetName: parsed.targetName,
            targetTypeRaw: parsed.targetTypeRaw,
            periodUnit: parsed.periodUnit
        )
    }

    private func normalize(_ raw: String) -> String {
        raw
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s&]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func monthRange(_ year: Int, _ month: Int) -> HomeQueryDateRange {
        HomeQueryDateRange(
            startDate: date(year, month, 1),
            endDate: date(year, month, 28, 23, 59, 59)
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
