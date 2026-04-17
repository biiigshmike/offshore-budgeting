//
//  HomeAssistantAliasMatcherTests.swift
//  OffshoreBudgetingTests
//
//  Created by Michael Brown on 2/8/26.
//

import Testing
@testable import Offshore

struct HomeAssistantAliasMatcherTests {

    @Test func matchedTarget_exactAlias_returnsMappedTarget() throws {
        let matcher = HomeAssistantAliasMatcher()
        let rules = [
            AssistantAliasRule(aliasKey: "groc", targetValue: "Groceries", entityType: .category),
            AssistantAliasRule(aliasKey: "salary", targetValue: "Primary Salary", entityType: .incomeSource)
        ]

        let match = matcher.matchedTarget(
            in: "How much did I spend on groc this month?",
            entityType: .category,
            rules: rules
        )

        #expect(match == "Groceries")
    }

    @Test func matchedTarget_fuzzyAliasTypo_returnsMappedTarget() throws {
        let matcher = HomeAssistantAliasMatcher()
        let rules = [
            AssistantAliasRule(aliasKey: "everyday", targetValue: "Everyday Card", entityType: .card)
        ]

        let match = matcher.matchedTarget(
            in: "How much did I spend on everyda card?",
            entityType: .card,
            rules: rules
        )

        #expect(match == "Everyday Card")
    }

    @Test func matchedTarget_entityTypeScope_preventsCrossTypeMatch() throws {
        let matcher = HomeAssistantAliasMatcher()
        let rules = [
            AssistantAliasRule(aliasKey: "salary", targetValue: "Primary Salary", entityType: .incomeSource)
        ]

        let cardMatch = matcher.matchedTarget(
            in: "Show salary trend",
            entityType: .card,
            rules: rules
        )

        #expect(cardMatch == nil)
    }

    @Test func matchedTarget_supportsMerchantAndBudgetScopes() throws {
        let matcher = HomeAssistantAliasMatcher()
        let rules = [
            AssistantAliasRule(aliasKey: "starbs", targetValue: "Starbucks", entityType: .merchant),
            AssistantAliasRule(aliasKey: "trip fund", targetValue: "Travel Budget", entityType: .budget)
        ]

        let merchantMatch = matcher.matchedTarget(
            in: "show starbs spending",
            entityType: .merchant,
            rules: rules
        )
        let budgetMatch = matcher.matchedTarget(
            in: "trip fund",
            entityType: .budget,
            rules: rules
        )

        #expect(merchantMatch == "Starbucks")
        #expect(budgetMatch == "Travel Budget")
    }
}
